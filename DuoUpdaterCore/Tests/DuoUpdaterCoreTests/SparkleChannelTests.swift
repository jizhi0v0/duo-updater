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

    /// `<enclosure length>` feeds "Update All"'s shortest-first ordering; the
    /// parser must surface it (the fixtures above all declare `length="1"`).
    @Test func parserReadsEnclosureLength() {
        for item in items {
            #expect(item.enclosureLength == 1)
        }
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

    /// An app whose channel preference says "beta" but is still on a stable build
    /// (no beta newer yet). Build-inference would call it stable and miss the
    /// beta line; the authoritative channel from `ChannelBinding` catches it.
    @Test func authoritativeBetaOnStableBuildSeesBeta() {
        let betaOptedOnStable = InstalledApp(
            name: "DuoPaste", bundleID: "io.duopaste.daemon",
            shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/DuoPaste.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key",
            releaseChannel: .beta, channelIsAuthoritative: true)
        let best = SparkleAppcastSource.bestItem(for: betaOptedOnStable, from: items, osVersion: "26.0.0")
        #expect(best?.version == "200")
        #expect(best?.channel == "beta")
    }

    /// A beta user must still get a newer *stable* release (Sparkle allows the
    /// default channel to everyone). Feed where stable 1.6/300 tops beta 2.0/200.
    @Test func betaUserStillGetsNewerStable() {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>1.6</title><sparkle:version>300</sparkle:version><sparkle:shortVersionString>1.6</sparkle:shortVersionString>
            <enclosure url="https://example.com/1.6.dmg" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
          <item><title>2.0 beta</title><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0-beta</sparkle:shortVersionString>
            <sparkle:channel>beta</sparkle:channel>
            <enclosure url="https://example.com/2.0-beta.dmg" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
        </channel></rss>
        """
        let parsed = SparkleAppcastParser.parse(Data(feed.utf8))
        let best = SparkleAppcastSource.bestItem(
            for: app(short: "2.0-beta", build: "200"), from: parsed, osVersion: "26.0.0")
        #expect(best?.version == "300")
        #expect(best?.channel == nil)
    }
}
