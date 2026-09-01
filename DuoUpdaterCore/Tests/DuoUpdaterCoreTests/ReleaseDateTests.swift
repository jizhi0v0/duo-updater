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

// MARK: - Bare digit runs

/// A bare number used to be handed to `TimeInterval(String)` and read as epoch
/// seconds, whatever its shape. `yyyyMMdd` came out in 1970, a millisecond epoch
/// in the year 57450, and "nan"/"infinity" produced a non-finite `Date` that then
/// went into sorts and formatters. Only an all-digit string is numeric now, and a
/// numeric string is a calendar date, seconds, milliseconds, or nothing.

@Test func eightDigitsIsACalendarDateNotAnEpoch() {
    // 2026-06-14T00:00:00Z — python: datetime(2026,6,14,tzinfo=utc).timestamp()
    #expect(ReleaseDate.parse("20260614") == Date(timeIntervalSince1970: 1_781_395_200))
    // Eight digits that are not a date are nothing, not 20-odd million seconds.
    #expect(ReleaseDate.parse("99999999") == nil)
    #expect(ReleaseDate.parse("20261301") == nil, "month 13")
    #expect(ReleaseDate.parse("20260230") == nil, "non-lenient: no 30 Feb")
}

@Test func thirteenDigitsIsMilliseconds() {
    // 2025-06-24T17:20:00Z — python: datetime.fromtimestamp(1750785600000/1000, utc)
    #expect(ReleaseDate.parse("1750785600000") == Date(timeIntervalSince1970: 1_750_785_600))
}

@Test func secondsAndMillisecondWindowsAre1990To2100() {
    // [1990-01-01, 2100-01-01) in seconds: 631152000 ..< 4102444800.
    #expect(ReleaseDate.parse("631152000") == Date(timeIntervalSince1970: 631_152_000))
    #expect(ReleaseDate.parse("631151999") == nil)
    #expect(ReleaseDate.parse("4102444799") == Date(timeIntervalSince1970: 4_102_444_799))
    #expect(ReleaseDate.parse("4102444800") == nil)
    // The same window ×1000 in milliseconds.
    #expect(ReleaseDate.parse("631152000000") == Date(timeIntervalSince1970: 631_152_000))
    #expect(ReleaseDate.parse("631151999999") == nil)
    #expect(ReleaseDate.parse("4102444799999")?.timeIntervalSince1970 == 4_102_444_799.999)
    #expect(ReleaseDate.parse("4102444800000") == nil)
    // Between the windows, and past them, is nothing.
    #expect(ReleaseDate.parse("100000000000") == nil, "12 digits, 1973 in ms")
    #expect(ReleaseDate.parse("99999999999999999999") == nil, "20 digits")
    #expect(ReleaseDate.parse("999999999999999999999") == nil, "21 digits, past UInt64")
}

@Test func onlyASCIIDigitsCountAsNumeric() {
    // Everything Double(String) accepts that is not a digit run falls through to
    // the textual formatters, which reject it — never a 1970 or non-finite Date.
    for raw in ["nan", "NaN", "infinity", "inf", "-inf", "1e9", "0x1p60",
                "1782320844.5", "-1782320844", "+1782320844", "2026", "١٧٨٢٣٢٠٨٤٤"] {
        #expect(ReleaseDate.parse(raw) == nil, "\(raw)")
    }
}

@Test func parsedDatesAreAlwaysFinite() {
    for raw in ["20260614", "1782320844", "1750785600000", "nan", "infinity", "inf",
                "1e999", "-1e999", "4102444799999", "631152000"] {
        if let date = ReleaseDate.parse(raw) {
            #expect(date.timeIntervalSince1970.isFinite, "\(raw)")
        }
    }
}

/// The same reading is what `AppcastMarkdownParser.displayDate` shows, so the
/// timeline and the rail subtitle cannot disagree about a bare number.
@Test func digitReadingIsSharedWithTheDisplayString() {
    for raw in ["20260614", "1782320844", "1750785600000", "631152000", "2026", "nan"] {
        let parsed = ReleaseDate.parse(raw)
        let shown = AppcastMarkdownParser.displayDate(from: raw)
        if let parsed {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            #expect(shown == f.string(from: parsed), "\(raw)")
        } else {
            #expect(shown == raw, "\(raw): a non-date passes through verbatim")
        }
    }
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
