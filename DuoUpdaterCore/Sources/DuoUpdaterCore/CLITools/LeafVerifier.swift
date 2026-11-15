import CryptoKit
import Foundation

/// Verifies Leaf before and after running its updater. Published SHA-256 values
/// name the tarball; the cached digest is the binary inside that verified archive.
struct LeafVerifier: Sendable {

    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.gz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: LeafPublishedDigests

    init(
        download: @escaping Download = LeafVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: LeafPublishedDigests = .shared
    ) {
        self.download = download
        self.extract = extract
        self.hash = hash
        self.digests = digests
    }

    /// Checks `binary` against `version` for `target`, downloading that release's
    /// archive when its binary's digest is not yet known.
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
            : .differs("\(binary) is not the leaf \(version) DeepanshuMishraa published")
    }

    /// The check a background verdict can make without the network: nil when the
    /// release's digest is not known yet. Blocking.
    func knownVerdict(binary: String, version: String, target: String) -> Bool? {
        guard let published = digests.digest(version: version, target: target) else { return nil }
        return CLIToolTrust.matches(hash(URL(fileURLWithPath: binary)), published: published)
    }

    struct Failure: Error {
        let reason: String
    }

    /// The sha256 of the `leaf` inside the release's archive, once the archive
    /// matched the digest published beside it.
    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard LeafRelease.isVersion(version), LeafRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published leaf \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(LeafRelease.digestURL(version: version, target: target)), as: UTF8.self)
            archive = try await download(LeafRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download leaf \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the leaf \(version) archive did not match the sha256 published beside it"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-leaf-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(LeafRelease.archiveURL(version: version, target: target).lastPathComponent)
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack leaf \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("leaf")) }) else {
            return .failure(Failure(reason: "the leaf \(version) archive has no leaf"))
        }
        await offCooperativePool { digests.remember(binary, version: version, target: target) }
        return .success(binary)
    }

    /// A release asset, through GitHub's redirect to its CDN. The archive is
    /// counted as an install, the digest as a version check.
    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let purpose: RequestPurpose = url.pathExtension == "sha256" ? .versionCheck : .install
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: purpose)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw LeafRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `leaf`, by version and target, as
/// `LeafVerifier` found it inside an archive that matched its published digest.
///
/// Kept in `com.duoupdater.app/leaf-published-digests.json` under
/// `DuoStateDirectory.base`, so an archive is downloaded once per version, not
/// once per click or relaunch. A release's assets do not change once published;
/// if one ever were replaced, a file matching the new build would read as not
/// verified until this file is removed — a click withheld, never one run.
public final class LeafPublishedDigests: @unchecked Sendable {

    public static let shared = LeafPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? DuoStateDirectory.testProcessScratchRoot
                .appendingPathComponent("duo-leaf-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("leaf-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("leaf-published-digests.json"))
    }

    static func key(version: String, target: String) -> String { "\(version) \(target)" }

    /// Blocking.
    func digest(version: String, target: String) -> String? {
        lock.withLock { load()[Self.key(version: version, target: target)] }
    }

    /// Blocking.
    func remember(_ digest: String, version: String, target: String) {
        lock.withLock {
            var entries = load()
            entries[Self.key(version: version, target: target)] = digest
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Under the lock.
    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return entries
    }
}
