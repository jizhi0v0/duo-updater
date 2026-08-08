import Foundation

/// Ghostty (`com.mitchellh.ghostty`) — a Sparkle app whose feed URL is set in code
/// rather than in Info.plist, so `AppScanner` finds no `SUFeedURL` and the app
/// reached us with no source at all ("no source applied → unknown", sitting on
/// 1.3.1 with nothing to compare against).
///
/// Supplying the feed here rather than scraping it with a `VendorProbeRecipe` is
/// deliberate: it IS a Sparkle appcast, so the normal path gives us the enclosure's
/// EdDSA signature (Ghostty ships `SUPublicEDKey`, so one-click is fully verified),
/// the release notes, and the version history — none of which a version regex
/// recovers.
///
/// Channel: stable only. Ghostty's `tip` builds are published to GitHub Releases
/// under a rolling `tip` prerelease tag, NOT to this appcast — the only tip entries
/// here are two from 2024-12 whose `shortVersionString` is a commit hash. Those sort
/// below any real release, so a stable user can't be offered one. A user actually
/// running tip is a different problem: their build shares this bundle id and its
/// hash version can't be compared, which is the known blocked case (see
/// CHANNEL_COVERAGE_TODO); this binding doesn't make that better or worse.
enum GhosttyChannel {
    static let bundleID = "com.mitchellh.ghostty"

    /// Ghostty's only appcast. Serves stable releases, newest last.
    static let feed = URL(string: "https://release.files.ghostty.org/appcast.xml")!

    static func resolveCurrent() -> ResolvedChannel {
        ResolvedChannel(channel: .stable, feedOverride: feed)
    }
}
