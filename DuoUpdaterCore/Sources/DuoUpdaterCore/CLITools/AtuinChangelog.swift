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
/// No dates (they come from `AtuinRelease.feed`), no prereleases. Each section goes through
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

    /// The dates, since the changelog has none, come from `AtuinRelease.feed`
    /// (`releases.atom`, the nightly check's source): not the API, so none of
    /// its 60 anonymous calls an hour. Read 2026-10-09: 205,492 bytes (served
    /// uncompressed), the ten newest releases and prereleases, back to
    /// 18.19.0-beta.3 — five stable versions. An entry's `<updated>` is the
    /// release's `updated_at`, not `published_at`; for all ten the UTC day was
    /// the same (18.23.0's time 2h05m later, edited after publishing). A release
    /// edited on a later day would show that day. Older versions stay undated.
    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        // Asked alongside the changelog. A failure of this one costs the dates
        // only, never the notes.
        async let feed = try? releaseFeed(force: force, session: session)
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        guard let feed = await feed else { return parsed }
        return await offCooperativePool { dated(parsed, feed: feed) }
    }

    /// Each entry with its release's `<updated>` day from the feed, by tag
    /// `v<version>`; an entry the feed does not reach keeps no date.
    static func dated(_ changelog: Changelog, feed: Data) -> Changelog {
        let dates = AtuinRelease.days(inFeed: feed)
        guard !dates.isEmpty else { return changelog }
        let entries = changelog.entries.map { entry in
            Changelog.Entry(title: entry.title, version: entry.version, date: entry.date ?? dates[entry.version],
                            items: entry.items, content: entry.content, markdown: entry.markdown)
        }
        return Changelog(entries: entries, itemSyntax: changelog.itemSyntax)
    }

    static func releaseFeed(force: Bool, session: URLSession) async throws -> Data {
        var request = URLRequest(url: AtuinRelease.feed)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: AtuinRelease.feed)
        }
        return data
    }
}
