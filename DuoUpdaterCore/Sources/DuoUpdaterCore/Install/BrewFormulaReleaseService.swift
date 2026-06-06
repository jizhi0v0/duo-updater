import Foundation

/// Release notes for one outdated Homebrew formula. A formula isn't an app, so it
/// has no Sparkle/recipe changelog — but most formulae are GitHub-hosted, and a
/// formula's `urls.stable.url` (read locally from `brew info`) names the repo and
/// the release tag. From that we fetch the GitHub release body and parse it into the
/// same structured `Changelog` the app rows render, so formula notes look native.
/// Non-GitHub formulae (Go, GNU tools) fall back to their homepage.
public struct FormulaRelease: Sendable {
    /// Structured notes, when a GitHub release body was found and parsed. nil falls
    /// the UI back to `pageURL` (rendered in a web view).
    public let changelog: Changelog?
    /// The GitHub release/tag page, or the formula's homepage when it's not on
    /// GitHub — somewhere to read or link the notes when there's nothing structured.
    public let pageURL: URL?

    public init(changelog: Changelog?, pageURL: URL?) {
        self.changelog = changelog
        self.pageURL = pageURL
    }
}

/// Fetches a formula's release notes: `brew info` (local) for the repo/tag, then
/// the GitHub Releases API for the body. Lazy by design — the UI calls this only
/// when a formula is selected, so a screenful of outdated formulae never burns the
/// GitHub rate limit up front.
public actor BrewFormulaReleaseService {
    private let session: URLSession
    public init(session: URLSession = .updates) { self.session = session }

    public func release(for name: String, version: String, token: String?) async -> FormulaRelease {
        guard let info = Self.brewInfo(name: name) else {
            return FormulaRelease(changelog: nil, pageURL: nil)
        }
        guard let gh = Self.deriveGitHub(fromStableURL: info.stableURL) else {
            // Not GitHub-hosted (Go, GNU, …): the homepage is the best we can offer.
            return FormulaRelease(changelog: nil, pageURL: info.homepage)
        }

        let tagPage = URL(string:
            "https://github.com/\(gh.owner)/\(gh.repo)/releases/tag/\(Self.encode(gh.tag))")
        if let release = try? await fetchRelease(owner: gh.owner, repo: gh.repo, tag: gh.tag, token: token) {
            let changelog = release.body.flatMap {
                $0.isEmpty ? nil : GitHubMarkdownParser.parse(body: $0, version: version, date: release.publishedAt)
            }
            return FormulaRelease(changelog: changelog, pageURL: release.htmlURL ?? tagPage)
        }
        // The git tag exists but carries no GitHub *release* (common for tarball-only
        // tags): no body to parse, but the tag page (or homepage) still works.
        return FormulaRelease(changelog: nil, pageURL: tagPage ?? info.homepage)
    }

    // MARK: - brew info (local)

    private struct Info { let homepage: URL?; let stableURL: String? }

    /// Read `homepage` + `urls.stable.url` for one formula from `brew info
    /// --json=v2` — local, no network, authoritative for the installed formula.
    private static func brewInfo(name: String) -> Info? {
        guard let brew = HomebrewInstaller.brewPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["info", "--json=v2", "--formula", name]
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formula = (root["formulae"] as? [[String: Any]])?.first
        else { return nil }
        let homepage = (formula["homepage"] as? String).flatMap { URL(string: $0) }
        let stable = ((formula["urls"] as? [String: Any])?["stable"] as? [String: Any])?["url"] as? String
        return Info(homepage: homepage, stableURL: stable)
    }

    // MARK: - GitHub derivation

    struct GitHubRef: Equatable { let owner: String; let repo: String; let tag: String }

    /// Pull (owner, repo, tag) out of a formula's stable source URL. Handles the two
    /// GitHub forms Homebrew uses:
    ///   …/releases/download/<tag>/asset            (release asset)
    ///   …/archive/refs/tags/<tag>.tar.gz           (source tarball; also bare /archive/<tag>…)
    /// The tag is taken from the URL, NOT the formula version — some tags are
    /// prefixed (e.g. azure-cli's `azure-cli-2.87.0`).
    static func deriveGitHub(fromStableURL url: String?) -> GitHubRef? {
        guard let url else { return nil }
        let patterns = [
            #"github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/"#,
            #"github\.com/([^/]+)/([^/]+)/archive/(?:refs/tags/)?(.+?)\.(?:tar\.(?:gz|xz|bz2)|zip|tgz)$"#,
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(url.startIndex..., in: url)
            guard let m = re.firstMatch(in: url, range: range), m.numberOfRanges == 4,
                  let oR = Range(m.range(at: 1), in: url),
                  let rR = Range(m.range(at: 2), in: url),
                  let tR = Range(m.range(at: 3), in: url)
            else { continue }
            var repo = String(url[rR])
            if repo.hasSuffix(".git") { repo.removeLast(4) }
            return GitHubRef(owner: String(url[oR]), repo: repo, tag: String(url[tR]))
        }
        return nil
    }

    private static func encode(_ tag: String) -> String {
        tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
    }

    // MARK: - GitHub release fetch

    private struct Release { let body: String?; let htmlURL: URL?; let publishedAt: String? }

    private func fetchRelease(owner: String, repo: String, tag: String, token: String?) async throws -> Release? {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(Self.encode(tag))"
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil  // 404 = tag has no GitHub release; treat as "no structured notes"
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Release(
            body: obj["body"] as? String,
            htmlURL: (obj["html_url"] as? String).flatMap { URL(string: $0) },
            publishedAt: obj["published_at"] as? String
        )
    }
}
