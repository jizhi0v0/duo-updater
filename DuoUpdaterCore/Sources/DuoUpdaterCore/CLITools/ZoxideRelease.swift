import CryptoKit
import Foundation

/// What zoxide's installer would install, the digest its archive was published
/// with, and zoxide's release notes — all from its GitHub Releases.
///
/// **Latest.** The installer asks `api.github.com/repos/ajeetdsouza/zoxide/releases/latest`
/// and installs it, so the same answer is the channel: `v0.10.0` on 2026-10-09
/// (published 2026-07-04). No release in the newest thirty is a prerelease.
///
/// **Published digest.** zoxide publishes no checksum file. What its releases do
/// carry is GitHub's own `digest` for each asset (`sha256:<hex>`, on 0.9.9 and
/// 0.10.0; 0.9.8 and older have none), which matched the archives downloaded on
/// 2026-10-09. **The user accepted that `digest` as zoxide's published hash on
/// 2026-10-09**, because zoxide offers no other: that decision is zoxide's
/// alone, and is not a rule for any other tool.
///
/// **Notes.** Each release body is Keep a Changelog: `### Added`, `### Changed`,
/// `### Fixed`, a `-` bullet per change. The repository's `CHANGELOG.md` has
/// no more: compared 2026-10-09 for 0.9.6 to 0.10.0, its sections match the
/// bodies but for a word in two bullets, and 0.10.0's body has one bullet the
/// file lacks. The bodies are what is read: dated, one per release.
public struct ZoxideRelease: Sendable {

    public static let repository = "ajeetdsouza/zoxide"
    public static let latestURL = URL(string: "https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest")!
    public static let listURL = URL(string: "https://api.github.com/repos/ajeetdsouza/zoxide/releases?per_page=30")!

    static func tagURL(version: String) -> URL {
        URL(string: "https://api.github.com/repos/ajeetdsouza/zoxide/releases/tags/v\(version)")!
    }

    static func archiveName(version: String, target: String) -> String { "zoxide-\(version)-\(target).tar.gz" }

    static func archiveURL(version: String, target: String) -> URL {
        URL(string: "https://github.com/ajeetdsouza/zoxide/releases/download/v\(version)/")!
            .appendingPathComponent(archiveName(version: version, target: target))
    }

    static let targets: Set<String> = ["aarch64-apple-darwin", "x86_64-apple-darwin"]

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        /// GitHub's API rate limit (`GitHubReleasesSource.isRateLimited`).
        case rateLimited(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .rateLimited(let status):
                return GitHubReleasesSource.GitHubError.rateLimited(status).errorDescription ?? "HTTP \(status)"
            case .unreadable: return "the answer could not be read"
            }
        }
    }

    /// One release: its version and the `digest` GitHub reports for each macOS
    /// archive that has one, by target.
    public struct Published: Sendable, Equatable {
        public let version: String
        public let archiveDigests: [String: String]
    }

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url, force in
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token = await ChangelogService.gitHubToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let purpose: RequestPurpose = url == ZoxideRelease.listURL ? .changelog : .versionCheck
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// What `releases/latest` names, as the installer reads it.
    public func latest() async throws -> Published {
        try await release(at: Self.latestURL)
    }

    /// The release of one version, for the digest of a build already installed.
    func release(version: String) async throws -> Published {
        guard Self.isVersion(version) else { throw Failure.unreadable }
        return try await release(at: Self.tagURL(version: version))
    }

    private func release(at url: URL) async throws -> Published {
        let (data, status, remaining) = try await fetch(url, false)
        guard status == 200 else {
            throw GitHubReleasesSource.isRateLimited(status, rateLimitRemaining: remaining)
                ? Failure.rateLimited(status) : Failure.http(status)
        }
        guard let published = Self.parseRelease(data) else { throw Failure.unreadable }
        return published
    }

    static func parseRelease(_ data: Data) -> Published? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, tag.hasPrefix("v")
        else { return nil }
        let version = String(tag.dropFirst())
        guard isVersion(version) else { return nil }
        var digests: [String: String] = [:]
        for asset in (json["assets"] as? [[String: Any]]) ?? [] {
            guard let name = asset["name"] as? String,
                  let digest = GitHubReleasesSource.sha256Digest(asset["digest"])
            else { continue }
            for target in targets where name == archiveName(version: version, target: target) {
                digests[target] = digest
            }
        }
        return Published(version: version, archiveDigests: digests)
    }

    /// `0.10.0`: three numbers, nothing else (zoxide has published no other
    /// shape). Also what keeps a version safe in a URL path.
    static func isVersion(_ s: String) -> Bool {
        s.count <= 20 && s.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// The newest page of releases, one entry per release with notes, newest first.
    public func notes(force: Bool) async throws -> Changelog {
        let (data, status, remaining) = try await fetch(Self.listURL, force)
        guard status == 200 else {
            throw CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: Self.listURL)
        }
        let parsed = await offCooperativePool { Self.parseNotes(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }

    /// Through `GitHubMarkdownParser`, as every GitHub Releases changelog is.
    static func parseNotes(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(json, format: .gitHubReleases, channel: nil, maxEntries: nil)
    }
}

/// Whether a `zoxide` is byte for byte the build ajeetdsouza published for its
/// version — the second arm of the trust rule (`CLIToolTrust`), for a binary
/// that is only ever ad hoc signed.
///
/// The published hash is GitHub's `digest` of the release's archive
/// (`ZoxideRelease`), not of the bare binary. So, as for Luvus
/// (`LuvusVerifier`): download the archive, check it against that digest, unpack
/// it, and hash its `zoxide`. What is remembered is that last hash, per version
/// and target (`ZoxidePublishedDigests`). The archive is downloaded once per
/// version, only by a click, never by a background check.
struct ZoxideVerifier: Sendable {

    /// The archive digests of one version's release.
    typealias Release = @Sendable (_ version: String) async throws -> ZoxideRelease.Published
    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.gz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let release: Release
    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: ZoxidePublishedDigests

    init(
        release: @escaping Release = { try await ZoxideRelease().release(version: $0) },
        download: @escaping Download = ZoxideVerifier.get,
        extract: @escaping Extract = UvVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: ZoxidePublishedDigests = .shared
    ) {
        self.release = release
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
            : .differs("\(binary) is not the zoxide \(version) ajeetdsouza published")
    }

    struct Failure: Error {
        let reason: String
    }

    /// The sha256 of the `zoxide` inside the release's archive, once the archive
    /// matched the `digest` GitHub reports for it.
    func publishedDigest(version: String, target: String) async -> Result<String, Failure> {
        guard ZoxideRelease.isVersion(version), ZoxideRelease.targets.contains(target) else {
            return .failure(Failure(reason: "no published zoxide \(version) for \(target)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(version: version, target: target) }) {
            return .success(known)
        }
        let archiveDigest: String
        do {
            guard let digest = try await release(version).archiveDigests[target] else {
                return .failure(Failure(reason: "the zoxide \(version) release names no digest for its \(target) archive"))
            }
            archiveDigest = digest
        } catch {
            return .failure(Failure(reason: "could not read the zoxide \(version) release: \(error)"))
        }
        let archive: Data
        do {
            archive = try await download(ZoxideRelease.archiveURL(version: version, target: target))
        } catch {
            return .failure(Failure(reason: "could not download zoxide \(version) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: archiveDigest) else {
            return .failure(Failure(reason: "the zoxide \(version) archive did not match its published digest"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-zoxide-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(ZoxideRelease.archiveName(version: version, target: target))
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack zoxide \(version): \(error)"))
        }
        let hash = self.hash
        guard let binary = await offCooperativePool({ hash(scratch.appendingPathComponent("zoxide")) }) else {
            return .failure(Failure(reason: "the zoxide \(version) archive has no zoxide"))
        }
        await offCooperativePool { digests.remember(binary, version: version, target: target) }
        return .success(binary)
    }

    /// A release asset, through GitHub's redirect to its CDN.
    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ZoxideRelease.Failure.http(status) }
        return data
    }
}

/// The sha256 of each release's `zoxide`, by version and target, as
/// `ZoxideVerifier` found it inside an archive that matched its published digest.
/// `LuvusPublishedDigests`, in `com.duoupdater.app/zoxide-published-digests.json`.
public final class ZoxidePublishedDigests: @unchecked Sendable {

    public static let shared = ZoxidePublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-zoxide-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("zoxide-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("zoxide-published-digests.json"))
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
