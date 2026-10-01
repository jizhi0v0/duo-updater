import Foundation

/// The version `uv self update` would install: what uv 0.12 itself reads.
///
/// uv's official update path (`find_matching_version`, `uv-bin-install`, `main`
/// on 2026-10-02) streams Astral's versions manifest —
/// `https://releases.astral.sh/github/versions/main/v1/uv.ndjson`, falling back
/// to `https://raw.githubusercontent.com/astral-sh/versions/main/v1/uv.ndjson` —
/// one JSON object per line, newest first, and takes the **first line that has
/// an artifact for its platform**. With no version asked for, nothing else
/// filters: no pre-release rule (uv has published none; all 319 lines of the
/// manifest on 2026-10-02 are plain `x.y.z`, `0.12.21` down to `0.0.5`).
///
/// The whole file is 1,449,375 bytes and its first line 4,804 (2026-10-02,
/// 18 artifacts), so only the first 64 KB are asked for (`Range`, honoured: 206
/// from Cloudflare) — a dozen lines, room for the first to grow. The response
/// carries `cache-control: public, max-age=300`, hence the version-feed cache
/// policy.
public struct UvRelease: Sendable {

    public static let manifests = [
        URL(string: "https://releases.astral.sh/github/versions/main/v1/uv.ndjson")!,
        URL(string: "https://raw.githubusercontent.com/astral-sh/versions/main/v1/uv.ndjson")!,
    ]

    /// Enough for a dozen lines of today's size; reading stops long before.
    static let headBytes = 64 * 1024

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
        case unpack(String)
    }

    /// The manifest's first `headBytes`. Injected so tests never reach the
    /// network.
    typealias Head = @Sendable (URL) async throws -> Data

    let head: Head

    public init(session: URLSession = .updates) {
        self.init(head: { try await Self.readHead(of: $0, session: session) })
    }

    init(head: @escaping Head) {
        self.head = head
    }

    /// The newest release with an archive for `arch` (`aarch64`, `x86_64`).
    public func latest(arch: String) async throws -> String {
        var lastError: Error = Failure.unreadable
        for url in Self.manifests {
            do {
                if let version = Self.firstVersion(in: try await head(url), platform: "\(arch)-apple-darwin") {
                    return version
                }
                lastError = Failure.unreadable
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// uv's rule over the complete lines of `data`: the first whose `artifacts`
    /// name `platform`. A last line cut off by the byte limit is not read.
    static func firstVersion(in data: Data, platform: String) -> String? {
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                // The first line that does not parse ends the read: uv stops with
                // an error there rather than looking past it.
                return nil
            }
            guard let version = json["version"] as? String, isVersion(version),
                  let artifacts = json["artifacts"] as? [[String: Any]]
            else { return nil }
            if artifacts.contains(where: { $0["platform"] as? String == platform }) {
                return version
            }
        }
        return nil
    }

    /// Three dot-separated runs of ASCII digits: every uv release so far.
    static func isVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 10 && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// The head of the manifest, streamed, so a server that ignores `Range`
    /// cannot put the whole file in memory (`countedBytes`' doc comment).
    static func readHead(of url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("bytes=0-\(headBytes - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.countedBytes(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else { throw Failure.http(status) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= headBytes { break }
        }
        return data
    }
}
