import Testing
import Foundation
@testable import DuoUpdaterCore

/// `SwiftVMChannel`: a copy built against the beta feed is on beta, whether or
/// not that feed still lists the copy's own build.
@Suite struct SwiftVMChannelTests {
    /// The beta feed as the vendor's workflow writes it when it starts from
    /// nothing: only the newest beta, tagged. Item shape copied from the real
    /// `appcast-beta.xml` (2026-10-11); enclosure and signature are placeholders.
    private static let betaFeedListingOnlyTheNewest = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Version 1.0.0-beta.16</title>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:version>16</sparkle:version>
          <sparkle:shortVersionString>1.0.0-beta.16</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.invalid/ZZFixture-SwiftVM-1.0.0-beta.16.dmg" sparkle:edSignature="x" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """#

    private static let stableFeed = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Version 1.0.0</title>
          <sparkle:version>16</sparkle:version>
          <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.invalid/ZZFixture-SwiftVM-1.0.0.dmg" sparkle:edSignature="x" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """#

    /// What the generic source offers a copy, resolved the way `AppScanner`
    /// resolves it: through `ChannelBinding.resolve` with the bundle's feeds.
    private func offered(
        shortVersion: String, build: String, bundleFeeds: [String: URL], feed: String
    ) -> String? {
        let bound = ChannelBinding.resolve(
            bundleID: SwiftVMChannel.bundleID, bundleFeeds: bundleFeeds,
            bounded: BoundedBlockingWork(label: "test"))
        let app = InstalledApp(
            name: "SwiftVM", bundleID: SwiftVMChannel.bundleID,
            shortVersion: shortVersion, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-SwiftVM.app"),
            isMASApp: false,
            sparkleFeedURL: bundleFeeds["SUFeedURL"],
            sparkleChannelNames: bound?.sparkleChannelNames ?? [],
            sparkleEdPublicKey: "key",
            releaseChannel: bound?.channel ?? .stable,
            channelIsAuthoritative: bound != nil)
        return SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(feed.utf8)),
            osVersion: "27.0", hostArch: .arm64, allowingIntelTranslation: false
        )?.shortVersionString
    }

    /// Mutation that turns this red: dropping SwiftVM's case from the resolver
    /// switch, or resolving `.stable` for the beta feed. Without the binding the
    /// copy's build 12 is not in the feed, so only untagged items are admitted
    /// and there are none.
    @Test func aBetaCopyMissingFromTheFeedIsStillOfferedTheNewerBeta() {
        #expect(offered(
            shortVersion: "1.0.0-beta.12", build: "12",
            bundleFeeds: SwiftVMChannel.betaBundleFeeds,
            feed: Self.betaFeedListingOnlyTheNewest) == "1.0.0-beta.16")
    }

    @Test func aStableCopyIsLeftToTheUntaggedFeed() {
        #expect(SwiftVMChannel.resolve(bundleFeeds: SwiftVMChannel.stableBundleFeeds) == nil)
        #expect(offered(
            shortVersion: "1.0.0", build: "16",
            bundleFeeds: SwiftVMChannel.stableBundleFeeds,
            feed: Self.stableFeed) == "1.0.0")
    }

    /// A copy that declares no feed (a development build) does not update itself,
    /// and a feed the vendor has not used is not guessed at.
    @Test func anyOtherFeedResolvesNothing() {
        #expect(SwiftVMChannel.resolve(bundleFeeds: [:]) == nil)
        #expect(SwiftVMChannel.resolve(bundleFeeds: [
            "SUFeedURL": URL(string: "https://example.invalid/ZZFixture-appcast-beta.xml")!,
        ]) == nil)
    }

    @Test func theBetaFeedResolvesTheDerivedBetaTag() {
        let resolved = SwiftVMChannel.resolve(bundleFeeds: SwiftVMChannel.betaBundleFeeds)
        #expect(resolved == ResolvedChannel(channel: .beta))
    }

    /// No preference to watch, so not in `boundBundleIDs`, but a real resolver.
    @Test func swiftVMHasAResolverButNothingToWatch() {
        #expect(ChannelBinding.hasResolver(bundleID: SwiftVMChannel.bundleID))
        #expect(!ChannelBinding.boundBundleIDs.contains(SwiftVMChannel.bundleID.lowercased()))
    }
}
