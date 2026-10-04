import Foundation

/// What `boat self-update` would install, and the hash the vendor published for
/// a build.
///
/// **The channel.** The binary asks
/// `https://boat.dev/api/boat/cli/version?platform=darwin-<arch>&channel=<channel>&current=<version>`
/// (the URL is in its error output) and installs the `downloadUrl` it answers,
/// after checking it against that release's `SHA256SUMS`. Answers on 2026-10-04:
///
///     {"requestedChannel":"prod","channel":"prod","platform":"darwin-arm64","current":"1.0.37",
///      "version":"1.0.38","tag":"boat-cli-v1.0.38","updateAvailable":true,
///      "downloadUrl":"https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-v1.0.38/boat-darwin-arm64"}
///     {"requestedChannel":"beta",…,"error":"No Boat CLI release found for channel beta",…}
///
/// `staging` answered `1.0.34-staging1`; `beta`, `dev` and `canary` the error.
/// The server's `updateAvailable` is `current != version` — `1.0.39` and
/// `garbage` both read as "update available" — so a newer copy would be
/// *downgraded* by `self-update`. The verdict therefore compares the versions
/// itself (`BoatCheck`) and `current` is not sent.
///
/// **The hash.** Every `boat-cli-v<version>` release on GitHub carries a
/// `SHA256SUMS` (417 bytes for 1.0.38), `<hex>  boat-darwin-arm64` per line.
/// The binary's own update refuses to run without it ("refusing CLI update:
/// could not fetch release SHA256SUMS").
public struct BoatRelease: Sendable {

    public static let api = URL(string: "https://boat.dev/api/boat/cli/version")!

    public struct Latest: Sendable, Equatable {
        public let version: String
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        /// The server's own `error`, e.g. a channel with no release.
        case server(String)
        /// `SHA256SUMS` names no build for this platform.
        case noDigest

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .server(let message): return message
            case .noDigest: return "SHA256SUMS lists no build for this Mac"
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

    public func latest(channel: String, platform: String) async throws -> Latest {
        var components = URLComponents(url: Self.api, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: platform), URLQueryItem(name: "channel", value: channel),
        ]
        let (data, status) = try await fetch(components.url!)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? String { throw Failure.server(error) }
        guard status == 200 else { throw Failure.http(status) }
        guard let version = json?["version"] as? String, Self.isVersion(version) else { throw Failure.unreadable }
        return Latest(version: version)
    }

    public static func sumsURL(version: String) -> URL {
        URL(string: "https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-v\(version)/SHA256SUMS")!
    }

    /// The sha256 the `boat-cli-v<version>` release publishes for
    /// `boat-<platform>`, lowercase hex.
    public func publishedDigest(version: String, platform: String) async throws -> String {
        guard Self.isVersion(version) else { throw Failure.unreadable }
        let (data, status) = try await fetch(Self.sumsURL(version: version))
        guard status == 200 else { throw Failure.http(status) }
        guard let digest = Self.digest(in: String(decoding: data, as: UTF8.self), asset: "boat-\(platform)") else {
            throw Failure.noDigest
        }
        return digest
    }

    /// The line naming `asset` exactly (`boat-darwin-arm64`, not
    /// `boat-darwin-arm64.exe`), in sha256sum's text or binary (`*name`) form.
    static func digest(in sums: String, asset: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count == 2 else { continue }
            let name = words[1].hasPrefix("*") ? words[1].dropFirst() : words[1]
            guard name == asset else { continue }
            let hex = words[0].lowercased()
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
            return hex
        }
        return nil
    }

    /// `1.0.38`, `1.0.34-staging1`, `1.0.6-anicet1`: three numbers and an
    /// optional alphanumeric suffix — every `boat-cli-v` tag so far. Also what
    /// makes a version safe to put in a URL.
    static func isVersion(_ s: String) -> Bool {
        guard s.count <= 40 else { return false }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ !$0.isEmpty && $0.count <= 10 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return false }
        guard parts.count == 2 else { return true }
        return !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
