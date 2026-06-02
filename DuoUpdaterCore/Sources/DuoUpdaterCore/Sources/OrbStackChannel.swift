import Foundation

/// OrbStack (`dev.kdrag0n.MacVirt`) — a channel-tag app whose one appcast
/// (`appcast.new.xml`) carries stable/beta/canary items via `<sparkle:channel>`.
/// It has no Info.plist `SUFeedURL` (the feed is set in code), so it reaches us
/// through the VendorProbe path, where channel selection is driven by the app's
/// `releaseChannel`. The user's choice is stored, cleanly, as the literal
/// channel name in `updates_optinChannel`:
///   "stable" / "beta" / "canary"  (absent → stable)
///
/// We don't override the feed: the per-channel VendorProbe recipes already point
/// at `appcast.new.xml` and anchor their regex to the matching `<sparkle:channel>`.
/// Install stays on the codesign-verified VendorInstall path (OrbStack ships no
/// `SUPublicEDKey`, so Sparkle's EdDSA path can't verify it).
enum OrbStackChannel {
    static let bundleID = "dev.kdrag0n.MacVirt"

    /// Map `updates_optinChannel` to a resolution. Pure and tested. An unknown
    /// or absent value falls back to `.stable` — never a higher channel.
    static func resolve(channelString: String?) -> ResolvedChannel {
        let channel = channelString.flatMap(ReleaseChannel.init(rawValue:)) ?? .stable
        return ResolvedChannel(channel: channel, feedOverride: nil)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(channelString: readChannelString())
    }

    static func readChannelString() -> String? {
        CFPreferencesCopyAppValue("updates_optinChannel" as CFString,
                                  bundleID as CFString) as? String
    }
}
