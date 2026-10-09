import Foundation

/// flyctl's release notes: its GitHub Releases, read as Luvus's are
/// (`LuvusChangelog`) — the Releases API list, the token `ChangelogService`
/// sends, and `StructuredChangelogDecoder`'s `.gitHubReleases` format.
///
/// The shape, fetched 2026-10-09: a release almost every weekday, none marked
/// prerelease since 0.2.24-pre-1. A body is goreleaser's `## Changelog` and one
/// bullet per commit, `* <40-hex sha> <subject> (#<pr>)`. The full commit hash
/// leads every bullet and says nothing to a reader, so it is taken off before
/// the parser sees the body.
public enum FlyctlChangelog {

    /// Thirty releases is about six weeks.
    public static let source = URL(string: "https://api.github.com/repos/superfly/flyctl/releases?per_page=30")!

    /// Newest first, one entry per release; nil when no release yields one.
    public static func parse(_ json: String) -> Changelog? {
        let cleaned = json.replacingOccurrences(of: #"\* [0-9a-f]{40} "#, with: "* ", options: .regularExpression)
        return StructuredChangelogDecoder.decode(cleaned, format: .gitHubReleases, channel: nil, maxEntries: nil)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
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
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
