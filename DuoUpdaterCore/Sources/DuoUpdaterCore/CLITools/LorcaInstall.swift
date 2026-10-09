import Foundation

/// The Lorca CLI — egoist's `lorca`, the Runner that pairs a computer with a
/// Lorca account — as its install script leaves it, identified by **its path**:
/// `~/.local/bin/lorca`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://lorca.app/install-cli.sh
/// | sh`, read 2026-10-09) and `crates/cli/src/update.rs` at cli-v0.1.11:
/// - The installer downloads `lorca-cli-macos-aarch64.tar.gz` from GitHub's
///   `releases/latest/download/` (or `cli-v$LORCA_VERSION`), checks it against
///   the `.sha256` beside it, and renames its one file `lorca` into
///   `$LORCA_INSTALL_DIR`, else `~/.local/bin`. There is no Intel Mac build.
/// - The Mac app carries its own `lorca` inside its bundle, runs it with its
///   own `LORCA_HOME`, and updates it with the app; it never links it into
///   `~/.local/bin`. A path that resolves into a `.app` is that copy, and not
///   this group's — `lorca update` refuses it too ("came with the Lorca app").
/// - The binary is Rust, **ad hoc and linker-signed** (`Identifier=lorca-<hash>`,
///   no Team) in every release looked at (0.1.1, 0.1.7, 0.1.10, 0.1.11), so it
///   is trusted by its release's published sha256 alone (`LorcaVerifier`).
/// - The version is compiled in as the User-Agent `lorca/<version>`, in every
///   build's bytes and nowhere with another version (once in 0.1.1 and 0.1.7,
///   five times in 0.1.10, seven in 0.1.11, measured 2026-10-09). It is read
///   from the file rather than by running it, so nothing of an unverified file
///   runs. `lorca-agent/<version>` is another literal and does not match.
public struct LorcaInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No `lorca/<version>` in the file, or several that disagree.
        case versionUnreadable
    }

    /// `~/.local/bin/lorca`: the row's identity.
    public let path: String
    /// The file `path` resolves to (`realpath`, as `lorca update` canonicalizes
    /// its own path before it renames over it); nil when it could not be resolved.
    public let binary: String?
    /// The version compiled into the file, nil when it could not be read.
    public let version: String?
    /// `macos-aarch64` for an arm64 file — the only Mac build Lorca publishes —
    /// else nil.
    public let target: String?
    public let quarantined: Bool
    /// Whether this user may create and rename files in the directory holding
    /// `binary` — what `lorca update` needs to stage its replacement beside it.
    public let writable: Bool
    /// `auto_update` in `~/.lorca/settings.json`; true when absent, as lorca reads it.
    public let autoUpdate: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "macos-aarch64",
        quarantined: Bool = false, writable: Bool = true, autoUpdate: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.quarantined = quarantined
        self.writable = writable
        self.autoUpdate = autoUpdate
        self.problem = problem
    }

    /// The first release with `lorca update` and the signed `lorca-cli.json` it
    /// reads (cli-v0.1.11, 2026-10-09). 0.1.10's binary has neither; its releases
    /// carry no manifest (`lorca-cli.json` answers 404 for cli-v0.1.1 to 0.1.10).
    public static let firstUpdatingVersion = "0.1.11"

    /// Whether this build has `lorca update` at all.
    public var hasUpdateCommand: Bool {
        guard let version else { return false }
        return VersionComparator.compare(version, Self.firstUpdatingVersion) != .orderedAscending
    }
}

/// Finds the Lorca CLI where its installer puts it. Network-free, and nothing is
/// run: the version is read out of the file.
public struct LorcaScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The release target of an executable. Injected so tests can stand a script
    /// in for the Mach-O file. Blocking.
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, isQuarantined: CLIToolTrust.hasQuarantine, readTarget: LorcaScanner.target(of:))
    }

    init(home: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead) {
        self.home = home
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    var location: String { home.path + "/.local/bin/lorca" }

    /// `settings.json` in lorca's folder, `~/.lorca` (`config.rs`, `settings_path`).
    var settingsFile: URL { home.appendingPathComponent(".lorca/settings.json") }

    /// Blocking: the file is stat'd and read.
    public func scan() -> [LorcaInstall] {
        read(location).map { [$0] } ?? []
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> LorcaInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String) -> LorcaInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        let autoUpdate = Self.autoUpdate(in: settingsFile)
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return LorcaInstall(path: path, binary: nil, version: nil, target: nil, autoUpdate: autoUpdate,
                                problem: .executableMissing)
        }
        // The Mac app's own copy (`update`'s `bundled` test: a path component
        // ending in `.app`).
        if binary.split(separator: "/").contains(where: { $0.hasSuffix(".app") }) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return LorcaInstall(path: path, binary: binary, version: nil, target: nil, autoUpdate: autoUpdate,
                                problem: .executableMissing)
        }
        // Read, never mapped (`ExecutableBytes`).
        let version = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 32)
            .flatMap(Self.compiledVersion)
        let directory = (binary as NSString).deletingLastPathComponent
        return LorcaInstall(
            path: path, binary: binary, version: version, target: readTarget(url),
            quarantined: isQuarantined(url), writable: access(directory, W_OK) == 0, autoUpdate: autoUpdate,
            problem: version == nil ? .versionUnreadable : nil)
    }

    /// `auto_update` as lorca reads it (`unwrap_or(true)`): only an explicit
    /// `false` turns it off. Blocking.
    static func autoUpdate(in file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["auto_update"] as? Bool
        else { return true }
        return value
    }

    static let marker = Data("lorca/".utf8)

    /// The version after the file's `lorca/` literals that are followed by one —
    /// `lorca/0.1.11`; nil when there is none, or several that disagree.
    ///
    /// The User-Agent sits against the next literal with no separator
    /// (`lorca/0.1.11x-opencode`, `lorca/0.1.11--version`), so it is read as
    /// `<n>.<n>.<n>` and stops there: what `LuvusScanner.version(at:in:)` reads,
    /// cut at a `-`, since Lorca's versions are plain `major.minor.patch`
    /// (`update.rs`'s `is_newer` reads nothing else).
    static func compiledVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            let start = window.startIndex + marker.count
            if let version = LuvusScanner.version(at: start, in: window)?.split(separator: "-").first {
                found.insert(String(version))
            }
        }
        guard found.count == 1, let version = found.first, LorcaRelease.isVersion(version) else { return nil }
        return version
    }

    /// `macos-aarch64` for a thin arm64 Mach-O, in Lorca's asset spelling. Blocking.
    static func target(of executable: URL) -> String? {
        ClaudeCodeRelease.platform(of: executable) == "darwin-arm64" ? "macos-aarch64" : nil
    }
}
