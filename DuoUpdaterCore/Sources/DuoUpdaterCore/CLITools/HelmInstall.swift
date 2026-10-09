import Foundation

/// Helm as its official script leaves it, identified by **its path**:
/// `/usr/local/bin/helm`.
///
/// The layout, from `scripts/get-helm-3` and `get-helm-4` (`helm/helm` main,
/// read 2026-10-09; the two differ only in which `helm<major>-latest-version`
/// they read):
/// - `HELM_INSTALL_DIR` defaults to `/usr/local/bin` and `USE_SUDO` to true:
///   the script `cp`s the binary into place through `sudo` unless `--no-sudo` or
///   `USE_SUDO=false`. It checks the archive against its `.sha256`, edits no
///   shell profile and writes no receipt. A GUI app has no `HELM_INSTALL_DIR`,
///   so only the default is looked at.
/// - The binary is Go, **ad hoc and linker-signed** (`Identifier=a.out`) in every
///   release looked at (3.14.0 to 3.22.0, 4.0.0 to 4.3.0 on arm64, 2026-10-09).
/// - The version is in the Go build information as the main module's version,
///   `mod\thelm.sh/helm/v<major>\tv<version>\t` — what `go version -m` prints —
///   twice in every build from 3.20.0 and 4.0.0 on. Earlier builds (3.14.0 to
///   3.19.0 looked at) carry `(devel)` there and no other literal tied to the
///   version: they read as `.versionUnreadable`. Running `helm version` instead
///   would mean running a file before the trust rule could vouch for it, and
///   the rule needs the version to pick the digest; so it is not run.
/// - A link to a Homebrew keg, a Nix store path or an app bundle is that
///   owner's copy and not looked at. A link to anywhere else is reported: the
///   script's `cp` would write through it.
public struct HelmInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        case executableMissing
        /// No main-module version in the file (builds before 3.20.0), or one
        /// that disagrees with itself.
        case versionUnreadable
        /// A link to a file elsewhere, which the script's `cp` would write through.
        case linked
    }

    public let path: String
    public let binary: String?
    public let version: String?
    /// `arm64` or `amd64`, the spelling of Helm's archives, from the Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether this user may overwrite the file (`cp` writes into it) in its
    /// directory without `sudo`.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "arm64",
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

    /// The major line the install is on, `3` or `4`: its own updates stay on it.
    public var major: Int? {
        version.flatMap { $0.split(separator: ".").first }.flatMap { Int($0) }
    }

    /// The directory the script would be told to install into.
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

/// Finds Helm where its script puts it. Network-free, and nothing is run.
public struct HelmScanner: Sendable {

    typealias QuarantineCheck = @Sendable (URL) -> Bool
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
    /// `/usr/local/bin`; a fixture directory in tests.
    let systemDirectory: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, systemDirectory: URL(fileURLWithPath: "/usr/local/bin"),
                  isQuarantined: CLIToolTrust.hasQuarantine, readTarget: HelmScanner.target(of:))
    }

    init(home: URL, systemDirectory: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead) {
        self.home = home
        self.systemDirectory = systemDirectory
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    var location: String { systemDirectory.path + "/helm" }

    /// Blocking.
    public func scan() -> [HelmInstall] {
        read(location).map { [$0] } ?? []
    }

    /// Blocking.
    func read(_ path: String) -> HelmInstall? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return HelmInstall(path: path, version: nil, target: nil, problem: .executableMissing)
        }
        if FlyctlScanner.isOtherOwner(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let target = try? FileManager.default.attributesOfItem(atPath: binary),
              target[.type] as? FileAttributeType == .typeRegular,
              (target[.size] as? Int ?? 0) > 0
        else {
            return HelmInstall(path: path, binary: binary, version: nil, target: nil, problem: .executableMissing)
        }
        let version = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 48)
            .flatMap(Self.moduleVersion)
        let problem: HelmInstall.Problem?
        if version == nil {
            problem = .versionUnreadable
        } else if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            problem = .linked
        } else {
            problem = nil
        }
        let directory = (path as NSString).deletingLastPathComponent
        return HelmInstall(
            path: path, binary: binary, version: version, target: readTarget(url), quarantined: isQuarantined(url),
            writable: access(directory, W_OK) == 0 && access(binary, W_OK) == 0, problem: problem)
    }

    static let marker = Data("mod\thelm.sh/helm/v".utf8)

    /// The version after each `mod\thelm.sh/helm/v<major>\tv`, when it is on that
    /// major line; nil when there is none, or several that disagree.
    static func moduleVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            let fields = window[(window.startIndex + marker.count)...]
                .split(separator: 0x09, maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let major = String(decoding: fields[0], as: UTF8.self)
            let tagged = String(decoding: fields[1], as: UTF8.self)
            guard tagged.hasPrefix("v") else { continue }
            let version = String(tagged.dropFirst())
            guard HelmRelease.isVersion(version), version.split(separator: ".").first.map(String.init) == major
            else { continue }
            found.insert(version)
        }
        guard found.count == 1 else { return nil }
        return found.first
    }

    /// Helm's archive spelling for a thin Mach-O. Blocking.
    static func target(of executable: URL) -> String? {
        switch ClaudeCodeRelease.platform(of: executable) {
        case "darwin-arm64": return "arm64"
        case "darwin-x64": return "amd64"
        default: return nil
        }
    }
}
