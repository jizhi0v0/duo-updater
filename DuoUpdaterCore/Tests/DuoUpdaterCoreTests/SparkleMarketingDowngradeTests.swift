import Testing
import Foundation
@testable import DuoUpdaterCore

/// A Sparkle feed must never walk a copy BACKWARDS in marketing version, however
/// the build numbers read (#368).
///
/// `usableItems` ranks items by `sparkle:version` and `UpdateChecker.evaluate`
/// compares builds whenever both sides have one, so nothing in the offer path had
/// ever read the marketing string. A vendor whose builds run monotonically across
/// two trains therefore fed a prerelease copy a stable package that was newer by
/// build and three releases older by name — signed, notarized, and behind an
/// Update button.
///
/// The fix is in two halves and so are these tests:
///
///  - `SparkleAppcastSource.offerableItem` decides WHICH item to name, stepping
///    over a head that walks backwards so the copy can find the entry it should
///    actually take. Pinned by `theNextBetaBelowAStablePatchIsFound` and
///    `theScanNeverPromotesAnEntryWithNoDownload`.
///  - `UpdateChecker.evaluate` decides whether that item is an UPDATE, and refuses
///    when the marketing version says backwards. Pinned by
///    `aTrimmedBetaIsNotOfferedTheOlderStable` and
///    `aSourceThatNamesItsOwnVersionsIsNotSecondGuessed`.
///
/// ⚠️ The rest are one-directional: they fail if the guard OVER-withholds, and
/// they pass with the guard deleted entirely. That is deliberate (over-withholding
/// is the failure mode that makes an app stop updating silently) but it means
/// "nine tests" is not "nine tests of the guard" — the ones above are.
///
/// The fixture is CotEditor's real appcast (fetched 2026-09-06, 13 items) cut to
/// the four that matter: the single `prerelease` entry, the stable line one build
/// below it, the newest of the legacy compatibility ladder, and the 2014 entry
/// that states a `sparkle:version` and NO `sparkle:shortVersionString`.
struct SparkleMarketingDowngradeTests {

    /// CotEditor's own items, verbatim in every field the selection reads.
    fileprivate static let cotEditorFeed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <title>CotEditor 7.1.0-beta.6</title>
          <pubDate>Sat, 05 Sep 2026 10:26:56 +0900</pubDate>
          <sparkle:channel>prerelease</sparkle:channel>
          <sparkle:version>845</sparkle:version>
          <sparkle:shortVersionString>7.1.0-beta.6</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/coteditor/CotEditor/releases/download/7.1.0-beta.6/CotEditor_7.1.0-beta.6.dmg" length="26458624" type="application/octet-stream" sparkle:edSignature="sig"/>
        </item>
        <item>
          <title>CotEditor 7.0.9</title>
          <pubDate>Sat, 05 Sep 2026 09:59:15 +0900</pubDate>
          <sparkle:version>843</sparkle:version>
          <sparkle:shortVersionString>7.0.9</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/coteditor/CotEditor/releases/download/7.0.9/CotEditor_7.0.9.dmg" length="25609728" type="application/octet-stream" sparkle:edSignature="sig"/>
        </item>
        <item>
          <title>CotEditor 5.2.3</title>
          <pubDate>Sat, 20 Jul 2024 12:00:00 +0900</pubDate>
          <sparkle:version>730</sparkle:version>
          <sparkle:shortVersionString>5.2.3</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/coteditor/CotEditor/releases/download/5.2.3/CotEditor_5.2.3.dmg" length="21000000" type="application/octet-stream" sparkle:edSignature="sig"/>
        </item>
        <item>
          <title>CotEditor 2.0.3</title>
          <pubDate>Sun, 14 Dec 2014 21:19:19 +0900</pubDate>
          <sparkle:version>2.0.3</sparkle:version>
          <sparkle:minimumSystemVersion>10.7</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/coteditor/CotEditor/releases/download/2.0.3/CotEditor_2.0.3.dmg" length="14414610" type="application/octet-stream" sparkle:dsaSignature="sig"/>
        </item>
      </channel>
    </rss>
    """

    private static let feedURL = URL(string: "https://coteditor.com/appcast.xml")!

    private var cotEditorItems: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(Self.cotEditorFeed.utf8), relativeTo: Self.feedURL)
    }

    private func cotEditor(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "CotEditor", bundleID: "com.coteditor.CotEditor",
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/CotEditor.app"),
            isMASApp: false, sparkleFeedURL: Self.feedURL)
    }

    /// A Sparkle remote, as `SparkleAppcastSource.latestVersion` builds it.
    private func sparkleRemote(_ item: SparkleAppcastItem?) -> RemoteVersion {
        RemoteVersion(
            shortVersion: item?.shortVersionString, version: item?.version,
            marketingMatchesBundle: true,
            downloadURL: item?.enclosureURL, sourceName: "Sparkle")
    }

    /// The reported bug. A copy on `7.1.0-beta.3` is not in the feed any more (the
    /// vendor keeps only the newest prerelease), so `channel(ofInstalled:)` misses
    /// on both passes, `allowedChannels` falls back to `{nil}`, and the highest
    /// build left is 843 — `7.0.9`, three marketing versions back. Installing it
    /// also ends the beta train: the copy then matches the STABLE item, so the
    /// channel inference reads it `.stable` from then on.
    ///
    /// The feed's newest entry is still NAMED (that is the row's version readout),
    /// it is just not an update.
    ///
    /// Mutation: drop the marketing test from `evaluate`'s build branch →
    /// `.updateAvailable(latest: "7.0.9")`.
    @Test func aTrimmedBetaIsNotOfferedTheOlderStable() {
        let app = cotEditor(short: "7.1.0-beta.3", build: "840")
        let best = SparkleAppcastSource.bestItem(
            for: app, from: cotEditorItems, osVersion: "26.6.0")
        #expect(best?.shortVersionString == "7.0.9")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best)) == .upToDate)
    }

    /// The same guard with nothing trimmed: CotEditor maintains 7.0.x and 7.1.0
    /// side by side, so a 7.0.x patch published above the newest beta reaches a
    /// beta copy whose own build IS in the feed.
    ///
    /// Here the copy's own build IS in the feed, so stepping over the stable head
    /// lands on it — the row names `7.1.0-beta.6`, the newest thing on this copy's
    /// train, rather than the stable that outranks it by build.
    ///
    /// Mutation: drop the marketing test from `evaluate` AND return the head
    /// unconditionally → the beta copy is offered `7.0.10`. Either half alone
    /// already makes this row safe, which is the point of having both.
    @Test func aStablePublishedAboveTheBetaIsNotAnUpdate() {
        let items = SparkleAppcastParser.parse(Data(Self.feed(
            replacing: "5.2.3", withShort: "7.0.10", build: "850", minOS: "15.0").utf8),
            relativeTo: Self.feedURL)
        let app = cotEditor(short: "7.1.0-beta.6", build: "845")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.6.0")
        #expect(best?.shortVersionString == "7.1.0-beta.6")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best)) == .upToDate)

        // And the same feed read by a STABLE copy still offers the stable patch.
        let onStable = cotEditor(short: "7.0.9", build: "843")
        let forStable = SparkleAppcastSource.bestItem(for: onStable, from: items, osVersion: "26.6.0")
        #expect(forStable?.version == "850")
        #expect(UpdateChecker.evaluate(installed: onStable, remote: sparkleRemote(forStable))
            == .updateAvailable(latest: "7.0.10"))
    }

    /// What the head-stepping is FOR: the entry this copy should take can sit
    /// BELOW a stable patch in build order, and naming the head unconditionally
    /// hides it. Feed: stable `7.0.10`/850 on top, the next beta `7.1.0-beta.7`/846
    /// under it, the installed `7.1.0-beta.6`/845 under that.
    ///
    /// Two mutations, and this is the only test that catches either: return the
    /// head unconditionally → `7.0.10` and no update; take the LAST provable
    /// non-downgrade instead of the first → `7.1.0-beta.6`, the build already
    /// installed, and no update.
    @Test func theNextBetaBelowAStablePatchIsFound() {
        let feed = Self.cotEditorFeed
            .replacingOccurrences(of: "<sparkle:version>730</sparkle:version>", with: "<sparkle:version>850</sparkle:version>")
            .replacingOccurrences(
                of: "<sparkle:shortVersionString>5.2.3</sparkle:shortVersionString>",
                with: "<sparkle:shortVersionString>7.0.10</sparkle:shortVersionString>")
            .replacingOccurrences(of: "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>", with: "<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>")
            .replacingOccurrences(of: """
                    <item>
                      <title>CotEditor 2.0.3</title>
                """, with: """
                    <item>
                      <title>CotEditor 7.1.0-beta.7</title>
                      <sparkle:channel>prerelease</sparkle:channel>
                      <sparkle:version>846</sparkle:version>
                      <sparkle:shortVersionString>7.1.0-beta.7</sparkle:shortVersionString>
                      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
                      <enclosure url="https://example.com/CotEditor_7.1.0-beta.7.dmg" length="1" type="application/octet-stream" sparkle:edSignature="sig"/>
                    </item>
                    <item>
                      <title>CotEditor 2.0.3</title>
                """)
        let items = SparkleAppcastParser.parse(Data(feed.utf8), relativeTo: Self.feedURL)
        #expect(items.count == 5)

        let app = cotEditor(short: "7.1.0-beta.6", build: "845")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.6.0")
        #expect(best?.shortVersionString == "7.1.0-beta.7")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best))
            == .updateAvailable(latest: "7.1.0-beta.7"))
    }

    /// `usableItems` admits an item with no `<enclosure>` at all — its filter asks
    /// only for a version — and `archVerdict` reads a nil URL as arch-neutral
    /// rather than unrunnable. Before the head-stepping existed such an entry was
    /// reachable only by topping the build ranking; the scan must not newly
    /// promote one into an Update button over a nil download.
    ///
    /// Mutation: drop `enclosureURL != nil` from the scan → `7.1.0-beta.4` is
    /// named, `evaluate` calls 841 newer than 840, and the row offers an update
    /// with nothing behind it.
    @Test func theScanNeverPromotesAnEntryWithNoDownload() {
        let feed = Self.cotEditorFeed.replacingOccurrences(of: """
                <item>
                  <title>CotEditor 5.2.3</title>
            """, with: """
                <item>
                  <title>CotEditor 7.1.0-beta.4</title>
                  <sparkle:version>841</sparkle:version>
                  <sparkle:shortVersionString>7.1.0-beta.4</sparkle:shortVersionString>
                </item>
                <item>
                  <title>CotEditor 5.2.3</title>
            """)
        let items = SparkleAppcastParser.parse(Data(feed.utf8), relativeTo: Self.feedURL)
        #expect(items.first(where: { $0.version == "841" })?.enclosureURL == nil)

        let app = cotEditor(short: "7.1.0-beta.3", build: "840")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.6.0")
        #expect(best?.version == "843")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best)) == .upToDate)
    }

    /// The stable line still updates stable copies — the guard only ever refuses
    /// something OLDER, and 7.0.9 is not older than 7.0.8.
    ///
    /// Mutation: invert the comparison in `isMarketingDowngrade` → nothing updates.
    @Test func aStableCopyStillGetsItsStableUpdate() {
        let app = cotEditor(short: "7.0.8", build: "842")
        let best = SparkleAppcastSource.bestItem(
            for: app, from: cotEditorItems, osVersion: "26.6.0")
        #expect(best?.version == "843")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best))
            == .updateAvailable(latest: "7.0.9"))
    }

    /// An app whose marketing version never moves — Amp shipped ten builds called
    /// `1.0` in a day — must still be offered its new build. Equal marketing is not
    /// a downgrade, and this is the case where treating it as one would take the
    /// app's ONLY comparison away.
    ///
    /// Mutation: widen `isMarketingDowngrade` to `!= .orderedDescending` → the
    /// frozen-marketing app never updates again.
    @Test func aFrozenMarketingVersionStillUpdates() {
        let app = InstalledApp(
            name: "Amp", bundleID: "com.example.amp",
            shortVersion: "1.0", buildVersion: "10",
            path: URL(fileURLWithPath: "/Applications/Amp.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
        let remote = RemoteVersion(
            shortVersion: "1.0", version: "11", marketingMatchesBundle: true,
            downloadURL: URL(string: "https://example.com/11.zip"), sourceName: "Sparkle")
        #expect(UpdateChecker.evaluate(installed: app, remote: remote)
            == .updateAvailable(latest: "1.0"))
    }

    /// Being AHEAD of your own feed is ordinary — a vendor pulls a release, or
    /// trims the build you are running — and those rows read "up to date" beside
    /// the feed's newest entry. Simulated over all 13 Sparkle feeds this Mac reads,
    /// with the installed build trimmed out of each in turn, that shape hit 12
    /// (app, version) pairs: Bartender 6.6.2 against a feed topping out at 6.6.1,
    /// six DuoPaste betas, Ghostty, IINA, MonitorControl, Rectangle, Surge. The
    /// feed's newest entry must still be NAMED for all of them, because nil means
    /// `.unknown`, which claims no source covers the app at all.
    ///
    /// Mutation: return nil instead of the head when everything is a downgrade →
    /// eight of thirteen real feeds lose their version readout.
    @Test func aCopyAheadOfItsFeedKeepsItsUpToDateRow() {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>6.6.1</title><sparkle:version>661000</sparkle:version><sparkle:shortVersionString>6.6.1</sparkle:shortVersionString>
            <enclosure url="https://example.com/661000.zip" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
        </channel></rss>
        """
        let app = InstalledApp(
            name: "Bartender 6", bundleID: "com.surteesstudios.Bartender",
            shortVersion: "6.6.2", buildVersion: "662000",
            path: URL(fileURLWithPath: "/Applications/Bartender 6.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
        let best = SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(feed.utf8)), osVersion: "26.6.0")
        #expect(best?.shortVersionString == "6.6.1")
        #expect(UpdateChecker.evaluate(installed: app, remote: sparkleRemote(best)) == .upToDate)
    }

    /// Ghostty publishes its tip builds with a commit hash and a date where the
    /// marketing version goes: `663205b5 (2024-12-20)`. Tokenized as a version its
    /// leading run is the number 663205, so EVERY real release reads as older than
    /// it — a tip copy would be offered nothing, ever, and the row would be
    /// indistinguishable from an app with no updates.
    ///
    /// Mutation: drop the whitespace test from `comparableMarketingVersion` →
    /// 1.3.2 stops being an update for a tip copy.
    @Test func aLabelShapedVersionIsNeverComparedAsOne() {
        let app = InstalledApp(
            name: "Ghostty", bundleID: "com.mitchellh.ghostty",
            shortVersion: "663205b5 (2024-12-20)", buildVersion: "8346",
            path: URL(fileURLWithPath: "/Applications/Ghostty.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
        let remote = RemoteVersion(
            shortVersion: "1.3.2", version: "15300", marketingMatchesBundle: true,
            downloadURL: URL(string: "https://example.com/1.3.2.zip"), sourceName: "Sparkle")
        #expect(UpdateChecker.evaluate(installed: app, remote: remote)
            == .updateAvailable(latest: "1.3.2"))
    }

    /// `Character.isNumber` is a Unicode property, so a full-width `１.０.０` would
    /// be accepted as version-shaped and then compared scalar-wise against ASCII
    /// digits — which orders it above every real release, silently and forever. No
    /// feed publishes one; rejecting it costs nothing.
    ///
    /// Mutation: drop `allSatisfy(\.isASCII)` → this update disappears.
    @Test func aFullWidthVersionIsNotComparedAgainstAnASCIIOne() {
        let app = InstalledApp(
            name: "Widescreen", bundleID: "com.example.widescreen",
            shortVersion: "１.０.０", buildVersion: "10",
            path: URL(fileURLWithPath: "/Applications/Widescreen.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
        let remote = RemoteVersion(
            shortVersion: "1.0.1", version: "11", marketingMatchesBundle: true,
            downloadURL: URL(string: "https://example.com/11.zip"), sourceName: "Sparkle")
        #expect(UpdateChecker.evaluate(installed: app, remote: remote)
            == .updateAvailable(latest: "1.0.1"))
    }

    /// Fork's feed states no `sparkle:shortVersionString` at all — its marketing
    /// string lives in `sparkle:version` — and CotEditor's own feed states one on
    /// twelve items and not on the thirteenth, so a feed that mixes the two is not
    /// hypothetical. Reaching for `shortVersionString ?? version` would compare a
    /// BUILD field against a marketing one, the namespace mistake
    /// `VersionComparator`'s pair API exists to prevent.
    ///
    /// Here the head states only a build (70) and the copy's marketing version is a
    /// year (2026.1), so that substitution reads the head as a downgrade and steps
    /// off it onto a LOWER build.
    ///
    /// Mutation: read `item.shortVersionString ?? item.version` in
    /// `SparkleAppcastSource.isMarketingDowngrade` → 65 is named instead of 70.
    @Test func aBuildNumberNeverStandsInForAMarketingVersion() {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>next</title><sparkle:version>70</sparkle:version>
            <enclosure url="https://example.com/70.zip" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
          <item><title>2026.5</title><sparkle:version>65</sparkle:version><sparkle:shortVersionString>2026.5</sparkle:shortVersionString>
            <enclosure url="https://example.com/65.zip" sparkle:edSignature="s" length="1" type="application/octet-stream" /></item>
        </channel></rss>
        """
        let app = InstalledApp(
            name: "Calver", bundleID: "com.example.calver",
            shortVersion: "2026.1", buildVersion: "62",
            path: URL(fileURLWithPath: "/Applications/Calver.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
        let best = SparkleAppcastSource.bestItem(
            for: app, from: SparkleAppcastParser.parse(Data(feed.utf8)), osVersion: "26.6.0")
        #expect(best?.version == "70")
    }

    /// A source whose `shortVersion` is not the bundle's own string must not be
    /// second-guessed — that is what `marketingMatchesBundle` is for, and both
    /// shapes it protects are live.
    ///
    /// `XcodeReleasesSource` composes a display label, "27.0 beta 6" against an
    /// installed "27.0", and says in its own comment that the pair is not
    /// comparable. Mozilla's pre-release probes are the sharper case: the endpoint
    /// names `155.0b5` while the bundle on disk says `155.0`, and a prerelease tag
    /// sorts BELOW the release it leads — so every beta and nightly build reads as
    /// a downgrade, with no whitespace or label shape to give it away.
    ///
    /// Mutation: apply the marketing test regardless of `marketingMatchesBundle` →
    /// the Mozilla half goes red here, and `MozillaPreReleaseTests` goes red for
    /// all seven real pre-release trains. (The Xcode half is protected twice over —
    /// the flag AND the label shape — so it survives that mutation alone; it is
    /// here because it is the source whose own comment predicted this.)
    @Test func aSourceThatDoesNotSpeakTheBundlesVersionsIsNotSecondGuessed() {
        let xcode = InstalledApp(
            name: "Xcode", bundleID: "com.apple.dt.Xcode",
            shortVersion: "27.0", buildVersion: "27A5194q",
            path: URL(fileURLWithPath: "/Applications/Xcode-beta.app"),
            isMASApp: false, sparkleFeedURL: nil)
        // The label really does read as a downgrade — that is the point.
        #expect(VersionComparator.compare("27.0 beta 6", "27.0") == .orderedAscending)
        #expect(UpdateChecker.evaluate(installed: xcode, remote: RemoteVersion(
            shortVersion: "27.0 beta 6", version: "27A5241x",
            downloadURL: nil, sourceName: "XcodeReleases"))
            == .updateAvailable(latest: "27.0 beta 6"))

        // Mozilla's shape, in the bundle build namespace its own suite covers with
        // the real BuildIDs: the marketing string alone says backwards.
        let firefox = InstalledApp(
            name: "Firefox", bundleID: "org.mozilla.firefox",
            shortVersion: "155.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Firefox.app"),
            isMASApp: false, sparkleFeedURL: nil)
        #expect(VersionComparator.compare("155.0b5", "155.0") == .orderedAscending)
        #expect(UpdateChecker.evaluate(installed: firefox, remote: RemoteVersion(
            shortVersion: "155.0b5", version: "101",
            downloadURL: nil, sourceName: "Vendor"))
            == .updateAvailable(latest: "155.0b5"))
    }

    /// Refusing to OFFER a release is not pretending it does not exist. The whole
    /// source, not the pure selection: the withheld entry has to come back as the
    /// row's version readout, with its notes and its timeline entry, and only its
    /// STATUS held down. Returning nil instead would land the row on `.unknown` —
    /// "no source covers this app, nothing was tried" — for an app whose feed we
    /// had just read and parsed.
    ///
    /// Mutations: return nil when everything is a downgrade → no version, no
    /// notes, no history; filter the downgrades out of `usableItems` instead of
    /// stepping over them → the history loses 7.0.9.
    @Test func theRefusedReleaseIsStillNamedWithItsNotesAndItsDate() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedProtocol.self]
        let source = SparkleAppcastSource(session: URLSession(configuration: config))

        let app = cotEditor(short: "7.1.0-beta.3", build: "840")
        let remote = try #require(try await source.latestVersion(for: app))
        #expect(remote.shortVersion == "7.0.9")
        #expect(remote.marketingMatchesBundle)
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
        #expect(remote.releaseHistory.contains { $0.version == "7.0.9" })

        // A stable copy on the same feed still gets the same release as an update.
        let stable = try #require(
            try await source.latestVersion(for: cotEditor(short: "7.0.8", build: "842")))
        #expect(stable.version == "843")
    }

    /// Swap one item's version fields, keeping the rest of the real feed.
    private static func feed(
        replacing short: String, withShort newShort: String, build: String, minOS: String
    ) -> String {
        cotEditorFeed
            .replacingOccurrences(
                of: "<sparkle:shortVersionString>\(short)</sparkle:shortVersionString>",
                with: "<sparkle:shortVersionString>\(newShort)</sparkle:shortVersionString>")
            .replacingOccurrences(of: "<sparkle:version>730</sparkle:version>", with: "<sparkle:version>\(build)</sparkle:version>")
            .replacingOccurrences(of: "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>", with: "<sparkle:minimumSystemVersion>\(minOS)</sparkle:minimumSystemVersion>")
    }

    private final class FeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(SparkleMarketingDowngradeTests.cotEditorFeed.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
