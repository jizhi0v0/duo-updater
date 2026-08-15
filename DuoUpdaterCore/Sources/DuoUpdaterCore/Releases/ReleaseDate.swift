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
///   - a bare Unix epoch, e.g. "1750785600" (Surge's appcast does this)
public enum ReleaseDate {

    /// Convert a raw feed date string to a `Date`, or nil when it's empty or in a
    /// format we don't recognize. Never throws — an unparseable date just means
    /// "no authoritative release time", which the timeline records as absent.
    public static func parse(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        // A bare number is a Unix epoch (seconds). Check this first: "1750785600"
        // would otherwise fall through every textual formatter and return nil.
        if let epoch = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: epoch)
        }

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
