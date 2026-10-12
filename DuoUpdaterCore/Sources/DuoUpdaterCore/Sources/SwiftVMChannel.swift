import Foundation

/// SwiftVM (`com.swiftvm.app`) — a Sparkle app whose channel is fixed when a
/// build is made, not chosen in the app: one bundle id, two feeds, and no
/// preference anywhere.
///
/// What SwiftVM does (read from `swiftvm-app/swiftvm`): `UpdateChannel` in
/// `App/Updates/UpdateService.swift` answers `allowedChannels` with `["beta"]`
/// when the copy's own `CFBundleShortVersionString` contains `-beta.`, and with
/// nothing otherwise. The release workflows build the two kinds of copy with
/// different `SUFeedURL`s, always together with their version:
/// `release-beta.yml` builds `X.Y.Z-beta.N` against `betaFeed` below, and
/// `release.yml` builds `X.Y.Z` against `releases/latest/download/appcast.xml`.
/// Every item of the beta feed is tagged `<sparkle:channel>beta`; the stable
/// feed's items are untagged. A beta copy stays on betas for good — each stable
/// release is a beta re-built under the stable version, with the same build
/// number.
///
/// Why a binding at all, when the generic source already resolves both kinds
/// today: without one, `SparkleAppcastSource.allowedChannels` learns that a copy
/// is on beta only by finding the copy's build in the feed. The vendor's
/// workflow rebuilds the beta feed from nothing when it cannot download the
/// previous one (and ships a "Republish Beta Appcast" workflow to put a beta
/// back), and a beta copy whose build is no longer listed would be admitted
/// only untagged items — of which the beta feed has none. Naming the channel
/// keeps that copy on its betas, as its own updater keeps it.
///
/// The signal is the bundle's `SUFeedURL` (`ChannelBinding.bundleFeeds`)
/// rather than the version SwiftVM itself reads, because a resolver is handed
/// the feeds and not the version; in the vendor's builds the two are written
/// from one workflow input. A copy built any other way (by hand, or a development
/// build) declares no feed and does not update — nil. The stable feed resolves
/// nil too: its items are untagged, and nil keeps the build-inferred default.
///
/// The tag is derived from `.beta` (`ReleaseChannel.rawValue`), the feed's own
/// spelling, so nothing is declared by hand. Not in `boundBundleIDs`: nothing a
/// user sets changes the answer.
enum SwiftVMChannel {
    static let bundleID = "com.swiftvm.app"

    /// The address every beta build declares as `SUFeedURL`.
    static let betaFeed = URL(
        string: "https://github.com/swiftvm-app/swiftvm/releases/download/beta-channel/appcast-beta.xml")!
    /// The address every stable build declares as `SUFeedURL`.
    static let stableFeed = URL(
        string: "https://github.com/swiftvm-app/swiftvm/releases/latest/download/appcast.xml")!

    /// The feeds of each kind of build (1.0.0-beta.16 and 1.0.0, 2026-10-11), for
    /// `ChannelBinding.allResolutions`, which enumerates without a bundle.
    static let betaBundleFeeds: [String: URL] = ["SUFeedURL": betaFeed]
    static let stableBundleFeeds: [String: URL] = ["SUFeedURL": stableFeed]

    /// `.beta` for a copy built against the beta feed, else nil. Pure and tested.
    static func resolve(bundleFeeds: [String: URL]) -> ResolvedChannel? {
        bundleFeeds["SUFeedURL"] == betaFeed ? ResolvedChannel(channel: .beta) : nil
    }
}
