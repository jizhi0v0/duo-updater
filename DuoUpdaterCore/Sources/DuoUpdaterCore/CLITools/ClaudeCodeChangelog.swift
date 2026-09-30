import Foundation

/// Claude Code's release notes, from the vendor's own `CHANGELOG.md`, and which of
/// them one install's reader wants to see.
///
/// Raw file rather than an API, like DuoUpdater's own notes (`SelfChangelogView`):
/// no token and no share of the GitHub rate budget the version checks use. Its
/// shape, as fetched on 2026-09-30: `# Changelog`, then one
/// `## <version>` section per release, newest first, each a list of `- ` bullets
/// written in Markdown (backticked commands and settings). The sections skip
/// versions that were never released (there is no `## 2.1.279`), so which ones
/// to show is decided by comparing versions, never by counting positions.
public enum ClaudeCodeChangelog {

    public static let source = URL(
        string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md")!

    /// Every `## <version>` section that carries at least one bullet, in file order.
    ///
    /// nil when the text has no such section — a 404 body, an error page, or a file
    /// whose shape changed — so the caller can say that, rather than show an empty
    /// list that reads as "no releases".
    public static func parse(_ markdown: String) -> Changelog? {
        var entries: [Changelog.Entry] = []
        var version: String?
        var items: [String] = []

        func close() {
            if let version, !items.isEmpty {
                entries.append(Changelog.Entry(version: version, date: nil, items: items))
            }
            items = []
        }

        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                close()
                // Only a level-2 heading that is a version opens a section. Anything
                // else (the `# Changelog` title, a heading we do not know) ends the
                // one before it, so its lines are not filed under the wrong release.
                version = Self.sectionVersion(line)
                continue
            }
            guard version != nil, !line.isEmpty else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if !items.isEmpty {
                // A bullet wrapped across source lines is one change, not two.
                items[items.count - 1] += " " + line
            } else {
                // Prose before any bullet is still what the vendor said about it.
                items.append(line)
            }
        }
        close()
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// `## 2.1.285` → "2.1.285"; nil for any other heading.
    static func sectionVersion(_ heading: String) -> String? {
        guard heading.hasPrefix("## ") else { return nil }
        let text = heading.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return text.range(of: #"^\d+(\.\d+)+([.\-+][0-9A-Za-z.\-]+)?$"#, options: .regularExpression) != nil
            ? text : nil
    }

    /// The sections worth putting in front of someone on `installed` whose channel
    /// points at `latest`, newest first.
    ///
    /// Every release they have not taken yet, up to the channel's latest and no
    /// further — a `stable` reader is not shown what `latest` has that stable does
    /// not. Then, when that is fewer than `minimum`, the releases they already have,
    /// down from their own, so an up-to-date install still shows what its version
    /// brought. An install ahead of its channel (a `latest` build on a Mac now set to
    /// `stable`) reads up to its own version.
    ///
    /// Either version may be unknown: without `installed` nothing counts as new;
    /// without `latest` the ceiling is the installed version, since nothing says the
    /// newer sections are on this reader's channel. With neither, the newest
    /// `minimum` sections.
    public static func relevant(
        _ changelog: Changelog, installed: String?, latest: String?, minimum: Int = 5
    ) -> Changelog? {
        let ceiling: String?
        switch (installed, latest) {
        case let (installed?, latest?):
            ceiling = VersionComparator.compare(installed, latest) == .orderedDescending ? installed : latest
        case let (installed, latest):
            ceiling = latest ?? installed
        }
        let candidates = changelog.entries
            .filter { entry in
                guard let ceiling else { return true }
                return VersionComparator.compare(entry.version, ceiling) != .orderedDescending
            }
            // The file is newest first today; sorted anyway, so a section filed out
            // of order cannot land among the wrong group.
            .sorted { VersionComparator.compare($0.version, $1.version) == .orderedDescending }
        let unseen = candidates.filter { entry in
            guard let installed else { return false }
            return VersionComparator.compare(entry.version, installed) == .orderedDescending
        }
        let taken = candidates.dropFirst(unseen.count).prefix(max(minimum - unseen.count, 0))
        let picked = unseen + taken
        return picked.isEmpty ? nil : Changelog(entries: Array(picked), itemSyntax: changelog.itemSyntax)
    }
}
