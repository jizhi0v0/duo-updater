import Foundation

/// mise's release notes: its GitHub Releases (`jdx/mise`), the Releases API list
/// with the token `ChangelogService` sends.
///
/// The shape, fetched 2026-10-09: 30 releases back to 2026.8.13, none marked
/// prerelease, 3–20 KB each. A body opens with a prose summary, then `## Added`,
/// `## Changed`, `## Fixed`, … with one bullet per change led by a bold title
/// and ending in its pull request links. Some bullets continue on indented
/// lines, and some carry an indented paragraph or a fenced example after a
/// blank line. Then `## New Contributors`, a `**Full Changelog**` link and
/// `## 💚 Sponsor mise`, a sponsorship appeal.
///
/// Each body goes through `UvChangelog.releaseBody` first, so the summary
/// paragraph becomes the entry's first item (the parser alone reads only
/// bullets when there are any, and would drop it), then `GitHubMarkdownParser`,
/// which joins wrapped bullets, keeps the section headings, leaves a bullet's
/// indented explanation and fenced example after a blank line out, and drops
/// the contributor and full-changelog sections by keyword. The sponsorship
/// section is skipped by name. Measured on the 30 releases: 812 items, 29 of
/// the entries with headings, none of them sponsorship or contributor lines.
public enum MiseChangelog {

    /// About one release a day; 30 reach back six weeks.
    public static let source = URL(string: "https://api.github.com/repos/jdx/mise/releases?per_page=30")!

    static let skipSections = ["💚 Sponsor mise"]

    struct Release: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let publishedAt: String?
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft
            case publishedAt = "published_at"
            case body
        }
    }

    /// Newest first, one entry per release; nil when no release yields one.
    public static func parse(_ data: Data) -> Changelog? {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return nil }
        let entries = releases.compactMap { release -> Changelog.Entry? in
            guard !release.prerelease, !release.draft, let body = release.body, release.tagName.hasPrefix("v")
            else { return nil }
            let version = String(release.tagName.dropFirst())
            guard MiseRelease.isVersion(version) else { return nil }
            let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
            return GitHubMarkdownParser.parse(
                body: UvChangelog.releaseBody(lines).body, version: version,
                date: StructuredChangelogDecoder.isoDay(release.publishedAt), skipSections: skipSections)?
                .entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        try await DenoChangelog.gitHubReleases(source, force: force, session: session) { parse($0) }
    }
}
