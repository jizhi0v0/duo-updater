import Testing
import Foundation
@testable import DuoUpdaterCore

/// `MonitorControlChannel`: `isBetaChannel` → `<sparkle:channel>beta`, the one
/// extra channel MonitorControl's own `allowedChannels` returns.
@Suite struct MonitorControlChannelTests {
    /// MonitorControl's live feed has no tagged item yet (2026-10-08), so this
    /// fixture is synthetic: one untagged release, and a newer beta-tagged one of
    /// the kind the source is written to admit.
    private static let feed = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>4.5.0-beta1</title>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:version>7200</sparkle:version>
          <sparkle:shortVersionString>4.5.0-beta1</sparkle:shortVersionString>
          <enclosure url="https://example.invalid/ZZFixture-MonitorControl-beta.dmg" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>
        <item>
          <title>4.4.0</title>
          <sparkle:version>7152</sparkle:version>
          <sparkle:shortVersionString>4.4.0</sparkle:shortVersionString>
          <enclosure url="https://example.invalid/ZZFixture-MonitorControl.dmg" length="1" type="application/octet-stream" sparkle:edSignature="x"/>
        </item>
      </channel>
    </rss>
    """#

    private func offered(isBeta: Bool) -> String? {
        let bound = MonitorControlChannel.resolve(isBetaChannel: isBeta)
        let app = InstalledApp(
            name: "MonitorControl", bundleID: MonitorControlChannel.bundleID,
            shortVersion: "4.4.0", buildVersion: "7152",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-MonitorControl.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://monitorcontrol.app/appcast2.xml"),
            sparkleChannelNames: bound?.sparkleChannelNames ?? [],
            sparkleEdPublicKey: "key",
            releaseChannel: bound?.channel ?? .stable,
            channelIsAuthoritative: bound != nil)
        return SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(Self.feed.utf8)),
            osVersion: "27.0", hostArch: .arm64, allowingIntelTranslation: true
        )?.shortVersionString
    }

    /// Mutation that turns this red: dropping MonitorControl's resolution, or
    /// resolving `.stable`.
    @Test func anOptedInStableCopyIsOfferedTheBeta() {
        #expect(offered(isBeta: true) == "4.5.0-beta1")
    }

    @Test func anOptedOutCopyStaysOnUntaggedReleases() {
        #expect(MonitorControlChannel.resolve(isBetaChannel: false) == nil)
        #expect(offered(isBeta: false) == "4.4.0")
    }

    @Test func monitorControlIsBound() {
        #expect(ChannelBinding.boundBundleIDs.contains(MonitorControlChannel.bundleID.lowercased()))
        #expect(ChannelBinding.hasResolver(bundleID: MonitorControlChannel.bundleID))
    }
}
