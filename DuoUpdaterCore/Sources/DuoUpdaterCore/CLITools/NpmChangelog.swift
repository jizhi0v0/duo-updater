import Foundation

/// A global npm package's release notes: the GitHub Releases of the repository
/// its installed `package.json` names, for the versions the row is about.
///
/// npm has no changelog of its own, and the registry's abbreviated metadata
/// carries no `repository`, so the installed manifest is where the repository
/// comes from. Only GitHub is read. A package with no repository, or one whose
/// repository has no releases for these versions, has an empty changelog — not
/// an error: `@tencent-qqmail/agently-cli` 1.0.6 names none (2026-10-02).
///
/// A release belongs to a version only by an **exact** tag: `v<version>`,
/// `<version>` or `<name>@<version>` (monorepos — pnpm's repository also carries
/// `pnpr@0.1.0-alpha.14`). Never "the first release in the list". Some
/// repositories have no tag for some versions (npm/cli); those versions have no
/// entry.
///
/// Measured 2026-10-02: openclaw/openclaw tags `v2026.9.7`, and lists its
/// maintenance lines out of version order (`v2026.8.33` between `v2026.9.7` and
/// `v2026.9.6`); vercel-labs/agent-browser `v0.38.1`; pnpm/pnpm `v12.8.2`.
/// geelen/mcp-remote is a renamed repository: `api.github.com/repos/geelen/…`
/// answers 301 to `/repositories/951601187/…`, and `URLSession` drops the
/// `Authorization` header following it, so that list is fetched with the
/// anonymous rate limit. The follow-up requests below go to the address the
/// redirect named, so they keep the token.
public enum NpmChangelog {

    public struct Repository: Sendable, Equatable {
        public let owner: String
        public let name: String
    }

    /// At most this many per-tag requests after the list, for versions the first
    /// page of releases did not reach.
    static let followUpLimit = 10

    /// The GitHub repository a `package.json` `repository` names, or nil:
    /// `github:o/r`, the bare `o/r` shorthand, and `https://`, `git+https://`,
    /// `git://`, `git+ssh://git@` and `git@github.com:` URLs, with or without `.git`.
    public static func gitHubRepository(_ raw: String?) -> Repository? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("github:") {
            text = String(text.dropFirst("github:".count))
        } else if !text.contains(":") {
            // `owner/repo` with nothing else is npm's GitHub shorthand.
        } else {
            let patterns = [#"^(?:git\+)?(?:https?|git|ssh)://(?:[^@/]+@)?github\.com[:/](.+)$"#, #"^git@github\.com:(.+)$"#]
            let range = NSRange(text.startIndex..., in: text)
            guard let path = patterns.lazy.compactMap({ pattern -> String? in
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: text, range: range),
                      let captured = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[captured])
            }).first else { return nil }
            text = path
        }
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        if text.hasSuffix(".git") { text.removeLast(4) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let allowed = { (c: Character) in c.isASCII && (c.isLetter || c.isNumber || "-_.".contains(c)) }
        guard parts.allSatisfy({ $0.allSatisfy(allowed) }) else { return nil }
        return Repository(owner: String(parts[0]), name: String(parts[1]))
    }

    /// The tags a release of `version` of `name` may carry, in the order tried.
    static func tags(name: String, version: String) -> [String] {
        ["v\(version)", version, "\(name)@\(version)"]
    }

    /// One entry per version in `versions` that has a release, in that order
    /// (newest first). `releases` is the API's list (`/releases`).
    static func parse(_ releases: Data, name: String, versions: [String]) -> (Changelog, missing: [String])? {
        guard let list = try? JSONSerialization.jsonObject(with: releases) as? [[String: Any]] else { return nil }
        var byTag: [String: [String: Any]] = [:]
        for release in list where (release["draft"] as? Bool) != true {
            if let tag = release["tag_name"] as? String, byTag[tag] == nil { byTag[tag] = release }
        }
        var entries: [Changelog.Entry] = []
        var missing: [String] = []
        for version in versions {
            guard let release = tags(name: name, version: version).lazy.compactMap({ byTag[$0] }).first else {
                missing.append(version)
                continue
            }
            if let entry = entry(release, version: version) { entries.append(entry) }
        }
        return (Changelog(entries: entries, itemSyntax: .markdown), missing)
    }

    /// The release body through `GitHubMarkdownParser`; nil when it says nothing
    /// (an empty body, a lone "Full Changelog" link).
    static func entry(_ release: [String: Any], version: String) -> Changelog.Entry? {
        guard let body = release["body"] as? String, !body.isEmpty else { return nil }
        let date = (release["published_at"] as? String).map { String($0.prefix(10)) }
        return GitHubMarkdownParser.parse(body: body, version: version, date: date)?.entries.first
    }

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Token = @Sendable () async -> String?

    /// The notes for `versions` (newest first) of the package at `repository`.
    static func fetch(
        repository raw: String?, name: String, versions: [String], force: Bool,
        fetch: Fetch = { try await URLSession.updates.countedData(for: $0, purpose: .changelog) },
        token: Token = { await ChangelogService.gitHubToken() }
    ) async throws -> Changelog {
        guard let repository = gitHubRepository(raw), !versions.isEmpty else { return Changelog(entries: []) }
        let list = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases?per_page=100")!
        let (data, response) = try await fetch(await request(list, force: force, token: token))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A repository that is gone or private has no notes to show.
        if status == 404 { return Changelog(entries: []) }
        guard (200..<300).contains(status) else { throw CLIToolReleaseNotesError.http(status) }
        guard let (first, missing) = await offCooperativePool({ parse(data, name: name, versions: versions) })
        else { throw CLIToolReleaseNotesError.noSections }
        // A full page may have left older releases out; anything shorter is all.
        let pageCount = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
        guard pageCount >= 100, !missing.isEmpty else { return first }

        // The releases endpoint as the server named it — after a rename's
        // redirect, `/repositories/<id>/releases` — so the token is sent again.
        var base = response.url ?? list
        base = URL(string: base.absoluteString.components(separatedBy: "?")[0])!
        var found: [String: Changelog.Entry] = [:]
        var requests = 0
        search: for version in missing {
            for tag in tags(name: name, version: version) {
                guard requests < followUpLimit else { break search }
                requests += 1
                let escaped = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? tag
                let url = base.appendingPathComponent("tags").appendingPathComponent(escaped, isDirectory: false)
                guard let (body, answer) = try? await fetch(await request(url, force: force, token: token)),
                      (answer as? HTTPURLResponse)?.statusCode == 200,
                      let release = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      (release["draft"] as? Bool) != true
                else { continue }
                if let entry = entry(release, version: version) { found[version] = entry }
                continue search
            }
        }
        let merged = versions.compactMap { version in
            first.entries.first { $0.version == version } ?? found[version]
        }
        return Changelog(entries: merged, itemSyntax: .markdown)
    }

    /// What `ChangelogService` sends to the GitHub API: the pinned media type and
    /// version, and the token when there is one.
    static func request(_ url: URL, force: Bool, token: Token) async -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if ChangelogService.isGitHubAPI(url), let token = await token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
