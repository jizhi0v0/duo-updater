import Foundation

/// Turns a Sparkle `<markdownDescription>` body into a flat list of change lines
/// for one `Changelog.Entry`.
///
/// Unlike `GitHubMarkdownParser` — which is bullet-only because GitHub bodies are
/// essentially bullet lists — vendor appcast notes (e.g. Surge's) mix section
/// headings, prose paragraphs, bullets, and fenced code. Dropping everything but
/// bullets would lose most of the content, so this parser keeps prose and folds
/// headings in as their own lines, preserving the author's order. The detail view
/// renders each returned string as one bulleted item.
enum AppcastMarkdownParser {

    /// Extract the change lines from a Markdown notes body, in document order.
    static func items(from markdown: String) -> [String] {
        var out: [String] = []
        var inFence = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks: keep the inner lines verbatim, drop the ``` fences.
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence {
                if !line.isEmpty { out.append(line) }
                continue
            }

            if line.isEmpty { continue }

            // Heading: strip the leading #'s and keep the title as its own line.
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { out.append(stripInline(heading)) }
                continue
            }

            // Bullet: `- `, `* `, `+ ` (top-level only; indented sub-bullets fold
            // into the parent line below via the prose path, kept verbatim).
            if let marker = ["- ", "* ", "+ "].first(where: { line.hasPrefix($0) }) {
                let body = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { out.append(stripInline(body)) }
                continue
            }

            // Prose paragraph line.
            out.append(stripInline(line))
        }
        return out
    }

    /// Normalize an item's publish date for display. Sparkle feeds spell `pubDate`
    /// several ways; Surge uses a bare Unix epoch. Convert a bare digit run that
    /// reads as a date to `yyyy-MM-dd`; pass anything else through verbatim (the
    /// renderer already formats ISO8601 and shows other strings as-is). nil stays
    /// nil.
    ///
    /// What a digit run means — seconds, milliseconds, `yyyyMMdd`, or nothing —
    /// is `ReleaseDate.date(fromDigits:)`'s call, not a second copy of it here:
    /// this string sits next to the timeline entry built from the same `pubDate`,
    /// and the two must not read one number two ways. Digits that are not a date
    /// pass through like any other string this does not understand.
    static func displayDate(from pubDate: String?) -> String? {
        guard let raw = pubDate?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        if let date = ReleaseDate.date(fromDigits: raw) {
            return epochFormatter.string(from: date)
        }
        return raw
    }

    // MARK: - Internals

    /// Strip the lightweight inline emphasis markers (`**`, `*`, `` ` ``) that
    /// would otherwise render literally in the plain-text item view. Links and
    /// emoji are left intact — they read fine as written.
    private static func stripInline(_ text: String) -> String {
        var s = text
        for token in ["**", "`"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static let epochFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
