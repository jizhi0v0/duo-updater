import Foundation

/// herdr's release notes, from the stable manifest `herdr update` reads
/// (`https://herdr.dev/latest.json`): its `releases` map carries every stable
/// release's `notes`, the Markdown herdr shows itself after an update and puts
/// in the GitHub release body — `### Added`, `### Changed`, `### Fixed`, … with
/// one bullet per change, sometimes a line of prose first (0.9.3: "This is a
/// hotfix release for v0.9.2. …"). Each goes through `GitHubMarkdownParser`.
///
/// Fetched 2026-10-07: 59 releases, 0.1.0 to 0.9.3, every one with notes. The
/// manifest dates none of them, so the entries carry no date. Preview builds
/// have no notes of their own ("Preview build <id>" and a compare link), so a
/// preview reader sees the stable notes up to its base.
public enum HerdrChangelog {

    public static var source: URL { HerdrRelease.stableManifest }

    /// Newest first, one entry per release with notes; nil when none yields one.
    public static func parse(_ data: Data) -> Changelog? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = json["releases"] as? [String: Any]
        else { return nil }
        let entries = releases.compactMap { name, value -> Changelog.Entry? in
            guard HerdrBuild.isBase(name), let notes = (value as? [String: Any])?["notes"] as? String,
                  !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return GitHubMarkdownParser.parse(body: notes, version: name, date: nil)?.entries.first
        }
        guard !entries.isEmpty else { return nil }
        return Changelog(
            entries: entries.sorted { VersionComparator.compare($0.version, $1.version) == .orderedDescending },
            itemSyntax: .markdown)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        let parsed = await offCooperativePool { parse(data) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
