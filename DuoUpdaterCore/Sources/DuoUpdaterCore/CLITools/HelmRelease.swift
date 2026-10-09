import CryptoKit
import Foundation

/// What Helm's script would install on an install's own major line.
///
/// Helm maintains two lines, each with its own script and its own pointer:
/// `get-helm-3` reads `https://get.helm.sh/helm3-latest-version` (`v3.22.0` on
/// 2026-10-09) and `get-helm-4` reads `helm4-latest-version` (`v4.3.0`), each a
/// one-line body with an `ETag`. A v3 install is compared on the v3 pointer and
/// never offered v4: moving to a new major is the user's call.
public struct HelmRelease: Sendable {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        case noLine(Int)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .noLine(let major): return "Helm has no maintained v\(major) line"
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

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The lines Helm's scripts install.
    static let majors: Set<Int> = [3, 4]

    static func pointer(major: Int) -> URL {
        URL(string: "https://get.helm.sh/helm\(major)-latest-version")!
    }

    /// The official script for a line, as Helm's install docs fetch it.
    static func installer(major: Int) -> URL? {
        guard majors.contains(major) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-\(major)")
    }

    /// The line's newest version, without its `v`; it must be on that line.
    public func latest(major: Int) async throws -> String {
        guard Self.majors.contains(major) else { throw Failure.noLine(major) }
        let (data, status) = try await fetch(Self.pointer(major: major))
        guard status == 200 else { throw Failure.http(status) }
        var version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("v") else { throw Failure.unreadable }
        version.removeFirst()
        guard Self.isVersion(version), version.hasPrefix("\(major).") else { throw Failure.unreadable }
        return version
    }

    /// `3.22.0`, or a release candidate's `4.3.0-rc.1`. Also what keeps a
    /// version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 40 && s.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}(-[0-9A-Za-z.]+)?$"#, options: .regularExpression) != nil
    }

    static func archiveName(version: String, target: String) -> String { "helm-v\(version)-darwin-\(target).tar.gz" }

    static func archiveURL(version: String, target: String) -> URL {
        URL(string: "https://get.helm.sh/\(archiveName(version: version, target: target))")!
    }

    /// The `.sha256` beside the archive: its bare hex digest.
    static func digestURL(version: String, target: String) -> URL {
        URL(string: "https://get.helm.sh/\(archiveName(version: version, target: target)).sha256")!
    }

    static let targets: Set<String> = ["arm64", "amd64"]
}

/// Whether a `helm` is byte for byte the build the Helm project published for
/// its version, as `LuvusVerifier` does it for luvus: the archive is checked
/// against the `.sha256` beside it on get.helm.sh (3.22.0 arm64: `4c9982a6…`,
/// measured 2026-10-09) — the same file the script checks — unpacked, and its
/// `darwin-<arch>/helm` hashed (3.22.0 arm64: `8566ea7d…`). That hash is
/// remembered per version and target (`HelmPublishedDigests`), the archive
/// fetched at the first click that needs it, never by a background check.
struct HelmVerifier: Sendable {

    typealias Download = @Sendable (URL) async throws -> Data
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: HelmPublishedDigests

    init(
        download: @escaping Download = HelmVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: HelmPublishedDigests = .shared
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
            : .differs("\(binary) is not the helm \(version) the Helm project published")
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
        guard HelmRelease.isVersion(version), HelmRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published helm \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(HelmRelease.digestURL(version: version, target: target)), as: UTF8.self)
            archive = try await download(HelmRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download helm \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the helm \(version) archive did not match the sha256 published beside it"))
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-helm-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(HelmRelease.archiveName(version: version, target: target))
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack helm \(version): \(error)"))
        }
        let hash = self.hash
        let inside = scratch.appendingPathComponent("darwin-\(target)").appendingPathComponent("helm")
        guard let binary = await offCooperativePool({ hash(inside) }) else {
            return .failure(Failure(reason: "the helm \(version) archive has no darwin-\(target)/helm"))
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
        guard (200..<300).contains(status) else { throw HelmRelease.Failure.http(status) }
        return data
    }
}

/// `LuvusPublishedDigests` for Helm, in `com.duoupdater.app/helm-published-digests.json`.
public final class HelmPublishedDigests: @unchecked Sendable {

    public static let shared = HelmPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-helm-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("helm-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("helm-published-digests.json"))
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
