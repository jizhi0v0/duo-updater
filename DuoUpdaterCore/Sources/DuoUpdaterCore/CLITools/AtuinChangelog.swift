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
/// No dates (they come from `releasesSource`), no prereleases. Each section goes through
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

    /// Where the dates come from, since the changelog has none: the Releases
    /// API list, asked as Deno's notes ask it (`DenoChangelog.gitHubReleases`:
    /// the token, the revalidating cache). Read 2026-10-09: 30 releases are
    /// 2,915,473 bytes decoded, nearly all assets, but sent gzipped — 209,113
    /// bytes on the wire, about what `releases.atom` costs uncompressed (205,492),
    /// which is why the API list stayed — and reach back to 18.13.4, prereleases
    /// included, which covers `CLIToolChangelog.relevant`'s unseen releases plus
    /// five. GitHub's own date, `published_at`, as every other tool's rail shows;
    /// the atom feed only has `updated`, which moves when a release is edited.
    public static let releasesSource = URL(string: "https://api.github.com/repos/atuinsh/atuin/releases?per_page=30")!

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        // Asked alongside the changelog. A failure of this one (the API's rate
        // limit, say) costs the dates only, never the notes.
        async let releases = try? releaseList(force: force, session: session)
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        guard let list = await releases else { return parsed }
        return await offCooperativePool { dated(parsed, releases: list) }
    }

    /// Each entry with its release's `published_at` day, by tag `v<version>`;
    /// an entry with no published release keeps no date.
    static func dated(_ changelog: Changelog, releases: Data) -> Changelog {
        let dates = publishedDays(releases)
        guard !dates.isEmpty else { return changelog }
        let entries = changelog.entries.map { entry in
            Changelog.Entry(title: entry.title, version: entry.version, date: entry.date ?? dates[entry.version],
                            items: entry.items, content: entry.content, markdown: entry.markdown)
        }
        return Changelog(entries: entries, itemSyntax: changelog.itemSyntax)
    }

    /// Version → `YYYY-MM-DD`, from a Releases API list; drafts left out.
    static func publishedDays(_ data: Data) -> [String: String] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var days: [String: String] = [:]
        for release in list where release["draft"] as? Bool != true {
            guard let tag = release["tag_name"] as? String, tag.hasPrefix("v"),
                  let day = StructuredChangelogDecoder.isoDay(release["published_at"] as? String)
            else { continue }
            days[String(tag.dropFirst())] = day
        }
        return days
    }

    static func releaseList(force: Bool, session: URLSession) async throws -> Data {
        var request = URLRequest(url: releasesSource)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if ChangelogService.isGitHubAPI(releasesSource), let token = await ChangelogService.gitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: releasesSource)
        }
        return data
    }
}
