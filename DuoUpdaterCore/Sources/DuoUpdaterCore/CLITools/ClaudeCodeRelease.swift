import Foundation

/// What the vendor publishes: the version each channel points at, and each
/// version's manifest.
///
/// A native install is compared against `downloads.claude.ai` (what `claude
/// update` itself reads); an npm-family install against the npm registry's
/// dist-tags of the same name, since that is what its package manager installs.
/// On 2026-09-30 the two agreed: stable 2.1.280, latest 2.1.285.
public struct ClaudeCodeRelease: Sendable {

    public static let releasesBase = URL(string: "https://downloads.claude.ai/claude-code-releases")!
    public static let npmDistTags = URL(string: "https://registry.npmjs.org/-/package/@anthropic-ai/claude-code/dist-tags")!

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
    }

    let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    /// The version `channel` currently points at, for this install's method.
    public func latestVersion(
        channel: ClaudeCodeSettings.Channel, for method: ClaudeCodeInstall.Method
    ) async throws -> String {
        switch method {
        case .npm, .pnpm, .bun:
            let tags = try JSONSerialization.jsonObject(with: try await get(Self.npmDistTags)) as? [String: Any]
            guard let version = tags?[channel.rawValue] as? String, Self.isVersion(version) else {
                throw Failure.unreadable
            }
            return version
        case .native, .unknown:
            let data = try await get(Self.releasesBase.appendingPathComponent(channel.rawValue))
            let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isVersion(version) else { throw Failure.unreadable }
            return version
        }
    }

    /// One platform's entry in `<version>/manifest.json`.
    public struct Artifact: Sendable, Equatable {
        public let size: Int
        public let sha256: String
    }

    public func artifact(version: String, platform: String) async throws -> Artifact {
        let url = Self.releasesBase.appendingPathComponent(version).appendingPathComponent("manifest.json")
        let json = try JSONSerialization.jsonObject(with: try await get(url)) as? [String: Any]
        guard let entry = (json?["platforms"] as? [String: Any])?[platform] as? [String: Any],
              let size = entry["size"] as? Int, let sha = entry["checksum"] as? String
        else { throw Failure.unreadable }
        return Artifact(size: size, sha256: sha)
    }

    /// The manifest's platform key for this Mac.
    public static var platform: String {
        HostArch.current == .arm64 ? "darwin-arm64" : "darwin-x64"
    }

    /// Does the file on disk have the size the manifest gives for the version the
    /// layout claims? Size, not sha256: it tells releases apart just as well
    /// (2.1.274 and 2.1.280 differ by 3 MB) without reading 200 MB per check,
    /// and the Developer ID seal already vouches for the bytes.
    public static func sizeMatches(_ executable: URL, _ artifact: Artifact) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: executable.path)[.size] as? Int) ?? -1
        return size == artifact.size
    }

    static func isVersion(_ s: String) -> Bool {
        s.range(of: #"^\d+\.\d+\.\d+([.\-+][0-9A-Za-z.\-]+)?$"#, options: .regularExpression) != nil
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        return data
    }
}
