import CryptoKit
import Foundation

/// What `lorca update` would install: the version in the signed `lorca-cli.json`
/// of the repository's latest GitHub release.
///
/// `crates/cli/src/update.rs` (`latest`, cli-v0.1.11) reads
/// `github.com/egoist/lorca/releases/latest/download/lorca-cli.json` and the
/// `lorca-cli.json.sig` beside it — a base64 Ed25519 signature of the file's
/// bytes by a key in `KEYS` — refuses the manifest unless the signature holds
/// and its `kind` is `lorca-cli`, and installs its `version` only when it is a
/// later `major.minor.patch` than the running build (`is_newer`), so it never
/// downgrades. This reads the same files under the same rules, so a version
/// lorca would refuse is never offered here.
///
/// One channel: no `cli-v` release is marked prerelease (10 on 2026-10-09), and
/// lorca takes no version of its own (`lorca update` has only `--check` and
/// `--auto`). The repository's other releases (`desktop-v`, `mobile-v`) are not
/// marked latest — the release docs require each CLI release to be — so
/// `releases/latest` is the CLI's; should another one take the mark, the
/// manifest answers 404 and the check says so, as `lorca update` would.
public struct LorcaRelease: Sendable {

    static let latestDownload = URL(string: "https://github.com/egoist/lorca/releases/latest/download")!
    public static let manifest = latestDownload.appendingPathComponent("lorca-cli.json")
    static let signature = latestDownload.appendingPathComponent("lorca-cli.json.sig")

    /// `KEYS` in `update.rs` at cli-v0.1.11: the public half of the key that
    /// signs `lorca-cli.json`, base64 of its 32 raw bytes. Lorca adds a new key
    /// a release before it signs with it; until it is added here, a manifest it
    /// signs reads as unverified and nothing is offered.
    static let keys = ["mQrlaAaYt9APwAWYN5smWgxI5QJ/W/9He3gsplur1gM="]

    /// The only Mac build Lorca publishes.
    static let target = "macos-aarch64"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        /// Not signed by a key Lorca's CLI trusts.
        case unsigned

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .unsigned: return "lorca-cli.json is not signed by Lorca's update key"
            }
        }
    }

    /// A manifest's version and its Mac build.
    public struct Manifest: Sendable, Equatable {
        public let version: String
        /// The archive's file name, sha256 and size; nil when the release has no
        /// Mac build.
        public let build: Build?

        public struct Build: Sendable, Equatable {
            public let file: String
            public let sha256: String
            public let size: Int
        }
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch
    let keys: [String]

    public init(session: URLSession = .updates) {
        self.init(fetch: { url in
            var request = URLRequest(url: url)
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network, and a key of
    /// their own signs the manifests they serve.
    init(fetch: @escaping Fetch, keys: [String] = LorcaRelease.keys) {
        self.fetch = fetch
        self.keys = keys
    }

    /// The latest manifest, its signature checked.
    public func latest() async throws -> Manifest {
        let (data, status) = try await fetch(Self.manifest)
        guard status == 200 else { throw Failure.http(status) }
        let (signature, signatureStatus) = try await fetch(Self.signature)
        guard signatureStatus == 200 else { throw Failure.http(signatureStatus) }
        guard Self.isSigned(data, signature: signature, keys: keys) else { throw Failure.unsigned }
        guard let manifest = Self.parse(data) else { throw Failure.unreadable }
        return manifest
    }

    /// `verify` in `update.rs`: the signature file, trimmed, is base64 of 64
    /// bytes, checked against each key in turn.
    static func isSigned(_ data: Data, signature: Data, keys: [String]) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else { return false }
        for key in keys {
            guard let raw = Data(base64Encoded: key),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            else { continue }
            if key.isValidSignature(signature, for: data) { return true }
        }
        return false
    }

    /// `{"kind": "lorca-cli", "version": "0.1.11", "builds": {"macos-aarch64":
    /// {"file": …, "sha256": …, "size": …}, …}}`; nil for another kind or a
    /// version that is not `major.minor.patch`.
    static func parse(_ data: Data) -> Manifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["kind"] as? String == "lorca-cli",
              let version = json["version"] as? String, isVersion(version)
        else { return nil }
        var build: Manifest.Build?
        if let builds = json["builds"] as? [String: Any], let mac = builds[target] as? [String: Any],
           let file = mac["file"] as? String, let sha256 = mac["sha256"] as? String,
           let size = mac["size"] as? Int {
            build = Manifest.Build(file: file, sha256: sha256, size: size)
        }
        return Manifest(version: version, build: build)
    }

    /// `0.1.11`. Also what keeps a version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 32 && s.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}$"#, options: .regularExpression) != nil
    }

    static let releases = URL(string: "https://github.com/egoist/lorca/releases/download")!

    static func archiveName(target: String) -> String { "lorca-cli-\(target).tar.gz" }

    static func archiveURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("cli-v\(version)").appendingPathComponent(archiveName(target: target))
    }

    /// The `.sha256` beside the archive: `<hex>  lorca-cli-macos-aarch64.tar.gz`,
    /// in every `cli-v` release (the manifest only from 0.1.11).
    static func digestURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("cli-v\(version)").appendingPathComponent("\(archiveName(target: target)).sha256")
    }
}

/// Whether a `lorca` is byte for byte the build Lorca published for its version
/// — the second arm of the trust rule (`CLIToolTrust`), for a binary that is
/// only ever ad hoc signed. Luvus's rule (`LuvusVerifier`), on Lorca's assets.
///
/// The release publishes a sha256 for the archive, not for the bare binary: the
/// `.sha256` beside it, the same digest GitHub's asset `digest` and, from
/// 0.1.11, the signed manifest report (0.1.11: `b8e2ee7f…`, measured
/// 2026-10-09). So the archive is downloaded, checked against it, unpacked, and
/// its one file `lorca` hashed (0.1.11: 17,788,021 bytes of archive, `lorca`
/// 48 MB). That last hash is remembered per version (`LorcaPublishedDigests`),
/// so the archive is downloaded once per version, at the first click that needs
/// it, never by a background check.
struct LorcaVerifier: Sendable {

    typealias Download = LuvusVerifier.Download
    typealias Extract = LuvusVerifier.Extract
    typealias Hash = LuvusVerifier.Hash

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: LorcaPublishedDigests

    init(
        download: @escaping Download = LorcaVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: LorcaPublishedDigests = .shared
    ) {
        self.download = download
        self.extract = extract
        self.hash = hash
        self.digests = digests
    }

    /// Checks `binary` against `version`, downloading that release's archive when
    /// its binary's digest is not yet known.
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
            : .differs("\(binary) is not the lorca \(version) Lorca published")
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

    /// The sha256 of the `lorca` inside the release's archive, once the archive
    /// matched the digest published beside it.
    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard LorcaRelease.isVersion(version), target == LorcaRelease.target else {
            return .failure(Failure(reason: "no published lorca \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(LorcaRelease.digestURL(version: version, target: target)), as: UTF8.self)
            archive = try await download(LorcaRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download lorca \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the lorca \(version) archive did not match the sha256 published beside it"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-lorca-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(LorcaRelease.archiveName(target: target))
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack lorca \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("lorca")) }) else {
            return .failure(Failure(reason: "the lorca \(version) archive has no lorca"))
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
        guard (200..<300).contains(status) else { throw LorcaRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `lorca`, by version and target, as
/// `LorcaVerifier` found it inside an archive that matched its published digest.
/// `LuvusPublishedDigests`, in `com.duoupdater.app/lorca-published-digests.json`.
public final class LorcaPublishedDigests: @unchecked Sendable {

    public static let shared = LorcaPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-lorca-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("lorca-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("lorca-published-digests.json"))
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
