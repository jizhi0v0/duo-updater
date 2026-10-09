import CryptoKit
import Foundation

/// What `atuin update` would install on the user's channel.
///
/// `atuin update` (axoupdater 0.10.0, `release/mod.rs`) asks GitHub's API:
/// - on `stable`, `repos/atuinsh/atuin/releases/latest` — the release GitHub
///   marks latest, when it carries `atuin-installer.sh`;
/// - on `nightly`, every page of `repos/atuinsh/atuin/releases`, and takes the
///   highest version that carries the installer, prereleases included.
///
/// Neither is asked here, so a check costs none of the API's 60 anonymous calls
/// an hour. The same answers come from outside the API:
/// - `stable`: `releases/latest/download/dist-manifest.json`, which GitHub
///   resolves through the same "latest" mark; cargo-dist's manifest names the
///   release (`announcement_tag` `v18.23.0`, `announcement_is_prerelease`
///   false, an `atuin-installer.sh` artifact; 66,428 bytes on 2026-10-09);
/// - `nightly`: `releases.atom`, the ten newest releases, whose highest semver
///   is the newest prerelease or release (`v18.23.0` down to `v18.19.0-beta.3`
///   on 2026-10-09; every one of the 93 releases then carried the installer).
///   Ten entries in GitHub's own order can miss a release just published; the
///   most that follows is a check that reads one release behind.
///
/// Versions are semver (`18.20.0-beta.3` sorts below `18.20.0`), as axoupdater
/// orders them.
public struct AtuinRelease: Sendable {

    public static let stableManifest =
        URL(string: "https://github.com/atuinsh/atuin/releases/latest/download/dist-manifest.json")!
    public static let feed = URL(string: "https://github.com/atuinsh/atuin/releases.atom")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        case unpack(String)

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            case .unpack(let reason): return "could not unpack: \(reason)"
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

    /// The newest version `atuin update` would install on `channel` ("stable" or
    /// "nightly").
    public func latest(channel: String) async throws -> String {
        let nightly = channel == "nightly"
        let (data, status) = try await fetch(nightly ? Self.feed : Self.stableManifest)
        guard status == 200 else { throw Failure.http(status) }
        guard let version = await offCooperativePool({
            nightly ? Self.newest(inFeed: data) : Self.stableVersion(inManifest: data)
        }) else { throw Failure.unreadable }
        return version
    }

    /// The manifest's release, when it is not a prerelease and carries the
    /// installer `atuin update` runs.
    static func stableVersion(inManifest data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["announcement_tag"] as? String, tag.hasPrefix("v"),
              json["announcement_is_prerelease"] as? Bool == false,
              let artifacts = json["artifacts"] as? [String: Any], artifacts["atuin-installer.sh"] != nil
        else { return nil }
        let version = String(tag.dropFirst())
        return isVersion(version) ? version : nil
    }

    /// The highest semver among the feed's `…/v<version></id>` entries.
    static func newest(inFeed data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: feedEntryID)
        else { return nil }
        let versions = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
        return versions.filter(isVersion).max { compare($0, $1) == .orderedAscending }
    }

    /// A feed entry's id: `…/v<version>`, the version captured. A tag without
    /// the `v` is not a release of this scheme and does not match.
    static let feedEntryID = #"<id>tag:github\.com,2008:Repository/\d+/v([^<]+)</id>"#

    /// Version → the UTC day of the entry's `<updated>` (the release's
    /// `updated_at`), for the release notes' dates (`AtuinChangelog.dated`).
    static func days(inFeed data: Data) -> [String: String] {
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: feedEntryID + #"\s*<updated>([^<]+)</updated>"#)
        else { return [:] }
        var days: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let version = Range(match.range(at: 1), in: text).map({ String(text[$0]) }), isVersion(version),
                  let day = StructuredChangelogDecoder.isoDay(Range(match.range(at: 2), in: text).map { String(text[$0]) })
            else { continue }
            days[version] = day
        }
        return days
    }

    /// `18.23.0`, `18.20.0-beta.3`: semver. Also what keeps a version safe in a
    /// URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 40 && NpmVersion(s) != nil && !s.hasPrefix("v") && !s.contains("+")
    }

    /// Semver order, as axoupdater compares releases.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        switch (NpmVersion(a), NpmVersion(b)) {
        case let (x?, y?): return x < y ? .orderedAscending : (y < x ? .orderedDescending : .orderedSame)
        default: return VersionComparator.compare(a, b)
        }
    }

    static let releases = URL(string: "https://github.com/atuinsh/atuin/releases/download")!

    /// `atuin-<target>`: the archive's name stem and the directory inside it.
    static func stem(target: String) -> String { "atuin-\(target)" }

    static func archiveURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent("\(stem(target: target)).tar.gz")
    }

    static func digestURL(version: String, target: String) -> URL {
        releases.appendingPathComponent("v\(version)").appendingPathComponent("\(stem(target: target)).tar.gz.sha256")
    }

    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
}

/// Whether an `atuin` is byte for byte the build atuinsh published for its
/// version — the second arm of the trust rule (`CLIToolTrust`), for a binary
/// that is only ever ad hoc signed.
///
/// The release publishes a sha256 for the archive, not for the bare binary:
/// `atuin-<target>.tar.gz.sha256` is `<hex> *atuin-<target>.tar.gz` (18.23.0
/// arm64: `c988be1c…`, the digest `atuin-installer.sh` also carries). So the
/// check is the archive's, as Luvus's is (`LuvusVerifier`): download it, check
/// it against the published digest, unpack it, and hash
/// `atuin-<target>/atuin`. That hash is remembered per version and target
/// (`AtuinPublishedDigests`); each check then only hashes the local file. The
/// archive is downloaded once per version, at the first click that needs it,
/// never by a background check.
struct AtuinVerifier: Sendable {

    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.gz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: AtuinPublishedDigests

    init(
        download: @escaping Download = AtuinVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: AtuinPublishedDigests = .shared
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
            : .differs("\(binary) is not the atuin \(version) atuinsh published")
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

    /// The sha256 of the `atuin` inside the release's archive, once the archive
    /// matched the digest published beside it.
    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard AtuinRelease.isVersion(version), AtuinRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published atuin \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let sidecar: String
        let archive: Data
        do {
            sidecar = String(decoding: try await download(AtuinRelease.digestURL(version: version, target: target)),
                             as: UTF8.self)
            archive = try await download(AtuinRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download atuin \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: sidecar) else {
            return .failure(Failure(reason: "the atuin \(version) archive did not match the sha256 published beside it"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-atuin-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent("\(AtuinRelease.stem(target: target)).tar.gz")
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack atuin \(version): \(error)"))
        }
        let hash = self.hash
        let inside = scratch.appendingPathComponent(AtuinRelease.stem(target: target)).appendingPathComponent("atuin")
        guard let binary = await offCooperativePool({ hash(inside) }) else {
            return .failure(Failure(reason: "the atuin \(version) archive has no atuin"))
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
        guard (200..<300).contains(status) else { throw AtuinRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `atuin`, by version and target, as
/// `AtuinVerifier` found it inside an archive that matched its published
/// digest: `LuvusPublishedDigests`, in
/// `com.duoupdater.app/atuin-published-digests.json`.
public final class AtuinPublishedDigests: @unchecked Sendable {

    public static let shared = AtuinPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-atuin-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("atuin-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("atuin-published-digests.json"))
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
