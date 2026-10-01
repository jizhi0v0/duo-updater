import Foundation

/// fx's release notes, from the vendor's own `CHANGELOG.md`.
///
/// Raw file rather than an API, like Claude Code's (`ClaudeCodeChangelog`). Its
/// shape, as fetched on 2026-10-01 (565 lines, `0.0.12` down to `0.0.1`):
///
///     # fx
///
///     ## 0.0.12
///
///     <!-- release:start -->
///
///     **Session listing is up to 560× faster, …**
///
///     ### Breaking Changes
///
///     - libfx now uses …
///
///     ### New Features
///     …
///     <!-- release:end -->
///
/// The markers wrap only the newest section; from 0.0.7 up each section opens
/// with a bold one-line summary; the `###` categories are Breaking Changes, New
/// Features, Improvements, Bug Fixes, Security, and on 0.0.7–0.0.8 Ecosystem
/// highlights. Older sections lead their bullets with a bold label
/// (`- **Memory clearing:** …`).
///
/// Each section goes through `GitHubMarkdownParser.parse(body:version:date:)`, so
/// the categories become `.heading` blocks by that parser's rules rather than a
/// flattener of our own. That parser keeps only bullets, so the summary line is
/// handed to it as the section's first bullet: it then leads the entry, ahead of
/// the first heading, and renders bold.
public enum FxChangelog {

    public static let source = URL(string: "https://raw.githubusercontent.com/vercel-labs/fx/main/CHANGELOG.md")!

    /// One entry per `## <version>` section that yields any change, in file order
    /// (newest first). nil when there is none — a 404 body, an error page, or a
    /// file whose shape changed.
    public static func parse(_ markdown: String) -> Changelog? {
        let entries = sections(markdown).compactMap { section in
            GitHubMarkdownParser.parse(body: releaseBody(section.body), version: section.version, date: nil)?
                .entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The `## <version>` sections and their lines. Any other `#` or `##` heading
    /// (the `# fx` title, a heading we do not know) ends the section before it, so
    /// its lines are not filed under the wrong release; `###` and deeper belong to
    /// the section.
    static func sections(_ markdown: String) -> [(version: String, body: [String])] {
        var result: [(version: String, body: [String])] = []
        var current: (version: String, body: [String])?
        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("#"), !line.hasPrefix("###") {
                if let current { result.append(current) }
                current = sectionVersion(line).map { ($0, []) }
                continue
            }
            current?.body.append(line)
        }
        if let current { result.append(current) }
        return result
    }

    /// `## 0.0.12` (or `## v0.0.12`) → "0.0.12"; nil for any other heading.
    static func sectionVersion(_ heading: String) -> String? {
        guard heading.hasPrefix("## ") else { return nil }
        var text = heading.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") { text.removeFirst() }
        return FxRelease.isVersion(text) ? text : nil
    }

    /// The part of a section that is the release: between the
    /// `<!-- release:start -->` / `<!-- release:end -->` markers when it has them,
    /// else all of it. Then the summary — the first line before any heading or
    /// bullet — becomes a bullet.
    static func releaseBody(_ lines: [String]) -> String {
        var body = lines
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if let start = trimmed.firstIndex(of: "<!-- release:start -->"),
           let end = trimmed[(start + 1)...].firstIndex(of: "<!-- release:end -->") {
            body = Array(lines[(start + 1)..<end])
        }
        for (index, line) in body.enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || (text.hasPrefix("<!--") && text.hasSuffix("-->")) { continue }
            if !text.hasPrefix("#"), !text.hasPrefix("- "), !text.hasPrefix("* ") {
                body[index] = "- " + text
            }
            break
        }
        return body.joined(separator: "\n")
    }
}
