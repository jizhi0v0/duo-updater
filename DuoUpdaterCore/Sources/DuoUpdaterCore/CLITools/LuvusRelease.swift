import CryptoKit
import Foundation

/// What `luvus update` would install: the version `luvus.dev/latest.json` names.
///
/// `src/update.rs` (`MANIFEST_URL`, v0.14.3) reads that manifest —
/// `{"version": "0.14.3", "date": "2026-09-30", "notes": "…"}` on 2026-10-07 —
/// and installs its `version` only when it is strictly newer than the running
/// build (`is_newer`, semver), so it never downgrades. It takes no version of its
/// own: `luvus update <anything>` prints its usage and exits 2. There is one
/// channel: no release of the repository is marked prerelease (35 releases on
/// 2026-10-07), and the config's only update setting, `check_updates`, turns
/// the background notice off, not an update channel.
public struct LuvusRelease: Sendable {

    public static let manifest = URL(string: "https://luvus.dev/latest.json")!

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

    /// The manifest's `version`, without a leading `v`, as luvus reads it.
    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.manifest)
        guard status == 200 else { throw Failure.http(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["version"] as? String
        else { throw Failure.unreadable }
        var version = raw.trimmingCharacters(in: .whitespaces)
        if version.hasPrefix("v") { version.removeFirst() }
        guard Self.isVersion(version) else { throw Failure.unreadable }
        return version
    }

    /// `0.14.3`, or a semver prerelease (`1.0.0-rc.1`), which `luvus update`
    /// would also accept. Also what keeps a version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 40 && s.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}(-[0-9A-Za-z.]+)?$"#, options: .regularExpression) != nil
    }

    static let releases = URL(string: "https://github.com/RizRiyz/luvus/releases/download")!

    /// `luvus-v<version>-<target>`, the stem of the release's archive and of the
    /// `.sha256` beside it.
    static func stem(version: String, target: String) -> String { "luvus-v\(version)-\(target)" }

    static func archiveURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent("\(stem(version: version, target: target)).tar.gz")
    }

    static func digestURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent("\(stem(version: version, target: target)).sha256")
    }

    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
}

/// Whether a `luvus` is byte for byte the build RizRiyz published for its
/// version — the second arm of the trust rule (`CLIToolTrust`), for a binary
/// that is only ever ad hoc signed.
///
/// The release publishes a sha256 for the archive, not for the bare binary:
/// `luvus-v<version>-<target>.sha256` is `<hex>  luvus-v<version>-<target>.tar.gz`,
/// the same digest GitHub's asset `digest` reports (0.14.3 arm64:
/// `3365665a…`, measured 2026-10-07). So the check is the archive's, as uv's is
/// (`UvVerifier`): download it, check it against the published digest, unpack
/// it, and hash its one file `luvus` (0.14.3 arm64: 5,820,205 bytes of archive,
/// `ab10688b…` for the binary).
///
/// What is remembered is that last hash, per version and target
/// (`LuvusPublishedDigests`) — a fact about the release, not about the file on
/// disk. Each check then only hashes the local file (13.6 MB for 0.14.3 arm64)
/// and compares; the archive is downloaded once per version, at the first click
/// that needs it, never by a background check.
struct LuvusVerifier: Sendable {

    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.gz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: LuvusPublishedDigests

    init(
        download: @escaping Download = LuvusVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: LuvusPublishedDigests = .shared
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
            : .differs("\(binary) is not the luvus \(version) RizRiyz published")
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

    /// The sha256 of the `luvus` inside the release's archive, once the archive
    /// matched the digest published beside it.
    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard LuvusRelease.isVersion(version), LuvusRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published luvus \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(LuvusRelease.digestURL(version: version, target: target)), as: UTF8.self)
            archive = try await download(LuvusRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download luvus \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the luvus \(version) archive did not match the sha256 published beside it"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-luvus-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent("\(LuvusRelease.stem(version: version, target: target)).tar.gz")
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack luvus \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("luvus")) }) else {
            return .failure(Failure(reason: "the luvus \(version) archive has no luvus"))
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
        guard (200..<300).contains(status) else { throw LuvusRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `luvus`, by version and target, as
/// `LuvusVerifier` found it inside an archive that matched its published digest.
///
/// Kept in `com.duoupdater.app/luvus-published-digests.json` under
/// `DuoStateDirectory.base`, so an archive is downloaded once per version, not
/// once per click or relaunch. A release's assets do not change once published;
/// if one ever were replaced, a file matching the new build would read as not
/// verified until this file is removed — a click withheld, never one run.
public final class LuvusPublishedDigests: @unchecked Sendable {

    public static let shared = LuvusPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-luvus-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("luvus-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("luvus-published-digests.json"))
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
