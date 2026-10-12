import Foundation

/// Which of the versions an update would bring the vendor's own release notes
/// mark as breaking. A hint for the row, never a gate: the update is offered
/// exactly as before.
///
/// Read from the notes rather than guessed from the version numbers. Surveyed
/// 2026-10-12 over every provider's notes through `releaseNotes` (26 tools):
/// of 74 releases that bumped the major number, or the minor one under 0.x, 7
/// carry a marker; 33 marked releases bumped neither — fx marks breaking
/// changes in 0.0.x patches, Herdr in patches, mise and openclaw are CalVer —
/// and Codex bumps its 0.x minor on every release. A version rule would have
/// flagged the wrong releases and missed most of the right ones.
///
/// Only the shapes the vendors were seen to use count:
/// - a category heading naming breaking changes (`### Breaking Changes` — fx,
///   uv, mise, GHCup, Herdr, Vite+; `🚨 Breaking Changes` — bub);
/// - a change line that opens with the word: `Breaking change: …` (Claude
///   Code), `**BREAKING**: …` (Atuin), `**Breaking:** …` (Herdr),
///   `**Breaking — Node runtime:** …` (openclaw), or one whose bold title ends
///   `(breaking)**` (Vite+).
///
/// The word anywhere else in a line is not a marker: 26 lines of Claude Code's
/// notes use it otherwise ("Fixed … breaking …" of a bug), and bub's say "No
/// breaking changes".
/// Rust's "Compatibility Notes" heading is in 90 of 155 releases, so it marks
/// nothing; "Removed" and "Deprecated" headings are not claims of breakage.
extension CLIToolChangelog {

    /// Whether `status`'s notes are worth reading for the hint: an update is
    /// offered and both ends of its range are known. Only these rows fetch
    /// notes before anyone opens them.
    public static func readsForBreaking(_ status: CLIToolStatus) -> Bool {
        status.state == .updateAvailable && status.installedVersion != nil && status.latestVersion != nil
    }

    /// The versions above `installed`, up to and including `latest`, whose
    /// entry in `changelog` is marked breaking, oldest first. Empty when either
    /// version is unknown: without both ends there is no range to read.
    public static func breakingVersions(in changelog: Changelog, installed: String?, latest: String?) -> [String] {
        guard let installed, let latest else { return [] }
        return changelog.entries
            .filter { entry in
                VersionComparator.compare(entry.version, installed) == .orderedDescending
                    && VersionComparator.compare(entry.version, latest) != .orderedDescending
                    && isMarkedBreaking(entry)
            }
            .map(\.version)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { VersionComparator.compare($0, $1) == .orderedAscending }
    }

    /// Whether the vendor marks `entry` as breaking, by the shapes above.
    static func isMarkedBreaking(_ entry: Changelog.Entry) -> Bool {
        let headings = entry.content.compactMap { block -> String? in
            if case .heading(let text) = block { return text }
            return nil
        } + (entry.markdown ?? "").split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#") ? String(trimmed.drop { $0 == "#" }) : nil
        }
        return headings.contains(where: isBreakingHeading) || entry.items.contains(where: isBreakingLine)
    }

    /// A heading naming breaking changes: it marks the section under it.
    static func isBreakingHeading(_ text: String) -> Bool {
        text.range(of: "breaking", options: .caseInsensitive) != nil
    }

    /// A change line that marks itself breaking, as its source text reads.
    static func isBreakingLine(_ item: String) -> Bool {
        item.range(of: breakingLead, options: .regularExpression) != nil
            || item.range(of: breakingTitle, options: .regularExpression) != nil
    }

    // MARK: - Where in the notes

    // What the notes pane tints when the reader asks to see a version's breaking
    // changes: indexes into whichever of an entry's forms the pane draws —
    // Markdown blocks, else `content`, else `items` — found by the same marks. A
    // breaking heading takes its section with it, up to the next heading (of its
    // level or higher, in Markdown). Empty when that form carries no mark the
    // pane can point at; it then tints the version's title instead.

    /// The `content` blocks that mark an entry breaking: a breaking heading and
    /// the blocks under it, and each change line that marks itself.
    public static func breakingBlocks(in content: [Changelog.Entry.Block]) -> IndexSet {
        var marked = IndexSet()
        var inSection = false
        for (index, block) in content.enumerated() {
            switch block {
            case .heading(let text):
                inSection = isBreakingHeading(text)
                if inSection { marked.insert(index) }
            case .note(let text):
                if inSection || isBreakingLine(text) { marked.insert(index) }
            case .image:
                if inSection { marked.insert(index) }
            }
        }
        return marked
    }

    /// The `items` that mark themselves breaking: what an entry without
    /// `content` draws, which has no headings.
    public static func breakingItems(_ items: [String]) -> IndexSet {
        IndexSet(items.indices.filter { isBreakingLine(items[$0]) })
    }

    /// The Markdown blocks (`ChangelogMarkdown.blocks`) that mark an entry
    /// breaking. Their text is parsed already, so the `**` of a bold title
    /// ending "(breaking)" is gone from the characters: that one is read off
    /// the runs.
    public static func breakingBlocks(in blocks: [ChangelogMarkdown.Block]) -> IndexSet {
        var marked = IndexSet()
        var section: Int?
        for (index, block) in blocks.enumerated() {
            if case .heading(let level) = block.kind {
                if let open = section, level <= open { section = nil }
                if section == nil, isBreakingHeading(String(block.text.characters)) { section = level }
                if section != nil { marked.insert(index) }
            } else if section != nil || isBreakingLine(String(block.text.characters))
                        || opensWithBreakingTitle(block.text) {
                marked.insert(index)
            }
        }
        return marked
    }

    /// Whether `text` opens with a bold run ending "(breaking)": `breakingTitle`
    /// on parsed Markdown.
    private static func opensWithBreakingTitle(_ text: AttributedString) -> Bool {
        var title = ""
        for run in text.runs {
            let characters = String(text[run.range].characters)
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                title += characters
            } else if title.isEmpty, characters.allSatisfy(\.isWhitespace) {
                continue
            } else {
                break
            }
        }
        return title.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix("(breaking)")
    }

    /// A line that opens with the word, then a colon or a dash: "Breaking
    /// change:", "**BREAKING**:", "**Breaking:**", "**Breaking — …".
    private static let breakingLead = #"^\s*(\*\*)?\s*(?i:breaking)(\s+(?i:changes?))?\s*(\*\*)?\s*[:—–-]"#

    /// A bold title that ends "(breaking)": "**`vp test` now … (breaking)**:".
    private static let breakingTitle = #"(?i)^\s*\*\*.*\(breaking\)\*\*"#
}
