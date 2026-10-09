import Foundation

/// zoxide — ajeetdsouza's "smarter cd command" — as its install script leaves
/// it, identified by **its path**: `~/.local/bin/zoxide`.
///
/// The layout, from the vendor's installer (`curl -sSfL
/// https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh`,
/// read 2026-10-09):
/// - It asks the GitHub API's `releases/latest` (anonymously), downloads that
///   release's `zoxide-<version>-<target>.tar.gz` (`aarch64-apple-darwin`,
///   `x86_64-apple-darwin`) with no hash check, and `cp`s its one `zoxide` to
///   `--bin-dir`, by default `~/.local/bin`, and its man pages to `--man-dir`,
///   by default `~/.local/share/man`. It falls back to `sudo` only when a `cp`
///   or `mkdir` fails. It edits no shell profile and leaves no receipt. It takes
///   no version: it always installs the latest release.
/// - The binary is Rust, **ad hoc and linker-signed** (`Identifier=zoxide-<hash>`,
///   no Team) in every release looked at.
/// - A path that resolves into a Homebrew Cellar, `/nix/store`, `~/.cargo` or an
///   app bundle belongs to that tool, not this group: Homebrew's copy is the brew
///   group's row.
/// - The version is compiled in as clap's `version`, and read from the file
///   rather than by running it (`ZoxideScanner.compiledVersion`).
public struct ZoxideInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No version after any of the anchors, or several that disagree.
        case versionUnreadable
    }

    /// `~/.local/bin/zoxide`: the row's identity.
    public let path: String
    /// The file `path` resolves to (`realpath`); nil when it could not be resolved.
    public let binary: String?
    /// The version compiled into the file, nil when it could not be read.
    public let version: String?
    /// `aarch64-apple-darwin` or `x86_64-apple-darwin`, from the Mach-O header.
    public let target: String?
    public let quarantined: Bool
    /// Whether `path` itself is a symlink — to a copy somewhere else, which the
    /// installer's `cp` would write through.
    public let linked: Bool
    /// Whether this user may write in the directory holding `binary` — where the
    /// installer's `cp` writes without falling back to `sudo`.
    public let writable: Bool
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "aarch64-apple-darwin",
        quarantined: Bool = false, linked: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.quarantined = quarantined
        self.linked = linked
        self.writable = writable
        self.problem = problem
    }
}

/// Finds zoxide where its installer puts it. Network-free, and nothing is run:
/// the version is read out of the file.
public struct ZoxideScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The release target of an executable. Injected so tests can stand a plain
    /// file in for the Mach-O. Blocking.
    typealias TargetRead = @Sendable (URL) -> String?

    let home: URL
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, isQuarantined: CLIToolTrust.hasQuarantine, readTarget: LuvusScanner.target(of:))
    }

    init(home: URL, isQuarantined: @escaping QuarantineCheck, readTarget: @escaping TargetRead) {
        self.home = home
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    var location: String { home.path + "/.local/bin/zoxide" }

    /// Blocking: the file is stat'd and read.
    public func scan() -> [ZoxideInstall] {
        read(location).map { [$0] } ?? []
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> ZoxideInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String) -> ZoxideInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard let own = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let linked = own[.type] as? FileAttributeType == .typeSymbolicLink
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return ZoxideInstall(path: path, binary: nil, version: nil, target: nil, problem: .executableMissing)
        }
        if isOwnedElsewhere(binary) { return nil }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return ZoxideInstall(path: path, binary: binary, version: nil, target: nil, problem: .executableMissing)
        }
        let version = Self.version(of: url)
        let directory = (binary as NSString).deletingLastPathComponent
        return ZoxideInstall(
            path: path, binary: binary, version: version, target: readTarget(url),
            quarantined: isQuarantined(url), linked: linked, writable: access(directory, W_OK) == 0,
            problem: version == nil ? .versionUnreadable : nil)
    }

    /// A file another tool installed and updates: a Homebrew keg (`…/Cellar/…`,
    /// or anything under `/opt/homebrew`), Nix, cargo (`~/.cargo`) or an app
    /// bundle.
    func isOwnedElsewhere(_ binary: String) -> Bool {
        let components = binary.split(separator: "/")
        return components.contains("Cellar") || components.contains(where: { $0.hasSuffix(".app") })
            || binary.hasPrefix("/opt/homebrew/") || binary.hasPrefix("/nix/store/")
            || binary.hasPrefix(home.path + "/.cargo/")
    }

    /// The literals zoxide's clap metadata puts right before its `version`. Which
    /// one depends on how the linker merged the strings, measured 2026-10-09 on
    /// the release archives (each build reads its own version, and only it):
    /// - `Resolve symlinks when storing paths` then `v0.8.3` / `v0.9.0`, or
    ///   `0.9.4` to `0.9.7` (arm64; 0.9.4 x86_64 too);
    /// - `A smarter cd command for your terminal` then `0.9.9` / `0.10.0` (arm64);
    /// - `Ajeet D'Souza <98ajeet@gmail.com>` then `0.9.8` (arm64 and x86_64);
    /// - `addimportqueryremove`, NUL padding, then `0.9.9` / `0.10.0` (x86_64).
    /// All four are zoxide's own text, never a dependency's: a crate's version
    /// elsewhere in the file (clap `4.6.0`, `0.18.0`, `0.89.0`, …) follows none.
    static let anchors = [
        "Resolve symlinks when storing paths", "A smarter cd command for your terminal",
        "<98ajeet@gmail.com>", "addimportqueryremove",
    ].map { Data($0.utf8) }

    /// The version after the anchors; nil when none has one, or they disagree.
    /// Read, never mapped (`ExecutableBytes`). Blocking.
    static func version(of url: URL) -> String? {
        var windows: [Data] = []
        for anchor in anchors {
            guard let found = ExecutableBytes.windows(in: url, marker: anchor, before: 0, after: 32) else { return nil }
            windows += found.map { Data($0.dropFirst(anchor.count)) }
        }
        return compiledVersion(after: windows)
    }

    /// Each window starts just past an anchor: NUL padding, an optional `v`, then
    /// `<n>.<n>.<n>` not followed by another digit or dot.
    static func compiledVersion(after windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            var start = window.startIndex
            while start < window.endIndex, window[start] == 0 { start += 1 }
            if start < window.endIndex, window[start] == UInt8(ascii: "v") { start += 1 }
            var end = start
            while end < window.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(window[end])
                    || window[end] == UInt8(ascii: ".") {
                end += 1
            }
            let candidate = String(decoding: window[start..<end], as: UTF8.self)
            let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 4 }) else { continue }
            found.insert(String(candidate))
        }
        guard found.count == 1, let version = found.first, ZoxideRelease.isVersion(version) else { return nil }
        return version
    }
}
