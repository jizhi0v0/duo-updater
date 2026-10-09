import Foundation

/// Starship as its install script leaves it, identified by **its path**:
/// `/usr/local/bin/starship`.
///
/// The layout, from `https://starship.rs/install.sh` (read 2026-10-09):
/// - `BIN_DIR` defaults to `/usr/local/bin` (`-b` overrides it). When the
///   script cannot write there it runs `sudo -v` and unpacks through `sudo`.
/// - It downloads `releases/latest/download/starship-<target>.tar.gz`, or
///   `releases/download/<tag>/…` with `-v <tag>`, checks **no hash**, and
///   unpacks the archive's one file `starship` straight into `BIN_DIR`. Without
///   `-y` it asks on `/dev/tty`. It edits no shell profile and writes no
///   receipt; a GUI app has no `BIN_DIR`, so only the default is looked at.
/// - The binary is Rust. Most releases are **ad hoc and linker-signed**
///   (1.16.0, 1.22.0, 1.24.0, 1.24.2, 1.25.0, 1.26.0 on arm64, 2026-10-09); a
///   few carry a Developer ID (1.23.0 and 1.25.1: "Kevin Song (V557D26667)").
///   Every release publishes a `.sha256` beside each archive, so every build is
///   held to its published hash (`StarshipVerifier`), signed or not.
/// - The version is compiled in as `pkg_version:<version>`, once in each of
///   those builds; it is read from the file, never by running it.
/// - A link to a Homebrew keg, a Nix store path or an app bundle is that
///   owner's copy and not looked at; a link to anywhere else is reported.
public struct StarshipInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        case executableMissing
        case versionUnreadable
        /// A link to a file elsewhere: the script would unpack over the link.
        case linked
    }

    public let path: String
    public let binary: String?
    public let version: String?
    /// `aarch64-apple-darwin` or `x86_64-apple-darwin`, from the Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether the script can write into the directory without `sudo` (its own
    /// test: it `touch`es a file there) and over the file.
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

    public var directory: String { (path as NSString).deletingLastPathComponent }
}

/// Finds Starship where its script puts it. Network-free, and nothing is run.
public struct StarshipScanner: Sendable {

    typealias QuarantineCheck = @Sendable (URL) -> Bool
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
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

    var location: String { systemDirectory.path + "/starship" }

    /// Blocking.
    public func scan() -> [StarshipInstall] {
        read(location).map { [$0] } ?? []
    }

    /// Blocking.
    func read(_ path: String) -> StarshipInstall? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return StarshipInstall(path: path, version: nil, target: nil, problem: .executableMissing)
        }
        if FlyctlScanner.isOtherOwner(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let file = try? FileManager.default.attributesOfItem(atPath: binary),
              file[.type] as? FileAttributeType == .typeRegular,
              (file[.size] as? Int ?? 0) > 0
        else {
            return StarshipInstall(path: path, binary: binary, version: nil, target: nil, problem: .executableMissing)
        }
        let version = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 48)
            .flatMap(Self.compiledVersion)
        let problem: StarshipInstall.Problem?
        if version == nil {
            problem = .versionUnreadable
        } else if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            problem = .linked
        } else {
            problem = nil
        }
        let directory = (path as NSString).deletingLastPathComponent
        return StarshipInstall(
            path: path, binary: binary, version: version, target: readTarget(url), quarantined: isQuarantined(url),
            writable: access(directory, W_OK) == 0 && access(binary, W_OK) == 0, problem: problem)
    }

    static let marker = Data("pkg_version:".utf8)

    /// The version after each `pkg_version:`; nil when there is none, or
    /// several that disagree.
    static func compiledVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            if let version = LuvusScanner.version(at: window.startIndex + marker.count, in: window) {
                found.insert(version)
            }
        }
        guard found.count == 1, let version = found.first, StarshipRelease.isVersion(version) else { return nil }
        return version
    }
}
