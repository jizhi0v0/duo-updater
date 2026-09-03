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

@Test func parseReturnsNilForADashedCalendarDayNeverAFabricatedMidnight() {
    // #239: "2026-08-31" IS a real, parseable date (Eudic's <pubDate> uses this
    // shape) — but `parse` must not hand it back as a plain `Date`, because every
    // existing caller (SparkleAppcastSource et al.) treats a non-nil `parse`
    // result as trustworthy to the minute. Day-only values only ever reach a
    // caller through `parseWithPrecision`, tagged `.day`.
    #expect(ReleaseDate.parse("2026-08-31") == nil)
    #expect(ReleaseDate.parse("  2026-08-31\n") == nil)
}

// MARK: - parseWithPrecision

@Test func parseWithPrecisionReadsADashedCalendarDayAsDayPrecision() {
    let parsed = ReleaseDate.parseWithPrecision("2026-08-31")
    #expect(parsed?.date == Date(timeIntervalSince1970: 1_788_134_400))
    #expect(parsed?.precision == .day)
    // Whitespace-trimming matches `parse`.
    #expect(ReleaseDate.parseWithPrecision("  2026-08-31\n")?.date
        == Date(timeIntervalSince1970: 1_788_134_400))
}

@Test func parseWithPrecisionAgreesWithParseOnEveryMinutePreciseShape() {
    // ISO8601 (with/without fraction), zone-less ISO, RFC822: `parseWithPrecision`
    // must read the same instant as `parse`, tagged `.minute` — the two can never
    // be allowed to answer "is this parseable?" differently.
    for raw in [
        "2026-06-24T17:07:24Z", "2026-06-24T17:07:24.512Z",
        "2026-08-14T22:50:24.042387", "2026-08-14T22:50:24",
        "Wed, 24 Jun 2026 17:07:24 +0000", "Wed, 24 Jun 2026 17:07:24 GMT",
        "1782320844",
    ] {
        let viaParse = ReleaseDate.parse(raw)
        let viaPrecision = ReleaseDate.parseWithPrecision(raw)
        #expect(viaParse != nil, "\(raw)")
        #expect(viaPrecision?.date == viaParse, "\(raw)")
        #expect(viaPrecision?.precision == .minute, "\(raw)")
    }
}

@Test func parseWithPrecisionReadsABareEightDigitCalendarDateAsDayPrecision() {
    // `parse("20260614")` already returns a plain `Date` (pre-existing, #222) —
    // unchanged here. But it is exactly as day-only as the dashed spelling, so
    // `parseWithPrecision` tags it `.day` too, for any future caller that reaches
    // this shape through the precision-aware entry point.
    let parsed = ReleaseDate.parseWithPrecision("20260614")
    #expect(parsed?.date == Date(timeIntervalSince1970: 1_781_395_200))
    #expect(parsed?.precision == .day)
    // A 13-digit millisecond epoch is a real instant, not a bare day.
    #expect(ReleaseDate.parseWithPrecision("1750785600000")?.precision == .minute)
}

@Test func parseWithPrecisionRejectsExactlyWhatParseRejects() {
    for raw in ["2026-02-29", "2026-13-01", "2026-8-31", "26-08-31",
                "2026-08-31junk", "２０２６-０８-３１", "not a date", "", "   "] {
        #expect(ReleaseDate.parseWithPrecision(raw) == nil, "\(raw)")
        #expect(ReleaseDate.parse(raw) == nil, "\(raw)")
    }
    #expect(ReleaseDate.parseWithPrecision(nil) == nil)
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

@Test func onlyABareDecimalCountsAsNumeric() {
    // Everything Double(String) accepts that is not a bare decimal falls through
    // to the textual formatters, which reject it — never a 1970 or non-finite Date.
    for raw in ["nan", "NaN", "infinity", "inf", "-inf", "1e9", "0x1p60",
                "-1782320844", "+1782320844", "1782320844.", ".5", "1.2.3",
                "2026", "١٧٨٢٣٢٠٨٤٤", "１７８２３２０８４４"] {
        #expect(ReleaseDate.parse(raw) == nil, "\(raw)")
    }
}

/// The predicate itself, called directly. `parse` cannot show whether it is
/// right: `UInt64("١٧٨٢٣٢٠٨٤٤")` is nil anyway, so a version of `isDigitRun`
/// that accepted digits in any script would leave every case above still green.
/// The byte test matters because the calendar-date branch counts *bytes*, and
/// four Arabic-Indic digits are also eight of them.
@Test func theNumericPredicatesAreASCIIOnlyAndAllowOneFraction() {
    #expect(ReleaseDate.isDigitRun("20260614"))
    #expect(!ReleaseDate.isDigitRun("١٧٨٢"), "Arabic-Indic digits are not ASCII digits")
    #expect(!ReleaseDate.isDigitRun("２０２６"), "nor are full-width ones")
    #expect(!ReleaseDate.isDigitRun("1782320844.0"), "a fraction is not a digit run")
    #expect(!ReleaseDate.isDigitRun(""))
    #expect("١٧٨٢".utf8.count == 8, "the shape the byte-counting branch has to survive")
    #expect(ReleaseDate.date(fromDigits: "١٧٨٢") == nil)
    // `displayDate` calls `date(fromDigits:)` directly, so its own guard has to
    // hold. This is the input that proves it does: `UInt64("+1750785600")` is
    // 1750785600 — Swift's integer initialiser takes a leading plus — so without
    // the guard a signed epoch reads as an in-window date. Delete the guard and
    // this is the only expectation that goes red.
    #expect(UInt64("+1750785600") == 1_750_785_600, "the reason the guard exists")
    #expect(ReleaseDate.date(fromDigits: "+1750785600") == nil)

    #expect(ReleaseDate.isNumericRun("1782320844"))
    #expect(ReleaseDate.isNumericRun("1782320844.0"))
    for bad in ["", ".", "1.", ".1", "1.2.3", "-1", "1e9", "nan", "١٧٨٢.0"] {
        #expect(!ReleaseDate.isNumericRun(bad), "\(bad)")
    }
}

/// A clock read as a float prints its fraction: Python's `time.time()` gives
/// `1750785600.0`, and `Double(String)` used to read that correctly. It is the
/// one shape the digit-run rule would otherwise have taken away, so it is pinned
/// — the fraction is carried, not dropped.
@Test func aSecondsEpochMayCarryAFraction() {
    #expect(ReleaseDate.parse("1750785600.0") == Date(timeIntervalSince1970: 1_750_785_600))
    #expect(ReleaseDate.parse("1750785600.5") == Date(timeIntervalSince1970: 1_750_785_600.5))
    // The window is judged on the whole part, and only seconds take a fraction:
    // a fractional millisecond is not a shape anything emits.
    #expect(ReleaseDate.parse("631151999.9") == nil, "below the window")
    #expect(ReleaseDate.parse("1750785600000.5") == nil, "milliseconds stay whole")
    #expect(ReleaseDate.parse("20260614.0") == nil, "a calendar date does not take a fraction")
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
