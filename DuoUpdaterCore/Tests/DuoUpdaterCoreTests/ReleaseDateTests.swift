import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ReleaseDate` turns the many ways feeds spell a publish timestamp into a real
/// `Date`. The whole point of the release timeline is the *time of day*, so the
/// load-bearing assertions are that the time component survives, not just the day.

@Test func parsesGitHubISO8601ToTheSecond() {
    // GitHub/Alcove `published_at`.
    let date = ReleaseDate.parse("2026-06-24T17:07:24Z")
    #expect(date != nil)
    // The exact instant must round-trip — including the time of day.
    #expect(date == Date(timeIntervalSince1970: 1_782_320_844))
}

@Test func parsesISO8601WithFractionalSeconds() {
    let date = ReleaseDate.parse("2026-06-24T17:07:24.512Z")
    #expect(date != nil)
    // Floors to the same whole second (fractional part preserved within the Date).
    let whole = ReleaseDate.parse("2026-06-24T17:07:24Z")!
    #expect(abs(date!.timeIntervalSince(whole) - 0.512) < 0.001)
}

@Test func parsesRFC822WithNumericZone() {
    // Sparkle `<pubDate>` RSS standard, the most common spelling.
    let date = ReleaseDate.parse("Wed, 24 Jun 2026 17:07:24 +0000")
    #expect(date == Date(timeIntervalSince1970: 1_782_320_844))
}

@Test func parsesRFC822WithNamedZoneAndOffset() {
    // GMT named zone, and a non-UTC offset both resolve to the right instant.
    let gmt = ReleaseDate.parse("Wed, 24 Jun 2026 17:07:24 GMT")
    #expect(gmt == Date(timeIntervalSince1970: 1_782_320_844))
    // +0200 means the same wall clock is two hours earlier in UTC.
    let plus2 = ReleaseDate.parse("Wed, 24 Jun 2026 19:07:24 +0200")
    #expect(plus2 == Date(timeIntervalSince1970: 1_782_320_844))
}

@Test func parsesBareUnixEpoch() {
    // Surge's appcast ships a bare epoch in <pubDate>.
    let date = ReleaseDate.parse("1782320844")
    #expect(date == Date(timeIntervalSince1970: 1_782_320_844))
}

@Test func returnsNilForEmptyOrGarbage() {
    #expect(ReleaseDate.parse(nil) == nil)
    #expect(ReleaseDate.parse("") == nil)
    #expect(ReleaseDate.parse("   ") == nil)
    #expect(ReleaseDate.parse("not a date") == nil)
}

@Test func trimsSurroundingWhitespace() {
    let date = ReleaseDate.parse("  2026-06-24T17:07:24Z  ")
    #expect(date == Date(timeIntervalSince1970: 1_782_320_844))
}
