import Foundation

/// DuoPaste (`io.duopaste.daemon`) — a textbook channel-tag Sparkle app. One
/// appcast with `<sparkle:channel>beta</sparkle:channel>` items, and an
/// `allowedChannels` delegate driven by a single Bool the app stores in its own
/// UserDefaults under `sparkleIncludePrereleases` (true → follow beta).
///
/// We don't override the feed (Info.plist `SUFeedURL` is correct); resolving the
/// channel just lets `SparkleAppcastSource` allow beta items for a user who
/// opted in but happens to be running a stable build — which build-inference
/// alone can't see.
enum DuoPasteChannel {
    static let bundleID = "io.duopaste.daemon"

    /// Map DuoPaste's `sparkleIncludePrereleases` flag to a resolution. Pure.
    static func resolve(includePrereleases: Bool) -> ResolvedChannel {
        ResolvedChannel(channel: includePrereleases ? .beta : .stable, feedOverride: nil)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(includePrereleases: readIncludePrereleases())
    }

    static func readIncludePrereleases() -> Bool {
        guard let raw = CFPreferencesCopyAppValue(
            "sparkleIncludePrereleases" as CFString, bundleID as CFString
        ) else { return false }
        return (raw as? NSNumber)?.boolValue ?? false
    }
}
