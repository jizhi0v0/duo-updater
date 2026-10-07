import Foundation

/// Luvus — RizRiyz's "mission control for your AI coding agents" — as its
/// installer leaves it, identified by **its path**: `/usr/local/bin/luvus` or
/// `~/.local/bin/luvus`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://luvus.dev/install.sh
/// | sh`, read 2026-10-07) and `src/update.rs` at v0.14.3:
/// - The installer resolves the tag from GitHub's `releases/latest` (or
///   `LUVUS_VERSION`), downloads `luvus-<tag>-<target>.tar.gz`
///   (`aarch64-apple-darwin` / `x86_64-apple-darwin`), extracts the one file
///   `luvus` and moves it to `$LUVUS_INSTALL_DIR`, else `/usr/local/bin` when
///   that is writable, else `~/.local/bin`. It checks no hash, and falls back to
///   `sudo mv` when the move fails.
/// - `luvus update` classifies its own canonical path (`classify_install`): a
///   path inside a Homebrew Cellar, `/nix/store`, `~/.cargo/bin` or a cargo
///   `target/` directory belongs to that tool, and only `~/.local/bin/luvus`
///   (compared with `$HOME` as written) and `/usr/local/bin/luvus` are "direct"
///   installs it replaces itself. The first are not looked at here (Homebrew's
///   copy is the brew group's); a link to anywhere else is reported, since
///   `luvus update` refuses it ("could not safely identify the installation
///   channel").
/// - The binary is Rust, **ad hoc and linker-signed** (`Identifier=luvus-<hash>`,
///   no Team) in every release looked at, so it is trusted by its release's
///   published sha256 alone (`LuvusVerifier`).
/// - The version is compiled in: `luvus <version>` — what `--version` prints —
///   is in every build's bytes, twice, and nowhere with another version (0.11.0,
///   0.12.0, 0.13.1, 0.13.2, 0.13.4, 0.14.1, 0.14.2 and 0.14.3 on arm64, 0.11.0 and
///   0.14.3 on x86_64, measured 2026-10-07). It is read from the file rather
///   than by running it, so nothing of an unverified file runs. Releases before
///   0.11.0 were named Bohay and installed a `bohay` binary.
public struct LuvusInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No `luvus <version>` in the file, or several that disagree.
        case versionUnreadable
        /// A link to somewhere `luvus update` does not treat as its own install.
        case unknownLocation
    }

    /// `/usr/local/bin/luvus` or `~/.local/bin/luvus`: the row's identity.
    public let path: String
    /// The file `path` resolves to (`realpath`, as `luvus update` canonicalizes
    /// its own path); nil when it could not be resolved.
    public let binary: String?
    /// The version compiled into the file, nil when it could not be read.
    public let version: String?
    /// The release target the file was built for, `aarch64-apple-darwin` or
    /// `x86_64-apple-darwin`, from its Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether this user may create and rename files in the directory holding
    /// `binary` — what `luvus update` needs to stage its replacement beside it
    /// without falling back to `sudo`.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "aarch64-apple-darwin",
        quarantined: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.quarantined = quarantined
        self.writable = writable
        self.problem = problem
    }

    /// The first release with `luvus update` (`feat(cli): add safe Luvus
    /// updates`, #88, in v0.12.0; 0.11.0's binary has no such command).
    public static let firstUpdatingVersion = "0.12.0"

    /// Whether this build has `luvus update` at all.
    public var hasUpdateCommand: Bool {
        guard let version else { return false }
        return VersionComparator.compare(version, Self.firstUpdatingVersion) != .orderedAscending
    }
}

/// Finds Luvus where its installer puts it. Network-free, and nothing is run:
/// the version is read out of the file.
public struct LuvusScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The release target of an executable. Injected so tests can stand a script
    /// in for the Mach-O file. Blocking.
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
    /// `/usr/local/bin`; a fixture directory in tests.
    let systemDirectory: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, systemDirectory: URL(fileURLWithPath: "/usr/local/bin"),
                  isQuarantined: CLIToolTrust.hasQuarantine, readTarget: LuvusScanner.target(of:))
    }

    init(home: URL, systemDirectory: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead) {
        self.home = home
        self.systemDirectory = systemDirectory
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    var userLocation: String { home.path + "/.local/bin/luvus" }
    var systemLocation: String { systemDirectory.path + "/luvus" }

    /// Each install, `/usr/local/bin` first; a path that is a link to the other
    /// one is the same install and is listed once, under the file's own path.
    /// Blocking: files are stat'd and read.
    public func scan() -> [LuvusInstall] {
        var installs: [LuvusInstall] = []
        for path in [systemLocation, userLocation] {
            guard let install = read(path) else { continue }
            if let index = installs.firstIndex(where: { $0.binary != nil && $0.binary == install.binary }) {
                // Keep the path that is the file itself.
                if install.path == install.binary { installs[index] = install }
                continue
            }
            installs.append(install)
        }
        return installs
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> LuvusInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String) -> LuvusInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        guard let binary = Self.canonicalPath(path) else {
            return LuvusInstall(path: path, binary: nil, version: nil, target: nil, problem: .executableMissing)
        }
        let location = classify(binary)
        guard location != .other else { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return LuvusInstall(path: path, binary: binary, version: nil, target: nil, problem: .executableMissing)
        }
        // Read, never mapped (`ExecutableBytes`).
        let version = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 48)
            .flatMap(Self.compiledVersion)
        let problem: LuvusInstall.Problem?
        if version == nil {
            problem = .versionUnreadable
        } else if location == .unknown {
            problem = .unknownLocation
        } else {
            problem = nil
        }
        let directory = (binary as NSString).deletingLastPathComponent
        return LuvusInstall(
            path: path, binary: binary, version: version, target: readTarget(url),
            quarantined: isQuarantined(url), writable: access(directory, W_OK) == 0, problem: problem)
    }

    enum Location: Equatable {
        /// A direct install `luvus update` replaces itself.
        case direct
        /// Homebrew, Nix, cargo, a development build, a system package: that
        /// tool's install, not this group's.
        case other
        /// Anywhere else: `luvus update` refuses it.
        case unknown
    }

    /// `classify_install` (`src/update.rs` at v0.14.3) on the canonical path, the
    /// home directory taken as written, as luvus takes `$HOME`.
    func classify(_ binary: String) -> Location {
        let lowered = binary.lowercased()
        if lowered.contains("/target/debug/luvus") || lowered.contains("/target/release/luvus")
            || lowered.contains("/cellar/luvus/") || lowered.hasPrefix("/nix/store/")
            || lowered == "/usr/bin/luvus" || lowered == "/bin/luvus"
            || binary == home.path + "/.cargo/bin/luvus" {
            return .other
        }
        if binary == userLocation || binary == systemLocation { return .direct }
        return .unknown
    }

    /// `realpath(3)`, which Rust's `canonicalize` is: symlinks resolved, `/tmp`
    /// as `/private/tmp`. Foundation's `resolvingSymlinksInPath` drops a
    /// `/private` prefix, which is not the path luvus compares.
    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static let marker = Data("luvus ".utf8)

    /// The version after the file's `luvus ` literals that are followed by one —
    /// `luvus 0.14.3`; nil when there is none, or several that disagree.
    ///
    /// Read as `<n>.<n>.<n>` and, when a `-` follows, the run of letters, digits
    /// and dots after it (a semver prerelease; Luvus has published none), so a
    /// letter that starts the next literal in the binary does not run on into the
    /// version. `luvus ` followed by anything else (`luvus update`) is skipped.
    static func compiledVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            let start = window.startIndex + marker.count
            if let version = version(at: start, in: window) { found.insert(version) }
        }
        guard found.count == 1, let version = found.first, LuvusRelease.isVersion(version) else { return nil }
        return version
    }

    static func version(at index: Data.Index, in data: Data) -> String? {
        func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
        func isSuffix(_ byte: UInt8) -> Bool {
            isDigit(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2E
        }
        var i = index
        func run(_ accept: (UInt8) -> Bool) -> Bool {
            let first = i
            while i < data.endIndex, i - first < 20, accept(data[i]) { i += 1 }
            return i > first
        }
        for part in 0..<3 {
            guard run(isDigit) else { return nil }
            if part < 2 {
                guard i < data.endIndex, data[i] == 0x2E else { return nil }
                i += 1
            }
        }
        var end = i
        if i < data.endIndex, data[i] == 0x2D {
            i += 1
            if run(isSuffix) { end = i }
        }
        return String(decoding: data[index..<end], as: UTF8.self)
    }

    /// The release target a thin Mach-O was built for, in Luvus's asset
    /// spelling. Blocking.
    static func target(of executable: URL) -> String? {
        switch ClaudeCodeRelease.platform(of: executable) {
        case "darwin-arm64": return "aarch64-apple-darwin"
        case "darwin-x64": return "x86_64-apple-darwin"
        default: return nil
        }
    }
}
