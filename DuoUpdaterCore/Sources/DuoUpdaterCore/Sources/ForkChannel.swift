import Foundation

/// Fork (`com.DanPristupov.Fork`) — a feed-swap app. It ships two Sparkle feeds,
/// one per channel, and picks between them at runtime from its own preference.
/// The channel is invisible the usual ways:
///   * the feeds carry no `<sparkle:channel>` elements, and
///   * the code-signed Info.plist `SUFeedURL` is always the Develop feed.
///
/// The Updates pane popup (`UpdatesPreferencesController.nib`) has two items,
/// "Develop" (the shipped default) and "Stable (delayed 1 week)". Their actions
/// write an Int into `applicationUpdateChannel`: `enableStableChannel(_:)` writes
/// **1**, `enableDevelopChannel(_:)` writes **2**. The feed picker is a single
/// comparison against 1, so 1 takes the stable feed and *everything else* — 2,
/// absent, junk — takes the Develop feed.
///
/// This file used to say 2 was Stable, which is exactly backwards, and it cost a
/// user their updates: with the pref at 2 (Develop, chosen in Fork's own UI) we
/// retargeted the install to the stable feed, whose head sat at 2.66.7 while the
/// installed copy was 2.69.0. A head *older* than installed reads as "up to date",
/// so 2.70.0 never surfaced — while Fork's own Sparkle dialog was offering it.
///
/// The original claim came from `channel-verify --scan`, which runs *our*
/// `detect()`: writing 2 and watching us answer "stable" only proved we were
/// self-consistent. The mapping below is read from Fork 2.69.0's arm64 slice
/// instead (2026-09-07) — `Contents/MacOS/Fork`, the feed picker at `0x1002156fc`:
///
///     bl   -[NSUserDefaults integerForKey:]   // "applicationUpdateChannel" -> x21
///     cmp  x21, #0x1
///     csel x20, <…/feed-stable.xml>, <…/feed.xml>, eq
///
/// and the two writers, each a `setInteger:forKey:` with an immediate:
/// `enableStableChannel(_:)` at `0x10030e888` moves `#0x1`,
/// `enableDevelopChannel(_:)` at `0x10030e774` moves `#0x2`.
enum ForkChannel {
    static let bundleID = "com.DanPristupov.Fork"

    static let developerFeed = URL(string: "https://fork.dev/update/feed.xml")!
    static let stableFeed = URL(string: "https://fork.dev/update/feed-stable.xml")!

    /// The integer Fork stores for the Stable channel. Fork compares against this
    /// one value and treats every other value as Develop, so mirroring the
    /// comparison — not enumerating the values — is what keeps us in step.
    static let stablePrefValue = 1

    /// The integer Fork's "Develop" menu item writes. Not used by `resolve` (the
    /// fallback already covers it) but named so a test can pin the value that
    /// actually appears in a Develop user's defaults, which is the case we got
    /// wrong.
    static let developerPrefValue = 2

    /// Map Fork's `applicationUpdateChannel` to a resolution. Pure and tested.
    static func resolve(channelPref: Int?) -> ResolvedChannel {
        channelPref == stablePrefValue
            ? ResolvedChannel(channel: .stable, feedOverride: stableFeed)
            : ResolvedChannel(channel: .beta, feedOverride: developerFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(channelPref: readChannelPref())
    }

    /// Read `applicationUpdateChannel` from Fork's defaults via CFPreferences, so
    /// the value is authoritative even while Fork is running. nil if unreadable.
    static func readChannelPref() -> Int? {
        channelPref(from: CFPreferencesCopyAppValue(
            "applicationUpdateChannel" as CFString, bundleID as CFString
        ))
    }

    /// The typed half of the read, split out so it can be tested without touching
    /// the real preference domain.
    ///
    /// A string is accepted because Fork reads the key with `integerForKey:`,
    /// which parses one. This used to take `NSNumber` only, and the difference is
    /// not academic in the direction it fails: a `applicationUpdateChannel` stored
    /// as the string "1" is Stable to Fork and unreadable to us, and unreadable
    /// falls through to Develop — pushing a Develop build at a copy its owner put
    /// on Stable, the mirror of the bug this file was written for. Fork's own UI
    /// writes an integer, so nothing observed produces a string; the point is that
    /// "we mirror Fork's comparison" is now true of the whole read and not just of
    /// the `== 1`.
    static func channelPref(from raw: Any?) -> Int? {
        switch raw {
        case let number as NSNumber: return number.intValue
        // `integerForKey:` on a non-numeric string yields 0, which is not 1 and so
        // is Develop. nil lands on the same branch of `resolve`, so returning nil
        // rather than 0 keeps "we could not read it" distinguishable at the call
        // site without changing the resolution.
        case let text as String: return Int(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}
