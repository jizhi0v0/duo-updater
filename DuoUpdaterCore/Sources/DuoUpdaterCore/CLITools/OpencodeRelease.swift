import Foundation

/// What the installer would install, and OpenCode's release notes.
///
/// **Latest.** For a curl install OpenCode itself asks
/// `api.github.com/repos/anomalyco/opencode/releases/latest` (`Installation.latest`,
/// `v1.18.34`), as the installer does without `--version`; the version is
/// `tag_name` without its `v`. On 2026-10-04 it named `v1.18.34` (published
/// 2026-09-30), with `opencode-darwin-arm64.zip` (45,538,151 bytes) among its
/// assets. The repository moved from `sst/opencode`, which redirects.
///
/// **Notes.** Each release's body is Markdown — `## Core`, `### Bugfixes`, a few
/// bullets — closed by a `**Thank you to N community contributors:**` paragraph
/// listing pull requests per author, which is credits, not notes. Releases are
/// patch-sized and frequent (1.18.15 → 1.18.34 in eight weeks), with no
/// prereleases among the newest, so one page of the list holds a reader's window.
public struct OpencodeRelease: Sendable {

    public static let latestURL = URL(string: "https://api.github.com/repos/anomalyco/opencode/releases/latest")!
    public static let listURL = URL(string: "https://api.github.com/repos/anomalyco/opencode/releases?per_page=30")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        /// The release has no build for this Mac.
        case noBuild(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .noBuild(let asset): return "the release has no \(asset)"
            }
        }
    }

    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int)

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
            let purpose: RequestPurpose = url == OpencodeRelease.latestURL ? .versionCheck : .changelog
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The installer's asset for an architecture: `opencode-darwin-arm64.zip`,
    /// `opencode-darwin-x64.zip` (the installer takes `-baseline` on an x64 CPU
    /// without AVX2; either has the same version).
    static func asset(architecture: String) -> String {
        "opencode-darwin-\(architecture).zip"
    }

    public func latest(architecture: String) async throws -> String {
        let (data, status) = try await fetch(Self.latestURL, false)
        guard status == 200 else { throw Failure.http(status) }
        return try await offCooperativePool { try Self.parseLatest(data, asset: Self.asset(architecture: architecture)) }
    }

    static func parseLatest(_ data: Data, asset: String) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, tag.hasPrefix("v")
        else { throw Failure.unreadable }
        let version = String(tag.dropFirst())
        guard isVersion(version) else { throw Failure.unreadable }
        let names = ((json["assets"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        guard names.contains(asset) else { throw Failure.noBuild(asset) }
        return version
    }

    /// The newest page of releases, one entry per release with notes, newest first.
    public func notes(force: Bool) async throws -> Changelog {
        let (data, status) = try await fetch(Self.listURL, force)
        guard status == 200 else { throw CLIToolReleaseNotesError.http(status) }
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

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        BunRelease.compare(a, b)
    }
}
