import Foundation

/// The vendor's actual notes, including patch releases whose GitHub release
/// body is only a compare link. Pin to a published tag, excluding Unreleased.
public enum LeafChangelog {
    static func source(version: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/DeepanshuMishraa/leaf/v\(version)/CHANGELOG.md")!
    }

    public static func parse(_ markdown: String) -> Changelog? {
        let entries = AtuinChangelog.sections(markdown).filter { LeafRelease.isVersion($0.version) }.compactMap {
            GitHubMarkdownParser.parse(body: $0.body.joined(separator: "\n"), version: $0.version, date: nil)?.entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    static func fetch(force: Bool, version: String? = nil, session: URLSession = .updates) async throws -> Changelog {
        let published: String
        if let version, LeafRelease.isVersion(version) { published = version }
        else { published = try await LeafRelease(session: session).latest() }
        let url = source(version: published)
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 20
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            // Older tags may have notes only in their GitHub release bodies.
            let releases = URL(string: "https://api.github.com/repos/DeepanshuMishraa/leaf/releases?per_page=30")!
            return try await DenoChangelog.gitHubReleases(releases, force: force, session: session) { data in
                StructuredChangelogDecoder.decode(String(decoding: data, as: UTF8.self), format: .gitHubReleases,
                                                  channel: nil, maxEntries: nil, tagPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#)
            }
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CLIToolReleaseNotesError.status(http, url: url)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
