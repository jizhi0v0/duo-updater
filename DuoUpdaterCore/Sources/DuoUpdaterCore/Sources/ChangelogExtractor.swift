import Foundation

/// Runs a `ChangelogRecipe` against a fetched page body and produces a
/// `Changelog`. Pure and side-effect-free (no network) so the fragile,
/// format-specific bit is unit-testable against a fixture string without hitting
/// the wire — exactly like `VendorProbeRecipe.extractVersion`.
///
/// Totally defensive: an invalid pattern, a no-match, or an entry with no items
/// yields fewer entries (or nil), never a throw and never a crash. A nil/empty
/// result is the caller's signal to fall back to the embedded web page.
public enum ChangelogExtractor {

    /// Parse `text` into a `Changelog` per `recipe`, or nil when nothing usable
    /// comes out (caller then falls back to the web view).
    public static func extract(from text: String, using recipe: ChangelogRecipe) -> Changelog? {
        guard let entryRegex = compile(recipe.entryPattern) else { return nil }
        let itemRegexes = recipe.itemPatterns.compactMap(compile)
        guard !itemRegexes.isEmpty else { return nil }
        let imageRegex = recipe.imagePattern.flatMap(compile)

        let whole = NSRange(text.startIndex..., in: text)
        var entries: [Changelog.Entry] = []
        // Some pages contain their own content twice. Cursor's changelog is one:
        // the streamed document carries the whole `<main>` (and a second `</html>`)
        // a second time, so every post matches twice and the pane would list each
        // release two rows apart. Keyed on version+title because that pair is what
        // identifies a release to a reader — two entries the user cannot tell apart
        // are a duplicate whatever produced them.
        var seen: Set<String> = []

        // `enumerateMatches` lets us stop scanning the moment we've collected
        // `maxEntries`, rather than `matches(in:)` eagerly finding every block in
        // a long cumulative page (HBuilderX lists 60+ versions) only to discard
        // the tail. Entries that yield no items don't count toward the cap, so a
        // gap doesn't end the scan early — same selection as before, less work.
        entryRegex.enumerateMatches(in: text, range: whole) { match, _, stop in
            guard let match else { return }
            let title = group(match, "title", in: text)
                .map { clean($0, recipe) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let version = group(match, "version", in: text)
                .map { clean($0, recipe) } ?? ""
            guard title != nil || !version.isEmpty else { return }

            let date = group(match, "date", in: text)
                .map { clean($0, recipe) }
                .flatMap { $0.isEmpty ? nil : $0 }

            // Items come from the `body` group when present, else the whole entry.
            let bodyText = group(match, "body", in: text)
                ?? group(match, nil, in: text)
                ?? ""

            let noteHits = firstNonEmptyItemHits(in: bodyText, regexes: itemRegexes, recipe: recipe)
            guard !noteHits.isEmpty else { return }
            let items = noteHits.map(\.text)

            // Interleave images with the notes by document position — but only when
            // the recipe asks for images AND this entry has at least one. Otherwise
            // `content` stays empty and the renderer just bullets `items` (unchanged
            // for every text-only recipe).
            let imageBlocks = imageRegex.map { imageHits(in: bodyText, regex: $0) } ?? []
            let content: [Changelog.Entry.Block] = imageBlocks.isEmpty
                ? []
                : (noteHits.map { ($0.location, Changelog.Entry.Block.note($0.text)) }
                    + imageBlocks.map { ($0.location, .image($0.url)) })
                    .sorted { $0.0 < $1.0 }
                    .map(\.1)

            guard seen.insert("\(version)\u{1}\(title ?? "")").inserted else { return }
            entries.append(.init(
                title: title, version: version, date: date,
                items: items, content: content))
            // For a newest-first page the cap can halt the scan early (we already
            // have the recent ones). For an oldest-first page (`newestLast`) the
            // recent entries are at the END, so we must read them all, then reverse
            // and cap below — no early stop here.
            if !recipe.newestLast, let cap = recipe.maxEntries, entries.count >= cap {
                stop.pointee = true
            }
        }

        // Oldest-first sources: flip to newest-first and keep the recent `maxEntries`
        // from that (new) end.
        if recipe.newestLast {
            entries.reverse()
            if let cap = recipe.maxEntries, entries.count > cap {
                entries = Array(entries.prefix(cap))
            }
        }

        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    // MARK: - Internals

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive])
    }

    /// Try each item regex in order; return the cleaned matches of the first that
    /// produces any, each tagged with its match location so the caller can order it
    /// against images. Each match contributes its `item` group, else group 1, else
    /// the whole match.
    private static func firstNonEmptyItemHits(
        in body: String,
        regexes: [NSRegularExpression],
        recipe: ChangelogRecipe
    ) -> [(location: Int, text: String)] {
        let range = NSRange(body.startIndex..., in: body)
        for regex in regexes {
            var hits: [(location: Int, text: String)] = []
            for match in regex.matches(in: body, range: range) {
                let raw = group(match, "item", in: body)
                    ?? group(match, nil, in: body)
                    ?? ""
                let cleaned = clean(raw, recipe)
                if cleaned.count >= recipe.minItemLength {
                    hits.append((match.range.location, cleaned))
                }
            }
            if !hits.isEmpty { return hits }
        }
        return []
    }

    /// Collect illustration images from an entry body, each tagged with its match
    /// location. Each match yields its `image` group (else group 1, else whole
    /// match); only absolute `http(s)` URLs are kept, and duplicates are dropped
    /// while preserving order. HTML entities in the URL (e.g. `&amp;`) are decoded.
    private static func imageHits(
        in body: String, regex: NSRegularExpression
    ) -> [(location: Int, url: URL)] {
        let range = NSRange(body.startIndex..., in: body)
        var hits: [(location: Int, url: URL)] = []
        var seen = Set<URL>()
        for match in regex.matches(in: body, range: range) {
            guard let raw = group(match, "image", in: body)
                ?? group(match, nil, in: body) else { continue }
            let decoded = decodeEntities(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let url = URL(string: decoded), let scheme = url.scheme,
                  scheme == "http" || scheme == "https", seen.insert(url).inserted else { continue }
            hits.append((match.range.location, url))
        }
        return hits
    }

    /// Extract a capture group's substring. `name` = a named group; nil = capture
    /// group 1 if present, else the whole match. Returns nil if absent/unmatched.
    private static func group(
        _ match: NSTextCheckingResult, _ name: String?, in text: String
    ) -> String? {
        let nsRange: NSRange
        if let name {
            nsRange = match.range(withName: name)
        } else {
            nsRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        }
        guard nsRange.location != NSNotFound,
              let r = Range(nsRange, in: text) else { return nil }
        return String(text[r])
    }

    /// Strip tags (optional), decode entities (optional), collapse whitespace, trim.
    private static func clean(_ raw: String, _ recipe: ChangelogRecipe) -> String {
        var s = raw
        if recipe.stripTags { s = stripTags(s) }
        if recipe.decodeEntities {
            // `.json` feeds carry JSON string escapes (`\"`, `\\`, `\n`, `\uXXXX`)
            // the HTML entity decoder doesn't understand — unescape them first so a
            // quote or newline inside a note renders as text, not as `\"`. Gated to
            // `.json` on purpose: in HTML prose a literal `\n` (a Windows path, say)
            // must stay literal, so the broad HTML path is left untouched.
            if recipe.mode == .json { s = decodeJSONStringEscapes(s) }
            s = decodeEntities(s)
            // The body was escaped markup (an RSS <description>), so the decode
            // just turned `&lt;a href=…&gt;` back into real tags, and prose
            // entities that were double-escaped (`&amp;rsquo;`) into single ones.
            // Strip once more and decode once more, or the rendered note shows raw
            // HTML and literal `&rsquo;`. See `escapedMarkup`.
            if recipe.escapedMarkup {
                if recipe.stripTags { s = stripTags(s) }
                s = decodeEntities(s)
            }
        }
        if recipe.markdownSource { s = unwrapMarkdownInline(s) }
        return collapseWhitespace(s)
    }

    /// Drop the backticks around Markdown inline code, keeping the code text.
    /// `` 通过`CLI pack cancel`取消打包 `` → `通过CLI pack cancel取消打包`, which is
    /// what the same note looked like when it came from HTML and `stripTags`
    /// removed the `<code>` wrapper.
    ///
    /// ONE pass, alternating double- then single-backtick spans — not two passes.
    /// Two passes is the obvious shape and it is wrong: unwrapping ``` ``a `b` c`` ```
    /// to ``` a `b` c ``` leaves inner backticks that the second pass then eats,
    /// turning the escape hatch for code-containing-a-backtick into `a b c`. A
    /// single alternation consumes each span once and never revisits what it
    /// produced. (Caught by a test, not by reading — the two-pass version looked
    /// right.)
    ///
    /// A lone unpaired backtick stays put: both alternatives are confined to one
    /// line, so an unterminated span simply doesn't match. The `$1$2` template
    /// works because a non-participating group substitutes as empty.
    static func unwrapMarkdownInline(_ s: String) -> String {
        flattenMarkdownLinks(unwrapMarkdownInlineCode(s))
    }

    /// `[text](url)` → `text`. The URL sub-pattern allows one level of nested
    /// parens (a Wikipedia-style `..._(bar)` URL) so the match consumes the whole
    /// link instead of leaving a dangling `)`. Same expression
    /// `StructuredChangelogDecoder.bulletItems` already uses.
    static func flattenMarkdownLinks(_ s: String) -> String {
        s.replacingOccurrences(
            of: #"\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)"#, with: "$1",
            options: .regularExpression)
    }

    static func unwrapMarkdownInlineCode(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "``([^\n]*?)``|`([^`\n]+?)`")
        else { return s }
        return regex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: (s as NSString).length),
            withTemplate: "$1$2")
    }

    /// Turn line-breaking tags into spaces, then drop every remaining tag. Done in
    /// that order so `<br>`/`</p>`/`</li>` don't glue adjacent words together.
    /// Internal (not `private`) so `StructuredChangelogDecoder` can reuse it for
    /// vendor HTML that arrives already JSON-unescaped by `Decodable`.
    /// Element names a real HTML changelog uses. Anything not on this list is
    /// left alone as text — which is the whole point (see `stripHTMLElements`).
    private static let htmlElementNames = [
        "a", "abbr", "article", "aside", "audio", "b", "blockquote", "br", "button",
        "caption", "cite", "code", "col", "colgroup", "dd", "del", "details", "div",
        "dl", "dt", "em", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hr", "i", "iframe", "img", "input", "ins", "kbd",
        "li", "main", "mark", "nav", "ol", "p", "picture", "pre", "q", "s", "samp",
        "section", "small", "source", "span", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul",
        "var", "video",
    ]

    /// Strip only *known* HTML elements, turning the block-level ones into a space
    /// so adjacent text doesn't glue together, and leave every other angle-bracket
    /// run as literal text.
    ///
    /// The difference from `stripTags` is the second half: that one finishes with a
    /// blind `<[^>]+>` sweep, which eats anything bracket-shaped. In a *recipe* that
    /// is fine — a recipe reading a page that deliberately shows markup as text sets
    /// `stripTags: false` and opts out wholesale. An appcast `<description>` has no
    /// such switch: it is one body mixing real markup with prose, and TablePro's
    /// notes contain `` `USE <database>` `` and `` `<unsupported: type>` `` inside
    /// CDATA as literal text. The recipe this parser replaced protected them with
    /// `stripTags: false`; a blind sweep here renders "SQL Server: `USE ` switches
    /// DB", silently deleting the identifier the sentence is about.
    ///
    /// Not a full parser and not trying to be: an unknown element (a vendor's
    /// `<custom-tag>`) survives as text, which is the safe direction — visible
    /// noise beats invisible deletion.
    static func stripHTMLElements(_ s: String) -> String {
        let names = htmlElementNames.joined(separator: "|")
        var out = s
        // Block/line-breaking elements first, to a space.
        if let breaks = try? NSRegularExpression(
            pattern: #"<\s*/?\s*(?:br|p|li|div|ul|ol|tr|td|th|h[1-6])\b[^>]*>"#,
            options: [.caseInsensitive]) {
            out = breaks.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: " ")
        }
        if let rest = try? NSRegularExpression(
            pattern: #"<\s*/?\s*(?:\#(names))\b[^>]*>"#, options: [.caseInsensitive]) {
            out = rest.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out
    }

    static func stripTags(_ s: String) -> String {
        let breaks = try? NSRegularExpression(
            pattern: #"<\s*/?\s*(br|p|li|div|ul|ol)\b[^>]*>"#,
            options: [.caseInsensitive])
        var out = s
        if let breaks {
            out = breaks.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: " ")
        }
        let anyTag = try? NSRegularExpression(pattern: #"<[^>]+>"#)
        if let anyTag {
            out = anyTag.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out
    }

    /// Decode the handful of entities that actually show up in changelogs, plus
    /// numeric (`&#39;`, `&#x2019;`) escapes. Deliberately small and pure — we
    /// avoid `NSAttributedString` HTML decoding (heavy and main-thread-only).
    /// Internal (not `private`) — see `stripTags`.
    static func decodeEntities(_ s: String) -> String {
        decodeJSONUnicodeEscapes(decodeHTMLEntities(s))
    }

    /// The HTML half on its own: named entities plus numeric `&#NNN;` / `&#xHHH;`.
    /// Split out from `decodeEntities` because the JSON `\uXXXX` pass that follows
    /// it there has nothing to do with HTML — it exists for json-mode feeds whose
    /// server escapes non-ASCII. A caller working on real markup (the Sparkle
    /// appcast HTML parser) wants this half only: running the JSON pass over a
    /// vendor's prose would rewrite a literal `\uXXXX` the vendor actually typed.
    static func decodeHTMLEntities(_ s: String) -> String {
        var out = s
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
            "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”", "&times;": "×",
        ]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric escapes: &#NNN; (decimal) and &#xHHH; (hex).
        out = decodeNumericEntities(out)
        return out
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"&#(x?[0-9a-fA-F]+);"#, options: [.caseInsensitive]) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let token = ns.substring(with: m.range(at: 1))
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            if let v = scalarValue, let scalar = Unicode.Scalar(v) {
                result.append(Character(scalar))
            } else {
                result += ns.substring(with: m.range)  // leave it untouched
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Full JSON string unescape (`\"`, `\\`, `\/`, `\n`, `\t`, `\r`, `\b`, `\f`,
    /// `\uXXXX`) in one left-to-right pass — used only for `.json`-mode feeds, where
    /// note text arrives as raw JSON string content. Single-pass over `\\(u…|.)` so
    /// an escaped backslash (`\\`) is consumed atomically and never re-interpreted.
    /// An unknown escape drops the backslash and keeps the char (lenient, like JSON).
    private static func decodeJSONStringEscapes(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        guard let regex = try? NSRegularExpression(
            pattern: #"\\(u[0-9a-fA-F]{4}|.)"#, options: [.dotMatchesLineSeparators]
        ) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let tok = ns.substring(with: m.range(at: 1))
            if tok.count == 5, tok.hasPrefix("u") || tok.hasPrefix("U"),
               let cp = UInt32(tok.dropFirst(), radix: 16), let scalar = Unicode.Scalar(cp) {
                result.append(Character(scalar))
            } else {
                switch tok {
                case "\"": result += "\""
                case "\\": result += "\\"
                case "/": result += "/"
                case "n": result += "\n"
                case "t": result += "\t"
                case "r": result += "\r"
                case "b": result += "\u{08}"
                case "f": result += "\u{0C}"
                default: result += tok  // unknown escape → keep the char, drop the `\`
                }
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func decodeJSONUnicodeEscapes(_ s: String) -> String {
        // JSON allows \/ as an escaped forward slash; normalise it first.
        var out = s.replacingOccurrences(of: "\\/", with: "/")
        guard out.contains("\\u") else { return out }
        guard let regex = try? NSRegularExpression(
            pattern: #"\\u([0-9a-fA-F]{4})"#, options: [.caseInsensitive]) else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hexStr = ns.substring(with: m.range(at: 1))
            if let codePoint = UInt32(hexStr, radix: 16),
               let scalar = Unicode.Scalar(codePoint) {
                result.append(Character(scalar))
            } else {
                result += ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        out = result
        return out
    }

    /// Internal (not `private`) — see `stripTags`.
    static func collapseWhitespace(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
