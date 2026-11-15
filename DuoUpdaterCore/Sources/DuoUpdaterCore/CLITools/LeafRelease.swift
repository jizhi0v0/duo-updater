import Foundation

/// The same stable release `leaf upgrade` follows, without spending API quota.
/// The vendor's src/upgrade.rs and release workflow were read 2026-11-15.
public struct LeafRelease: Sendable {
    public static let repository = "DeepanshuMishraa/leaf"
    public static let latestURL = URL(string: "https://github.com/DeepanshuMishraa/leaf/releases/latest")!
    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]

    enum Failure: Error { case http(Int), unreadable }
    typealias Fetch = @Sendable (URL) async throws -> (Int, URL?)
    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 20
            let (_, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, response.url)
        })
    }

    init(fetch: @escaping Fetch) { self.fetch = fetch }

    public func latest() async throws -> String {
        let (status, finalURL) = try await fetch(Self.latestURL)
        guard status == 200 else { throw Failure.http(status) }
        guard let finalURL, let version = Self.version(from: finalURL) else { throw Failure.unreadable }
        return version
    }

    static func version(from url: URL) -> String? {
        let prefix = "/DeepanshuMishraa/leaf/releases/tag/v"
        guard url.scheme == "https", url.host == "github.com", url.path.hasPrefix(prefix) else { return nil }
        let version = String(url.path.dropFirst(prefix.count))
        return isVersion(version) ? version : nil
    }

    static func isVersion(_ text: String) -> Bool {
        text.count <= 32 && text.range(of: #"^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$"#,
                                      options: .regularExpression) != nil
    }

    static func archiveURL(version: String, target: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/v\(version)/leaf-\(target).tar.gz")!
    }

    static func digestURL(version: String, target: String) -> URL {
        archiveURL(version: version, target: target).appendingPathExtension("sha256")
    }
}
