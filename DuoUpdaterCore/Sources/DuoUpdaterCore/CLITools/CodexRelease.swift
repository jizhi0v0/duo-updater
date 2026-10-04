import Foundation

/// What the standalone installer would install: the release its `latest`
/// channel names.
///
/// `install.sh` (`rust-v0.160.0`) asks `https://releases.openai.com/codex/channels/latest`
/// first (`resolve_release_from_releases`) and falls back to GitHub's
/// `releases/latest` only when that fails. The answer is GitHub's release object
/// re-hosted — `tag_name` and an `assets` array of `name`, `digest`
/// (`sha256:<hex>`) and `browser_download_url` — and the installer takes the
/// version out of `tag_name` (`rust-v<version>`). On 2026-10-04 it answered
/// `rust-v0.160.0`, 176 assets, 52,514 bytes, `cache-control: public, max-age=300`
/// and an `ETag`, so the version-feed cache policy revalidates. The channel
/// carries stable releases only: the alphas (`0.162.0-alpha.12` the same day) are
/// GitHub prereleases, which neither source names as latest.
///
/// The installer needs the release's `codex-package-<target>.tar.gz` and
/// `codex-package_SHA256SUMS` (it falls back to the legacy npm tarball
/// otherwise), so a channel without them for this Mac is not offered.
public struct CodexRelease: Sendable {

    public static let channel = URL(string: "https://releases.openai.com/codex/channels/latest")!

    /// The installer's own channel name: it installs `CODEX_RELEASE`, default
    /// `latest`, and DuoUpdater never sets another.
    public static let channelName = "latest"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        /// The release has no package for this Mac.
        case noPackage(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .noPackage(let target): return "the release has no package for \(target)"
            }
        }
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The version `latest` names, for `target`.
    public func latest(target: String) async throws -> String {
        let (data, status) = try await fetch(Self.channel)
        guard status == 200 else { throw Failure.http(status) }
        return try await offCooperativePool { try Self.parse(data, target: target) }
    }

    static func parse(_ data: Data, target: String) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, tag.hasPrefix("rust-v")
        else { throw Failure.unreadable }
        let version = String(tag.dropFirst("rust-v".count))
        guard isVersion(version) else { throw Failure.unreadable }
        let names = Set(((json["assets"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String })
        guard names.contains("codex-package-\(target).tar.gz"), names.contains("codex-package_SHA256SUMS") else {
            throw Failure.noPackage(target)
        }
        return version
    }

    /// The versions the installer accepts (`validate_version`):
    /// `x.y.z[-alpha[.N[.M]]|-beta[.N]]`. Also what makes a version safe to put
    /// in a URL or a path.
    static func isVersion(_ s: String) -> Bool {
        parse(s) != nil
    }

    /// Numbers, then the pre-release's rank (alpha 0, beta 1, a release 2) and its
    /// own numbers.
    private struct Parsed {
        let core: [Int]
        let rank: Int
        let pre: [Int]
    }

    private static func parse(_ s: String) -> Parsed? {
        guard s.count <= 40 else { return nil }
        let halves = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        func numbers<S: StringProtocol>(_ part: S) -> [Int]? {
            let pieces = part.split(separator: ".", omittingEmptySubsequences: false)
            var values: [Int] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.count <= 9, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int(piece)
                else { return nil }
                values.append(value)
            }
            return values
        }
        guard let core = numbers(halves[0]), core.count == 3 else { return nil }
        guard halves.count == 2 else { return Parsed(core: core, rank: 2, pre: []) }
        let tail = halves[1]
        for (label, rank, most) in [("alpha", 0, 2), ("beta", 1, 1)] where tail.hasPrefix(label) {
            let rest = tail.dropFirst(label.count)
            if rest.isEmpty { return Parsed(core: core, rank: rank, pre: []) }
            guard rest.hasPrefix("."), let pre = numbers(rest.dropFirst()), pre.count <= most else { return nil }
            return Parsed(core: core, rank: rank, pre: pre)
        }
        return nil
    }

    /// Semantic order: `0.160.0-alpha.6.2` < `0.160.0-beta` < `0.160.0` <
    /// `0.161.0-alpha.1`. A string that is not a Codex version sorts below every
    /// one that is, so it is never "newer".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        switch (parse(a), parse(b)) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (x?, y?):
            for (l, r) in zip(x.core, y.core) where l != r { return l < r ? .orderedAscending : .orderedDescending }
            if x.rank != y.rank { return x.rank < y.rank ? .orderedAscending : .orderedDescending }
            for index in 0..<max(x.pre.count, y.pre.count) {
                let l = index < x.pre.count ? x.pre[index] : -1
                let r = index < y.pre.count ? y.pre[index] : -1
                if l != r { return l < r ? .orderedAscending : .orderedDescending }
            }
            return .orderedSame
        }
    }
}
