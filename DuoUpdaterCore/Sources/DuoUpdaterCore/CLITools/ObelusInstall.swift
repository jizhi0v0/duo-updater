import Foundation

/// Obelus — obelus-editor's code editor — as its install script leaves it:
/// `~/.local/bin/obg` (the window) and `~/.local/bin/ob` (the terminal), a row
/// each, identified by **its path**.
///
/// The layout, from the vendor's installer (`curl -fsSL
/// https://raw.githubusercontent.com/obelus-editor/obelus/master/contrib/install.sh | sh`,
/// read 2026-10-19):
/// - It asks `github.com/obelus-editor/obelus/releases/latest` for its redirect
///   (not the API), or takes `--version vX.Y.Z`; downloads that release's
///   `SHA256SUMS` and `<bin>-<version>-universal2-apple-darwin.tar.xz` (one
///   universal build: no architecture is asked), refuses an archive whose sha256
///   is not the one `SHA256SUMS` names, and `install -m 755`s its one binary to
///   `--dir`, by default `$OBELUS_INSTALL_DIR` or `~/.local/bin`. `--bin` takes
///   `obg` (the default), `ob` or `both`. On a Mac it writes nothing outside
///   `--dir` (the desktop entries and omarchy's theme are Linux's), edits no
///   shell profile, leaves no receipt and never uses `sudo`.
/// - Both binaries are Rust, **ad hoc and linker-signed** (`Identifier=obg-<hash>`,
///   no Team) in every release from 0.9.0 to 0.16.0, measured 2026-10-19.
/// - A path that resolves into a Homebrew Cellar, `/nix/store`, `~/.cargo`, mise's
///   `installs/` or an app bundle belongs to that tool, not this group: mise's
///   `github:obelus-editor/obelus` copies are `mise upgrade`'s, as Herdr's are
///   (`HerdrInstall`).
/// - The version is compiled in as the User-Agent `obelus/<version>`, and read
///   from the file rather than by running it (`ObelusScanner.version(of:)`).
///   Only `ob`/`obg` builds that carry `obelus/` at all are this group's: another
///   tool's `~/.local/bin/ob` is not looked at.
/// - `OBELUS_INSTALL_DIR` and `--dir` can put them anywhere; only the default
///   directory is scanned, as for zoxide (`ZoxideScanner`).
public struct ObelusInstall: Sendable, Equatable, Codable {

    /// Which of the two the row is. Both are the same editor and version; each is
    /// its own archive and its own `--bin`.
    public enum Binary: String, Sendable, Codable, CaseIterable {
        /// The window.
        case obg
        /// The terminal.
        case ob
    }

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// The file is Obelus's, but no version follows its `obelus/`, or several
        /// that disagree.
        case versionUnreadable
    }

    /// `~/.local/bin/obg`: the row's identity.
    public let path: String
    public let name: Binary
    /// The file `path` resolves to (`realpath`); nil when it could not be resolved.
    public let binary: String?
    /// The version compiled into the file, nil when it could not be read.
    public let version: String?
    public let quarantined: Bool
    /// Whether `path` itself is a symlink — to a copy somewhere else, which the
    /// installer's `install` would replace with a file of its own.
    public let linked: Bool
    /// Whether this user may write in the directory holding `binary`.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, name: Binary = .obg, binary: String? = nil, version: String?, quarantined: Bool = false,
        linked: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.name = name
        self.binary = binary
        self.version = version
        self.quarantined = quarantined
        self.linked = linked
        self.writable = writable
        self.problem = problem
    }
}

/// Finds Obelus where its installer puts it. Network-free, and nothing is run:
/// the version is read out of the file.
public struct ObelusScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let isQuarantined: QuarantineCheck

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, isQuarantined: CLIToolTrust.hasQuarantine)
    }

    init(home: URL, isQuarantined: @escaping QuarantineCheck) {
        self.home = home
        self.isQuarantined = isQuarantined
    }

    var directory: String { home.path + "/.local/bin" }

    /// Blocking: each file is stat'd and read (`obg` is 167–198 MB, 0.9.0 to 0.16.0).
    public func scan() -> [ObelusInstall] {
        ObelusInstall.Binary.allCases.compactMap { read(directory + "/" + $0.rawValue, as: $0) }
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> ObelusInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String, as name: ObelusInstall.Binary) -> ObelusInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard let own = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let linked = own[.type] as? FileAttributeType == .typeSymbolicLink
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return ObelusInstall(path: path, name: name, version: nil, linked: linked, problem: .executableMissing)
        }
        if isOwnedElsewhere(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return ObelusInstall(path: path, name: name, binary: binary, version: nil, linked: linked,
                                 problem: .executableMissing)
        }
        // Another tool's `ob`: not Obelus at all, so not a row.
        guard let windows = Self.windows(of: url), !windows.isEmpty else { return nil }
        let version = ZoxideScanner.compiledVersion(after: windows)
        let directory = (binary as NSString).deletingLastPathComponent
        return ObelusInstall(
            path: path, name: name, binary: binary, version: version, quarantined: isQuarantined(url),
            linked: linked, writable: access(directory, W_OK) == 0, problem: version == nil ? .versionUnreadable : nil)
    }

    /// A file another tool installed and updates: a Homebrew keg (`…/Cellar/…`,
    /// or anything under `/opt/homebrew`), Nix, cargo (`~/.cargo`), mise
    /// (`…/mise/installs/…`) or an app bundle.
    func isOwnedElsewhere(_ binary: String) -> Bool {
        let components = binary.split(separator: "/")
        return components.contains("Cellar") || components.contains(where: { $0.hasSuffix(".app") })
            || binary.hasPrefix("/opt/homebrew/") || binary.hasPrefix("/nix/store/")
            || binary.hasPrefix(home.path + "/.cargo/") || binary.contains("/mise/installs/")
    }

    /// `obelus/`, the User-Agent's prefix. Measured 2026-10-19 on every macOS
    /// build of both binaries from 0.9.0 to 0.16.0: `obelus/<version>` twice (a
    /// slice each), always the build's own version; every other `obelus/` in
    /// the file is a path (`obelus/src/…`), which reads as no version.
    static let anchor = Data("obelus/".utf8)

    /// What follows each `obelus/`; nil when the file cannot be read. Read, never
    /// mapped (`ExecutableBytes`). Blocking.
    static func windows(of url: URL) -> [Data]? {
        ExecutableBytes.windows(in: url, marker: anchor, before: 0, after: 24)?
            .map { Data($0.dropFirst(anchor.count)) }
    }

    /// The version in `obelus/<version>`: nil when none has one, or they disagree
    /// (`ZoxideScanner.compiledVersion`'s rule: three numbers, not followed by
    /// another digit or dot).
    static func version(of url: URL) -> String? {
        windows(of: url).flatMap(ZoxideScanner.compiledVersion(after:))
    }
}
