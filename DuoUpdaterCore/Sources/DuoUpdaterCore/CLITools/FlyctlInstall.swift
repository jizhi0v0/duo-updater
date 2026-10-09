import Foundation

/// Fly.io's flyctl as its installer leaves it, identified by **its path**:
/// `~/.fly/bin/flyctl`.
///
/// The layout, from `https://fly.io/install.sh` (read 2026-10-09):
/// - The installer asks `api.fly.io/app/flyctl_releases/<os>/<arch>/latest` for
///   the archive's URL, downloads it to `$FLYCTL_INSTALL/tmp` (default `~/.fly`),
///   unpacks it there and `mv`s `flyctl` into `$FLYCTL_INSTALL/bin/flyctl`, then
///   points `bin/fly` at it with `ln -sf`. It checks no hash. It then runs the new
///   `flyctl version -s shell`, which records `channel: shell` in
///   `~/.fly/state.yml` and `auto_update: true` in `~/.fly/config.yml`.
/// - It edits a shell profile only when asked on a terminal (or `--setup-path`),
///   and never when `flyctl` is already on `PATH`.
/// - `flyctl version upgrade` updates only a binary whose real path lies under
///   `$FLYCTL_INSTALL` (`CanUpdateThisInstallation`, `internal/update/update.go`):
///   a link from `~/.fly/bin/flyctl` to anywhere else is reported, never updated.
/// - The binary is Go, **ad hoc and linker-signed** (`Identifier=a.out`, no Team)
///   in every release looked at (0.4.0, 0.4.50, 0.4.100, 0.4.114, 0.4.115 on
///   arm64, 2026-10-09), so it is trusted by its release's published sha256 alone
///   (`FlyctlVerifier`).
/// - The version is in the Go build information every release carries:
///   `-X github.com/superfly/flyctl/internal/buildinfo.buildVersion=<version>`,
///   the value `flyctl version` prints, twice in each of those builds and never
///   with another version. It is read from the file rather than by running it.
///
/// A GUI app has no `FLYCTL_INSTALL`, so only the default `~/.fly` is looked at.
public struct FlyctlInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No build version in the file, or several that disagree.
        case versionUnreadable
        /// A link to a file outside `~/.fly`, which `flyctl version upgrade`
        /// refuses ("cannot update this installation").
        case unknownLocation
    }

    /// `~/.fly/bin/flyctl`: the row's identity.
    public let path: String
    /// The file `path` resolves to; nil when it could not be resolved.
    public let binary: String?
    public let version: String?
    /// `arm64` or `x86_64`, the spelling of the release's macOS archives, from
    /// the file's Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether this user may create and rename files in `~/.fly/bin` and
    /// `~/.fly/tmp`, which the installer writes.
    public let writable: Bool
    /// `channel` in `~/.fly/state.yml`, as written; nil when there is none.
    public let channel: String?
    /// `auto_update` in `~/.fly/config.yml`; true when absent, as flyctl reads it.
    public let autoUpdate: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "arm64",
        quarantined: Bool = false, writable: Bool = true, channel: String? = "shell", autoUpdate: Bool = true,
        problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.quarantined = quarantined
        self.writable = writable
        self.channel = channel
        self.autoUpdate = autoUpdate
        self.problem = problem
    }

    /// Whether `flyctl version upgrade` would follow its `pre` track: only the
    /// channels flyctl maps there (`translateChannelForRails`: `pre`,
    /// `prerelease`). The installer's own `shell` and `shell-prerel` map to
    /// `latest`.
    public var followsPrerelease: Bool {
        guard let channel = channel?.lowercased() else { return false }
        return channel == "pre" || channel == "prerelease"
    }
}

/// Finds flyctl where its installer puts it. Network-free, and nothing is run.
public struct FlyctlScanner: Sendable {

    typealias QuarantineCheck = @Sendable (URL) -> Bool
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, isQuarantined: CLIToolTrust.hasQuarantine, readTarget: FlyctlScanner.target(of:))
    }

    init(home: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead) {
        self.home = home
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    /// `$FLYCTL_INSTALL` as the installer defaults it.
    var installDirectory: String { home.path + "/.fly" }
    var location: String { installDirectory + "/bin/flyctl" }

    /// Blocking.
    public func scan() -> [FlyctlInstall] {
        read(location).map { [$0] } ?? []
    }

    /// Blocking.
    func read(_ path: String) -> FlyctlInstall? {
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        let channel = Self.value(of: "channel", inYAML: installDirectory + "/state.yml")
        let autoUpdate = Self.value(of: "auto_update", inYAML: installDirectory + "/config.yml")?.lowercased() != "false"
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return FlyctlInstall(path: path, version: nil, target: nil, channel: channel, autoUpdate: autoUpdate,
                                 problem: .executableMissing)
        }
        if Self.isOtherOwner(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return FlyctlInstall(path: path, binary: binary, version: nil, target: nil, channel: channel,
                                 autoUpdate: autoUpdate, problem: .executableMissing)
        }
        let version = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 48)
            .flatMap(Self.buildVersion)
        let root = LuvusScanner.canonicalPath(installDirectory) ?? installDirectory
        let problem: FlyctlInstall.Problem?
        if version == nil {
            problem = .versionUnreadable
        } else if !binary.hasPrefix(root + "/") {
            problem = .unknownLocation
        } else {
            problem = nil
        }
        let bin = (path as NSString).deletingLastPathComponent
        return FlyctlInstall(
            path: path, binary: binary, version: version, target: readTarget(url), quarantined: isQuarantined(url),
            writable: access(bin, W_OK) == 0 && access(installDirectory, W_OK) == 0,
            channel: channel, autoUpdate: autoUpdate, problem: problem)
    }

    /// A Homebrew keg, a Nix store path, an app bundle: that owner's copy.
    static func isOtherOwner(_ binary: String) -> Bool {
        let lowered = binary.lowercased()
        return lowered.contains("/cellar/") || lowered.hasPrefix("/nix/store/") || lowered.contains(".app/")
    }

    static let marker = Data("internal/buildinfo.buildVersion=".utf8)

    /// The version after each `buildVersion=` in the file; nil when there is
    /// none, or several that disagree.
    static func buildVersion(in windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            let start = window.startIndex + marker.count
            var end = start
            while end < window.endIndex, ![0x20, 0x22, 0x00, 0x0A, 0x09].contains(window[end]) { end += 1 }
            found.insert(String(decoding: window[start..<end], as: UTF8.self))
        }
        guard found.count == 1, let version = found.first, FlyctlRelease.isVersion(version) else { return nil }
        return version
    }

    /// A top-level `key: value` of a flat YAML file such as `~/.fly/state.yml`,
    /// quotes taken off; nil when the file or the key is missing. Blocking.
    static func value(of key: String, inYAML path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix(key + ":") {
            var value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    /// The release's archive spelling for a thin Mach-O. Blocking.
    static func target(of executable: URL) -> String? {
        switch ClaudeCodeRelease.platform(of: executable) {
        case "darwin-arm64": return "arm64"
        case "darwin-x64": return "x86_64"
        default: return nil
        }
    }
}
