import Foundation

/// bub's release notes, which it publishes only as GitHub Releases.
///
/// Read through the same pieces every other GitHub-hosted changelog uses: the
/// Releases API list (one request, every release with its Markdown body), the
/// token `ChangelogService` sends to `api.github.com` (Settings, `GITHUB_TOKEN`,
/// or `gh`), and `StructuredChangelogDecoder`'s `.gitHubReleases` format, which
/// runs each body through `GitHubMarkdownParser`, keeps stable releases only and
/// strips a leading `v` from the tag. `releases.atom` would spare the rate limit
/// but carries rendered HTML, not the Markdown the parser reads.
///
/// The shape, fetched 2026-10-01: 24 releases, tags without a `v` (`0.5.0`),
/// two prereleases (`0.3.0a1`, `0.1.0-alpha.1`). From 0.3.6 on the bodies are
/// changelogithub's — `### &nbsp;&nbsp;&nbsp;🚀 Features` headings, bullets
/// ending `&nbsp;-&nbsp; by @x in https://…/issues/N [<samp>(abc12)</samp>](…)`,
/// and a `**scope**:` bullet with the scope's changes nested under it;
/// `GitHubMarkdownParser` reads all three since generation 8. Older bodies are
/// GitHub's "What's Changed" or hand-written. `0.2.1`'s is only a "Full
/// Changelog" link, so that version has no entry.
public enum BubChangelog {

    /// One page of 40 holds every release so far; `CLIToolChangelog.relevant`
    /// needs the reader's unseen releases plus five, and bub publishes about two
    /// a month.
    public static let source = URL(string: "https://api.github.com/repos/bubbuild/bub/releases?per_page=40")!

    /// Newest first, one entry per stable release; nil when no release yields one.
    public static func parse(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        // What `ChangelogService` sends to the GitHub API: the pinned media type and
        // version, and the token when there is one (5000 requests an hour instead
        // of 60 per IP, shared with every GitHub version check).
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
