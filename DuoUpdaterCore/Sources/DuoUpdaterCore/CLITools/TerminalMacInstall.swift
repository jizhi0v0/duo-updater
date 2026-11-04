import Foundation

/// terminal-mac — govijr's separate macOS desktop for computer-use agents — as
/// its installer leaves it, identified by **its path**:
/// `~/.local/bin/terminal-mac`.
///
/// The layout, from the release installer (`scripts/install.sh` in
/// `terminal-mac-<version>-<build>-macos-arm64.zip`, read 2026-11-04):
/// - `get.sh` (attached to every release, and what
///   `releases/latest/download/get.sh` answers) downloads one archive, checks
///   its pinned sha256, unpacks it and runs the archive's `install.sh`.
///   `install.sh` is also the whole install: it copies `TerminalMac.app` to
///   `<prefix>/lib/terminal-mac/<version>-<build>-<digest12>/` — `<digest12>`
///   being the first twelve hex digits of the app executable's sha256 — and
///   points `<prefix>/bin/terminal-mac`, a symlink, at that copy's executable.
///   The prefix defaults to `$HOME/.local`; `--prefix` (or
///   `TERMINAL_MAC_PREFIX`) moves it. No sudo, no receipt, no shell profile
///   edit, and old versions are left beside the new one.
/// - Every public release is self-signed by "Govijr Code Signing", a local
///   certificate with no Team; `install.sh` only checks
///   `codesign --verify --deep --strict`, which accepts it. The signature
///   therefore names no vendor identity to check, and the update is pinned to
///   the release asset's published sha256 instead (`TerminalMacRelease`).
/// - The version and build are the bundle's `CFBundleShortVersionString` and
///   `CFBundleVersion` (`0.2.0`, `6`); the release tag is `v0.2.0-6`. The
///   marketing version is frozen across builds (`0.2.0-4`, `-5`, `-6` were
///   published the same day), so both parts must be compared (`VersionSide`).
/// - A launcher that is not the installer's symlink — a plain file, a link
///   somewhere other than `<prefix>/lib/terminal-mac/…/TerminalMac.app/Contents/MacOS/terminal-mac`,
///   or a bundle whose identifier is not `dev.terminal-mac.host` — is not this
///   installer's copy. `install.sh` refuses to replace it, so the row says why
///   rather than offering a click.
public struct TerminalMacInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty regular file.
        case executableMissing
        /// A launcher whose target is not one `install.sh` left, or whose
        /// directory name disagrees with the bundle's own version and build.
        /// `install.sh` refuses to replace it.
        case notInstallerLayout
        /// A bundle that is not terminal-mac's.
        case foreignBundle
        /// The bundle's `Info.plist` carries no readable version or build.
        case versionUnreadable
    }

    /// `~/.local/bin/terminal-mac`: the row's identity.
    public let path: String
    /// The executable `path` resolves to (`realpath`); nil when it could not be
    /// resolved.
    public let binary: String?
    /// `CFBundleShortVersionString`.
    public let version: String?
    /// `CFBundleVersion`.
    public let build: String?
    /// `<prefix>` in `<prefix>/bin/terminal-mac`: where `install.sh` installs.
    public let prefix: String?
    /// Whether this user may write the prefix's `bin` and `lib/terminal-mac`,
    /// where the installer makes the new copy and points the launcher.
    public let writable: Bool
    /// Whether `path` itself is a symlink — the one thing `install.sh` replaces.
    public let linked: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, build: String?, prefix: String? = nil,
        writable: Bool = true, linked: Bool = false, problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.build = build
        self.prefix = prefix
        self.writable = writable
        self.linked = linked
        self.problem = problem
    }

    /// What the installer named this copy: `0.2.0 (6)`, never `0.2.0` alone,
    /// because the marketing version does not move between builds.
    public var displayVersion: String { side.text(withBuild: true) }

    /// The two strings the release tag carries, kept together for
    /// `VersionComparator` so the build decides when the marketing version ties.
    public var side: VersionSide { VersionSide(marketing: version, build: build) }
}

/// Finds terminal-mac where its installer puts it. Network-free, and nothing is
/// run: the version is read from the bundle's `Info.plist`.
public struct TerminalMacScanner: Sendable {

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var location: String { home.path + "/.local/bin/terminal-mac" }

    /// Blocking: the launcher is stat'd and the bundle's `Info.plist` read.
    public func scan() -> [TerminalMacInstall] {
        read(location).map { [$0] } ?? []
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> TerminalMacInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String) -> TerminalMacInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard let own = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let linked = own[.type] as? FileAttributeType == .typeSymbolicLink
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return TerminalMacInstall(path: path, version: nil, build: nil, linked: linked,
                                      problem: .executableMissing)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: binary)
        guard attributes?[.type] as? FileAttributeType == .typeRegular,
              (attributes?[.size] as? Int ?? 0) > 0
        else {
            return TerminalMacInstall(path: path, binary: binary, version: nil, build: nil, linked: linked,
                                      problem: .executableMissing)
        }

        // The launcher `install.sh` leaves is `$prefix/bin/terminal-mac`, a
        // symlink into `$prefix/lib/terminal-mac/<version>-<build>-<digest>/`.
        // Anything else — a plain file, a link elsewhere — is some other copy,
        // and the installer would refuse to touch it. `layout` was read through
        // `realpath`, so the launcher's directory is compared canonically too:
        // a `~/.local` that is itself a symlink still holds the installer's copy.
        let launcherDirectory = LuvusScanner.canonicalPath((path as NSString).deletingLastPathComponent)
        guard linked, let layout = Self.layout(of: binary),
              launcherDirectory == layout.prefix + "/bin"
        else {
            return TerminalMacInstall(path: path, binary: binary, version: nil, build: nil, linked: linked,
                                      problem: .notInstallerLayout)
        }
        let writable = Self.isWritable(layout.prefix)
        guard let info = Self.info(of: layout.bundle) else {
            return TerminalMacInstall(path: path, binary: binary, version: nil, build: nil, prefix: layout.prefix,
                                      writable: writable, linked: linked, problem: .versionUnreadable)
        }
        guard info.identifier == Self.bundleIdentifier else {
            return TerminalMacInstall(path: path, binary: binary, version: info.version, build: info.build,
                                      prefix: layout.prefix, writable: writable, linked: linked,
                                      problem: .foreignBundle)
        }
        guard let version = info.version, let build = info.build,
              layout.directory == "\(version)-\(build)-\(layout.digest)"
        else {
            return TerminalMacInstall(path: path, binary: binary, version: info.version, build: info.build,
                                      prefix: layout.prefix, writable: writable, linked: linked,
                                      problem: info.version == nil || info.build == nil
                                          ? .versionUnreadable : .notInstallerLayout)
        }
        return TerminalMacInstall(path: path, binary: binary, version: version, build: build,
                                  prefix: layout.prefix, writable: writable, linked: linked)
    }

    static let bundleIdentifier = "dev.terminal-mac.host"

    /// Where `install.sh` put the copy `binary` runs from.
    struct Layout: Equatable {
        /// `<prefix>`: everything before `/lib/terminal-mac`.
        let prefix: String
        /// `<version>-<build>-<digest12>`: the directory `install.sh` made.
        let directory: String
        let digest: String
        /// `<prefix>/lib/terminal-mac/<directory>/TerminalMac.app`.
        let bundle: String
    }

    /// The installer's shape, read from the executable's path:
    /// `<prefix>/lib/terminal-mac/<version>-<build>-<12 hex>/TerminalMac.app/Contents/MacOS/terminal-mac`.
    static func layout(of binary: String) -> Layout? {
        let executable = URL(fileURLWithPath: binary)
        guard executable.lastPathComponent == "terminal-mac",
              executable.deletingLastPathComponent().lastPathComponent == "MacOS",
              executable.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents",
              executable.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().lastPathComponent == "TerminalMac.app"
        else { return nil }
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = bundle.deletingLastPathComponent()
        let library = directory.deletingLastPathComponent()
        guard library.lastPathComponent == "terminal-mac", library.deletingLastPathComponent().lastPathComponent == "lib"
        else { return nil }
        // `install.sh` writes exactly `<version>-<build>-<digest12>`, and the
        // version itself carries no dash (`0.2.0`, not a semver prerelease).
        let parts = directory.lastPathComponent.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let version = parts.first, let build = parts.dropFirst().first,
              version.range(of: #"^\d{1,9}\.\d{1,9}\.\d{1,9}$"#, options: .regularExpression) != nil,
              build.range(of: #"^[1-9]\d{0,8}$"#, options: .regularExpression) != nil,
              parts[2].range(of: #"^[0-9a-f]{12}$"#, options: .regularExpression) != nil
        else { return nil }
        return Layout(
            prefix: library.deletingLastPathComponent().deletingLastPathComponent().path,
            directory: directory.lastPathComponent, digest: String(parts[2]), bundle: bundle.path)
    }

    /// The two version strings and the identity a bundle claims. Nil when the
    /// `Info.plist` cannot be read at all.
    struct Info: Equatable {
        let identifier: String?
        let version: String?
        let build: String?
    }

    static func info(of bundle: String) -> Info? {
        let url = URL(fileURLWithPath: bundle).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        else { return nil }
        return Info(identifier: plist["CFBundleIdentifier"] as? String,
                    version: VersionSide.plistVersionField(plist["CFBundleShortVersionString"]),
                    build: VersionSide.plistVersionField(plist["CFBundleVersion"]))
    }

    /// Whether the installer could write where it must: the prefix itself, its
    /// `bin`, and its `lib/terminal-mac`.
    static func isWritable(_ prefix: String) -> Bool {
        guard access(prefix, W_OK) == 0 else { return false }
        for sub in ["/bin", "/lib/terminal-mac"] {
            let path = prefix + sub
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return false }
            if access(path, W_OK) != 0 { return false }
        }
        return true
    }
}
