import Foundation

/// The two documents the Rust group's release notes come from: rustup's own
/// `CHANGELOG.md` for the rustup row, and Rust's `RELEASES.md` for every
/// toolchain row. Raw files, like Claude Code's and fx's.
///
/// Each version's section is rewritten into the Markdown `GitHubMarkdownParser`
/// reads — `### ` subsections, one `- ` line per change — and handed to it, so
/// subsections become `.heading` blocks by that parser's rules. The rewrite
/// (`normalize`):
/// - a setext subsection (`Language` over `--------`) becomes `### Language`;
/// - a bullet wrapped over several source lines becomes one line;
/// - a nested bullet becomes a bullet of its own: in both documents it carries
///   the detail of the change above it (rustup 1.29.1's "Concurrency … has been
///   improved:" has its two changes nested under it), which the parser, reading
///   top-level bullets only, would drop;
/// - reference links (`[pr#4752]`, `[an issue][issue tracker]`) become inline
///   links from the document's own `[label]: url` lines, which are dropped, as
///   are `<a id="…"></a>` anchors and fenced code.
public enum RustChangelog {

    public static let rustupSource = URL(
        string: "https://raw.githubusercontent.com/rust-lang/rustup/stable/CHANGELOG.md")!
    public static let rustSource = URL(
        string: "https://raw.githubusercontent.com/rust-lang/rust/stable/RELEASES.md")!

    // MARK: - rustup

    /// rustup's `CHANGELOG.md`, read from its `stable` branch: on 2026-10-01
    /// `main` did not yet have the 1.29.1 section that `stable` had.
    ///
    /// Keep a Changelog headings, `## [1.29.1] - 2026-08-13`, newest first. From
    /// 1.28.0 a section is prose and a bulleted list of headlines, then `###
    /// Detailed changes`, every merged pull request (234 for 1.29.0, renovate's
    /// lock-file bumps among them); older sections file their bullets under
    /// `### Added` / `### Changed` / `### Fixed` / `### Removed`, and some end with
    /// `### Thanks`, a list of contributors. The headlines are the release as
    /// rustup tells it, so the pull-request list and the thanks are skipped like
    /// GitHub's "New Contributors"; the prose around the headlines is not kept
    /// when there are bullets (the parser's rule).
    ///
    /// nil when no section yields any change.
    public static func parseRustup(_ markdown: String) -> Changelog? {
        let lines = markdown.components(separatedBy: "\n")
        let links = referenceLinks(lines)
        var entries: [Changelog.Entry] = []
        var current: (version: String, date: String?, body: [String])?

        func close() {
            guard let section = current else { return }
            current = nil
            let body = normalize(section.body, links: links)
            if let entry = GitHubMarkdownParser.parse(
                body: body, version: section.version, date: section.date, skipSections: rustupSkippedSections
            )?.entries.first {
                entries.append(entry)
            }
        }

        for line in lines {
            if line.hasPrefix("#"), !line.hasPrefix("###") {
                close()
                if let (version, date) = rustupHeading(line) { current = (version, date, []) }
                continue
            }
            current?.body.append(line)
        }
        close()
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    static let rustupSkippedSections = ["Detailed changes", "Thanks"]

    /// `## [1.29.1] - 2026-08-13` → ("1.29.1", "2026-08-13"); nil for any other
    /// heading (`# Changelog`, `## [Unreleased]`).
    static func rustupHeading(_ line: String) -> (String, String?)? {
        guard let match = line.range(
            of: #"^## \[([0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.\-]*)\](?:\s+-\s+([0-9]{4}-[0-9]{2}-[0-9]{2}))?\s*$"#,
            options: .regularExpression)
        else { return nil }
        let text = String(line[match])
        let version = text.dropFirst(4).prefix { $0 != "]" }
        let date = text.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression).map { String(text[$0]) }
        return (String(version), date)
    }

    // MARK: - Rust

    /// Rust's `RELEASES.md` (930 KB on 2026-10-01, 1.99.0 down to 0.1). Each
    /// release is a setext heading, `Version 1.99.0 (2026-10-01)` over `====`;
    /// a minor release's subsections are setext too (`Language` over `--------`,
    /// each after an `<a id="1.99.0-Language"></a>` line), its changes
    /// `- [text](pull request)` bullets, sometimes with a sentence after the link
    /// or a nested bullet under it. A patch release (1.98.1) is a few bullets
    /// under no subsection, `*` or `-`.
    ///
    /// Only stable releases have sections: a beta or nightly toolchain's row
    /// reads the newest of them, all at or below its own version.
    public static func parseRust(_ markdown: String) -> Changelog? {
        let lines = markdown.components(separatedBy: "\n")
        let links = referenceLinks(lines)
        var entries: [Changelog.Entry] = []
        var current: (version: String, date: String?, body: [String])?

        func close() {
            guard let section = current else { return }
            current = nil
            if let entry = GitHubMarkdownParser.parse(
                body: normalize(section.body, links: links), version: section.version, date: section.date
            )?.entries.first {
                entries.append(entry)
            }
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if index + 1 < lines.count, isUnderline(lines[index + 1], "="), !line.isEmpty {
                close()
                if let (version, date) = rustHeading(line) { current = (version, date, []) }
                index += 2
                continue
            }
            current?.body.append(line)
            index += 1
        }
        close()
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// `Version 1.99.0 (2026-10-01)` → ("1.99.0", "2026-10-01"). The oldest
    /// headings are `Version 0.10 (2014-04-03)` and `Version 0.3  (2012-07-12)`.
    static func rustHeading(_ line: String) -> (String, String?)? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.range(of: #"^Version [0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z.]+)?\s+\([0-9]{4}-[0-9]{2}-[0-9]{2}\)$"#,
                         options: .regularExpression) != nil
        else { return nil }
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        return (String(parts[1]), String(parts[2].dropFirst().dropLast()))
    }

    // MARK: - Rewriting a section

    /// A setext underline: two or more of `character` and nothing else.
    static func isUnderline(_ line: String, _ character: Character) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count >= 2 && text.allSatisfy { $0 == character }
    }

    /// One section's lines as the Markdown `GitHubMarkdownParser` reads (see the
    /// type's doc comment).
    static func normalize(_ lines: [String], links: [String: String]) -> String {
        var out: [String] = []
        /// The index in `out` of the bullet still taking continuation lines.
        var open: Int?
        var afterBlank = false
        var inFence = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            index += 1

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || isAnchor(trimmed) || isLinkDefinition(trimmed) { continue }
            if trimmed.isEmpty {
                afterBlank = true
                continue
            }
            // A setext subsection: this line over a run of `-`.
            if index < lines.count, isUnderline(lines[index], "-"), !isBullet(trimmed) {
                out.append("### " + trimmed)
                open = nil
                afterBlank = false
                index += 1
                continue
            }
            // A thematic break, or an underline whose text was dropped.
            if isUnderline(trimmed, "-") || isUnderline(trimmed, "=") || isUnderline(trimmed, "*") { continue }
            if trimmed.hasPrefix("#") {
                out.append(trimmed)
                open = nil
            } else if let content = bulletContent(trimmed) {
                out.append("- " + content)
                open = out.count - 1
            } else if let open, line.first?.isWhitespace == true || !afterBlank {
                // Indented under the item, or the next line of it with no blank
                // line between: the same change.
                out[open] += " " + trimmed
            } else {
                out.append(trimmed)
                open = nil
            }
            afterBlank = false
        }
        // Once the lines are joined: a reference wraps across them as often as
        // not (`…the\n  MMIO stale data vulnerability][98126]`, Rust 1.62.1).
        return out.map { resolve($0, links: links) }.joined(separator: "\n")
    }

    static func isBullet(_ trimmed: String) -> Bool { bulletContent(trimmed) != nil }

    static func bulletContent(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// `<a id="1.99.0-Language"></a>`.
    static func isAnchor(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^<a\s+(?:id|name)="[^"]*"\s*>\s*</a>$"#, options: .regularExpression) != nil
    }

    /// `[pr#4752]: https://github.com/rust-lang/rustup/pull/4752`.
    static func isLinkDefinition(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^\[[^\]]+\]:\s*\S+"#, options: .regularExpression) != nil
    }

    /// Every `[label]: url` in the document, labels lowercased (Markdown matches
    /// them case-insensitively); the first definition of a label wins.
    static func referenceLinks(_ lines: [String]) -> [String: String] {
        var links: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isLinkDefinition(trimmed), let close = trimmed.firstIndex(of: "]") else { continue }
            let label = trimmed[trimmed.index(after: trimmed.startIndex)..<close].lowercased()
            let rest = trimmed[trimmed.index(after: close)...].dropFirst().trimmingCharacters(in: .whitespaces)
            guard let url = rest.split(separator: " ").first.map(String.init), links[label] == nil else { continue }
            links[label] = url.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        return links
    }

    /// `[text][label]`, and the collapsed `[label][]` (rustup's older sections).
    /// The text may hold one level of brackets — Rust's
    /// `[Implement internal traits that enable `[OsStr]::join`.][96881]`.
    private static let fullReference = try! NSRegularExpression(
        pattern: #"\[((?:[^\[\]]|\[[^\[\]]*\])+)\]\[([^\[\]]*)\]"#)
    /// `[label]` alone, not part of an inline link, a definition or an image.
    private static let shortcutReference = try! NSRegularExpression(
        pattern: #"(?<![\]\\!])\[([^\[\]]+)\](?![\(\[:])"#)

    /// References with a definition become `[text](url)`; anything without one
    /// is left as written.
    static func resolve(_ text: String, links: [String: String]) -> String {
        guard !links.isEmpty, text.contains("[") else { return text }
        var result = text
        for (regex, textGroup, labelGroup) in [(fullReference, 1, 2), (shortcutReference, 1, 1)] {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let shown = ns.substring(with: match.range(at: textGroup))
                var label = ns.substring(with: match.range(at: labelGroup))
                if label.isEmpty { label = shown }
                guard let url = links[label.lowercased()] else { continue }
                result = (result as NSString).replacingCharacters(in: match.range, with: "[\(shown)](\(url))")
            }
        }
        return result
    }
}
