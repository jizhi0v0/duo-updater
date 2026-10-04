import Foundation

/// OpenCode — the terminal coding agent — as its installer leaves it, identified
/// by **its path**, `~/.opencode/bin/opencode`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://opencode.ai/install
/// | bash`, read 2026-10-04) and the install on the development Mac (1.18.15,
/// laid down 2026-08-08):
/// - `$HOME/.opencode/bin/opencode` is one Mach-O executable (a compiled Bun
///   program, ~144 MB), hard-coded from `$HOME` (`INSTALL_DIR`). The installer
///   unzips `github.com/anomalyco/opencode/releases/download/v<version>/opencode-darwin-<arm64|x64[-baseline]>.zip`
///   and `mv`s the file into place. `~/.opencode/package.json` and its
///   `node_modules` are OpenCode's own plugin dependencies, not the install.
/// - Up to 1.18.33 the binary is ad hoc signed (1.18.15: `Signature=adhoc`,
///   identifier `a.out`); from 1.18.34 ("Sign macOS CLI release binaries with a
///   Developer ID", its release notes) it carries Anomaly Innovations, Inc.'s
///   Developer ID, Team `5NZ4Q7NXJ4` (`codesign -dvv` on the published 1.18.34,
///   2026-10-04). Nothing here runs the installed file, so an ad hoc copy is
///   offered the installer; what the installer leaves must carry that Team ID
///   (`OpencodeUpdater`).
/// - The version is compiled in: the npm user agent it passes to its bundled bun
///   is the literal `--user-agent=opencode/<version> `, once in the file (1.18.15
///   and 1.18.34). It is read from the bytes.
///
/// An OpenCode from npm (`opencode-ai`), bun or Homebrew is its package
/// manager's; the copy the OpenCode desktop app carries is the app's.
public struct OpencodeInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or an empty file.
        case executableMissing
        /// No single `--user-agent=opencode/<version>` in the file.
        case versionUnreadable
    }

    /// `~/.opencode/bin/opencode`: the row's identity.
    public let path: String
    public let version: String?
    /// The file's CPU in the release assets' spelling, `arm64` or `x64`.
    public let architecture: String?
    /// Anomaly's Team ID on the file, measured by the check: informational
    /// before an update — the file is never run — and a gate after one.
    public let signature: CLIToolTrust.Signature?
    public let problem: Problem?

    public init(
        path: String, version: String?, architecture: String? = "arm64", signature: CLIToolTrust.Signature? = nil,
        problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.architecture = architecture
        self.signature = signature
        self.problem = problem
    }

    func with(signature: CLIToolTrust.Signature?) -> OpencodeInstall {
        OpencodeInstall(path: path, version: version, architecture: architecture, signature: signature, problem: problem)
    }
}

/// OpenCode's own setting that decides an offer: `autoupdate` in its global
/// config.
///
/// From `cli/upgrade.ts` at `v1.18.34` (read 2026-10-04): at startup OpenCode
/// checks its channel unless `autoupdate` is `false` (or
/// `OPENCODE_DISABLE_AUTOUPDATE` is set); it installs a newer **patch** release
/// itself — through the same installer, for a curl install — and only announces
/// a minor or major one, or any one when `autoupdate` is `"notify"`. So `false`
/// is the user's choice to take updates some other way: reported with the
/// command, never run — Claude Code's rule. `"notify"` and the default leave the
/// click.
///
/// The global config is `~/.config/opencode/` `opencode.json`, `opencode.jsonc`
/// or `config.json` (JSONC: comments and trailing commas). Not seen: a project's
/// own config, and `OPENCODE_DISABLE_AUTOUPDATE` in the user's shell.
public struct OpencodeSettings: Sendable, Equatable, Codable {

    public var autoUpdate: Bool = true

    public init() {}

    public init(autoUpdate: Bool) {
        self.autoUpdate = autoUpdate
    }

    static let files = ["opencode.json", "opencode.jsonc", "config.json"]

    /// Blocking file reads: keep them off the cooperative pool. The first file
    /// that sets `autoupdate` decides.
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> OpencodeSettings {
        let directory = home.appendingPathComponent(".config/opencode")
        for name in files {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let settings = parse(data)
            else { continue }
            return settings
        }
        return OpencodeSettings()
    }

    /// nil when the file does not set `autoupdate`. Only a JSON `false` is off.
    static func parse(_ data: Data) -> OpencodeSettings? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
              let value = root["autoupdate"]
        else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return OpencodeSettings(autoUpdate: number.boolValue)
        }
        return OpencodeSettings()
    }
}

/// Finds OpenCode at `~/.opencode/bin/opencode`, the one place its installer
/// puts it. Network-free, and nothing is run.
public struct OpencodeScanner: Sendable {

    /// Anomaly Innovations, Inc.
    public static let teamIdentifier = "5NZ4Q7NXJ4"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature

    let home: URL
    let checkSignature: SignatureCheck
    /// The CPU of an executable's bytes. Injected so tests can stand a script in
    /// for the Mach-O file.
    let readArchitecture: @Sendable (Data) -> String?

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: OpencodeScanner.teamIdentifier)
        }
    ) {
        self.init(home: home, checkSignature: checkSignature, readArchitecture: BoatScanner.architecture)
    }

    init(home: URL, checkSignature: @escaping SignatureCheck, readArchitecture: @escaping @Sendable (Data) -> String?) {
        self.home = home
        self.checkSignature = checkSignature
        self.readArchitecture = readArchitecture
    }

    var location: URL { home.appendingPathComponent(".opencode/bin/opencode") }

    /// OpenCode, or nothing. Blocking: the file is read and searched.
    public func scan() -> OpencodeInstall? {
        let url = location
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        // Read, never mapped: every OpenCode before 1.18.34 has a signature that
        // no longer validates, and a mapped page of it can end a hardened
        // process (`ExecutableBytes`).
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let head = ExecutableBytes.head(of: resolved),
              let literals = ExecutableBytes.joinedWindows(in: resolved, marker: Self.marker, before: 0, after: 40)
        else {
            return OpencodeInstall(path: url.path, version: nil, architecture: nil, problem: .executableMissing)
        }
        let version = Self.compiledVersion(in: literals)
        return OpencodeInstall(
            path: url.path, version: version, architecture: readArchitecture(head),
            problem: version == nil ? .versionUnreadable : nil)
    }

    /// The install with its signature read: blocking, the whole file is hashed.
    public func withSignature(_ install: OpencodeInstall) -> OpencodeInstall {
        guard install.problem != .executableMissing else { return install }
        return install.with(signature: checkSignature(URL(fileURLWithPath: install.path).resolvingSymlinksInPath()))
    }

    static let marker = Data("--user-agent=opencode/".utf8)

    /// The version after the file's one `--user-agent=opencode/` literal, up to
    /// the space that ends it; nil when there is none, or several that disagree.
    static func compiledVersion(in data: Data) -> String? {
        var found: Set<String> = []
        var start = data.startIndex
        while let range = data.range(of: marker, in: start..<data.endIndex) {
            var end = range.upperBound
            while end < data.endIndex, end - range.upperBound < 40, data[end] != 0x20, data[end] != 0x22, data[end] != 0 {
                end += 1
            }
            found.insert(String(decoding: data[range.upperBound..<end], as: UTF8.self))
            start = range.upperBound
        }
        guard found.count == 1, let version = found.first, OpencodeRelease.isVersion(version) else { return nil }
        return version
    }
}
