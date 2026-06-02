import Foundation

/// Fork (`com.DanPristupov.Fork`) — a feed-swap app. It ships two Sparkle feeds,
/// one per channel, and picks between them at runtime from its own preference.
/// The channel is invisible the usual ways:
///   * the feeds carry no `<sparkle:channel>` elements, and
///   * the code-signed Info.plist `SUFeedURL` is always the Developer feed.
///
/// The Updates popup (`UpdatesPreferencesController.nib`) has exactly two items:
/// "Developer" (beta — the shipped default) and "Stable (delayed 1 week)".
/// Selecting Stable writes `applicationUpdateChannel = 2`; the Developer default
/// leaves the key unset (or non-2). We treat 2 as Stable, everything else as
/// Developer/beta.
enum ForkChannel {
    static let bundleID = "com.DanPristupov.Fork"

    static let developerFeed = URL(string: "https://fork.dev/update/feed.xml")!
    static let stableFeed = URL(string: "https://fork.dev/update/feed-stable.xml")!

    /// The integer Fork stores for the Stable channel.
    static let stablePrefValue = 2

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
        guard let raw = CFPreferencesCopyAppValue(
            "applicationUpdateChannel" as CFString, bundleID as CFString
        ) else { return nil }
        return (raw as? NSNumber)?.intValue
    }
}
