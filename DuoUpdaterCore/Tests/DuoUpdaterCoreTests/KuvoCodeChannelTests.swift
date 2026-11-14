import Foundation
import Testing
@testable import DuoUpdaterCore

struct KuvoCodeChannelTests {
    /// The real stable and beta item shapes from Kuvo Code's appcast. Notes are
    /// trimmed; the version pair, channel, OS floor and asset names are retained.
    private static let feed = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Kuvo Code 0.8.0-beta.1</title>
          <sparkle:version>0.8.0b1</sparkle:version>
          <sparkle:shortVersionString>0.8.0-beta.1</sparkle:shortVersionString>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <description sparkle:format="markdown"><![CDATA[
    - Removing a machine in Settings › Machines now only takes it off this Mac.
    ]]></description>
          <enclosure url="https://github.com/serhatandic/kuvo-code/releases/download/v0.8.0-beta.1/KuvoCode.dmg"/>
        </item>
        <item>
          <title>Kuvo Code 0.7.2</title>
          <sparkle:version>0.7.2</sparkle:version>
          <sparkle:shortVersionString>0.7.2</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <description sparkle:format="markdown"><![CDATA[
    - Edit Bot shows the model a bot really talks on.
    - Ask the agent for a screenshot of the page it's browsing and it shows in the conversation.
    ]]></description>
          <enclosure url="https://github.com/serhatandic/kuvo-code/releases/download/v0.7.2/KuvoCode.dmg"/>
        </item>
      </channel>
    </rss>
    """

    private func app(version: String, includeBetas: Bool?, bound: Bool = true) throws -> InstalledApp {
        let binding = try #require(KuvoCodeChannel.resolve(
            includeBetas: includeBetas, bundleStrings: ["CFBundleShortVersionString": version]))
        return InstalledApp(
            name: "Kuvo Code", bundleID: KuvoCodeChannel.bundleID,
            shortVersion: version, buildVersion: version == "0.8.0-beta.1" ? "0.8.0b1" : version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-KuvoCode.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://github.com/serhatandic/kuvo-code/releases/latest/download/appcast.xml"),
            releaseChannel: bound ? binding.channel : .beta,
            channelIsAuthoritative: bound)
    }

    private func offeredBuild(version: String, includeBetas: Bool?, bound: Bool = true) throws -> String? {
        SparkleAppcastSource.bestItem(
            for: try app(version: version, includeBetas: includeBetas, bound: bound),
            from: SparkleAppcastParser.parse(Data(Self.feed.utf8)),
            osVersion: "27.0", hostArch: .arm64, allowingIntelTranslation: true)?.version
    }

    @Test func anUntouchedStableCopyStaysOnStable() throws {
        #expect(try offeredBuild(version: "0.7.1", includeBetas: nil) == "0.7.2")
    }

    @Test func anUntouchedBetaCopyDefaultsToBeta() throws {
        #expect(try offeredBuild(version: "0.8.0-beta.1", includeBetas: nil) == "0.8.0b1")
    }

    @Test func optingInOffersABetaToAStableCopy() throws {
        #expect(try offeredBuild(version: "0.7.2", includeBetas: true) == "0.8.0b1")
    }

    /// Without an authoritative false, the installed beta item infers beta and
    /// silently undoes the user's opt-out. Stable's older build is not installed
    /// over the beta: the shared comparison gate waits for stable to catch up.
    @Test func optingOutStopsBetaInferenceOnABetaCopy() throws {
        #expect(try offeredBuild(version: "0.8.0-beta.1", includeBetas: false) == "0.7.2")
        #expect(try offeredBuild(version: "0.8.0-beta.1", includeBetas: false, bound: false) == "0.8.0b1")
    }

    @Test func missingBundleContextDoesNotHideAnExplicitOptOut() {
        let before = KuvoCodeChannel.resolve(includeBetas: nil)
        let after = KuvoCodeChannel.resolve(includeBetas: false)
        #expect(before == nil)
        #expect(after?.channel == .stable)
        let id = KuvoCodeChannel.bundleID
        let changes = ChannelSwitchDetector.changes(
            current: [id: ChannelSwitchDetector.fingerprint(of: after)],
            lastSeen: [id: ChannelSwitchDetector.fingerprint(of: before)])
        #expect(changes.changed == [id])
    }

    @Test func theBindingKeepsTheProductsAndTheirFeedsSeparate() throws {
        #expect(ChannelBinding.hasResolver(bundleID: KuvoCodeChannel.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(KuvoCodeChannel.bundleID))
        #expect(!ChannelBinding.hasResolver(bundleID: "run.kuvo.app"))
        for flag in [true, false] {
            let resolution = try #require(KuvoCodeChannel.resolve(includeBetas: flag))
            #expect(resolution.feedOverride == nil)
            #expect(resolution.feedHTTPHeaders.isEmpty)
            #expect(resolution.sparkleChannelNames.isEmpty)
        }
        #expect(Set(ChannelBinding.allResolutions.filter { $0.bundleID == KuvoCodeChannel.bundleID }
            .map(\.resolved.channel)) == [.stable, .beta])
    }

    @Test func theRealFeedFormatProvidesNativeNotes() throws {
        let items = SparkleAppcastParser.parse(Data(Self.feed.utf8))
        let stable = try #require(items.first { $0.version == "0.7.2" })
        let changelog = try #require(SparkleAppcastSource.structuredChangelog(from: [stable]))
        #expect(changelog.entries.first?.version == "0.7.2")
        #expect(changelog.entries.first?.items == [
            "Edit Bot shows the model a bot really talks on.",
            "Ask the agent for a screenshot of the page it's browsing and it shows in the conversation.",
        ])
    }
}
