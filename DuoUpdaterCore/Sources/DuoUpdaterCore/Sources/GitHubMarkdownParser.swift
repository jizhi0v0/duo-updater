import Foundation

/// Parses a GitHub release body (GitHub-flavored Markdown) into a structured
/// `Changelog`. Handles both hand-written bodies and the auto-generated
/// "What's Changed" format GitHub produces from pull requests.
///
/// Auto-generated bodies look like:
///   ## What's Changed
///   * Fix X by @user in https://github.com/owner/repo/pull/123
///   ## New Contributors
///   * @user made their first contribution ...
///   **Full Changelog**: https://github.com/...
///
/// Hand-written bodies use arbitrary section headings and bullet styles.
/// Both go through the same pipeline — bullets are extracted, contributor-
/// noise sections are skipped, and the "by @user in URL" suffix is stripped.
public enum GitHubMarkdownParser {

    /// Parse a single release body into a `Changelog` with one entry, or nil
    /// when the body contains no extractable bullet items.
    ///
    /// Two passes. The strict pass (original behavior) takes only top-level
    /// `-`/`*`/`+` bullets. ONLY when that finds nothing do we retry leniently —
    /// also accepting indented bullets and numbered lists, and skipping fenced code
    /// blocks. Gating the lenient pass on an empty strict result means every body
    /// that already parsed is byte-for-byte unchanged (no regression for the GitHub
    /// apps that share this parser); the lenient pass purely rescues bodies that
    /// would otherwise fall back to a raw web view — e.g. nvm's space-indented
    /// `- ` lists, or any project that writes its notes as a numbered list.
    ///
    /// A THIRD pass, prose, runs only when both bullet passes come back empty: a
    /// release whose notes are written as sentences rather than a list. Returning
    /// nil for those was a real hole — for a multi-release source it drops that
    /// version out of the rail entirely, so a user sitting on exactly that build
    /// finds no entry for their own version (Zed's `v1.5.3-pre`, "No public-facing
    /// changes in this release.", is the live case; Waku's `v0.1.9`, "See
    /// CHANGELOG.md for details.", is another). Gated the same way the lenient pass
    /// is, so no body that already parsed changes at all.
    public static func parse(body: String, version: String, date: String?) -> Changelog? {
        var items = extractItems(from: body, lenient: false)
        if items.isEmpty {
            items = extractItems(from: body, lenient: true)
        }
        if items.isEmpty {
            items = proseItems(from: body)
        }
        guard !items.isEmpty else { return nil }
        let entry = Changelog.Entry(version: version, date: date, items: items)
        // The body is Markdown and the items keep their inline syntax — say so,
        // or the renderer prints `**bold**` and `[text](url)` verbatim.
        return Changelog(entries: [entry], itemSyntax: .markdown)
    }

    // MARK: - Internals

    private static let skippedSectionKeywords = [
        "new contributors", "contributors", "full changelog",
    ]

    /// Extra headings the lenient pass skips: release bodies that aren't bullet
    /// changelogs often still carry a checksum/hash block, which we never want as
    /// "change items".
    private static let lenientExtraSkipKeywords = [
        "sha256", "sha-256", "sha1", "md5", "checksum", "hashes", "artifacts",
    ]

    /// Sentences from a release body that contains no list at all, in document
    /// order. Deliberately conservative about what it drops, because at this point
    /// the alternative is showing the user nothing:
    ///
    ///   - headings and fenced code blocks (same as the bullet passes);
    ///   - a line that is only an image or a badge — LuLu opens its notes with a
    ///     `[![](shields.io/...)](...)` sponsor banner, which as an "item" is a URL
    ///     the reader cannot use;
    ///   - a checksum: both the `🔐 Disk Image Hash (SHA256):` label line and the
    ///     `file.dmg: <64 hex>` line under it. Neither is a change.
    ///
    /// Everything else is kept verbatim, including Markdown links — the entry is
    /// emitted with `.markdown` syntax, so they render rather than showing as raw
    /// brackets.
    ///
    /// Two hard bails, both of which mean "this is a shape I don't understand, and
    /// showing part of it as bullets is worse than not converting at all":
    ///
    ///   - a Markdown TABLE. Headlamp writes its whole changelog as tables — 142
    ///     table rows in v0.45.0 — and line-by-line that renders as bullets reading
    ///     `|:--|--:|` and `| <img src="…">`, next to download links for other
    ///     platforms. Verified against the live release before this guard existed.
    ///   - more than `proseItemCap` lines. Prose notes are a sentence or a handful;
    ///     dozens of lines means real structure this pass is misreading. Not a
    ///     display limit — the entry is abandoned, not truncated, so the caller
    ///     falls back to the renderer that shows the body whole.
    private static let proseItemCap = 12

    private static func proseItems(from body: String) -> [String] {
        guard body.range(of: #"(?m)^\s*\|"#, options: .regularExpression) == nil
        else { return [] }
        var items: [String] = []
        var inCodeBlock = false
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock || trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if isImageOnly(trimmed) || isBareURL(trimmed) || isChecksum(trimmed) { continue }
            if skippedSectionKeywords.contains(where: {
                trimmed.lowercased().hasPrefix("**\($0)")
            }) { continue }
            items.append(trimmed)
            if items.count > proseItemCap { return [] }
        }
        return items
    }

    /// A line that is nothing but a URL. Not a change description — the same
    /// reasoning as the image-only skip. Caught by an existing test: an
    /// azure-cli-style body of "a bare link, a SHA256 heading, a hash code block"
    /// must still yield nothing, and without this the bare link became its one
    /// "change". A sentence that merely CONTAINS a URL is untouched (kitty's notes
    /// are exactly that), because the whole line has to be the URL.
    private static func isBareURL(_ line: String) -> Bool {
        line.range(of: #"^<?https?://\S+>?$"#, options: .regularExpression) != nil
    }

    /// A line whose entire content is one image, optionally wrapped in a link.
    private static func isImageOnly(_ line: String) -> Bool {
        line.range(
            of: #"^\[?!\[[^\]]*\]\([^)]*\)\]?(\([^)]*\))?$"#,
            options: .regularExpression) != nil
    }

    /// A checksum label (`… SHA256 …:`) or a line carrying a 32+ character hex run.
    private static func isChecksum(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasSuffix(":"),
           lenientExtraSkipKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        return line.range(of: #"\b[0-9a-fA-F]{32,}\b"#, options: .regularExpression) != nil
    }

    private static func extractItems(from body: String, lenient: Bool) -> [String] {
        let lines = body.components(separatedBy: .newlines)
        let skipKeywords = lenient ? skippedSectionKeywords + lenientExtraSkipKeywords
                                   : skippedSectionKeywords
        var items: [String] = []
        var inSkippedSection = false
        var inCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block (lenient only): skip its contents so a release's
            // SHA256 table or example snippet isn't mistaken for change items.
            if lenient, trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }

            // Section heading: ## Title or ### Title
            if trimmed.hasPrefix("#") {
                let heading = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                inSkippedSection = skipKeywords.contains(where: { heading.contains($0) })
                continue
            }

            if inSkippedSection { continue }

            if lenient {
                // Indented bullets and numbered lists count too. Safe here because
                // the strict pass already came up empty, so there are no top-level
                // items for an indented line to be a duplicate sub-detail of.
                if let raw = bulletContent(from: trimmed) ?? numberedContent(from: trimmed) {
                    let cleaned = cleanItem(raw)
                    if cleaned.count >= 6 { items.append(cleaned) }
                }
            } else {
                // Bullet: `- text`, `* text`, `+ text`.
                // Skip any indented sub-bullet — a leading space or tab marks PR-body
                // detail that usually duplicates the top-level item. (Checked on the
                // raw line; `trimmed` below has the indentation stripped.)
                guard let first = line.first, first != " ", first != "\t" else { continue }

                if let raw = bulletContent(from: trimmed) {
                    let cleaned = cleanItem(raw)
                    // Drop very short items (emoji-only, single-word, link-only lines).
                    if cleaned.count >= 6 { items.append(cleaned) }
                }
            }
        }

        return items
    }

    /// A numbered-list item's text: "1. text" / "12) text" → "text". nil otherwise.
    private static func numberedContent(from line: String) -> String? {
        guard let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        return String(line[r.upperBound...])
    }

    private static func bulletContent(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Strip the "by @user in https://..." suffix GitHub appends to auto-generated
    /// PR-merge entries so only the human-readable change title remains.
    private static func cleanItem(_ item: String) -> String {
        var s = item

        // "Something by @user in https://github.com/owner/repo/pull/123"
        if let r = s.range(of: #"\s+by\s+@\S+\s+in\s+https?://\S+"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        // Trailing bare PR reference: " (#1234)"
        if let r = s.range(of: #"\s+\(#\d+\)\s*$"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        return s.trimmingCharacters(in: .whitespaces)
    }
}
