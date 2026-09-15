import Testing
import Foundation
@testable import DuoUpdaterCore

/// `sparkle:maximumSystemVersion` — the vendor saying "this build is not for an
/// OS this new".
///
/// It is the only field any source we read can use to express "we have not
/// adapted to macOS 27 yet", which makes it the exact shape of the problem this
/// work started from: a build offered to, and downloaded by, a Mac the vendor
/// has already said it does not serve. Sparkle's own resolver honours it
/// (`SPUAppcastItemStateResolver -isMaximumOperatingSystemVersionOK:`) and
/// Sparkle ships a dedicated user-facing string for the case ("…your macOS
/// version is too new for this update"), so a feed that sets it means it.
///
/// Rarely set in practice: none of the 14 reachable feeds among one machine's
/// installed Sparkle apps declared one (measured 2026-08-30). Which is exactly
/// why it needs a test rather than a live check — there is no real feed to point
/// at, and an unimplemented field whose absence is silent stays unimplemented.
@Suite struct SparkleMaximumSystemVersionTests {

    private static func feed(min: String?, max: String?) -> String {
        let minLine = min.map { "<sparkle:minimumSystemVersion>\($0)</sparkle:minimumSystemVersion>" } ?? ""
        let maxLine = max.map { "<sparkle:maximumSystemVersion>\($0)</sparkle:maximumSystemVersion>" } ?? ""
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>2.0</title>
              <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
              <sparkle:version>200</sparkle:version>
              \(minLine)
              \(maxLine)
              <enclosure url="https://example.com/Subject-2.0.dmg" sparkle:version="200" length="100"/>
            </item>
          </channel>
        </rss>
        """
    }

    private static let app = InstalledApp(
        name: "Subject", bundleID: "com.example.subject", shortVersion: "1.0",
        buildVersion: "100", path: URL(fileURLWithPath: "/Applications/Subject.app"),
        isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))

    private static func usable(min: String?, max: String?, on os: String) -> [SparkleAppcastItem] {
        let items = SparkleAppcastParser.parse(Data(feed(min: min, max: max).utf8))
        return SparkleAppcastSource.usableItems(for: app, from: items, osVersion: os)
    }

    @Test func theElementIsParsedAtAll() {
        let items = SparkleAppcastParser.parse(Data(Self.feed(min: "14.0", max: "26.99").utf8))
        #expect(items.first?.maximumSystemVersion == "26.99")
        #expect(items.first?.minimumSystemVersion == "14.0")
    }

    /// The shape that motivated this was first seen on obdev's Little Snitch feed
    /// (`final` capped at "26.99" while `nightly` carried "27.99", read live
    /// 2026-08-30) — but that feed is a bespoke plist read by `VendorProbeSource`,
    /// which never reaches this code. Its own guard is
    /// `VendorProbeOSBoundTests`; this suite tests the Sparkle path on a synthetic
    /// item, because no reachable real appcast declared a ceiling when it was
    /// written. A macOS 27 Mac must not be offered a build capped at 26.99.
    @Test func aBuildCappedBelowTheHostIsNotOffered() {
        #expect(Self.usable(min: "14.0", max: "26.99", on: "27.0.0").isEmpty)
        #expect(Self.usable(min: nil, max: "15.0", on: "26.6.0").isEmpty)
    }

    /// Mirrors Sparkle's own `!= NSOrderedAscending`: the cap is inclusive, so a
    /// Mac exactly at the cap still gets the build. Off-by-one here would hide an
    /// update from every Mac on the newest supported OS — the largest group.
    @Test func aHostExactlyAtTheCapStillGetsTheBuild() {
        #expect(Self.usable(min: "14.0", max: "27.0.0", on: "27.0.0").count == 1)
        #expect(Self.usable(min: "14.0", max: "27.1", on: "27.0.0").count == 1)
    }

    /// A feed that sets no cap — every real feed measured — must behave exactly
    /// as it did before this element was parsed. This is the regression that
    /// matters: the change touches the filter every Sparkle app goes through.
    @Test func aFeedWithNoCapIsUnaffected() {
        #expect(Self.usable(min: "14.0", max: nil, on: "27.0.0").count == 1)
        #expect(Self.usable(min: nil, max: nil, on: "27.0.0").count == 1)
        #expect(Self.usable(min: nil, max: "", on: "27.0.0").count == 1)
        // And the floor still does its own job, unchanged.
        #expect(Self.usable(min: "28.0", max: nil, on: "27.0.0").isEmpty)
    }

    /// A capped OLD item beside an uncapped NEW one — the standard use of the
    /// field (route legacy Macs to a legacy build), and the shape every other
    /// test here misses by using a one-item feed.
    ///
    /// Pins the consequence nobody had written down: `usableItems` also feeds
    /// `structuredChangelog` and `releaseHistory`, so a capped release does not
    /// merely go un-offered — it disappears from the release timeline too. That
    /// matches what the architecture filter already does deliberately, and is
    /// asserted here so a future change to either has to face it.
    @Test func aCappedLegacyItemIsDroppedFromTheHistoryToo() {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
              <sparkle:version>200</sparkle:version>
              <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.com/Subject-2.0.dmg" sparkle:version="200" length="100"/>
            </item>
            <item>
              <sparkle:shortVersionString>1.9</sparkle:shortVersionString>
              <sparkle:version>190</sparkle:version>
              <sparkle:maximumSystemVersion>15.0</sparkle:maximumSystemVersion>
              <enclosure url="https://example.com/Subject-1.9.dmg" sparkle:version="190" length="100"/>
            </item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(feed.utf8))
        #expect(items.count == 2, "premise: the feed really has both items")

        // A modern Mac: the capped legacy item is gone entirely, history included.
        let modern = SparkleAppcastSource.usableItems(for: Self.app, from: items, osVersion: "27.0.0")
        #expect(modern.count == 1)
        #expect(modern.first?.shortVersionString == "2.0")

        // A legacy Mac: the new item is below its floor, the old one is within
        // its cap — which is exactly the routing the vendor wrote the cap for.
        let legacy = SparkleAppcastSource.usableItems(for: Self.app, from: items, osVersion: "14.0.0")
        #expect(legacy.count == 1)
        #expect(legacy.first?.shortVersionString == "1.9")
    }

    /// Both bounds together, which is how obdev writes it: inside the window the
    /// build is offered, outside it in either direction it is not.
    @Test func theWindowIsClosedAtBothEnds() {
        #expect(Self.usable(min: "14.0", max: "26.99", on: "13.7.1").isEmpty)
        #expect(Self.usable(min: "14.0", max: "26.99", on: "26.6.0").count == 1)
        #expect(Self.usable(min: "14.0", max: "26.99", on: "27.0.0").isEmpty)
    }

    // MARK: - Saying why the feed offers nothing (#634 part 3)

    private static func refusal(min: String?, max: String?, on os: String) -> OSWindowRefusal? {
        let items = SparkleAppcastParser.parse(Data(feed(min: min, max: max).utf8))
        return SparkleAppcastSource.osWindowRefusal(for: app, from: items, osVersion: os)?.refusal
    }

    /// A feed emptied by the vendor's window names the refusal instead of going
    /// quiet — the release this copy is missing, which bound refused it, and the
    /// host it was refused on. Before, this was a nil and the row a "no source"
    /// dash that a ceiling never cleared.
    ///
    /// Mutation: ignore `honouringOSWindow` in `usableItems` (always honour) →
    /// the window-free list is empty too, and both answers are nil → red.
    @Test func aFeedEmptiedByTheWindowNamesTheRefusal() throws {
        let ceiling = try #require(Self.refusal(min: "14.0", max: "26.99", on: "27.0.0"))
        #expect(ceiling.bound == .ceiling(maximum: "26.99"))
        #expect(ceiling.version == "2.0")
        #expect(ceiling.hostOS == "27.0.0")

        let floor = try #require(Self.refusal(min: "28.0", max: nil, on: "27.0.0"))
        #expect(floor.bound == .floor(minimum: "28.0"))
    }

    /// Only the WINDOW is set aside. A feed that offers nothing because of its
    /// channel is a feed with nothing for this copy — naming a capped release on a
    /// channel the user never joined would blame the wrong thing.
    ///
    /// Mutation: evaluate the head of `items` instead of the window-free usable
    /// list → the beta item is named → red.
    @Test func aFeedEmptiedByTheChannelIsNotARefusal() {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:shortVersionString>2.0b1</sparkle:shortVersionString>
              <sparkle:version>201</sparkle:version>
              <sparkle:channel>beta</sparkle:channel>
              <sparkle:maximumSystemVersion>26.99</sparkle:maximumSystemVersion>
              <enclosure url="https://example.com/Subject-2.0b1.dmg" sparkle:version="201" length="100"/>
            </item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(feed.utf8))
        #expect(items.count == 1, "premise: the item parsed")
        #expect(SparkleAppcastSource.osWindowRefusal(for: Self.app, from: items, osVersion: "27.0.0") == nil)
    }

    /// A ceiling spelled without a digit is a ceiling the vendor did not state.
    /// The inline check this replaced had no such guard, and `VersionComparator`
    /// ranks a text token below every number — so `any` hid the build from every
    /// Mac. Now it goes through `OSWindowRefusal.evaluate`, which guards it.
    ///
    /// Mutation: drop the ceiling's digit guard in `OSWindowRefusal.evaluate` → red.
    @Test func aTextCeilingDoesNotHideTheBuild() {
        #expect(Self.usable(min: nil, max: "any", on: "27.0.0").count == 1)
    }

    /// The whole source, so the refusal is known to reach `UpdateChecker` and not
    /// just to be computable. `latestVersion` reads the host's macOS itself, so the
    /// cap is set where no host can be: "10.0" is below this app's deployment
    /// target (macOS 14), so every Mac that can run the test is above it.
    ///
    /// Mutation: `return nil` in place of `throw OSWindowRefused(refusal)` in
    /// `latestVersion(for:)` → red.
    @Test func latestVersionThrowsTheRefusalRatherThanNil() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CappedFeedProtocol.self]
        let source = SparkleAppcastSource(session: URLSession(configuration: config))
        #expect(!FileManager.default.fileExists(atPath: Self.app.path.path))

        do {
            let remote = try await source.latestVersion(for: Self.app)
            Issue.record("expected OSWindowRefused, got \(String(describing: remote))")
        } catch let refused as OSWindowRefused {
            #expect(refused.refusal.bound == .ceiling(maximum: "10.0"))
            #expect(refused.refusal.version == "2.0")
        } catch {
            Issue.record("expected OSWindowRefused, got \(error)")
        }
    }

    /// The window only speaks when it left NOTHING to offer. A capped newest item
    /// beside an older one this Mac can run is Sparkle's own routing — the older
    /// item is the answer, and no refusal is thrown. `latestVersion` reads the host
    /// itself, so the cap is "10.0", below every Mac that can run the test.
    ///
    /// Mutation: compute the refusal before `guard let best` and throw whenever
    /// the feed's head is refused → red.
    @Test func aCappedHeadWithAnOlderUsableItemIsAnsweredNotRefused() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CappedHeadFeedProtocol.self]
        let source = SparkleAppcastSource(session: URLSession(configuration: config))
        let remote = try await source.latestVersion(for: Self.app)
        #expect(remote?.shortVersion == "1.5")
    }

    static let cappedHeadFeed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
          <sparkle:version>200</sparkle:version>
          <sparkle:maximumSystemVersion>10.0</sparkle:maximumSystemVersion>
          <enclosure url="https://example.com/Subject-2.0.dmg" sparkle:version="200" length="100"/>
        </item>
        <item>
          <sparkle:shortVersionString>1.5</sparkle:shortVersionString>
          <sparkle:version>150</sparkle:version>
          <enclosure url="https://example.com/Subject-1.5.dmg" sparkle:version="150" length="100"/>
        </item>
      </channel>
    </rss>
    """

    private final class CappedHeadFeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(SparkleMaximumSystemVersionTests.cappedHeadFeed.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class CappedFeedProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self, didLoad: Data(SparkleMaximumSystemVersionTests.feed(min: nil, max: "10.0").utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
