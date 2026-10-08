import Foundation

/// Vite+'s release notes: its GitHub Releases, read the way bub's are
/// (`BubChangelog`) — the Releases API list, the token `ChangelogService` sends,
/// and `StructuredChangelogDecoder`'s `.gitHubReleases` format, which runs each
/// body through `GitHubMarkdownParser` and keeps the releases not marked
/// prerelease.
///
/// The shape, fetched 2026-10-06: 100 releases, of which the 0.1.x `-alpha.N`
/// and `0.0.x-g<commit>` builds are marked prerelease and dropped; the
/// `1.0.0-rc.N` ones are not, and stay — 1.0.0's own notes only point at
/// them. A body is `### Highlights`, `### Features`, `### Fixes &
/// Enhancements`, `### Docs`, `### Chore`, … with one bullet per change, then the
/// same tail on every release: a `### Bundled Versions` table, `### Upgrade` and
/// `### Installation` code blocks, and `### Published Packages`. The parser
/// already drops the table and the code blocks; the package list is the one
/// section that comes through as changes, so it is taken out (`trimmed`). All 22
/// stable releases on the first page yielded an entry, every one with headings.
public enum VitePlusChangelog {

    /// 30 releases reach back to 0.1.20 (May 2026): enough for
    /// `CLIToolChangelog.relevant`, which needs the reader's unseen releases plus
    /// five, at about one release a week.
    public static let source = URL(string: "https://api.github.com/repos/voidzero-dev/vite-plus/releases?per_page=30")!

    /// The section that names the npm packages a release published.
    static let packagesHeading = "Published Packages"

    /// Newest first, one entry per stable release; nil when no release yields one.
    public static func parse(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil).map(trimmed)
    }

    /// `changelog` without each entry's "Published Packages" section.
    static func trimmed(_ changelog: Changelog) -> Changelog {
        Changelog(entries: changelog.entries.map { entry in
            guard let start = entry.content.firstIndex(of: .heading(packagesHeading)) else { return entry }
            let end = entry.content[(start + 1)...].firstIndex { if case .heading = $0 { return true } else { return false } }
                ?? entry.content.endIndex
            let removed = entry.content[start..<end].compactMap { block -> String? in
                if case .note(let text) = block { return text } else { return nil }
            }
            var content = entry.content
            content.removeSubrange(start..<end)
            // `items` holds the same notes in the same order: drop that run of them.
            var items = entry.items
            if let at = items.indices.first(where: { Array(items[$0...].prefix(removed.count)) == removed }) {
                items.removeSubrange(at..<(at + removed.count))
            }
            return Changelog.Entry(
                title: entry.title, version: entry.version, date: entry.date, items: items,
                content: content, markdown: entry.markdown)
        }, itemSyntax: changelog.itemSyntax)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        // What `ChangelogService` sends to the GitHub API (`BubChangelog.fetch`).
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if ChangelogService.isGitHubAPI(source), let token = await ChangelogService.gitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
