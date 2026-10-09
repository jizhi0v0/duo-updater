import CryptoKit
import Foundation

/// What Starship's script would install: the release GitHub calls latest.
///
/// The script downloads `releases/latest/download/…`, which GitHub resolves to
/// the newest release that is not a prerelease. The same redirect tells the
/// version without the Releases API and its anonymous rate limit:
/// `https://github.com/starship/starship/releases/latest` answers 302 to
/// `…/releases/tag/v1.26.0` (2026-10-09). A `HEAD` request follows it and the
/// final URL's last component is the tag.
public struct StarshipRelease: Sendable {

    public static let latestPage = URL(string: "https://github.com/starship/starship/releases/latest")!

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

    /// The final URL after redirects, and its status.
    typealias Resolve = @Sendable (URL) async throws -> (URL?, Int)

    let resolve: Resolve

    public init(session: URLSession = .updates) {
        self.init(resolve: { url in
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (_, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (response.url, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    init(resolve: @escaping Resolve) {
        self.resolve = resolve
    }

    public func latest() async throws -> String {
        let (final, status) = try await resolve(Self.latestPage)
        guard status == 200 else { throw Failure.http(status) }
        guard let final, final.host == "github.com",
              final.deletingLastPathComponent().path == "/starship/starship/releases/tag"
        else { throw Failure.unreadable }
        var version = final.lastPathComponent
        guard version.hasPrefix("v") else { throw Failure.unreadable }
        version.removeFirst()
        guard Self.isVersion(version) else { throw Failure.unreadable }
        return version
    }

    static func isVersion(_ s: String) -> Bool {
        s.count <= 40 && s.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}(-[0-9A-Za-z.]+)?$"#, options: .regularExpression) != nil
    }

    static let releases = URL(string: "https://github.com/starship/starship/releases/download")!

    static func archiveName(target: String) -> String { "starship-\(target).tar.gz" }

    static func archiveURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent(archiveName(target: target))
    }

    /// `<archive>.sha256`: the archive's bare hex digest.
    static func digestURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent(archiveName(target: target) + ".sha256")
    }

    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
}

/// Whether a `starship` is byte for byte the build published for its version,
/// as `LuvusVerifier` does it for luvus: the archive against the `.sha256`
/// beside it (1.26.0 arm64: `c40b27b1…`, measured 2026-10-09), unpacked, its
/// `starship` hashed (1.26.0 arm64: `01532ebb…`), that hash remembered per
/// version and target (`StarshipPublishedDigests`). The archive is fetched at
/// the first click that needs it, never by a background check.
struct StarshipVerifier: Sendable {

    typealias Download = @Sendable (URL) async throws -> Data
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: StarshipPublishedDigests

    init(
        download: @escaping Download = StarshipVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: StarshipPublishedDigests = .shared
    ) {
        self.download = download
        self.extract = extract
        self.hash = hash
        self.digests = digests
    }

    func verify(binary: String, version: String, target: String) async -> UvVerifier.Result {
        let published: String
        switch await publishedDigest(version: version, target: target) {
        case .success(let digest): published = digest
        case .failure(let failure): return .couldNotVerify(failure.reason)
        }
        let hash = self.hash
        let actual = await offCooperativePool { hash(URL(fileURLWithPath: binary)) }
        return CLIToolTrust.matches(actual, published: published)
            ? .matches
            : .differs("\(binary) is not the starship \(version) published on GitHub")
    }

    /// Blocking.
    func knownVerdict(binary: String, version: String, target: String) -> Bool? {
        guard let published = digests.digest(version: version, target: target) else { return nil }
        return CLIToolTrust.matches(hash(URL(fileURLWithPath: binary)), published: published)
    }

    struct Failure: Error {
        let reason: String
    }

    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard StarshipRelease.isVersion(version), StarshipRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published starship \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(StarshipRelease.digestURL(version: version, target: target)), as: UTF8.self)
            archive = try await download(StarshipRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download starship \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the starship \(version) archive did not match the sha256 published beside it"))
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-starship-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(StarshipRelease.archiveName(target: target))
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack starship \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("starship")) }) else {
            return .failure(Failure(reason: "the starship \(version) archive has no starship"))
        }
        await offCooperativePool { digests.remember(binary, version: version, target: target) }
        return .success(binary)
    }

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        let purpose: RequestPurpose = url.pathExtension == "sha256" ? .versionCheck : .install
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: purpose)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw StarshipRelease.Failure.http(status) }
        return data
    }
}

/// `LuvusPublishedDigests` for Starship, in `com.duoupdater.app/starship-published-digests.json`.
public final class StarshipPublishedDigests: @unchecked Sendable {

    public static let shared = StarshipPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-starship-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("starship-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("starship-published-digests.json"))
    }

    /// Blocking.
    func digest(version: String, target: String) -> String? {
        lock.withLock { load()["\(version) \(target)"] }
    }

    /// Blocking.
    func remember(_ digest: String, version: String, target: String) {
        lock.withLock {
            var entries = load()
            entries["\(version) \(target)"] = digest
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return entries
    }
}
