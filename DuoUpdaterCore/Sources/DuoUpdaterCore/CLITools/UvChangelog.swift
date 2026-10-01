import Foundation

/// uv's release notes, from the vendor's own `CHANGELOG.md` and the per-series
/// files it points to.
///
/// The shape, fetched 2026-10-02:
/// - `CHANGELOG.md` (62 KB) holds only the current minor series, newest first —
///   `## 0.12.21` down to `## 0.12.0` — and then one stub per older series,
///   `## 0.11.x` / `See [changelogs/0.11.x](./changelogs/0.11.x.md)`, down to
///   `0.1.x`;
/// - each `changelogs/<series>.md` holds that series **oldest first** (`0.9.x`:
///   `## 0.9.0` … `## 0.9.30`);
/// - a section is `## <version>`, `Released on 2026-09-29.`, sometimes a prose
///   paragraph or two (0.12.12 announces the signing; 0.12.0 and 0.9.0 open
///   with what the breaking release is about), then `### Enhancements`,
///   `### Bug fixes`, `### Preview features`, `### Python`, `### Documentation`,
///   `### Performance`, `### Configuration`, … with `- … ([#22076](…))` bullets;
/// - the archive files wrap at 80 columns: 211 of the 325 bullets in `0.9.x.md`
///   continue on an indented line (most often the `([#17080](…))` link), which
///   the current file does not do. A breaking change's bullet is followed by a
///   blank line and indented paragraphs, sometimes a code block, explaining it.
///
/// Each section goes through `GitHubMarkdownParser.parse(body:version:date:)`,
/// so the `###` categories become `.heading` blocks by that parser's rules,
/// as `FxChangelog` does. Two things are done to a section first, since that
/// parser reads one line per bullet and only top-level bullets: a bullet's
/// wrapped continuation lines are joined onto it, and each prose paragraph
/// before the first heading becomes one bullet, so it leads the entry. A
/// breaking change's indented explanation is left out; its bold title stays.
///
/// One `Changelog` is built newest first across files: the current file, then
/// each older series the reader's installed version needs (`wantsMore`).
public enum UvChangelog {

    public static let source = URL(string: "https://raw.githubusercontent.com/astral-sh/uv/main/CHANGELOG.md")!

    /// The changes in one file, plus the older series it points to.
    struct Document: Equatable {
        /// In file order.
        var entries: [Changelog.Entry]
        /// `0.11.x` → `changelogs/0.11.x.md`, newest series first.
        var archives: [(series: String, path: String)]

        static func == (a: Document, b: Document) -> Bool {
            a.entries == b.entries && a.archives.map(\.series) == b.archives.map(\.series)
                && a.archives.map(\.path) == b.archives.map(\.path)
        }
    }

    /// The current file: entries newest first, nil when there is none — a 404
    /// body, an error page, or a file whose shape changed.
    public static func parse(_ markdown: String) -> Changelog? {
        let entries = document(markdown).entries
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The whole notes `installed` needs: the current file, then each older
    /// series, newest first, until the entries reach `installed` and hold what
    /// `CLIToolChangelog.relevant` shows around it — every release after it, and
    /// enough at or below it to make `minimum` in all.
    static func fetch(
        installed: String?, force: Bool, minimum: Int = 5,
        get: @Sendable (URL, Bool) async throws -> Data = UvChangelog.get
    ) async throws -> Changelog {
        let data = try await get(source, force)
        let main = await offCooperativePool { document(String(decoding: data, as: UTF8.self)) }
        guard !main.entries.isEmpty else { throw CLIToolReleaseNotesError.noSections }
        var entries = main.entries
        for archive in main.archives {
            guard wantsMore(entries, installed: installed, minimum: minimum) else { break }
            let data = try await get(source.deletingLastPathComponent().appendingPathComponent(archive.path), force)
            let older = await offCooperativePool { document(String(decoding: data, as: UTF8.self)).entries }
            guard !older.isEmpty else { throw CLIToolReleaseNotesError.noSections }
            entries += older.sorted { VersionComparator.compare($0.version, $1.version) == .orderedDescending }
        }
        return Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// Whether `entries` fall short of what `relevant` would show `installed`:
    /// they do not yet reach it (no entry at or below it, so a release after it
    /// may still be in an older file), or fewer than `minimum` minus the unseen
    /// ones are at or below it. Never, for an unknown `installed`: the current
    /// series is what there is to show.
    static func wantsMore(_ entries: [Changelog.Entry], installed: String?, minimum: Int) -> Bool {
        guard let installed else { return false }
        let atOrBelow = entries.filter { VersionComparator.compare($0.version, installed) != .orderedDescending }.count
        let unseen = entries.count - atOrBelow
        return atOrBelow == 0 || atOrBelow < minimum - unseen
    }

    /// One file's `## <version>` sections, each parsed, and its `## <series>.x`
    /// stubs.
    static func document(_ markdown: String) -> Document {
        var document = Document(entries: [], archives: [])
        for section in sections(markdown) {
            switch section.heading {
            case .version(let version):
                let (date, body) = releaseBody(section.body)
                if let entry = GitHubMarkdownParser.parse(body: body, version: version, date: date)?.entries.first {
                    document.entries.append(entry)
                }
            case .series(let series):
                if let path = archivePath(section.body) {
                    document.archives.append((series, path))
                }
            }
        }
        return document
    }

    enum Heading: Equatable {
        case version(String)
        /// `0.11.x`, a stub pointing at an archive file.
        case series(String)
    }

    /// The `##` sections and their lines. Any other `#` or `##` heading (the `#
    /// Changelog` title, a heading we do not know) ends the section before it, so
    /// its lines are not filed under the wrong release; `###` and deeper belong to
    /// the section.
    static func sections(_ markdown: String) -> [(heading: Heading, body: [String])] {
        var result: [(heading: Heading, body: [String])] = []
        var current: (heading: Heading, body: [String])?
        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("#"), !line.hasPrefix("###") {
                if let current { result.append(current) }
                current = heading(line).map { ($0, []) }
                continue
            }
            current?.body.append(line)
        }
        if let current { result.append(current) }
        return result
    }

    static func heading(_ line: String) -> Heading? {
        guard line.hasPrefix("## ") else { return nil }
        let text = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if UvRelease.isVersion(text) { return .version(text) }
        if text.range(of: #"^\d+\.\d+\.x$"#, options: .regularExpression) != nil { return .series(text) }
        return nil
    }

    /// `See [changelogs/0.11.x](./changelogs/0.11.x.md)` → `changelogs/0.11.x.md`.
    /// Only a relative path under `changelogs/`: the file is fetched next to
    /// `CHANGELOG.md`, and nothing else.
    static func archivePath(_ lines: [String]) -> String? {
        for line in lines {
            guard let range = line.range(of: #"\]\(\./(changelogs/\d+\.\d+\.x\.md)\)"#, options: .regularExpression)
            else { continue }
            return String(line[range].dropFirst(4).dropLast())
        }
        return nil
    }

    /// The section as the parser should read it, and its date.
    ///
    /// `Released on 2026-09-29.` is the date and not a change. Before the first
    /// heading, each paragraph (blank-line separated, its wrapped lines joined)
    /// becomes one bullet. After it:
    /// - a bullet's continuation lines — indented, directly under it, not a list
    ///   item or a fence themselves — are joined onto it;
    /// - a bullet with a list directly under it (no blank line between) is a
    ///   group: 0.11.21's "Bug fixes" is four of them, 22 changes under labels
    ///   like `- Improve cache robustness and pruning behavior`. The label is
    ///   rewritten `- **<label>**:`, the shape whose nested bullets
    ///   `GitHubMarkdownParser` reads as `**<label>**: <change>` items, and each
    ///   nested bullet gets its own continuation lines. A list after a blank
    ///   line belongs to a breaking change's explanation and stays out.
    static func releaseBody(_ lines: [String]) -> (date: String?, body: String) {
        var date: String?
        var out: [String] = []
        var paragraph: [String] = []
        var seenHeading = false
        var inFence = false
        /// The last top-level bullet, while only its own lines have followed it.
        var bullet: Int?
        /// The last nested bullet of `bullet`'s group, likewise.
        var nested: Int?

        func flushParagraph() {
            if !paragraph.isEmpty { out.append("- " + paragraph.joined(separator: " ")) }
            paragraph = []
        }

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle() }
            if !seenHeading, !inFence, date == nil,
               let match = trimmed.range(of: #"^Released on (\d{4}-\d{2}-\d{2})\.$"#, options: .regularExpression) {
                date = String(trimmed[match].dropFirst("Released on ".count).dropLast())
                continue
            }
            if trimmed.hasPrefix("#") { seenHeading = true }
            if !seenHeading && !inFence {
                // Before the first heading: paragraphs, or a list kept as written.
                if trimmed.isEmpty {
                    flushParagraph()
                } else if trimmed.hasPrefix("<!--") {
                    continue
                } else if raw.hasPrefix("- ") || raw.hasPrefix("* ") {
                    flushParagraph()
                    out.append(raw)
                } else if paragraph.isEmpty, raw.hasPrefix(" "), let last = out.last,
                          last.hasPrefix("- ") || last.hasPrefix("* ") {
                    out[out.count - 1] += " " + trimmed
                } else {
                    paragraph.append(trimmed)
                }
                continue
            }
            flushParagraph()
            if !inFence, !trimmed.isEmpty, raw.hasPrefix(" "), !trimmed.hasPrefix("```"), let top = bullet {
                if isListItem(trimmed) {
                    // A group's change: the label becomes a scope the first time.
                    if nested == nil, let label = groupLabel(out[top]) { out[top] = "- **\(label)**:" }
                    if out[top].hasSuffix("**:") {
                        out.append("  - " + trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
                        nested = out.count - 1
                        continue
                    }
                } else {
                    // A wrapped line, joined onto what it continues.
                    out[nested ?? top] += " " + trimmed
                    continue
                }
            }
            bullet = !inFence && (raw.hasPrefix("- ") || raw.hasPrefix("* ")) ? out.count : nil
            nested = nil
            out.append(raw)
        }
        flushParagraph()
        return (date, out.joined(separator: "\n"))
    }

    /// A bullet's text as a group label, when it can be one: plain words with no
    /// emphasis or link of its own (a `*` inside would break the scope's `**`).
    static func groupLabel(_ bullet: String) -> String? {
        let text = bullet.dropFirst(2).trimmingCharacters(in: .whitespaces)
        let label = text.hasSuffix(":") ? String(text.dropLast()) : text
        guard !label.isEmpty, !label.contains("*"), !label.contains("](") else { return nil }
        return label
    }

    static func isListItem(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
            || trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
    }

    /// A raw GitHub file, 15 s, revalidated unless `force`.
    static func get(_ url: URL, force: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        return data
    }
}
