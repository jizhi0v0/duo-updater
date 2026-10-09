import Foundation

/// What `deno upgrade` would install: the newest stable release, as Deno itself
/// reads it.
///
/// `deno upgrade` with no argument (`cli/tools/upgrade.rs`, v2.9.7) asks
/// `https://dl.deno.land/release-latest.txt` — a single line, `v2.9.7` on
/// 2026-10-09, agreeing with GitHub's latest release — and installs that version
/// from GitHub's release assets (or patches the running build up to it with the
/// bsdiff deltas it has fetched first since 2.8). The installer reads the same
/// file. The LTS, RC and canary channels have files of their own
/// (`release-lts-latest.txt`, `release-rc-latest.txt`, `canary-<target>-latest.txt`);
/// only stable builds are offered an update (`DenoInstall`), so only this one is
/// read.
///
/// The answer carries `cache-control: max-age=14400` and an `ETag`, hence the
/// version-feed cache policy, which revalidates instead of trusting four hours.
public struct DenoRelease: Sendable {

    public static let channel = URL(string: "https://dl.deno.land/release-latest.txt")!

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

    /// The body and the status. Injected so tests never reach the network.
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

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.channel)
        guard status == 200 else { throw Failure.http(status) }
        guard let version = Self.parse(data) else { throw Failure.unreadable }
        return version
    }

    /// `v2.9.7` (and a trailing newline) → `2.9.7`. Anything else — an error
    /// page, a prerelease — is nil.
    static func parse(_ data: Data) -> String? {
        guard data.count <= 64 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("v") else { return nil }
        let version = String(text.dropFirst())
        guard isVersion(version), !version.contains("-") else { return nil }
        return version
    }

    /// `2.9.7`, `2.0.0-rc.10`: three numbers and an optional dotted alphanumeric
    /// suffix. Also what makes a version safe in a message.
    static func isVersion(_ s: String) -> Bool {
        BunRelease.isVersion(s)
    }

    /// Release order, as semver orders it: a prerelease sorts below its release.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        BunRelease.compare(a, b)
    }
}
