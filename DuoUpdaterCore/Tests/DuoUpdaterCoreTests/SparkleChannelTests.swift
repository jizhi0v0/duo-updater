import Testing
import Foundation
@testable import DuoUpdaterCore

/// Channel-gating for Sparkle appcasts: we can't read the host app's
/// `allowedChannels` (it's compiled into the app), so we infer the user's
/// channel from the build they're running and only ever offer same-channel
/// updates — a stable user is never pushed a beta, a beta user is never
/// dropped onto a stable.
struct SparkleChannelTests {

    /// A DuoPaste-shaped feed: a default-channel line and a beta line.
    private let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <title>2.0 beta</title>
          <sparkle:version>200</sparkle:version>
          <sparkle:shortVersionString>2.0-beta</sparkle:shortVersionString>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/2.0-beta.dmg" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
        <item>
          <title>1.5</title>
          <sparkle:version>150</sparkle:version>
          <sparkle:shortVersionString>1.5</sparkle:shortVersionString>
          <enclosure url="https://example.com/1.5.dmg" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
        <item>
          <title>1.0</title>
          <sparkle:version>100</sparkle:version>
          <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/1.0.dmg" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """

    private func app(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "DuoPaste", bundleID: "io.duopaste.daemon",
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/DuoPaste.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key")
    }

    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(feed.utf8))
    }

    @Test func parserReadsChannelElement() {
        let parsed = items
        #expect(parsed.count == 3)
        #expect(parsed.first(where: { $0.version == "200" })?.channel == "beta")
        #expect(parsed.first(where: { $0.version == "150" })?.channel == nil)
    }

    @Test func stableUserNeverOffersBeta() {
        // On the 1.0 stable build → the only newer in-channel item is 1.5.
        let best = SparkleAppcastSource.bestItem(
            for: app(short: "1.0", build: "100"), from: items, osVersion: "26.0.0")
        #expect(best?.version == "150")
    }

    @Test func betaUserStaysOnBetaNotStable() {
        // On a beta build (matched by short version) → only the beta line, even
        // though a numerically-newer key could exist on stable.
        let best = SparkleAppcastSource.bestItem(
            for: app(short: "2.0-beta", build: "200"), from: items, osVersion: "26.0.0")
        #expect(best?.channel == "beta")
        #expect(best?.version == "200")
    }

    @Test func unknownBuildFallsBackToStable() {
        // Installed build isn't in the feed (history trimmed) → default channel
        // only, so we never surprise the user with a prerelease.
        let best = SparkleAppcastSource.bestItem(
            for: app(short: "0.9", build: "90"), from: items, osVersion: "26.0.0")
        #expect(best?.version == "150")
        #expect(best?.channel == nil)
    }

    @Test func channelOfInstalledMatchesOnBuildThenShortVersion() {
        #expect(SparkleAppcastSource.channel(ofInstalled: app(short: "x", build: "200"), in: items) == "beta")
        #expect(SparkleAppcastSource.channel(ofInstalled: app(short: "1.5", build: "x"), in: items) == nil)
    }
}
