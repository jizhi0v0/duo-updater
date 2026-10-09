import Foundation

/// Atuin's release notes, from its own `CHANGELOG.md` on `main`.
///
/// Raw file rather than the GitHub Releases, read 2026-10-09: each release body
/// is the same notes (`## Release Notes`, then `### Bug Fixes`, `### Features`,
/// …) followed by cargo-dist's install commands and download tables for
/// `atuin` and `atuin-server` and an attestation section, and each release
/// object carries ~70 KB of assets — ten of them are 712 KB of API, against one
/// of the 60 anonymous calls an hour. The changelog (123,904 bytes, git-cliff)
/// is the notes alone, one `## <version>` section per stable release, newest
/// first, under `# Changelog`:
///
///     ## 18.23.0
///
///     ### Bug Fixes
///
///     - *(common)* Sleep before each backoff attempt ([#4129](…))
///
/// No dates, no prereleases. Each section goes through
/// `GitHubMarkdownParser.parse(body:version:date:)`, so the `###` categories
/// become `.heading` blocks by that parser's rules.
public enum AtuinChangelog {

    public static let source = URL(string: "https://raw.githubusercontent.com/atuinsh/atuin/main/CHANGELOG.md")!

    /// One entry per `## <version>` section that yields any change, in file order
    /// (newest first). nil when there is none.
    public static func parse(_ markdown: String) -> Changelog? {
        let entries = sections(markdown).compactMap { section in
            GitHubMarkdownParser.parse(body: section.body.joined(separator: "\n"), version: section.version, date: nil)?
                .entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The `## <version>` sections and their lines. Any other `#` or `##` heading
    /// ends the section before it; `###` and deeper belong to the section.
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

    /// `## 18.23.0` (or `## v18.23.0`) → "18.23.0"; nil for any other heading.
    static func sectionVersion(_ heading: String) -> String? {
        guard heading.hasPrefix("## ") else { return nil }
        var text = heading.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") { text.removeFirst() }
        return AtuinRelease.isVersion(text) ? text : nil
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
