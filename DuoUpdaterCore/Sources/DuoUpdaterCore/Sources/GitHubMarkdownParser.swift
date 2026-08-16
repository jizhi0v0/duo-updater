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
    public static func parse(body: String, version: String, date: String?) -> Changelog? {
        var items = extractItems(from: body, lenient: false)
        if items.isEmpty {
            items = extractItems(from: body, lenient: true)
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
