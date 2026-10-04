import Foundation

/// What `bun upgrade` would install: the release its own channel names.
///
/// bun 1.3.10's `upgrade_command.zig` (`bun-v1.3.10`, read 2026-10-04) asks
/// `https://api.github.com/repos/Jarred-Sumner/bun-releases-for-updater/releases/latest`
/// — not oven-sh/bun's own releases — takes the version out of `tag_name`
/// (`bun-v<version>`), and downloads the asset named `bun-darwin-<arch>.zip`
/// (`application/zip`). On 2026-10-04 both repositories' latest was `bun-v1.4.2`
/// (published 2026-09-05), as was the npm registry's `bun`. A canary build asks
/// nothing: it downloads oven-sh/bun's `canary` tag, which has no version.
///
/// It is GitHub's API, so each check costs one of 60 anonymous calls an hour;
/// the token `ChangelogService` keeps is sent when there is one, and the
/// version-feed cache policy revalidates with the `ETag`.
public struct BunRelease: Sendable {

    public static let channel =
        URL(string: "https://api.github.com/repos/Jarred-Sumner/bun-releases-for-updater/releases/latest")!

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

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch
    /// `bun-darwin-aarch64.zip` or `bun-darwin-x64.zip`: the build `bun upgrade`
    /// on this Mac downloads.
    let asset: String

    public init(session: URLSession = .updates, arch: HostArch = .current) {
        self.init(
            fetch: { url in
                var request = URLRequest(url: url)
                request.cachePolicy = URLRequest.versionFeedCachePolicy
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                if let token = await ChangelogService.gitHubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            },
            asset: Self.assetName(arch))
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch, asset: String = "bun-darwin-aarch64.zip") {
        self.fetch = fetch
        self.asset = asset
    }

    static func assetName(_ arch: HostArch) -> String {
        arch == .arm64 ? "bun-darwin-aarch64.zip" : "bun-darwin-x64.zip"
    }

    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.channel)
        guard status == 200 else { throw Failure.http(status) }
        let asset = self.asset
        return try await offCooperativePool { try Self.parse(data, asset: asset) }
    }

    static func parse(_ data: Data, asset: String) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, tag.hasPrefix("bun-v")
        else { throw Failure.unreadable }
        let version = String(tag.dropFirst("bun-v".count))
        guard isVersion(version) else { throw Failure.unreadable }
        let names = ((json["assets"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        guard names.contains(asset) else { throw Failure.noBuild(asset) }
        return version
    }

    /// `1.4.2`, `1.3.11-canary.20`: three numbers and an optional dotted
    /// alphanumeric suffix. Also what makes a version safe in a URL or a message.
    static func isVersion(_ s: String) -> Bool {
        guard s.count <= 40 else { return false }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return false }
        guard parts.count == 2 else { return true }
        return !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }

    /// Release order, as npm's semver orders bun's versions: a prerelease sorts
    /// below its release.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        switch (NpmVersion(a), NpmVersion(b)) {
        case let (x?, y?): return x < y ? .orderedAscending : (y < x ? .orderedDescending : .orderedSame)
        default: return VersionComparator.compare(a, b)
        }
    }
}
