import Foundation

/// Starship's release notes: its GitHub Releases, read as Luvus's are
/// (`LuvusChangelog`).
///
/// The shape, fetched 2026-10-09: release-please's — `## [1.26.0](<compare>)
/// (<date>)`, then `### Features`, `### Bug Fixes`, `### Performance
/// Improvements`, each bullet `* **<scope>:** <text> ([#n](…)) ([<sha>](…))`.
/// None marked prerelease. Releases come every month or two, so thirty reach
/// back years.
public enum StarshipChangelog {

    public static let source = URL(string: "https://api.github.com/repos/starship/starship/releases?per_page=30")!

    public static func parse(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil)
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
