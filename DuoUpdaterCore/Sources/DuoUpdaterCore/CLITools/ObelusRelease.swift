import CryptoKit
import Foundation

/// What Obelus's installer would install, the sha256 its archives were published
/// with, and Obelus's release notes — all from its GitHub Releases.
///
/// **Latest.** The installer follows `github.com/obelus-editor/obelus/releases/latest`
/// to its tag. The same release's `SHA256SUMS`, at `releases/latest/download/SHA256SUMS`,
/// names each archive as `<bin>-<version>-<target>.<ext>`, so one fetch of it is
/// both the channel and the published hash — a release download, not the API,
/// so no check spends GitHub's API budget. `v0.16.0` on 2026-10-19; every
/// release from v0.9.0 is stable, none marked prerelease.
///
/// **Published hash.** `SHA256SUMS` is Obelus's own (`<hex>  <name>` lines),
/// the file its installer checks each archive against. On 2026-10-19 its line
/// for each macOS archive of v0.9.0 to v0.16.0 matched GitHub's `digest` for that
/// asset, and the archives downloaded for v0.15.0 and v0.16.0.
///
/// **Notes.** Each release body is GitHub's generated "What's Changed": a `*`
/// bullet per pull request. The bodies are what is read: dated, one per release.
public struct ObelusRelease: Sendable {

    public static let repository = "obelus-editor/obelus"
    public static let latestSums = URL(string: "https://github.com/obelus-editor/obelus/releases/latest/download/SHA256SUMS")!
    public static let listURL = URL(string: "https://api.github.com/repos/obelus-editor/obelus/releases?per_page=30")!

    static let downloads = URL(string: "https://github.com/obelus-editor/obelus/releases/download")!

    static func sumsURL(version: String) -> URL {
        downloads.appendingPathComponent("v\(version)").appendingPathComponent("SHA256SUMS")
    }

    /// The only macOS build: one universal binary for both architectures.
    static let target = "universal2-apple-darwin"

    static func archiveDirectory(_ binary: ObelusInstall.Binary, version: String) -> String {
        "\(binary.rawValue)-\(version)-\(target)"
    }

    static func archiveName(_ binary: ObelusInstall.Binary, version: String) -> String {
        archiveDirectory(binary, version: version) + ".tar.xz"
    }

    static func archiveURL(_ binary: ObelusInstall.Binary, version: String) -> URL {
        downloads.appendingPathComponent("v\(version)").appendingPathComponent(archiveName(binary, version: version))
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "SHA256SUMS could not be read"
            }
        }
    }

    /// One release: its version and the sha256 `SHA256SUMS` names for each
    /// macOS archive it lists, by binary.
    public struct Published: Sendable, Equatable {
        public let version: String
        public let archiveDigests: [ObelusInstall.Binary: String]
    }

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url, force in
            var request = URLRequest(url: url)
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
            request.timeoutInterval = 15
            let purpose: RequestPurpose
            if url == ObelusRelease.listURL {
                purpose = .changelog
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                if let token = await ChangelogService.gitHubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            } else {
                purpose = .versionCheck
            }
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// What `releases/latest` names, as the installer follows it.
    public func latest() async throws -> Published {
        try await sums(at: Self.latestSums, version: nil)
    }

    /// The release of one version, for the digest of a build already installed.
    func release(version: String) async throws -> Published {
        guard ZoxideRelease.isVersion(version) else { throw Failure.unreadable }
        return try await sums(at: Self.sumsURL(version: version), version: version)
    }

    private func sums(at url: URL, version: String?) async throws -> Published {
        let (data, status, _) = try await fetch(url, false)
        guard status == 200 else { throw Failure.http(status) }
        guard let published = Self.parseSums(data), version == nil || published.version == version
        else { throw Failure.unreadable }
        return published
    }

    /// `<64 hex>  <name>` per line (or `*<name>`, as the installer also accepts).
    /// The version is the one every macOS archive's name carries; nil when there
    /// is none, or two names disagree.
    static func parseSums(_ data: Data) -> Published? {
        let pattern = #"^([a-z]+)-(\d{1,4}\.\d{1,4}\.\d{1,4})-universal2-apple-darwin\.tar\.xz$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var version: String?
        var digests: [ObelusInstall.Binary: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { continue }
            let hex = String(fields[0]).lowercased()
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let binaryRange = Range(match.range(at: 1), in: name),
                  let versionRange = Range(match.range(at: 2), in: name),
                  let binary = ObelusInstall.Binary(rawValue: String(name[binaryRange]))
            else { continue }
            let named = String(name[versionRange])
            if let version, version != named { return nil }
            version = named
            digests[binary] = hex
        }
        guard let version, ZoxideRelease.isVersion(version) else { return nil }
        return Published(version: version, archiveDigests: digests)
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

/// Whether an `obg` or `ob` is byte for byte the build obelus-editor published
/// for its version — the second arm of the trust rule (`CLIToolTrust`), for a
/// binary that is only ever ad hoc signed.
///
/// The published hash is `SHA256SUMS`'s line for the release's archive
/// (`ObelusRelease`), not for the bare binary. So, as for zoxide
/// (`ZoxideVerifier`): download the archive, check it against that line, unpack
/// it, and hash the binary in it. What is remembered is that last hash, per
/// version and binary (`ObelusPublishedDigests`). The archive (~25–35 MB) is
/// downloaded once per version, only by a click, never by a background check.
struct ObelusVerifier: Sendable {

    /// The archive digests of one version's release.
    typealias Release = @Sendable (_ version: String) async throws -> ObelusRelease.Published
    /// A URL's body; throws on anything but a 2xx.
    typealias Download = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.xz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let release: Release
    let download: Download
    let extract: Extract
    let hash: Hash
    let digests: ObelusPublishedDigests

    init(
        release: @escaping Release = { try await ObelusRelease().release(version: $0) },
        download: @escaping Download = ZoxideVerifier.get,
        extract: @escaping Extract = ObelusVerifier.untar,
        hash: @escaping Hash = CLIToolTrust.sha256(of:),
        digests: ObelusPublishedDigests = .shared
    ) {
        self.release = release
        self.download = download
        self.extract = extract
        self.hash = hash
        self.digests = digests
    }

    /// Checks `binary` against `version` of `name`, downloading that release's
    /// archive when its binary's digest is not yet known.
    func verify(binary: String, name: ObelusInstall.Binary, version: String) async -> UvVerifier.Result {
        let published: String
        switch await publishedDigest(name, version: version) {
        case .success(let digest): published = digest
        case .failure(let failure): return .couldNotVerify(failure.reason)
        }
        let hash = self.hash
        let actual = await offCooperativePool { hash(URL(fileURLWithPath: binary)) }
        return CLIToolTrust.matches(actual, published: published)
            ? .matches
            : .differs("\(binary) is not the \(name.rawValue) \(version) obelus-editor published")
    }

    struct Failure: Error {
        let reason: String
    }

    /// The sha256 of the binary inside the release's archive, once the archive
    /// matched the line `SHA256SUMS` has for it.
    func publishedDigest(_ name: ObelusInstall.Binary, version: String) async -> Result<String, Failure> {
        let what = "\(name.rawValue) \(version)"
        guard ZoxideRelease.isVersion(version) else {
            return .failure(Failure(reason: "no published \(what)"))
        }
        let digests = self.digests
        if let known = await offCooperativePool({ digests.digest(name, version: version) }) {
            return .success(known)
        }
        let archiveDigest: String
        do {
            guard let digest = try await release(version).archiveDigests[name] else {
                return .failure(Failure(reason: "the Obelus \(version) SHA256SUMS names no \(ObelusRelease.archiveName(name, version: version))"))
            }
            archiveDigest = digest
        } catch {
            return .failure(Failure(reason: "could not read the Obelus \(version) SHA256SUMS: \(error)"))
        }
        let archive: Data
        do {
            archive = try await download(ObelusRelease.archiveURL(name, version: version))
        } catch {
            return .failure(Failure(reason: "could not download \(what) to compare: \(error)"))
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: archiveDigest) else {
            return .failure(Failure(reason: "the \(what) archive did not match its SHA256SUMS"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-obelus-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent(ObelusRelease.archiveName(name, version: version))
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .failure(Failure(reason: "could not unpack \(what): \(error)"))
        }
        let hash = self.hash
        let inside = scratch.appendingPathComponent(ObelusRelease.archiveDirectory(name, version: version))
            .appendingPathComponent(name.rawValue)
        guard let binary = await offCooperativePool({ hash(inside) }) else {
            return .failure(Failure(reason: "the \(what) archive has no \(name.rawValue)"))
        }
        await offCooperativePool { digests.remember(binary, name, version: version) }
        return .success(binary)
    }

    /// `tar -xJf`: the system's bsdtar reads xz itself.
    static func untar(_ archive: URL, _ directory: URL) async throws {
        let outcome = try await ChildProcess.run(
            "/usr/bin/tar", ["-xJf", archive.path, "-C", directory.path],
            environment: ["PATH": CLIToolCommandRunner.systemPath],
            standardOutput: .discard, standardError: .capture,
            deadline: ChildProcess.Deadline(terminateAfter: .seconds(60), killAfter: .seconds(65)),
            onCancel: .terminateChild)
        guard outcome.succeeded else {
            throw UvRelease.Failure.unpack(String(decoding: outcome.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// The sha256 of each release's `obg` and `ob`, by version and binary, as
/// `ObelusVerifier` found them inside archives that matched `SHA256SUMS`.
/// `ZoxidePublishedDigests`, in `com.duoupdater.app/obelus-published-digests.json`.
public final class ObelusPublishedDigests: @unchecked Sendable {

    public static let shared = ObelusPublishedDigests()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? DuoStateDirectory.testProcessScratchRoot
                .appendingPathComponent("duo-obelus-digests-tests-\(UUID().uuidString)")
                .appendingPathComponent("obelus-published-digests.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("obelus-published-digests.json"))
    }

    static func key(_ name: ObelusInstall.Binary, version: String) -> String { "\(version) \(name.rawValue)" }

    /// Blocking.
    func digest(_ name: ObelusInstall.Binary, version: String) -> String? {
        lock.withLock { load()[Self.key(name, version: version)] }
    }

    /// Blocking.
    func remember(_ digest: String, _ name: ObelusInstall.Binary, version: String) {
        lock.withLock {
            var entries = load()
            entries[Self.key(name, version: version)] = digest
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
