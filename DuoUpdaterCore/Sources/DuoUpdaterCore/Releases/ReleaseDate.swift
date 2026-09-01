import Foundation

/// Parses the many ways update feeds spell a release timestamp into a real
/// `Date` — preserving the time of day, not just the calendar day.
///
/// This is deliberately separate from `AppcastMarkdownParser.displayDate`, which
/// only produces a *display string* and passes most inputs through verbatim. The
/// release timeline needs an actual `Date` so it can sort, dedupe, and (later)
/// answer "what time of day does this vendor ship?" — a question that dies the
/// moment we round to a bare day. Three wire formats cover every source we feed
/// from here (Sparkle `<pubDate>`, GitHub/Alcove `published_at`):
///   - RFC822, e.g. "Wed, 24 Jun 2026 17:07:24 +0000" (RSS standard)
///   - ISO8601, e.g. "2026-06-24T17:07:24Z" (GitHub, Alcove), with or without
///     fractional seconds
///   - a bare digit run: a Unix epoch in seconds, e.g. "1750785600" (Surge's
///     appcast does this), in milliseconds, or a `yyyyMMdd` calendar date — told
///     apart by `date(fromDigits:)`, whose rules are documented there
public enum ReleaseDate {

    /// Convert a raw feed date string to a `Date`, or nil when it's empty or in a
    /// format we don't recognize. Never throws — an unparseable date just means
    /// "no authoritative release time", which the timeline records as absent.
    public static func parse(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        // A bare digit run is decided here and never handed on: none of the
        // textual formatters below accepts one, and digits that are not a date
        // must come back nil rather than as a guess. This used to be
        // `TimeInterval(trimmed)`, which also accepts "nan", "infinity", "1e9",
        // "0x1p60" and a sign, and read every one of them as epoch seconds.
        if isDigitRun(trimmed) { return date(fromDigits: trimmed) }

        // ISO8601 with fractional seconds (e.g. "...:24.123Z"), then without.
        if let date = isoWithFraction.date(from: trimmed) { return date }
        if let date = isoPlain.date(from: trimmed) { return date }

        // ISO8601 shape with NO zone at all, e.g. "2026-08-14T22:50:24.042387" —
        // what a `datetime.utcnow().isoformat()` backend emits. `ISO8601DateFormatter`
        // rejects these outright, so they used to read as "no release time".
        // Read as UTC: for the endpoint that prompted this (Claude's rollout API)
        // the stamp sits 39s after the artifact's `Last-Modified: ... GMT`, which
        // only lines up if the clock is UTC. A vendor that meant local time would
        // land the release up to a day off in the timeline — so only feed
        // zone-less stamps in from sources where that has been checked.
        for formatter in zonelessISOFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        // RFC822, the RSS pubDate standard. Try the common spellings vendors use.
        for formatter in rfc822Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        return nil
    }

    // MARK: - Bare digit runs

    /// True when `s` is one or more ASCII digits and nothing else. This — not
    /// "does `Double` accept it" — is what makes a feed value numeric.
    public static func isDigitRun(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }

    /// The one reading of a bare digit run, shared by `parse` and by
    /// `AppcastMarkdownParser.displayDate` so the release timeline and the
    /// changelog rail cannot disagree about what a number means. The policy:
    ///
    ///   - Only an all-ASCII-digit string is numeric. No sign, no decimal point,
    ///     no exponent, no hex, no "nan"/"inf": those return nil here and, from
    ///     `parse`, fall through to the textual formatters, which reject them.
    ///   - Exactly 8 digits is a bare calendar date, `yyyyMMdd` (UTC, en_US_POSIX,
    ///     non-lenient) — never an epoch. "20260614" is 2026-06-14, and eight
    ///     digits that are not a date ("99999999") are nil.
    ///   - A value inside [1990-01-01, 2100-01-01) read as **seconds** is seconds.
    ///   - A value inside the same window read as **milliseconds** (×1000, i.e.
    ///     12–13 digits) is milliseconds.
    ///   - Anything else numeric is nil. Never 1970, never the year 57450, and
    ///     never a non-finite `Date`: the value goes through `UInt64` (so more
    ///     than 20 digits is already nil) and the window caps the magnitude.
    ///
    /// The two windows do not overlap and neither overlaps 8 digits, so no digit
    /// run has two readings.
    public static func date(fromDigits digits: String) -> Date? {
        guard isDigitRun(digits) else { return nil }
        if digits.utf8.count == 8 { return yyyyMMdd.date(from: digits) }
        guard let value = UInt64(digits) else { return nil }
        if secondsWindow.contains(value) {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if millisecondsWindow.contains(value) {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }
        return nil
    }

    /// 1990-01-01T00:00:00Z ..< 2100-01-01T00:00:00Z, in seconds. Wide enough for
    /// any release a feed could truthfully describe, narrow enough that no
    /// `yyyyMMdd` (≤ 99 999 999) or millisecond value (≥ 631 152 000 000) lands in it.
    private static let secondsWindow: Range<UInt64> = 631_152_000 ..< 4_102_444_800
    /// The same window in milliseconds.
    private static let millisecondsWindow: Range<UInt64> =
        631_152_000_000 ..< 4_102_444_800_000

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.isLenient = false
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    // MARK: - Formatters

    // `nonisolated(unsafe)`: these formatters are only ever read (parsing), which
    // Foundation's date formatters are thread-safe for on modern macOS — the
    // external synchronization the compiler asks us to vouch for.
    private nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private nonisolated(unsafe) static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Zone-less ISO8601, with and without fractional seconds. `SSSSSS` covers
    /// Python's 6-digit microseconds; `DateFormatter` tolerates fewer digits.
    private nonisolated(unsafe) static let zonelessISOFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"].map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = pattern
            return f
        }
    }()

    /// RFC822 spellings seen in the wild: with and without leading weekday, and
    /// with a numeric (`+0000`) or named (`GMT`) zone.
    private nonisolated(unsafe) static let rfc822Formatters: [DateFormatter] = {
        let patterns = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = pattern
            return f
        }
    }()
}
