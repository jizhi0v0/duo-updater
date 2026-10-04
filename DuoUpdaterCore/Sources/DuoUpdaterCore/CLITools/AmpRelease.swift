import Foundation

/// What the installer would install: `https://static.ampcode.com/cli/cli-version.txt`,
/// one line, the version (`0.0.1791121193-ge297b9` on 2026-10-04). The installer
/// reads it before downloading `cli/<version>/amp-darwin-<arm64|x64>` "to ensure
/// consistent downloads", and the binary's own update asks the same file.
///
/// Versions are `0.0.<unix seconds>-g<commit>`: the middle number is the build
/// time (1791121193 is 2026-10-04 13:39 UTC), so the order is numeric. Releases
/// come several times a day, and the vendor publishes no per-release notes.
public struct AmpRelease: Sendable {

    public static let channel = URL(string: "https://static.ampcode.com/cli/cli-version.txt")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "cli-version.txt does not name a version"
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

    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.channel)
        guard status == 200 else { throw Failure.http(status) }
        let version = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isVersion(version) else { throw Failure.unreadable }
        return version
    }

    /// `0.0.1791121193-ge297b9`: three numbers and a `g<commit>`, as every
    /// release so far. Also what makes it safe in an environment variable or a URL.
    static func isVersion(_ s: String) -> Bool {
        guard s.count <= 48 else { return false }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.count <= 12 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return false }
        guard parts.count == 2 else { return true }
        return !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// By the numbers; two builds with the same numbers and another commit are
    /// told apart only as different, which is read as an update (a rebuild).
    static func compare(_ installed: String, _ latest: String) -> ComparisonResult {
        func numbers(_ s: String) -> [Int] {
            s.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = numbers(installed), b = numbers(latest)
        for (x, y) in zip(a, b) where x != y { return x < y ? .orderedAscending : .orderedDescending }
        return installed == latest ? .orderedSame : .orderedAscending
    }
}
