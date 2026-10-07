import Foundation

/// Luvus's release notes: its GitHub Releases, read the way Vite+'s are
/// (`VitePlusChangelog`) — the Releases API list, the token `ChangelogService`
/// sends, and `StructuredChangelogDecoder`'s `.gitHubReleases` format, which runs
/// each body through `GitHubMarkdownParser`.
///
/// The shape, fetched 2026-10-07: 35 releases, none marked prerelease (0.1.1 to
/// 0.10.2 were published as Bohay, the project's earlier name). A body is a
/// summary paragraph, then `## Features`, `## Improvements` and `## Fixes`, one
/// bullet per change led by a bold scope (`- **Web:** …`) and ending in its
/// commit and pull request links; then `## Contributors` (avatars and names),
/// from 0.13.4 an `## Issue reporters` list of names, and `## Full changelog`.
/// The parser already drops the contributor and full-changelog sections by
/// keyword; the issue reporters come through as changes, and so did the
/// `### Install` commands of 0.7.1, 0.7.2 and 0.8.0, so both are skipped by name.
public enum LuvusChangelog {

    /// About one release a week; 30 reach back to 0.5.0 (July 2026), enough for
    /// `CLIToolChangelog.relevant`, which needs the reader's unseen releases plus
    /// five.
    public static let source = URL(string: "https://api.github.com/repos/RizRiyz/luvus/releases?per_page=30")!

    /// The section that credits who reported the issues a release fixed, and the
    /// install commands a few early releases listed.
    static let skipSections = ["Issue reporters", "Install"]

    /// Newest first, one entry per release; nil when no release yields one.
    public static func parse(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil,
                                          skipSections: skipSections)
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
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
