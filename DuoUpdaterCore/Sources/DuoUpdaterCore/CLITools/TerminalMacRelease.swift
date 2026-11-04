import Foundation

/// terminal-mac's latest release, as its installer reads it: one GitHub release,
/// one signed archive.
///
/// The data, read from `govijr/terminal-mac` on 2026-11-04: releases are tagged
/// `v<marketing>-<build>` (`v0.2.0-4`, `v0.2.0-5`, `v0.2.0-6` were published the
/// same day, all stable), and each carries
/// `terminal-mac-<marketing>-<build>-macos-arm64.zip`, its `.sha256` and the
/// `get.sh` that pins both. GitHub's asset `digest` is the sha256 of the zip
/// itself, so the check gets the digest the installer's own `get.sh` hardcodes
/// without downloading the zip or the `.sha256`.
///
/// **One channel.** No release is a prerelease or a draft, and the app has no
/// update command or channel setting; the installer always takes the latest
/// release. Releases are immutable (the vendor's `release.sh` refuses to replace
/// a version/build), which is what lets the updater pin one tag between the
/// check and the click.
public struct TerminalMacRelease: Sendable {

    public static let latestURL = URL(string: "https://api.github.com/repos/govijr/terminal-mac/releases/latest")!

    /// `https://github.com/govijr/terminal-mac/releases/download`, where a
    /// release's assets live.
    static let downloadBase = "https://github.com/govijr/terminal-mac/releases/download"

    /// One release, with everything the check and the updater need.
    public struct Published: Sendable, Equatable {
        /// `CFBundleShortVersionString`: `0.2.0`.
        public let marketing: String
        /// `CFBundleVersion`: `6`.
        public let build: String
        /// `v0.2.0-6`: the tag and the URL path segment.
        public let tag: String
        /// `terminal-mac-0.2.0-6-macos-arm64.zip`.
        public let asset: String
        public let zip: URL
        /// The zip's sha256, lowercase hex (GitHub's `digest` without `sha256:`).
        public let digest: String

        public var side: VersionSide { VersionSide(marketing: marketing, build: build) }
        public var displayVersion: String { side.text(withBuild: true) }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case rateLimited(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .rateLimited(let status):
                return GitHubReleasesSource.GitHubError.rateLimited(status).errorDescription ?? "HTTP \(status)"
            case .unreadable: return "the release could not be read"
            }
        }
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            // A cached answer would keep a row "up to date" without a request
            // (the review rule every version feed follows).
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if ChangelogService.isGitHubAPI(url), let token = await ChangelogService.gitHubToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func latest() async throws -> Published {
        let (data, status) = try await fetch(Self.latestURL)
        switch status {
        case 200:
            guard let published = await offCooperativePool({ Self.parse(data) }) else {
                throw Failure.unreadable
            }
            return published
        case 403, 429:
            throw Failure.rateLimited(status)
        default:
            throw Failure.http(status)
        }
    }

    /// The release JSON as `releases/latest` answers it. Nil for anything that
    /// is not a stable terminal-mac arm64 release: a draft, a prerelease, a tag
    /// in another shape, or an archive with no published digest or with an
    /// address outside the vendor's releases.
    static func parse(_ data: Data) -> Published? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true,
              json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let parts = parseTag(tag),
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        let asset = "terminal-mac-\(parts.marketing)-\(parts.build)-macos-arm64.zip"
        guard let entry = assets.first(where: { $0["name"] as? String == asset }),
              let address = entry["browser_download_url"] as? String,
              let url = URL(string: address), url.scheme == "https", url.host == "github.com",
              url.path == "/govijr/terminal-mac/releases/download/\(tag)/\(asset)",
              let digest = digest(entry["digest"] as? String)
        else { return nil }
        return Published(marketing: parts.marketing, build: parts.build, tag: tag, asset: asset, zip: url,
                         digest: digest)
    }

    /// `v0.2.0-6` → `0.2.0` and `6`. Nil for the bare `v0.2.0` or anything a
    /// publisher would have written by hand without its build.
    static func parseTag(_ tag: String) -> (marketing: String, build: String)? {
        guard tag.hasPrefix("v") else { return nil }
        let parts = tag.dropFirst().split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}$"#, options: .regularExpression) != nil,
              parts[1].range(of: #"^[1-9]\d{0,8}$"#, options: .regularExpression) != nil
        else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// GitHub's `digest`, `"sha256:<64 hex>"`, as the bare lowercase hex.
    static func digest(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.lowercased()
        guard value.hasPrefix("sha256:") else { return nil }
        let hex = value.dropFirst("sha256:".count)
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return String(hex)
    }


    /// The `get.sh` pinned to `published`'s tag: what a person would run, and
    /// the command the row hands over when it cannot click.
    static func getScriptURL(tag: String) -> URL {
        URL(string: "\(downloadBase)/\(tag)/get.sh")!
    }
}
