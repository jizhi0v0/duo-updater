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
        if headings.contains(where: { $0.range(of: "breaking", options: .caseInsensitive) != nil }) {
            return true
        }
        return entry.items.contains { item in
            item.range(of: breakingLead, options: .regularExpression) != nil
                || item.range(of: breakingTitle, options: .regularExpression) != nil
        }
    }

    /// A line that opens with the word, then a colon or a dash: "Breaking
    /// change:", "**BREAKING**:", "**Breaking:**", "**Breaking — …".
    private static let breakingLead = #"^\s*(\*\*)?\s*(?i:breaking)(\s+(?i:changes?))?\s*(\*\*)?\s*[:—–-]"#

    /// A bold title that ends "(breaking)": "**`vp test` now … (breaking)**:".
    private static let breakingTitle = #"(?i)^\s*\*\*.*\(breaking\)\*\*"#
}
