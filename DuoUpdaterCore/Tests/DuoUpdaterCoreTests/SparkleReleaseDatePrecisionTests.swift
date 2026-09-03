import Testing
import Foundation
@testable import DuoUpdaterCore

/// #239: date-only vendor timestamps ("2026-08-31", no time of day) are real
/// feed data — Eudic's real appcast ships exactly this shape
/// (`<pubDate>2026-08-31</pubDate>`, fixture in `ChangelogExtractorTests.swift`)
/// — but must never be read as a to-the-minute `publishedAt`: that field is what
/// `ReleaseTimelineStore` plots on the release-habits heatmap, and a fabricated
/// midnight there is a lie about when the vendor shipped, not merely an
/// approximation of it.
///
/// `SparkleAppcastSource` is the only source this fix touches — it is the one
/// with a real fixture proving the date-only shape reaches it. The other four
/// sources (`AlcoveUpdateSource`, `GitHubReleasesSource`, `ElectronManifestSource`,
/// `VendorProbeSource`) keep calling `ReleaseDate.parse`, whose contract is
/// unchanged: nil for a bare calendar day, exactly as before this PR.
///
/// The invariant under test, twice over — once on the pure routing function and
/// once through the real XML parser end to end: a day-precision date routes to
/// `vendorDay` and NEVER to `publishedAt`.

@Test func publishedFieldsRoutesAMinutePreciseDateToPublishedAtOnly() {
    let fields = SparkleAppcastSource.publishedFields(from: "Wed, 24 Jun 2026 17:07:24 +0000")
    #expect(fields.publishedAt == Date(timeIntervalSince1970: 1_782_320_844))
    #expect(fields.vendorDay == nil)
}

@Test func publishedFieldsRoutesADayOnlyDateToVendorDayNeverPublishedAt() {
    // The exact shape Eudic's appcast ships.
    let fields = SparkleAppcastSource.publishedFields(from: "2026-08-31")
    #expect(
        fields.publishedAt == nil,
        "a day-only pubDate must never reach publishedAt — that would fabricate a midnight the vendor never stated")
    #expect(fields.vendorDay == Date(timeIntervalSince1970: 1_788_134_400))
}

@Test func publishedFieldsIsNilForUnparseableOrMissingDates() {
    let missing = SparkleAppcastSource.publishedFields(from: nil)
    #expect(missing.publishedAt == nil)
    #expect(missing.vendorDay == nil)
    let garbage = SparkleAppcastSource.publishedFields(from: "not a date")
    #expect(garbage.publishedAt == nil)
    #expect(garbage.vendorDay == nil)
}

/// A small appcast with three items — the eudic-shaped date-only release, a
/// normal RFC822-dated one, and one with no `<pubDate>` at all — parsed through
/// the real `SparkleAppcastParser`, not hand-built `SparkleAppcastItem` values.
/// This is what proves the routing survives the XML round trip, not just the
/// pure string-in/tier-out function above.
private let mixedPrecisionFeed = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>26.9.0</title>
      <sparkle:version>26.9.0</sparkle:version>
      <sparkle:shortVersionString>26.9.0</sparkle:shortVersionString>
      <enclosure url="https://example.com/App-26.9.0.zip" length="1000"
                 type="application/octet-stream"/>
      <pubDate>2026-08-31</pubDate>
    </item>
    <item>
      <title>4.9.0</title>
      <sparkle:version>4.9.0</sparkle:version>
      <sparkle:shortVersionString>4.9.0</sparkle:shortVersionString>
      <enclosure url="https://example.com/App-4.9.0.zip" length="1000"
                 type="application/octet-stream"/>
      <pubDate>Wed, 24 Jun 2026 17:07:24 +0000</pubDate>
    </item>
    <item>
      <title>1.7.0</title>
      <sparkle:version>1.7.0</sparkle:version>
      <sparkle:shortVersionString>1.7.0</sparkle:shortVersionString>
      <enclosure url="https://example.com/App-1.7.0.zip" length="1000"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""

@Test func releaseHistorySplitsEntriesByThePrecisionTheFeedActuallyStated() throws {
    let items = SparkleAppcastParser.parse(Data(mixedPrecisionFeed.utf8))
    #expect(items.count == 3)

    let history = SparkleAppcastSource.releaseHistory(from: items)
    // The undated item produces no entry at all — never a fabricated one.
    #expect(history.map(\.version) == ["26.9.0", "4.9.0"])

    let dayOnly = try #require(history.first { $0.version == "26.9.0" })
    #expect(dayOnly.publishedAt == nil)
    #expect(dayOnly.vendorDay == Date(timeIntervalSince1970: 1_788_134_400))

    let minutePrecise = try #require(history.first { $0.version == "4.9.0" })
    #expect(minutePrecise.publishedAt == Date(timeIntervalSince1970: 1_782_320_844))
    #expect(minutePrecise.vendorDay == nil)
}

/// Mutation guard: if the day/minute split in `publishedFields` were ever
/// collapsed back to "always publishedAt" (the exact regression this PR fixes),
/// this must fail. Verified by hand during review: temporarily changing
/// `publishedFields`'s `.day` case to `return (parsed.date, nil)` turns this red
/// (`fields.publishedAt == nil` fails) while every other test in this file still
/// compiles — i.e. the assertion is load-bearing, not decorative.
@Test func dayPrecisionNeverReachesPublishedAtEvenWhenItIsTheOnlyDateOnTheRelease() {
    let fields = SparkleAppcastSource.publishedFields(from: "2026-01-01")
    #expect(fields.publishedAt == nil)
    #expect(fields.vendorDay != nil)
}
