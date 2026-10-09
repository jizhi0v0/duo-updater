import CryptoKit
import Foundation

/// What `flyctl version upgrade` would install: the release
/// `api.fly.io/app/flyctl_releases/darwin/<arch>/latest` names.
///
/// `LatestRelease` (`internal/update/update.go`) asks that endpoint with
/// `Accept: application/json` for the channel `translateChannelForRails` makes of
/// the one in `~/.fly/state.yml`: `latest` for everything but `pre` and
/// `prerelease`. On 2026-10-09 it answered `{"version":"v0.4.115","prerelease":false,
/// "download_url":"https://github.com/superfly/flyctl/releases/download/v0.4.115/
/// flyctl_0.4.115_macOS_arm64.tar.gz","timestamp":…}`, with an `ETag`. A
/// `…/stable` path answers 404: `latest` is the stable track's name. The `pre`
/// track answered the same stable build that day; no flyctl release has been a
/// GitHub prerelease since 0.2.24-pre-1.
public struct FlyctlRelease: Sendable {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        case noBuild(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .noBuild(let target): return "no stable macOS \(target) build"
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
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// `arm64` → the endpoint's `arm64`, `x86_64` → Go's `amd64`, as flyctl asks.
    static func channelURL(target: String) -> URL? {
        let arch: String
        switch target {
        case "arm64": arch = "arm64"
        case "x86_64": arch = "amd64"
        default: return nil
        }
        return URL(string: "https://api.fly.io/app/flyctl_releases/darwin/\(arch)/latest")
    }

    /// The stable track's version, without its `v`.
    public func latest(target: String) async throws -> String {
        guard let url = Self.channelURL(target: target) else { throw Failure.noBuild(target) }
        let (data, status) = try await fetch(url)
        guard status == 200 else { throw Failure.http(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["version"] as? String
        else { throw Failure.unreadable }
        guard json["prerelease"] as? Bool != true else { throw Failure.noBuild(target) }
        var version = raw.trimmingCharacters(in: .whitespaces)
        if version.hasPrefix("v") { version.removeFirst() }
        guard Self.isVersion(version) else { throw Failure.unreadable }
        return version
    }

    /// `0.4.115`, or an old prerelease's `0.2.24-pre-1`. Also what keeps a
    /// version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 40 && s.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}(-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    static let releases = URL(string: "https://github.com/superfly/flyctl/releases/download")!

    /// `flyctl_<version>_macOS_<target>.tar.gz`.
    static func archiveName(version: String, target: String) -> String { "flyctl_\(version)_macOS_\(target).tar.gz" }

    static func archiveURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent(archiveName(version: version, target: target))
    }

    /// `flyctl_<version>_checksums.txt`: one `<hex>  <archive>` line per asset.
    static func checksumsURL(version: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent("flyctl_\(version)_checksums.txt")
    }

    static let targets: Set<String> = ["arm64", "x86_64"]

    /// The digest `checksums` names for `archive`; nil when no line does.
    static func digest(for archive: String, in checksums: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, fields[1] == archive else { continue }
            return String(fields[0])
        }
        return nil
    }
}

/// Whether a `flyctl` is byte for byte the build Fly.io published for its
/// version — the second arm of the trust rule (`CLIToolTrust`) — as
/// `LuvusVerifier` does it for luvus.
///
/// The release publishes a sha256 for the archive, in `flyctl_<v>_checksums.txt`
/// (0.4.115 macOS arm64: `16bd29f7…`, measured 2026-10-09), not for the bare
/// binary. So the archive is downloaded, checked against that line, unpacked,
/// and its one file `flyctl` hashed (0.4.115 arm64: `b4a3eb05…`, 110,583,234
/// bytes). That last hash is remembered per version and target
/// (`FlyctlPublishedDigests`); the archive is fetched at the first click that
/// needs it, never by a background check.
struct FlyctlVerifier: Sendable {

    typealias Download = @Sendable (URL) async throws -> Data
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: FlyctlPublishedDigests

    init(
        download: @escaping Download = FlyctlVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: FlyctlPublishedDigests = .shared
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
            : .differs("\(binary) is not the flyctl \(version) Fly.io published")
    }

    /// Without the network: nil when the release's digest is not known yet. Blocking.
    func knownVerdict(binary: String, version: String, target: String) -> Bool? {
        guard let published = digests.digest(version: version, target: target) else { return nil }
        return CLIToolTrust.matches(hash(URL(fileURLWithPath: binary)), published: published)
    }

    struct Failure: Error {
        let reason: String
    }

    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard FlyctlRelease.isVersion(version), FlyctlRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published flyctl \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let name = FlyctlRelease.archiveName(version: version, target: target)
        let checksums: String
        let archive: Data
        do {
            checksums = String(decoding: try await download(FlyctlRelease.checksumsURL(version: version)), as: UTF8.self)
            archive = try await download(FlyctlRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download flyctl \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: FlyctlRelease.digest(for: name, in: checksums)) else {
            return .failure(Failure(reason: "the flyctl \(version) archive did not match its published checksum"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-flyctl-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(name)
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack flyctl \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("flyctl")) }) else {
            return .failure(Failure(reason: "the flyctl \(version) archive has no flyctl"))
        }
        await offCooperativePool { digests.remember(binary, version: version, target: target) }
        return .success(binary)
    }

    /// A release asset, through GitHub's redirect to its CDN. The archive is
    /// counted as an install, the checksums as a version check.
    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        let purpose: RequestPurpose = url.pathExtension == "txt" ? .versionCheck : .install
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: purpose)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FlyctlRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `flyctl`, by version and target, as
/// `FlyctlVerifier` found it inside an archive that matched its published
/// checksum. `LuvusPublishedDigests`, in `com.duoupdater.app/flyctl-published-digests.json`.
public final class FlyctlPublishedDigests: @unchecked Sendable {

    public static let shared = FlyctlPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-flyctl-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("flyctl-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("flyctl-published-digests.json"))
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
