import Foundation

/// nvm's latest release and its release notes, from its GitHub Releases.
///
/// **Latest.** `api.github.com/repos/nvm-sh/nvm/releases/latest`: `v0.40.8` on
/// 2026-10-09 (published 2026-09-21; about one a month). The releases carry no
/// assets — the installer fetches the tag's files from
/// raw.githubusercontent.com — and none of the newest thirty is a prerelease.
///
/// **Notes.** Each body is `## <Section>` headings (`## Bug Fixes`, `## New
/// Stuff`, `## Robustness`, `## Docs`, `## Tests`, …) over ` - ` bullets with a
/// single leading space, the shape `GitHubMarkdownParser` already reads
/// (`GitHubMarkdownParserTests`, nvm style).
public struct NvmRelease: Sendable {

    public static let latestURL = URL(string: "https://api.github.com/repos/nvm-sh/nvm/releases/latest")!
    public static let listURL = URL(string: "https://api.github.com/repos/nvm-sh/nvm/releases?per_page=30")!

    /// The documented update: the installer of the newer tag, run again (README,
    /// "Install & Update Script").
    static func installer(version: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/nvm-sh/nvm/v\(version)/install.sh")!
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        /// GitHub's API rate limit (`GitHubReleasesSource.isRateLimited`).
        case rateLimited(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .rateLimited(let status):
                return GitHubReleasesSource.GitHubError.rateLimited(status).errorDescription ?? "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            }
        }
    }

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url, force in
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token = await ChangelogService.gitHubToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let purpose: RequestPurpose = url == NvmRelease.latestURL ? .versionCheck : .changelog
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The latest release's version, without its `v`.
    public func latest() async throws -> String {
        let (data, status, remaining) = try await fetch(Self.latestURL, false)
        guard status == 200 else {
            throw GitHubReleasesSource.isRateLimited(status, rateLimitRemaining: remaining)
                ? Failure.rateLimited(status) : Failure.http(status)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, tag.hasPrefix("v"),
              case let version = String(tag.dropFirst()), Self.isVersion(version)
        else { throw Failure.unreadable }
        return version
    }

    /// `0.40.8`. Also what keeps a version safe in the command's URL.
    static func isVersion(_ s: String) -> Bool {
        ZoxideRelease.isVersion(s)
    }

    /// The newest page of releases, one entry per release, newest first.
    public func notes(force: Bool) async throws -> Changelog {
        let (data, status, remaining) = try await fetch(Self.listURL, force)
        guard status == 200 else {
            throw CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: Self.listURL)
        }
        let parsed = await offCooperativePool { Self.parseNotes(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }

    static func parseNotes(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil)
    }
}
