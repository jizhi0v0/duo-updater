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

    @Test func equivalentBuildSpellingStillPreservesTheInstalledChannel() {
        let collidingMarketing = [
            SparkleAppcastItem(shortVersionString: "1.0", version: "101"),
            SparkleAppcastItem(
                shortVersionString: "1.0", version: "v100", channel: "beta"),
        ]

        #expect(SparkleAppcastSource.channel(
            ofInstalled: app(short: "1.0", build: "100"),
            in: collidingMarketing) == "beta",
            "the semantically identical build must win before marketing fallback")
    }

    @Test func exactBuildSpellingBeatsAnEarlierEquivalentBuild() {
        let duplicateSpellings = [
            SparkleAppcastItem(
                shortVersionString: "1.0", version: "1.0.0", channel: "tip"),
            SparkleAppcastItem(
                shortVersionString: "1.0", version: "1.0", channel: "beta"),
        ]

        #expect(SparkleAppcastSource.channel(
            ofInstalled: app(short: "1.0", build: "1.0"),
            in: duplicateSpellings) == "beta")
    }

    /// TypeWhisper's real appcast, 2026-08-31: three trains on one bundle id,
    /// and the `release-candidate` build ships the SAME
    /// `CFBundleShortVersionString` (`1.6.0`) as the stable item that sits
    /// AHEAD of it in the feed. The fixture above can't catch this — its two
    /// keys never disagree about which item they pick.
    ///
    /// "Build first, then short" has to mean "build across every item, then
    /// short across every item". Matching per-item instead let the stable
    /// entry's short string win before the rc entry's exact build was ever
    /// compared, so the rc install read as stable and its own train vanished
    /// from `usableItems`. Verified against the real rc2 bundle before the fix.
    ///
    /// Note what this does NOT change: with the bug the rc user was still
    /// offered 1091, because the default channel is allowed to everyone and
    /// stable was the newer of the two that day. The damage only lands when
    /// the rc train moves ahead — covered by the second half of the test.
    private var typeWhisperItems: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>1.7.0-daily.20260830</title>
              <sparkle:version>1161</sparkle:version>
              <sparkle:shortVersionString>1.7.0-daily.20260830</sparkle:shortVersionString>
              <sparkle:channel>daily</sparkle:channel>
              <enclosure url="https://example.com/daily.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
            <item>
              <title>1.6.0</title>
              <sparkle:version>1091</sparkle:version>
              <sparkle:shortVersionString>1.6.0</sparkle:shortVersionString>
              <enclosure url="https://example.com/1.6.0.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
            <item>
              <title>1.6.0-rc2</title>
              <sparkle:version>1083</sparkle:version>
              <sparkle:shortVersionString>1.6.0-rc2</sparkle:shortVersionString>
              <sparkle:channel>release-candidate</sparkle:channel>
              <enclosure url="https://example.com/rc2.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """.utf8))
    }

    @Test func anExactBuildMatchBeatsAnEarlierItemSharingTheShortVersion() {
        // The rc bundle: short `1.6.0` (collides with the stable item), build 1083.
        let rc = InstalledApp(
            name: "TypeWhisper", bundleID: "com.typewhisper.mac",
            shortVersion: "1.6.0", buildVersion: "1083",
            path: URL(fileURLWithPath: "/Applications/TypeWhisper.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key")
        #expect(SparkleAppcastSource.channel(ofInstalled: rc, in: typeWhisperItems) == "release-candidate")

        // The user's own train is visible again: its entry survives the gate,
        // which is what feeds the notes and the release history.
        let usable = SparkleAppcastSource.usableItems(
            for: rc, from: typeWhisperItems, osVersion: "26.0.0")
        #expect(usable.contains { $0.version == "1083" })

        // And once the rc train moves ahead of stable, the rc user is actually
        // offered it — the case the gate was silently answering "no" to.
        let withNewerRC = typeWhisperItems + SparkleAppcastParser.parse(Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>1.6.1-rc1</title>
              <sparkle:version>1095</sparkle:version>
              <sparkle:shortVersionString>1.6.1-rc1</sparkle:shortVersionString>
              <sparkle:channel>release-candidate</sparkle:channel>
              <enclosure url="https://example.com/rc3.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """.utf8))
        let best = SparkleAppcastSource.bestItem(for: rc, from: withNewerRC, osVersion: "26.0.0")
        #expect(best?.version == "1095")
        #expect(best?.channel == "release-candidate")
    }

    /// Supacode's shape, same date and same failure: the `tip` build
    /// (`1787740786`) is item #10 while item #0 is the default `0.10.8` — and
    /// tip carries that identical short string. Kept alongside the TypeWhisper
    /// case because the two differ in where the colliding item sits, and a fix
    /// that only sorted the feed would pass one and fail the other.
    @Test func aTipBuildIsNotStolenByTheDefaultItemAheadOfIt() {
        let items = SparkleAppcastParser.parse(Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>0.10.8</title>
              <sparkle:version>1785775286</sparkle:version>
              <sparkle:shortVersionString>0.10.8</sparkle:shortVersionString>
              <enclosure url="https://example.com/default.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
            <item>
              <title>0.10.8 tip</title>
              <sparkle:version>1787740786</sparkle:version>
              <sparkle:shortVersionString>0.10.8</sparkle:shortVersionString>
              <sparkle:channel>tip</sparkle:channel>
              <enclosure url="https://example.com/tip.zip" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """.utf8))
        let tip = InstalledApp(
            name: "supacode", bundleID: "app.supabit.supacode",
            shortVersion: "0.10.8", buildVersion: "1787740786",
            path: URL(fileURLWithPath: "/Applications/supacode.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key")
        #expect(SparkleAppcastSource.channel(ofInstalled: tip, in: items) == "tip")
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
    /// default channel to everyone). Feed where stable 2.1/300 tops beta 2.0/200.
    @Test func betaUserStillGetsNewerStable() {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>2.1</title><sparkle:version>300</sparkle:version><sparkle:shortVersionString>2.1</sparkle:shortVersionString>
            <enclosure url="https://example.com/2.1.dmg" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
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

    /// ⚠️ The fixture above used to be stable **1.6**/300 over beta 2.0-beta/200,
    /// asserting that the beta copy took the 1.6 — which is #368 in miniature: a
    /// higher build carrying a lower marketing version, offered as an update. The
    /// rule it was written for ("the default channel is allowed to everyone") is
    /// real and still holds above; what it cannot mean is that a stable release
    /// the vendor numbered BELOW the installed one is an update. Kept as its own
    /// case so the old expectation is visible as a decision rather than deleted.
    ///
    /// Promotion still works, and that is the case this could plausibly have
    /// broken: a 2.0 final over a 2.0-beta reads as newer (a release outranks its
    /// own prerelease tag), so it is offered — asserted here beside the refusal.
    @Test func betaUserIsNotDroppedOntoAnOlderStable() {
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
        #expect(best?.version == "200")

        let promoted = SparkleAppcastParser.parse(Data(feed
            .replacingOccurrences(of: "<title>1.6</title>", with: "<title>2.0</title>")
            .replacingOccurrences(
                of: "<sparkle:shortVersionString>1.6</sparkle:shortVersionString>",
                with: "<sparkle:shortVersionString>2.0</sparkle:shortVersionString>").utf8))
        let final = SparkleAppcastSource.bestItem(
            for: app(short: "2.0-beta", build: "200"), from: promoted, osVersion: "26.0.0")
        #expect(final?.version == "300")
        #expect(final?.shortVersionString == "2.0")
    }
}
