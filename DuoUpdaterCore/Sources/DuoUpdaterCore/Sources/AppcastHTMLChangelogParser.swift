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
///
/// Scope, stated honestly: of the 19 live appcasts surveyed, four pass
/// `isStructured` (TablePro, Fork, TablePlus, ImageOptim) and three of those are
/// served by a `ChangelogRecipe` first, which takes precedence. **TablePro is the
/// only registry app this parser actually renders today.** The other fixtures are
/// still worth keeping as tests — they are real markup, and the next feed to lose
/// its recipe lands here — but nobody should read this file believing it is
/// carrying three vendors.
///
/// The failure mode to keep in mind while editing: this parser only produces a
/// non-nil entry when it is confident, because a non-nil entry SUPPRESSES the
/// fallback. Anything it half-understands must return nil rather than a partial
/// answer — a partial answer is invisible to the user, and silent bullet loss is
/// the bug this file was written to fix.
enum AppcastHTMLChangelogParser {

    /// Whether `html` has enough list structure to be worth converting. Requires
    /// at least one `<li>` — the one shape (`<ul>`/`<ol>` bullets, optionally
    /// grouped under `<h2>`/`<h3>`/`<h4>` section headings) this parser actually
    /// understands. Pure prose (`<p>` only, no lists) fails this and the caller
    /// keeps rendering the raw HTML through the existing fallback path.
    static func isStructured(_ html: String) -> Bool {
        let opens = count(of: #"<li\b[^>]*>"#, in: html)
        guard opens > 0 else { return false }
        // Every `<li>` must be closed. `</li>` is OPTIONAL in HTML5 and vendors do
        // omit it — ImageOptim's live appcast writes all eight of its bullets that
        // way — while the extractor below is anchored on `</li>`. All-unclosed was
        // already harmless (zero items, so `entry` returns nil and the caller falls
        // back). MIXED was not: the closed ones parse, the unclosed ones vanish, and
        // because *something* parsed there is no fallback — silently dropping
        // bullets, which is the exact bug this parser was written to fix, in a new
        // shape. Balanced-or-bail sends the whole body to the existing HTML path,
        // which renders all of them (less prettily) rather than some of them.
        return opens == count(of: #"</li\s*>"#, in: html)
    }

    private static func count(of pattern: String, in s: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return 0 }
        return regex.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    /// Convert one appcast item's `<description>` HTML into a `Changelog.Entry`.
    /// Walks `<h2>`/`<h3>`/`<h4>` headings and `<li>` items in document order —
    /// same shape `StructuredChangelogDecoder.decodeWeChatDevTools` uses for its
    /// category titles — folding each heading in as its own line immediately
    /// before the items under it, so "Added" / "Fixed" style sections land in the
    /// right place in the flattened `items` list instead of getting shuffled or
    /// dropped. Readable text between those matches (a bare sentence or `<p>`
    /// outside the lists) is kept too, one item per paragraph, in place.
    ///
    /// Returns nil (never throws) when `isStructured` is false, `version` is
    /// empty, or no `<li>` survives cleaning — the caller falls back to the raw
    /// HTML path in every one of those cases.
    static func entry(html: String, version: String, date: String?) -> Changelog.Entry? {
        guard !version.isEmpty, isStructured(html) else { return nil }

        // `</h\1>` — a BACKREFERENCE, so the closing level must match the opening
        // one. With `</h[234]>` a heading whose closer is mistyped (TablePlus's live
        // feed really does write `<h2>…<h2>`) matches greedily up to the next
        // heading close of ANY level, swallowing every `<li>` in between into one
        // glued blob. Requiring the same level means a mistyped closer simply
        // doesn't match: the heading is dropped and its items survive, which is the
        // right way to fail.
        let pattern = #"<h([234])[^>]*>(.*?)</h\1>|<li[^>]*>(.*?)</li>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var items: [String] = []
        var pendingHeading: String?
        var cursor = 0
        var listItems = 0

        // Text the vendor wrote OUTSIDE any heading or `<li>` — a bare sentence or
        // `<p>` before, between or after the lists. Rectangle's 2.0.2 opens with
        // the one sentence that describes 2.0.2 and then repeats 2.0's bullets, so
        // reading only the matches showed 2.0's notes under 2.0.2's number. Kept in
        // document order, a heading still pending goes first (the text sits under
        // it). `gapParagraphs` drops what is chrome rather than content.
        func takeGap(upTo end: Int) {
            guard end > cursor else { return }
            for text in gapParagraphs(ns.substring(with: NSRange(location: cursor, length: end - cursor))) {
                if let heading = pendingHeading {
                    items.append(heading)
                    pendingHeading = nil
                }
                items.append(text)
            }
        }

        for match in matches {
            takeGap(upTo: match.range.location)
            cursor = match.range.location + match.range.length

            let headingRange = match.range(at: 2)   // group 1 is the heading level
            let itemRange = match.range(at: 3)

            if headingRange.location != NSNotFound {
                let raw = ns.substring(with: headingRange)
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
            listItems += 1
        }
        takeGap(upTo: ns.length)

        // At least one real `<li>` must have survived: kept prose alone is the
        // "one bullet per paragraph" shape the type doc says the fallback renders
        // better.
        guard listItems > 0 else { return nil }
        return Changelog.Entry(version: version, date: date, items: items)
    }

    // MARK: - Internals

    /// Block-level tags a gap (the HTML between two heading/`<li>` matches) is cut
    /// into paragraphs on. `<br>` is deliberately absent: a line break inside one
    /// paragraph joins with a space, as it does inside an `<li>`.
    private static let gapBlockRegex = try? NSRegularExpression(
        pattern: #"<\s*/?\s*(?:p|div|ul|ol|li|h[1-6]|hr|blockquote|section|table|tr|pre)\b[^>]*>"#,
        options: [.caseInsensitive])

    /// The readable paragraphs in a gap, in order. Dropped, because they are
    /// chrome rather than notes:
    /// - whitespace and empty paragraphs (`cleanInline` returns nil);
    /// - a paragraph with no letter or digit OUTSIDE its links — Rectangle's
    ///   `<p><a href="…/releases/tag/v2.0">Details</a></p>` and bare
    ///   `<a href="…/versions">Recent version history</a>` on every item, and
    ///   TablePlus's/Proxyman's `<h2><a href='…'>Older change logs.</a><h2>`
    ///   footers (mistyped closer, so they reach here instead of the heading arm).
    ///   A link inside a sentence keeps the sentence; a properly closed heading
    ///   that is a link never reaches here at all;
    /// - a "Release date: …" line, for the same reason the heading arm drops it.
    private static func gapParagraphs(_ gap: String) -> [String] {
        guard let gapBlockRegex else { return [] }
        let marked = gapBlockRegex.stringByReplacingMatches(
            in: gap, range: NSRange(gap.startIndex..., in: gap), withTemplate: "\u{0}")
        return marked.split(separator: "\u{0}").compactMap { piece in
            let raw = String(piece)
            guard let cleaned = cleanInline(raw), !looksLikeDateOnly(cleaned) else { return nil }
            var outsideLinks = raw
            if let anchorRegex {
                outsideLinks = anchorRegex.stringByReplacingMatches(
                    in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            }
            let rest = ChangelogExtractor.decodeHTMLEntities(
                ChangelogExtractor.stripHTMLElements(outsideLinks))
            guard rest.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
            return cleaned
        }
    }

    /// Matches the common Sparkle boilerplate "Release date: 12 August 2026" (and
    /// bare "Release date" with no value) so it can be dropped as metadata rather
    /// than shown as a change line.
    private static func looksLikeDateOnly(_ cleaned: String) -> Bool {
        cleaned.range(of: #"^release date\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Compiled once: `cleanInline` runs per `<li>`, and a long appcast
    /// `<description>` has dozens. Same reasoning — and same thread-safety — as
    /// `ChangelogExtractor.elementBreakRegex`.
    private static let anchorRegex = try? NSRegularExpression(
        pattern: #"<a\b[^>]*>([\s\S]*?)</a>"#, options: [.caseInsensitive])

    /// Clean one captured heading/`<li>` body for plain-text display: flatten
    /// `<a href="…">text</a>` to just `text` (no bracket/paren markup, no bare
    /// URL — `Changelog.itemSyntax` for this path is `.plain`, so anything left
    /// over would show up literally), strip whatever tags remain (`<code>`,
    /// `<strong>`, …) while keeping their inner text, decode HTML entities, and
    /// collapse whitespace. nil when nothing readable is left.
    private static func cleanInline(_ raw: String) -> String? {
        var s = raw
        if let anchorRegex {
            s = anchorRegex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }
        // Known HTML elements only — NOT a blind `<[^>]+>` sweep. TablePro's notes
        // carry `` `USE <database>` `` and `` `<unsupported: type>` `` as literal
        // text inside CDATA, and a blind sweep deletes exactly the identifier the
        // sentence is about ("SQL Server: `USE ` switches DB"). The recipe this
        // parser replaced protected them with `stripTags: false`; an appcast
        // description has no such switch, so the stripper has to be the careful one.
        // Block-level elements become a space in the process, so `<li>a<br>b</li>`
        // no longer glues into "ab".
        s = ChangelogExtractor.stripHTMLElements(s)
        // Shared with the recipe extractor rather than reimplemented: this file
        // originally carried its own copies because the batch that made these
        // internal had not landed in that worktree yet. `decodeHTMLEntities` (not
        // `decodeEntities`) on purpose — the JSON \uXXXX pass in the latter is for
        // json-mode feeds and would rewrite a literal \uXXXX a vendor typed.
        s = ChangelogExtractor.decodeHTMLEntities(s)
        s = ChangelogExtractor.collapseWhitespace(s)
        return s.isEmpty ? nil : s
    }
}
