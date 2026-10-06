import CryptoKit
import Foundation

/// Whether an unsigned uv is byte for byte the release its receipt names — the
/// second arm of the trust rule (`CLIToolTrust`), for every uv up to 0.12.11.
///
/// Astral publishes no digest for the bare executables, only for the archives:
/// each GitHub release carries `uv-<arch>-apple-darwin.tar.gz` and a
/// `….tar.gz.sha256` beside it (`<hex>  <name>`), and the versions manifest
/// repeats the same digest. So the check is the archive's: download it for the
/// receipt's version and the executable's own architecture, check it against the
/// published digest, unpack it, and compare `uv` and `uvx` with what is on disk.
/// Measured 2026-10-02 for 0.9.18 on arm64: the archive is 18,986,443 bytes,
/// its digest matched `dc3bee4a…` from the `.sha256` asset, and both unpacked
/// files hashed the same as this Mac's `~/.local/bin/uv` and `uvx`.
///
/// ~19 MB is too much for a background check, so this runs only when the user
/// clicks the update, and what it found is remembered (`UvVerifiedFiles`).
struct UvVerifier: Sendable {

    enum Result: Sendable, Equatable {
        case matches
        /// The files are not the release; the reason, for the row.
        case differs(String)
        /// The check itself could not be made (network, a missing digest); nothing
        /// is remembered, and nothing is run.
        case couldNotVerify(String)
    }

    /// Fetches a URL's body; throws on anything but a 2xx.
    typealias Fetch = @Sendable (URL) async throws -> Data
    /// Unpacks a `.tar.gz` into a directory.
    typealias Extract = @Sendable (URL, URL) async throws -> Void
    /// An executable's architecture, in uv's archive spelling. Blocking.
    typealias Architecture = @Sendable (URL) -> String?

    let fetch: Fetch
    let extract: Extract
    let architecture: Architecture
    let verified: UvVerifiedFiles

    static let releases = URL(string: "https://github.com/astral-sh/uv/releases/download")!

    init(
        fetch: @escaping Fetch = UvVerifier.download,
        extract: @escaping Extract = UvVerifier.untar,
        architecture: @escaping Architecture = UvScanner.architecture,
        verified: UvVerifiedFiles = .shared
    ) {
        self.fetch = fetch
        self.extract = extract
        self.architecture = architecture
        self.verified = verified
    }

    /// Checks `install` against its receipt's release and remembers a definite
    /// answer for the files as they are now.
    func verify(_ install: UvInstall) async -> Result {
        guard let version = install.receiptVersion, let executable = install.executable else {
            return .couldNotVerify("no receipt version to check the file against")
        }
        let architecture = self.architecture
        guard let arch = await offCooperativePool({ architecture(URL(fileURLWithPath: executable)) })
        else { return .couldNotVerify("\(executable) is not a uv executable this check can read") }
        // Who the files are now, taken before they are read: a file replaced
        // while this runs is remembered under the old identity, which then
        // matches nothing.
        let path = install.path, uvx = install.uvx
        let identity = await offCooperativePool { UvVerifiedFiles.identity(of: path, uvx: uvx) }

        let result = await compare(executable: executable, uvx: uvx, version: version, arch: arch)
        let verdict: UvInstall.HashVerdict?
        switch result {
        case .matches: verdict = .matches
        case .differs: verdict = .differs
        case .couldNotVerify: verdict = nil
        }
        if let verdict, let identity {
            let verified = self.verified
            await offCooperativePool { verified.remember(verdict, for: path, identity: identity) }
        }
        return result
    }

    private func compare(executable: String, uvx: String?, version: String, arch: String) async -> Result {
        let name = "uv-\(arch)-apple-darwin"
        let archiveURL = Self.releases.appendingPathComponent(version).appendingPathComponent("\(name).tar.gz")
        let published: String
        let archive: Data
        do {
            published = String(decoding: try await fetch(archiveURL.appendingPathExtension("sha256")), as: UTF8.self)
            archive = try await fetch(archiveURL)
        } catch {
            return .couldNotVerify("could not download uv \(version) to compare: \(error)")
        }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard CLIToolTrust.matches(digest, published: published) else {
            return .couldNotVerify("the uv \(version) archive did not match the sha256 Astral publishes for it")
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-uv-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archiveFile = scratch.appendingPathComponent("\(name).tar.gz")
        do {
            try await offCooperativePool {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                try archive.write(to: archiveFile)
            }
            try await extract(archiveFile, scratch)
        } catch {
            return .couldNotVerify("could not unpack uv \(version): \(error)")
        }
        let unpacked = scratch.appendingPathComponent(name)
        let pairs: [(String, URL)] = [(executable, unpacked.appendingPathComponent("uv"))]
            + (uvx.map { [($0, unpacked.appendingPathComponent("uvx"))] } ?? [])
        return await offCooperativePool {
            for (installed, published) in pairs {
                guard let expected = CLIToolTrust.sha256(of: published) else {
                    return .couldNotVerify("the uv \(version) archive has no \(published.lastPathComponent)")
                }
                let actual = CLIToolTrust.sha256(of: URL(fileURLWithPath: installed).resolvingSymlinksInPath())
                guard CLIToolTrust.matches(actual, published: expected) else {
                    return .differs("\(installed) is not the \(published.lastPathComponent) Astral published for uv \(version)")
                }
            }
            return .matches
        }
    }

    // MARK: - The host

    /// A release asset, through GitHub's redirect to its CDN. The archive is
    /// counted as an install, the digest as a version check.
    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let purpose: RequestPurpose = url.pathExtension == "sha256" ? .versionCheck : .install
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: purpose)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw UvRelease.Failure.http(status) }
        return data
    }

    /// `/usr/bin/tar -xzf`, as uv's own installer unpacks the same archive.
    static func untar(_ archive: URL, _ directory: URL) async throws {
        let outcome = try await ChildProcess.run(
            "/usr/bin/tar", ["-xzf", archive.path, "-C", directory.path],
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

/// What `UvVerifier` found, per install path, for exactly the files it looked
/// at: `uv` and `uvx` by device, inode, size and modification time. A file
/// replaced since — `uv self update` writes new inodes, measured 2026-10-02 —
/// no longer matches, and the verdict is gone.
///
/// Kept in `com.duoupdater.app/uv-verified-files.json` under
/// `DuoStateDirectory.base`, so a copy found not to be the release reads as
/// `.unverified` after a relaunch too, without another 19 MB download.
public final class UvVerifiedFiles: @unchecked Sendable {

    struct FileIdentity: Codable, Hashable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    struct Identity: Codable, Hashable {
        let uv: FileIdentity
        let uvx: FileIdentity?
    }

    struct Entry: Codable {
        let identity: Identity
        let verdict: UvInstall.HashVerdict
    }

    public static let shared = UvVerifiedFiles()

    private let lock = NSLock()
    let fileURL: URL

    /// `name` is the file's: another tool trusted the same way keeps its own
    /// (`UvVerifiedFiles.vitePlus`).
    init(fileURL: URL? = nil, name: String = "uv-verified-files.json") {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-uv-verified-tests-\(UUID().uuidString)")
                .appendingPathComponent(name)
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent(name))
    }

    /// The verdict for the files at `path` (and `uvx`) as they are now. Blocking.
    func verdict(for path: String, uvx: String?) -> UvInstall.HashVerdict? {
        guard let identity = Self.identity(of: path, uvx: uvx) else { return nil }
        let entries = lock.withLock { load() }
        guard let entry = entries[path], entry.identity == identity else { return nil }
        return entry.verdict
    }

    func remember(_ verdict: UvInstall.HashVerdict, for path: String, identity: Identity) {
        lock.withLock {
            var entries = load()
            entries[path] = Entry(identity: identity, verdict: verdict)
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Under the lock.
    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    /// The files' identities, symlinks followed; nil when `uv` cannot be stat'd.
    static func identity(of path: String, uvx: String?) -> Identity? {
        guard let uv = fileIdentity(path) else { return nil }
        return Identity(uv: uv, uvx: uvx.flatMap(fileIdentity))
    }

    static func fileIdentity(_ path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileIdentity(
            device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }
}
