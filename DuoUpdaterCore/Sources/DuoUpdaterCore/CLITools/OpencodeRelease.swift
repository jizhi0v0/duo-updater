import Foundation

/// OpenCode's two release lines — where each one's newest version is — and the
/// notes both publish.
///
/// **OpenCode 1's channel** is the `latest` dist-tag of the `opencode-ai` npm
/// package, what `curl -fsSL https://opencode.ai/install | bash` installs when it
/// is given no `--version`. Its script says why npm and not GitHub: "The
/// opencode-ai npm package only contains OpenCode 1 (OpenCode 2 ships as
/// @opencode/cli). npm is published before the GitHub release, so fall back to
/// the newest v1 entry in GitHub's release list until its assets exist. GitHub's
/// Latest release may be OpenCode 2, so it's never used" (read 2026-10-31; that
/// day's answer was `1.19.5`).
///
/// **OpenCode 2's channel** is the endpoint its own installer reads,
/// `https://opencode.ai/update/api/latest/cli/npm`, which answers
/// `{"channel":"latest","name":"cli","distribution":"npm","version":"2.2.5",…}`
/// (2026-10-31) — the `@opencode/cli` release that installer then fetches from npm.
///
/// **Notes.** Both lines publish into the one GitHub repository, whose release
/// bodies are Markdown — `## Core`, `### Bugfixes`, a few bullets — closed by a
/// `**Thank you to N community contributors:**` paragraph listing pull requests
/// per author, which is credits, not notes. The repository also tags components
/// with their own scheme (`process-daemon-v0.4.0`), which `isVersion` rejects.
public struct OpencodeRelease: Sendable {

    public static let latestURL = URL(string: "https://registry.npmjs.org/opencode-ai/latest")!
    public static let secondURL = URL(string: "https://opencode.ai/update/api/latest/cli/npm")!
    public static let listURL = URL(string: "https://api.github.com/repos/anomalyco/opencode/releases?per_page=30")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
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
            // Two hosts answer here: npm's registry and opencode.ai for the two
            // channels, GitHub for the notes. Only GitHub wants its media type, its
            // API version and a token.
            if url.host == "api.github.com" {
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                if let token = await ChangelogService.gitHubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            let purpose: RequestPurpose = Self.readsVersion(url) ? .versionCheck : .changelog
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Whether `url` is one of the channels rather than the note list: the
    /// request log files the two apart.
    static func readsVersion(_ url: URL) -> Bool {
        url == latestURL || url == secondURL
    }

    /// OpenCode 1's newest: the `latest` dist-tag document of `opencode-ai`.
    public func latest() async throws -> String {
        let (data, status, _) = try await fetch(Self.latestURL, false)
        guard status == 200 else { throw Failure.http(status) }
        return try await offCooperativePool { try Self.parseLatest(data) }
    }

    /// `{"name":"opencode-ai","version":"1.19.5",…}`, the registry's dist-tag
    /// document. Only a 1.x version is OpenCode 1's channel: a 2.x published under
    /// this name would be the other line, and this read must not offer it.
    static func parseLatest(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, isVersion(version), major(of: version) == 1
        else { throw Failure.unreadable }
        return version
    }

    /// OpenCode 2's newest, or nil when its channel cannot be read or names
    /// something that is not OpenCode 2. Best-effort by design: this is a notice
    /// beside the 1.x verdict, and a channel that is down must not turn a current
    /// install into "unknown" (`OpencodeCheck`).
    public func second() async -> String? {
        guard let (data, status, _) = try? await fetch(Self.secondURL, false), status == 200 else { return nil }
        return await offCooperativePool { Self.parseSecond(data) }
    }

    /// The vendor's update document: `channel`, `name` ("cli"), `distribution`
    /// ("npm"), `version`. Anchored on all three so a change in what the endpoint
    /// serves degrades to "no OpenCode 2 seen" instead of to a made-up version.
    static func parseSecond(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, isVersion(version), major(of: version) >= 2,
              json["distribution"] as? String == "npm", json["name"] as? String == "cli"
        else { return nil }
        return version
    }

    /// The newest page of releases, one entry per release with notes, newest first.
    public func notes(force: Bool) async throws -> Changelog {
        let (data, status, remaining) = try await fetch(Self.listURL, force)
        guard status == 200 else {
            throw CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: Self.listURL)
        }
        let changelog = await offCooperativePool { Self.parseNotes(data) }
        guard let changelog else { throw CLIToolReleaseNotesError.noSections }
        return changelog
    }

    /// nil when the answer is not a release list.
    static func parseNotes(_ data: Data) -> Changelog? {
        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let entries = releases.compactMap { release -> Changelog.Entry? in
            guard release["draft"] as? Bool != true, release["prerelease"] as? Bool != true,
                  let tag = release["tag_name"] as? String, tag.hasPrefix("v"),
                  isVersion(String(tag.dropFirst())),
                  let body = release["body"] as? String
            else { return nil }
            let notes = withoutCredits(body)
            guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let date = StructuredChangelogDecoder.isoDay(release["published_at"] as? String)
            return GitHubMarkdownParser.parse(body: notes, version: String(tag.dropFirst()), date: date)?.entries.first
        }
        return Changelog(entries: entries.sorted { compare($0.version, $1.version) == .orderedDescending },
                         itemSyntax: .markdown)
    }

    /// The body up to its `**Thank you to … contributors:**` paragraph.
    static func withoutCredits(_ body: String) -> String {
        guard let credits = body.range(of: "**Thank you to ") else { return body }
        return String(body[..<credits.lowerBound])
    }

    /// `1.18.34`, `1.19.0-beta.2`: three numbers and an optional dotted
    /// alphanumeric suffix. Also what makes a version safe in a URL or an argument.
    static func isVersion(_ s: String) -> Bool {
        BunRelease.isVersion(s)
    }

    /// `1.19.5` → 1: which line a version belongs to. Only a version `isVersion`
    /// let through reaches here, so 0 never enters a comparison.
    static func major(of version: String) -> Int {
        Int(version.prefix { $0 != "." }) ?? 0
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        BunRelease.compare(a, b)
    }
}
