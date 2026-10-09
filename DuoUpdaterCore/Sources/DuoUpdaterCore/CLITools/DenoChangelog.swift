import Foundation

/// Deno's release notes: its GitHub Releases (`denoland/deno`), the Releases
/// API list with the token `ChangelogService` sends.
///
/// The shape, fetched 2026-10-09: 30 releases back to 2.6.8, none marked
/// prerelease. A body is `### 2.9.7 / 2026.09.16`, sometimes a `Read more:
/// <blog link>` line (minor releases), then one flat list of `- fix(cli): …
/// (#36835)` bullets — 2.9.0 has about a hundred — wrapped at 80 columns, the
/// continuation indented two spaces. `StructuredChangelogDecoder`'s
/// `.gitHubReleases` format reads them: `GitHubMarkdownParser` joins a wrapped
/// bullet's lines (`joiningListContinuations`) and keeps the bullets only, so
/// the `Read more:` line is not an item; the `### <version> / <date>` heading
/// carries digits, so it is never styled. The entries have no headings because
/// the notes have none. Measured on the 30 releases: 2,003 items, every
/// wrapped bullet whole.
public enum DenoChangelog {

    /// About one release a week; 30 reach back eight months, enough for
    /// `CLIToolChangelog.relevant`, which needs the reader's unseen releases plus
    /// five.
    public static let source = URL(string: "https://api.github.com/repos/denoland/deno/releases?per_page=30")!

    /// Newest first, one entry per stable release; nil when no release yields one.
    public static func parse(_ data: Data) -> Changelog? {
        StructuredChangelogDecoder.decode(
            String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: nil, maxEntries: nil)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        try await gitHubReleases(source, force: force, session: session) { parse($0) }
    }

    /// A GitHub Releases list, as `LuvusChangelog.fetch` asks for one, parsed.
    static func gitHubReleases(
        _ source: URL, force: Bool, session: URLSession, parse: @escaping @Sendable (Data) -> Changelog?
    ) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if ChangelogService.isGitHubAPI(source), let token = await ChangelogService.gitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(data) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
