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

    /// The case that motivated this: obdev's Little Snitch feed declares its
    /// stable train tops out at "26.99" while a nightly train carries "27.99"
    /// (values read live from `sw-update.obdev.at/update-feeds/littlesnitch6.plist`,
    /// 2026-08-30 — a bespoke plist rather than an appcast, but the same claim in
    /// the same shape). A macOS 27 Mac must not be offered the capped build.
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
}
