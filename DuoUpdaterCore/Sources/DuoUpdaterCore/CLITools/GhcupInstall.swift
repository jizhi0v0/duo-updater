import Foundation

/// GHCup — the Haskell toolchain installer — as its bootstrap script leaves it,
/// identified by **its path**: `~/.ghcup/bin/ghcup`. Only the `ghcup` binary is
/// tracked; the toolchains it installs (GHC, cabal, HLS, stack) are not.
///
/// The layout, from the vendor's bootstrap (`curl … https://get-ghcup.haskell.org
/// | sh`) and ghcup-hs at v0.2.6.2 (`GHCup.Query.GHCupDirs`), read 2026-10-09:
/// - the bootstrap downloads `downloads.haskell.org/~ghcup/<ver>/<arch>-apple-darwin-ghcup-<ver>`
///   with `curl` straight to `~/.ghcup/bin/ghcup`, then asks questions, edits
///   the shell rc files and installs toolchains (which can bring up the Xcode
///   command line tools dialog). None of that is ever run here.
/// - With `GHCUP_USE_XDG_DIRS` set the binary goes to `~/.local/bin/ghcup`
///   instead. That is a directory many tools share, and nothing on disk says a
///   file there is ghcup's XDG install rather than a copy, so only the default
///   place is looked at.
/// - `ghcup upgrade` (no option) replaces `<binDir>/ghcup`, `binDir` being
///   `~/.ghcup/bin` without the XDG variable.
/// - The binary is Haskell, **ad hoc and linker-signed** (`Identifier=ghcup`, no
///   Team) in 0.2.6.1 and 0.2.6.2, so it is trusted by its release's published
///   sha256 alone (`GhcupVerifier`). That digest is of the bare binary
///   (`SHA256SUMS`), so no archive is involved.
/// - The version is in the file only as a package id: `ghcup-0.2.6.2-inplace`,
///   539 times in 0.2.6.2 and `ghcup-0.2.6.1-inplace` 533 times in 0.2.6.1
///   (arm64, 2026-10-09). That is a weak claim by itself, so it is only the
///   *candidate*: the check asks that version's `SHA256SUMS` and the file must
///   hash to it, which names the version and vouches for the bytes in one step.
///   ghcup is never run to ask (`--numeric-version` would run an unverified
///   file, and its answer would name the version whose hash to compare against).
///
/// Hashing and reading 135 MB on every check is not cheap, so both are
/// remembered for the file as it is (`GhcupFileFacts`): by device, inode, size
/// and modification time, forgotten when any changes.
public struct GhcupInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// A link: `ghcup upgrade` deletes it and writes a file in its place,
        /// leaving the file it pointed at as it was.
        case link
        /// No `ghcup-<version>-inplace` in the file, or several that disagree.
        case versionUnreadable
    }

    /// `~/.ghcup/bin/ghcup`: the row's identity.
    public let path: String
    /// The version the file claims (`ghcup-<version>-inplace`); trusted only once
    /// its sha256 is that version's published one.
    public let version: String?
    /// The file's sha256, lowercase hex.
    public let sha256: String?
    /// `aarch64-apple-darwin` or `x86_64-apple-darwin`, from its Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether this user may replace files in `~/.ghcup/bin`.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, version: String?, sha256: String? = nil, target: String? = "aarch64-apple-darwin",
        quarantined: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.sha256 = sha256
        self.target = target
        self.quarantined = quarantined
        self.writable = writable
        self.problem = problem
    }

    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// Finds ghcup where its bootstrap puts it. Network-free, and nothing is run:
/// the file is hashed and its claimed version read, once per change of the file.
public struct GhcupScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The release target of an executable. Blocking.
    typealias TargetRead = @Sendable (URL) -> String?
    /// The file's sha256 and claimed version. Blocking.
    typealias Read = @Sendable (URL) -> (sha256: String?, version: String?)

    let home: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead
    let readFile: Read
    let facts: GhcupFileFacts

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, isQuarantined: CLIToolTrust.hasQuarantine, readTarget: LuvusScanner.target(of:),
                  readFile: GhcupScanner.readFile, facts: .shared)
    }

    init(
        home: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead,
        readFile: @escaping Read, facts: GhcupFileFacts
    ) {
        self.home = home
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
        self.readFile = readFile
        self.facts = facts
    }

    var location: String { home.appendingPathComponent(".ghcup/bin/ghcup").path }

    /// Blocking.
    public func scan() -> [GhcupInstall] {
        read().map { [$0] } ?? []
    }

    /// Blocking.
    func read() -> GhcupInstall? {
        let path = location
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            guard let resolved = LuvusScanner.canonicalPath(path) else {
                return GhcupInstall(path: path, version: nil, target: nil, problem: .executableMissing)
            }
            if AtuinScanner.belongsElsewhere(resolved) { return nil }
            return GhcupInstall(path: path, version: nil, target: nil, problem: .link)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? Int ?? 0) > 0 else {
            return GhcupInstall(path: path, version: nil, target: nil, problem: .executableMissing)
        }
        let url = URL(fileURLWithPath: path)
        let read: (sha256: String?, version: String?)
        if let identity = UvVerifiedFiles.fileIdentity(path), let known = facts.facts(for: path, identity: identity) {
            read = (known.sha256, known.version)
        } else {
            let identity = UvVerifiedFiles.fileIdentity(path)
            read = readFile(url)
            // Only what was read from the file the identity was taken of.
            if let identity, let sha256 = read.sha256, UvVerifiedFiles.fileIdentity(path) == identity {
                facts.remember(GhcupFileFacts.Entry(identity: identity, sha256: sha256, version: read.version), for: path)
            }
        }
        return GhcupInstall(
            path: path, version: read.version, sha256: read.sha256, target: readTarget(url),
            quarantined: isQuarantined(url), writable: access(url.deletingLastPathComponent().path, W_OK) == 0,
            problem: read.version == nil ? .versionUnreadable : nil)
    }

    static let marker = Data("-inplace".utf8)

    /// The file's sha256 and the version its `ghcup-<version>-inplace` package
    /// ids claim. Blocking: reads the whole file twice.
    static func readFile(_ url: URL) -> (sha256: String?, version: String?) {
        let version = ExecutableBytes.windows(in: url, marker: marker, before: 32, after: 0)
            .flatMap(claimedVersion)
        return (CLIToolTrust.sha256(of: url), version)
    }

    /// The version in every `ghcup-<version>-inplace`, when they agree; ids of
    /// other packages (`<name>-<version>-inplace`) are not ghcup's and are skipped.
    static func claimedVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            let text = String(decoding: window.dropLast(marker.count), as: UTF8.self)
            guard let range = text.range(of: "ghcup-", options: .backwards) else { continue }
            // `ghcup-` must start the package id: not `foo-ghcup-…`.
            if range.lowerBound > text.startIndex {
                let before = text[text.index(before: range.lowerBound)]
                if before.isLetter || before.isNumber || before == "-" || before == "_" { continue }
            }
            let version = String(text[range.upperBound...])
            if GhcupRelease.isVersion(version) { found.insert(version) }
        }
        return found.count == 1 ? found.first : nil
    }
}

/// What `GhcupScanner` read from ghcup's file, per path, for exactly the file it
/// read: by device, inode, size and modification time (`UvVerifiedFiles`'
/// identity). A file replaced since — `ghcup upgrade` deletes the old one and
/// copies the new one in — no longer matches, and is read again.
///
/// Kept in `com.duoupdater.app/ghcup-file-facts.json` under
/// `DuoStateDirectory.base`, so a relaunch does not hash 135 MB again.
public final class GhcupFileFacts: @unchecked Sendable {

    struct Entry: Codable, Equatable {
        let identity: UvVerifiedFiles.FileIdentity
        let sha256: String
        let version: String?
    }

    public static let shared = GhcupFileFacts()

    private let lock = NSLock()
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? (DuoStateDirectory.isTestProcess
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-ghcup-facts-tests-\(UUID().uuidString)")
                .appendingPathComponent("ghcup-file-facts.json")
            : DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("ghcup-file-facts.json"))
    }

    /// Blocking.
    func facts(for path: String, identity: UvVerifiedFiles.FileIdentity) -> Entry? {
        guard let entry = lock.withLock({ load()[path] }), entry.identity == identity else { return nil }
        return entry
    }

    /// Blocking.
    func remember(_ entry: Entry, for path: String) {
        lock.withLock {
            var entries = load()
            entries[path] = entry
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
}
