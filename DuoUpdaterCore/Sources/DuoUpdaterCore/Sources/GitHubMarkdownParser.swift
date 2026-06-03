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
    public static func parse(body: String, version: String, date: String?) -> Changelog? {
        let items = extractItems(from: body)
        guard !items.isEmpty else { return nil }
        let entry = Changelog.Entry(version: version, date: date, items: items)
        return Changelog(entries: [entry])
    }

    // MARK: - Internals

    private static let skippedSectionKeywords = [
        "new contributors", "contributors", "full changelog",
    ]

    private static func extractItems(from body: String) -> [String] {
        let lines = body.components(separatedBy: .newlines)
        var items: [String] = []
        var inSkippedSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section heading: ## Title or ### Title
            if trimmed.hasPrefix("#") {
                let heading = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                inSkippedSection = skippedSectionKeywords.contains(where: { heading.contains($0) })
                continue
            }

            if inSkippedSection { continue }

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

        return items
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
