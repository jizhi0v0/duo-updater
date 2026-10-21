import Foundation

/// Biome — the JavaScript/TypeScript linter and formatter (biomejs.dev) — as its
/// installer leaves it, identified by **its path**: `~/.local/bin/biome`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://biomejs.dev/install
/// | bash`, read 2026-10-21):
/// - It reads the version to install from `biomejs.dev/api/versions/latest.txt`
///   (or `--version <v>` / `BIOME_VERSION`), downloads the release's raw binary
///   `github.com/biomejs/biome/releases/download/@biomejs/biome@<v>/biome-darwin-<arm64|x64>`
///   into `mktemp -d <dir>/.biome-install.XXXXXX` with no hash check, and `mv`s
///   it to `${BIOME_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}/biome`. No
///   `sudo`, no receipt. Without `--no-modify-path` it appends a `PATH` line to
///   the shell's rc file.
/// - The binary is Rust, **ad hoc and linker-signed** (`Identifier=biome-<hash>`,
///   no Team) in every build looked at (2.4.6, 2.5.0, 2.5.15, 2.6.2, both
///   architectures), and no release carries a checksum file.
/// - Its version is **not** readable from the file: the build's version literal
///   (`2.6.2`) appears once, between whatever strings the linker put around it,
///   and those differ from build to build (2.4.6: after `configuration.rs`;
///   2.5.15: after a rule's docs; 2.6.2: after `.gitignore.ignore`, measured
///   2026-10-21). Running `biome --version` would run a file before it is
///   trusted. So the file is identified by its **sha256**: it is the release
///   whose published `digest` for this Mac's binary it equals
///   (`BiomePublishedDigests`), which is the trust rule's own check
///   (`CLIToolTrust`) and gives the version at once. A file that matches no
///   published build is reported, never run.
/// - npm's `@biomejs/biome` and Homebrew's `biome` are their package managers'
///   rows: a path that resolves into `node_modules`, a Homebrew Cellar,
///   `/opt/homebrew`, `/nix/store`, `~/.cargo`, mise's installs or an app
///   bundle is not this group's, and neither is a file that is not a Mach-O
///   executable (pnpm's and Yarn's shims are shell scripts).
public struct BiomeInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// The file's sha256 matches no Biome build this Mac knows was published.
        case unrecognized
    }

    /// `~/.local/bin/biome`: the row's identity.
    public let path: String
    /// The file `path` resolves to (`realpath`); nil when it could not be resolved.
    public let binary: String?
    /// The version of the published build the file is, nil when it is none.
    public let version: String?
    /// `darwin-arm64` or `darwin-x64`, from the Mach-O header: the release
    /// asset's suffix.
    public let target: String?
    /// The file's sha256, lowercase hex.
    public let sha256: String?
    /// Whether `path` itself is a symlink — to a copy somewhere else, which the
    /// installer's `mv` would replace with a file of its own.
    public let linked: Bool
    /// Whether this user may write in the directory holding `path` — where the
    /// installer makes its temporary directory and `mv`s the new binary.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "darwin-arm64",
        sha256: String? = nil, linked: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.sha256 = sha256
        self.linked = linked
        self.writable = writable
        self.problem = problem
    }

    /// The same file, now known to be `version`'s published build.
    func identified(as version: String) -> BiomeInstall {
        BiomeInstall(path: path, binary: binary, version: version, target: target, sha256: sha256,
                     linked: linked, writable: writable, problem: nil)
    }
}

/// Finds Biome where its installer puts it. Network-free, and nothing is run:
/// the file is hashed and looked up among the published builds already known.
public struct BiomeScanner: Sendable {

    /// The release target of an executable. Injected so tests can stand a plain
    /// file in for the Mach-O. Blocking.
    typealias TargetRead = @Sendable (URL) -> String?
    /// A file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let home: URL
    let digests: BiomePublishedDigests
    let readTarget: TargetRead
    let hash: Hash

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, digests: .shared, readTarget: Self.target(of:), hash: CLIToolTrust.sha256(of:))
    }

    init(home: URL, digests: BiomePublishedDigests, readTarget: @escaping TargetRead,
         hash: @escaping Hash = CLIToolTrust.sha256(of:)) {
        self.home = home
        self.digests = digests
        self.readTarget = readTarget
        self.hash = hash
    }

    var location: String { home.path + "/.local/bin/biome" }

    /// Blocking: the file is stat'd and hashed (~74 MB for 2.6.2 arm64).
    public func scan() -> [BiomeInstall] {
        read(location).map { [$0] } ?? []
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> BiomeInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String) -> BiomeInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard let own = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let linked = own[.type] as? FileAttributeType == .typeSymbolicLink
        let writable = access((path as NSString).deletingLastPathComponent, W_OK) == 0
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return BiomeInstall(path: path, binary: nil, version: nil, target: nil, linked: linked,
                                writable: writable, problem: .executableMissing)
        }
        if isOwnedElsewhere(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return BiomeInstall(path: path, binary: binary, version: nil, target: nil, linked: linked,
                                writable: writable, problem: .executableMissing)
        }
        // A script or anything else that is not a macOS executable is some other
        // tool's `biome` (a package manager's shim), not the installer's.
        guard let target = readTarget(url) else { return nil }
        guard let sha256 = digests.sha256(of: binary, hash: hash) else {
            return BiomeInstall(path: path, binary: binary, version: nil, target: target, linked: linked,
                                writable: writable, problem: .executableMissing)
        }
        let version = digests.version(sha256: sha256, target: target)
        return BiomeInstall(
            path: path, binary: binary, version: version, target: target, sha256: sha256,
            linked: linked, writable: writable, problem: version == nil ? .unrecognized : nil)
    }

    /// A file another tool installed and updates: npm's package
    /// (`…/node_modules/…`), a Homebrew keg (`…/Cellar/…`, or anything under
    /// `/opt/homebrew`), Nix, cargo (`~/.cargo`), mise (`…/mise/installs/…`) or
    /// an app bundle.
    func isOwnedElsewhere(_ binary: String) -> Bool {
        let components = binary.split(separator: "/")
        return components.contains("Cellar") || components.contains("node_modules")
            || components.contains(where: { $0.hasSuffix(".app") })
            || binary.hasPrefix("/opt/homebrew/") || binary.hasPrefix("/nix/store/")
            || binary.hasPrefix(home.path + "/.cargo/") || binary.contains("/mise/installs/")
    }

    /// The release asset's platform for a Mach-O executable: `darwin-arm64`,
    /// `darwin-x64`; nil for anything else.
    static func target(of executable: URL) -> String? {
        switch ClaudeCodeRelease.platform(of: executable) {
        case "darwin-arm64": return "darwin-arm64"
        case "darwin-x64": return "darwin-x64"
        default: return nil
        }
    }
}
