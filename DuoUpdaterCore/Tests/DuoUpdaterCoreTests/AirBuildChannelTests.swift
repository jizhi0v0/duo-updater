import Testing
import Foundation
@testable import DuoUpdaterCore

/// `AirBuildChannel`: Settings ▸ General ▸ "Receive Beta Updates"
/// (`ReceiveBetaVersions`) → `<sparkle:channel>beta`.
@Suite struct AirBuildChannelTests {
    /// Two real items of `release.air.build/macos/appcast.xml` (2026-10-19),
    /// lengths and signatures cut: the stable 1.1.93 and the beta 1.1.120, as the
    /// feed stood before 1.1.121 was promoted.
    private static let feed = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>1.1</title>
          <sparkle:version>1.1.120</sparkle:version>
          <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://release.air.build/macos/AirBuild-macOS-1.1-120.zip" length="1" type="application/octet-stream" sparkle:edSignature="x" />
        </item>
        <item>
          <title>1.1</title>
          <sparkle:version>1.1.93</sparkle:version>
          <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <enclosure url="https://release.air.build/macos/AirBuild-macOS-1.1-93.zip" length="1" type="application/octet-stream" sparkle:edSignature="x" />
        </item>
      </channel>
    </rss>
    """#

    private func offeredBuild(installed build: String, receiveBeta: Bool, bound: Bool = true) -> String? {
        let binding = AirBuildChannel.resolve(receiveBetaVersions: receiveBeta)
        let app = InstalledApp(
            name: "AirBuild", bundleID: AirBuildChannel.bundleID,
            shortVersion: "1.1", buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-AirBuild.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://release.air.build/macos/appcast.xml"),
            sparkleChannelNames: binding.sparkleChannelNames,
            sparkleEdPublicKey: "key",
            releaseChannel: bound ? binding.channel : .stable,
            channelIsAuthoritative: bound)
        return SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(Self.feed.utf8)),
            osVersion: "27.0", hostArch: .arm64, allowingIntelTranslation: true
        )?.version
    }

    /// Mutation that turns this red: dropping the binding's beta answer.
    @Test func aStableCopyWithTheBoxTickedIsOfferedTheBeta() {
        #expect(offeredBuild(installed: "1.1.93", receiveBeta: true) == "1.1.120")
        // Without the binding, feed inference keeps it on the stable items.
        #expect(offeredBuild(installed: "1.1.93", receiveBeta: true, bound: false) == "1.1.93")
    }

    @Test func aStableCopyWithTheBoxUntickedStaysStable() {
        #expect(offeredBuild(installed: "1.1.93", receiveBeta: false) == "1.1.93")
    }

    /// What the app wrote on the real 1.1.93: ticked `1`, unticked a boolean `0`,
    /// and no key before the box was ever touched.
    @Test func readsTheValuesTheAppWrites() {
        #expect(AirBuildChannel.receiveBetaVersions(from: NSNumber(value: true)))
        #expect(!AirBuildChannel.receiveBetaVersions(from: NSNumber(value: false)))
        #expect(!AirBuildChannel.receiveBetaVersions(from: nil))
        #expect(AirBuildChannel.receiveBetaVersions(from: "YES"))
        #expect(!AirBuildChannel.receiveBetaVersions(from: "no"))
        #expect(AirBuildChannel.resolve(receiveBetaVersions: false).channel == .stable)
        #expect(AirBuildChannel.resolve(receiveBetaVersions: true).channel == .beta)
    }

    /// 1.1.120 (beta) and 1.1.121 (stable) both read `1.1`: nothing in the bundle
    /// marks a beta.
    @Test func theBundleVersionCarriesNoChannel() {
        #expect(ReleaseChannel.detect(
            name: "AirBuild", bundleID: AirBuildChannel.bundleID,
            keystoneChannel: nil, version: "1.1") == .stable)
    }

    @Test func airBuildIsBound() {
        #expect(ChannelBinding.boundBundleIDs.contains(AirBuildChannel.bundleID.lowercased()))
        #expect(ChannelBinding.hasResolver(bundleID: AirBuildChannel.bundleID))
    }
}
