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

            // Bullet: `- `, `* `, `+ `. Indentation is trimmed above, so a
            // sub-bullet reaches this branch too and is emitted as its own item
            // rather than folded into the parent line.
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

    /// One version's notes as a `Changelog.Entry`, or nil when the body has none.
    ///
    /// The Workbench draws `markdown` — the body as written, noise taken out
    /// (`renderableMarkdown`) — so the author's own headings, nesting and code show
    /// as such. `items` is the flat reading above, headings included as lines,
    /// kept for text-only consumers and as the view's fallback when Foundation
    /// parses no blocks.
    static func entry(from markdown: String, version: String, date: String?) -> Changelog.Entry? {
        let notes = items(from: markdown)
        guard !notes.isEmpty else { return nil }
        return Changelog.Entry(
            version: version, date: date, items: notes,
            markdown: renderableMarkdown(from: markdown, version: version))
    }

    /// The body with the lines not worth showing taken out, for rendering as
    /// Markdown; nil when nothing is left. Everything else stays byte-for-byte —
    /// blank lines and indentation included — because they ARE the block structure
    /// the renderer reads.
    ///
    /// Taken out, with `GitHubMarkdownParser`'s own predicates so the two paths
    /// agree on what is noise:
    ///   - a boilerplate section (`## New Contributors`, `## Full Changelog`, …),
    ///     heading and body, up to the next heading;
    ///   - a `**Full Changelog**: <compare url>` line — every Osaurus entry ends
    ///     with one;
    ///   - a line that is only an image or badge, only a URL, or a checksum;
    ///   - a heading that restates this entry's own version (TablePro opens every
    ///     body with `# What's New in TablePro 0.76.1`), which the rail beside the
    ///     notes already shows.
    /// Nothing inside a fenced code block is judged: it is shown as the vendor
    /// wrote it, unless its whole section is boilerplate.
    static func renderableMarkdown(from markdown: String, version: String) -> String? {
        var kept: [String] = []
        var inFence = false
        var inSkippedSection = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                if !inSkippedSection { kept.append(rawLine) }
                continue
            }
            if inFence {
                if !inSkippedSection { kept.append(rawLine) }
                continue
            }
            if let heading = GitHubMarkdownParser.headingRawText(of: line) {
                let lowered = heading.lowercased()
                inSkippedSection = GitHubMarkdownParser.skippedSectionKeywords
                    .contains { lowered.contains($0) }
                if restatesVersion(heading, version) { continue }
            }
            if inSkippedSection { continue }
            let lowered = line.lowercased()
            if GitHubMarkdownParser.skippedSectionKeywords.contains(where: { lowered.hasPrefix("**\($0)") })
                || GitHubMarkdownParser.isImageOnly(line)
                || GitHubMarkdownParser.isBareURL(line)
                || GitHubMarkdownParser.isChecksum(line) {
                continue
            }
            kept.append(rawLine)
        }
        let body = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
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
        // The same trim as `ReleaseDate.parse`. With `.whitespaces` here and
        // `.whitespacesAndNewlines` there, a pubDate carrying a newline was a date
        // to the timeline and a raw string to the rail — the exact disagreement
        // the shared reading below exists to prevent.
        guard let raw = pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let date = ReleaseDate.date(fromDigits: raw) {
            return epochFormatter.string(from: date)
        }
        return raw
    }

    // MARK: - Internals

    /// `version` appears in `heading` as a whole version — not as the tail of a
    /// longer number, so `6.0` is not found in `macOS 26.0` or `6.0.1`.
    private static func restatesVersion(_ heading: String, _ version: String) -> Bool {
        guard !version.isEmpty else { return false }
        let pattern = #"(?<![0-9.])"# + NSRegularExpression.escapedPattern(for: version) + #"(?![0-9]|\.[0-9])"#
        return heading.range(of: pattern, options: .regularExpression) != nil
    }

    /// Strip the lightweight inline emphasis markers (`**`, `` ` ``) that would
    /// otherwise render literally in the plain-text item view; a single `*` is
    /// left alone. Links and emoji are left intact — they read fine as written.
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
