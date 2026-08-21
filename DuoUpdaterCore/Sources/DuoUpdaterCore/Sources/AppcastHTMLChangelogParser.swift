import Foundation

/// Turns a Sparkle `<description>` body — inline HTML notes, the common case for
/// appcast feeds that don't ship `<markdownDescription>` — into one
/// `Changelog.Entry`, so those feeds get the same native rendering
/// `AppcastMarkdownParser` already gives Markdown-only feeds (Surge).
///
/// This exists because `NSAttributedString`'s HTML importer (the fallback path,
/// `ReleaseNotesText` in the app target) has three visible problems that all trace
/// to the same root: it's rendering raw HTML with no injected font/style, so it
/// falls back to Times, mis-indents `<ul>` bullets, and — the real bug — the
/// chunk-splitter that feeds it can cut a `<ul>` in half when a release's notes
/// have no blank line to split on, silently dropping bullets from the back half.
/// Converting to a native `Changelog` sidesteps the whole path: no HTML importer,
/// no chunking, no splitting.
///
/// Only a minority of vendor feeds are worth this: one written as list markup
/// (`<li>`), which is the shape a native bulleted view can render faithfully. A
/// feed that's just prose paragraphs (`<p>…</p>`, no lists) would come out as one
/// bullet per paragraph — worse than the web-view/attributed-string fallback,
/// which at least renders the paragraphs as paragraphs — so `isStructured` gates
/// entry into this whole path and `entry(html:version:date:)` returns nil (never
/// throws) whenever it isn't confident the result is an improvement.
enum AppcastHTMLChangelogParser {

    /// Whether `html` has enough list structure to be worth converting. Requires
    /// at least one `<li>` — the one shape (`<ul>`/`<ol>` bullets, optionally
    /// grouped under `<h2>`/`<h3>`/`<h4>` section headings) this parser actually
    /// understands. Pure prose (`<p>` only, no lists) fails this and the caller
    /// keeps rendering the raw HTML through the existing fallback path.
    static func isStructured(_ html: String) -> Bool {
        html.range(of: #"<li[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Convert one appcast item's `<description>` HTML into a `Changelog.Entry`.
    /// Walks `<h2>`/`<h3>`/`<h4>` headings and `<li>` items in document order —
    /// same shape `StructuredChangelogDecoder.decodeWeChatDevTools` uses for its
    /// category titles — folding each heading in as its own line immediately
    /// before the items under it, so "Added" / "Fixed" style sections land in the
    /// right place in the flattened `items` list instead of getting shuffled or
    /// dropped.
    ///
    /// Returns nil (never throws) when `isStructured` is false, `version` is
    /// empty, or nothing survives cleaning — the caller falls back to the raw
    /// HTML path in every one of those cases.
    static func entry(html: String, version: String, date: String?) -> Changelog.Entry? {
        guard !version.isEmpty, isStructured(html) else { return nil }

        let pattern = #"<h[234][^>]*>(.*?)</h[234]>|<li[^>]*>(.*?)</li>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var items: [String] = []
        var pendingHeading: String?

        for match in matches {
            let headingRange = match.range(at: 1)
            let itemRange = match.range(at: 2)

            if headingRange.location != NSNotFound {
                let raw = ns.substring(with: headingRange)
                // A heading whose entire body is one link is vendor-page chrome —
                // "Older change logs." / "Bug report." (TablePlus appends both as
                // trailing `<h2>`s) — not a section title, so it's dropped outright
                // rather than becoming a pending heading (and never overwrites one).
                guard !isPureLinkHeading(raw) else { continue }
                guard let cleaned = cleanInline(raw), !cleaned.isEmpty else { continue }
                // A "Release date: …" heading is boilerplate metadata the entry
                // already carries in its own `date` field (from `pubDate`); folding
                // it into `items` would just duplicate the date the header already
                // shows. Skipped without disturbing any heading already pending.
                guard !looksLikeDateOnly(cleaned) else { continue }
                pendingHeading = cleaned
                continue
            }

            guard itemRange.location != NSNotFound,
                  let cleaned = cleanInline(ns.substring(with: itemRange)), !cleaned.isEmpty
            else { continue }

            if let heading = pendingHeading {
                items.append(heading)
                pendingHeading = nil
            }
            items.append(cleaned)
        }

        guard !items.isEmpty else { return nil }
        return Changelog.Entry(version: version, date: date, items: items)
    }

    // MARK: - Internals

    /// True when, after trimming whitespace, the whole heading body is a single
    /// `<a>…</a>` — i.e. it exists to link somewhere, not to title a group of
    /// change lines.
    private static func isPureLinkHeading(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // `[\s\S]` (rather than `.dotMatchesLineSeparators`, which
        // `String.CompareOptions` doesn't have) so a link title that happens to
        // wrap a line still matches.
        return trimmed.range(
            of: #"^<a\b[^>]*>[\s\S]*</a>$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Matches the common Sparkle boilerplate "Release date: 12 August 2026" (and
    /// bare "Release date" with no value) so it can be dropped as metadata rather
    /// than shown as a change line.
    private static func looksLikeDateOnly(_ cleaned: String) -> Bool {
        cleaned.range(of: #"^release date\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Clean one captured heading/`<li>` body for plain-text display: flatten
    /// `<a href="…">text</a>` to just `text` (no bracket/paren markup, no bare
    /// URL — `Changelog.itemSyntax` for this path is `.plain`, so anything left
    /// over would show up literally), strip whatever tags remain (`<code>`,
    /// `<strong>`, …) while keeping their inner text, decode HTML entities, and
    /// collapse whitespace. nil when nothing readable is left.
    private static func cleanInline(_ raw: String) -> String? {
        var s = raw
        s = s.replacingOccurrences(
            of: #"<a\b[^>]*>([\s\S]*?)</a>"#, with: "$1",
            options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(
            of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = collapseWhitespace(s)
        return s.isEmpty ? nil : s
    }

    /// Decode the handful of HTML entities vendor notes actually use: the five
    /// XML predefined entities, `&nbsp;`, and numeric decimal/hex escapes
    /// (`&#39;`, `&#x27;`). Deliberately not a full HTML5 entity table — appcast
    /// `<description>` bodies are simple release notes, not arbitrary web pages.
    private static func decodeEntities(_ s: String) -> String {
        var result = s
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        if let hexRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            result = replace(in: result, using: hexRegex) { hex in
                guard let scalarValue = UInt32(hex, radix: 16),
                      let scalar = Unicode.Scalar(scalarValue) else { return nil }
                return String(Character(scalar))
            }
        }
        if let decRegex = try? NSRegularExpression(pattern: "&#([0-9]+);") {
            result = replace(in: result, using: decRegex) { dec in
                guard let scalarValue = UInt32(dec), let scalar = Unicode.Scalar(scalarValue) else {
                    return nil
                }
                return String(Character(scalar))
            }
        }
        return result
    }

    /// Run `regex` over `text`, replacing each match with `transform` applied to
    /// its first capture group; a match whose transform returns nil is left as-is
    /// (never dropped or corrupted).
    private static func replace(
        in text: String, using regex: NSRegularExpression, transform: (String) -> String?
    ) -> String {
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { continue }
            let captured = ns.substring(with: match.range(at: 1))
            guard let replacement = transform(captured) else { continue }
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            result += replacement
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    /// Collapse runs of whitespace (including the `&#xA;`-decoded newlines/tabs
    /// XML entity-escaping introduces) to single spaces and trim the ends.
    private static func collapseWhitespace(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
