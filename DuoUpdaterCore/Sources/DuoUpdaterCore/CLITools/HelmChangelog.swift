import Foundation

/// Helm's release notes: its GitHub Releases (`helm/helm`), cut to the install's
/// own major line.
///
/// The shape, fetched 2026-10-09 (40 releases, back to 3.18.6): v3 and v4
/// releases interleaved (`v4.3.0`, `v3.22.0`, …), release candidates marked
/// prerelease. A body opens with a sentence or two and a bullet list of
/// community links (Slack channels, the developer call, ArtifactHub), then
/// usually `## Notable Changes` (`* type: … by @user in <pull URL>`) or
/// `## Security fixes`, then `## Installation and Upgrading` (download links and
/// their checksums), `## What's Next` and `## Changelog` (one line per commit,
/// `- <subject> <40-hex sha> (<author>)`). Some patch releases (3.21.3, 4.2.3,
/// the 3.19 patches) have no section of their own, only the commit list.
public enum HelmChangelog {

    public static let source = URL(string: "https://api.github.com/repos/helm/helm/releases?per_page=40")!

    /// The sections that are never this release's changes.
    static let skipSections = [
        "Installation and Upgrading", "What's Next", "What’s Next", "New Contributors", "Community", "Thank You!",
    ]

    /// Newest first, the line's stable releases only; nil when none yields one.
    public static func parse(_ json: String, major: Int) -> Changelog? {
        StructuredChangelogDecoder.decode(
            cleaned(json), format: .gitHubReleases, channel: nil, maxEntries: nil,
            skipSections: skipSections, tagPattern: "^v(\(major)\\.\\d+\\.\\d+)$")
    }

    /// Each body cut to what describes the release before the parser sees it
    /// (`cleanedBody`).
    static func cleaned(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              var releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return json }
        for index in releases.indices {
            guard let body = releases[index]["body"] as? String else { continue }
            releases[index]["body"] = cleanedBody(body)
        }
        guard let cleaned = try? JSONSerialization.data(withJSONObject: releases) else { return json }
        return String(decoding: cleaned, as: UTF8.self)
    }

    /// - From the first `## ` heading that is not the version itself on: the
    ///   opening sentence and community links before it would otherwise be
    ///   listed as changes.
    /// - With a section of its own (`## Notable Changes`, `## Security fixes`, …),
    ///   without `## Changelog`, the commit list behind them.
    /// - With none, the commit list kept, each line's trailing `<sha> (<author>)`
    ///   taken off.
    static func cleanedBody(_ raw: String) -> String {
        var body = "\n" + raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let first = body.range(of: "\n## ") else { return raw }
        body = String(body[first.lowerBound...])
        // 3.20.2 put its opening paragraph and the community links under a
        // `## v3.20.2` heading of their own: the same preamble, cut too.
        if body.range(of: #"^\n## v\d+\.\d+\.\d+\s*\n"#, options: .regularExpression) != nil,
           let next = body.dropFirst().range(of: "\n## ") {
            body = String(body[next.lowerBound...])
        }
        let headings = body.split(separator: "\n").filter { $0.hasPrefix("## ") }
            .map { $0.dropFirst(3).trimmingCharacters(in: .whitespaces) }
        let ownSections = headings.filter { !skipSections.contains($0) && $0 != "Changelog" }
        if !ownSections.isEmpty {
            if let changelog = body.range(of: "\n## Changelog\n") {
                let rest = body[changelog.upperBound...]
                let end = rest.range(of: "\n## ").map(\.lowerBound) ?? rest.endIndex
                body.removeSubrange(changelog.lowerBound..<end)
            }
        } else {
            body = body.replacingOccurrences(
                of: #"(?m) [0-9a-f]{40} \([^)\n]*\)$"#, with: "", options: .regularExpression)
        }
        return String(body.drop(while: \.isNewline))
    }

    static func fetch(major: Int, force: Bool, session: URLSession = .updates) async throws -> Changelog {
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
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self), major: major) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
