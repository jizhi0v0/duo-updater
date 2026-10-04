import Foundation

/// OpenAI's Codex CLI as its standalone installer leaves it, identified by **its
/// launcher**, `~/.local/bin/codex`.
///
/// The layout, from the vendor's `install.sh` (`openai/codex`
/// `scripts/install/install.sh` at `rust-v0.160.0`, read 2026-10-04) and the
/// install on the development Mac (0.142.4 → 0.142.5 → 0.143.0, each laid down by
/// that installer):
/// - `~/.codex/packages/standalone/releases/<version>-<target>/` holds one release:
///   `bin/codex` (one ~250 MB Mach-O), `bin/codex-code-mode-host`,
///   `codex-path/rg`, `codex-resources/`, a `codex -> bin/codex` link and
///   `codex-package.json` (`{"layoutVersion":1,"version":"0.143.0",
///   "target":"aarch64-apple-darwin","variant":"codex",…}`). The installer names
///   the directory `$resolved_version-$vendor_target` and accepts a release only
///   when its binary reports that version (`release_dir_is_complete`). Releases
///   the installer laid down before the package layout (`legacy-platform-npm`)
///   have `<release>/codex` and no `bin/` or `codex-package.json`.
/// - `~/.codex/packages/standalone/current` → that directory, an absolute
///   symlink swapped by rename (`update_current_link`). Older releases stay
///   beside it; nothing removes them.
/// - `~/.local/bin/codex` → `…/standalone/current/bin/codex`, an absolute
///   symlink (`update_visible_command`). `CODEX_INSTALL_DIR` moves it and
///   `CODEX_HOME` moves `~/.codex`; neither is in a GUI app's environment, so
///   only the default places are read. A launcher that does not point into the
///   standalone root is not this install's (`Problem.launcherElsewhere`).
/// - Every release is Developer ID signed by OpenAI OpCo, LLC, Team
///   `2DC432GLL2` (`codesign -dv` on 0.142.4, 0.142.5 and 0.143.0) — the same
///   Team as uv's newer builds.
///
/// Nothing here runs Codex: the version is the release directory's name, which
/// `codex-package.json` must agree with. The copy the ChatGPT desktop app
/// carries (`ChatGPT.app/Contents/Resources/codex`) is the app's and is never
/// looked at; npm, bun and Homebrew installs are their package managers'.
public struct CodexInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// `current` is missing or not a symlink.
        case noCurrent
        /// `current` names something other than `releases/<version>-<target>`.
        case versionUnreadable
        /// The release directory has no executable `bin/codex` (or legacy `codex`).
        case binaryMissing
        /// `codex-package.json` names another version or target than the
        /// directory's name.
        case packageMismatch
        /// `~/.local/bin/codex` is missing or does not point at `current`: the
        /// installer would write a new launcher there, beside whatever is on the
        /// user's `PATH`.
        case launcherElsewhere
    }

    /// `~/.local/bin/codex`: the row's identity.
    public let path: String
    /// `~/.codex/packages/standalone`.
    public let root: String
    /// From the name of the directory `current` points at.
    public let version: String?
    /// `aarch64-apple-darwin` or `x86_64-apple-darwin`, from the same name.
    public let target: String?
    /// The release's executable, `bin/codex` (or the legacy layout's `codex`).
    public let binary: String?
    /// OpenAI's Team ID on `binary`, measured by the check (`CodexScanner.withSignature`):
    /// ~1.3 s for a 250 MB binary, so nil until then.
    public let signature: CLIToolTrust.Signature?
    public let quarantined: Bool
    public let problem: Problem?

    public init(
        path: String, root: String? = nil, version: String?, target: String? = "aarch64-apple-darwin",
        binary: String? = nil, signature: CLIToolTrust.Signature? = nil, quarantined: Bool = false,
        problem: Problem? = nil
    ) {
        self.path = path
        self.root = root ?? URL(fileURLWithPath: path)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex/packages/standalone").path
        self.version = version
        self.target = target
        self.binary = binary
        self.signature = signature
        self.quarantined = quarantined
        self.problem = problem
    }

    func with(signature: CLIToolTrust.Signature?) -> CodexInstall {
        CodexInstall(
            path: path, root: root, version: version, target: target, binary: binary,
            signature: signature, quarantined: quarantined, problem: problem)
    }
}

/// Codex's own setting that decides an offer: `check_for_update_on_startup` at
/// the top level of `~/.codex/config.toml`.
///
/// Its documentation in `config_toml.rs` (`rust-v0.160.0`): "When `true`, checks
/// for Codex updates on startup and surfaces update prompts. Set to `false` only
/// if your Codex updates are centrally managed. Defaults to `true`." Off is
/// therefore read as the user's (or their admin's) choice to take updates some
/// other way: reported with the command, never run — Claude Code's rule.
///
/// What this does not see: the system and MDM layers (`requirements.toml`,
/// the `com.openai.codex` managed preference `requirements_toml_base64`), which
/// can pin the value; a profile or a `-c` on the command line; a `CODEX_HOME`
/// set in the user's shell.
public struct CodexSettings: Sendable, Equatable, Codable {

    public var checkForUpdates: Bool = true

    public init() {}

    public init(checkForUpdates: Bool) {
        self.checkForUpdates = checkForUpdates
    }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent(".codex/config.toml")
    }

    /// Blocking file read: keep it off the cooperative pool.
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexSettings {
        guard let data = try? Data(contentsOf: location(home: home)) else { return CodexSettings() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The key at the top level only — before the first table header — as TOML
    /// scopes it; under `[tui]` or `[projects."…"]` it is another key. Only a
    /// bare `false` is off: anything else is Codex's default.
    static func parse(_ toml: String) -> CodexSettings {
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "check_for_update_on_startup" || key == "\"check_for_update_on_startup\"" else { continue }
            var value = line[line.index(after: equals)...]
            if let hash = value.firstIndex(of: "#") { value = value[..<hash] }
            return CodexSettings(checkForUpdates: value.trimmingCharacters(in: .whitespaces) != "false")
        }
        return CodexSettings()
    }
}

/// Finds the standalone Codex: `~/.codex/packages/standalone` and its launcher.
/// Network-free and runs nothing.
public struct CodexScanner: Sendable {

    /// OpenAI OpCo, LLC.
    public static let teamIdentifier = "2DC432GLL2"

    /// The two targets the installer picks on a Mac (`vendor_target`).
    static let targets = ["aarch64-apple-darwin", "x86_64-apple-darwin"]

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    public typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let checkSignature: SignatureCheck
    let isQuarantined: QuarantineCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: CodexScanner.teamIdentifier)
        },
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.isQuarantined = isQuarantined
    }

    var launcher: URL { home.appendingPathComponent(".local/bin/codex") }
    var root: URL { home.appendingPathComponent(".codex/packages/standalone") }
    var current: URL { root.appendingPathComponent("current") }
    /// `install.lock`, which every run of the installer holds (`CodexActivity`).
    var lock: URL { root.appendingPathComponent("install.lock") }

    /// The install, or nothing. Blocking.
    public func scan() -> [CodexInstall] {
        install().map { [$0] } ?? []
    }

    /// The install with its signature read: blocking, ~1.3 s (the whole binary
    /// is hashed).
    public func withSignature(_ install: CodexInstall) -> CodexInstall {
        guard let binary = install.binary, install.problem == nil else { return install }
        return install.with(signature: checkSignature(URL(fileURLWithPath: binary)))
    }

    /// nil when there is no standalone root with a `current` entry: a Codex from
    /// npm or Homebrew is not reported here.
    func install() -> CodexInstall? {
        let fm = FileManager.default
        guard (try? fm.attributesOfItem(atPath: current.path)) != nil else { return nil }
        func broken(_ problem: CodexInstall.Problem, version: String? = nil, target: String? = nil) -> CodexInstall {
            CodexInstall(path: launcher.path, root: root.path, version: version, target: target, problem: problem)
        }
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: current.path) else {
            return broken(.noCurrent)
        }
        let name = (destination as NSString).lastPathComponent
        guard let (version, target) = Self.release(name) else { return broken(.versionUnreadable) }
        let release = root.appendingPathComponent("releases/\(name)")
        let packaged = release.appendingPathComponent("bin/codex")
        let legacy = release.appendingPathComponent("codex")
        let binary: URL
        if Self.isExecutableFile(packaged) {
            binary = packaged
        } else if !fm.fileExists(atPath: release.appendingPathComponent("codex-package.json").path),
                  Self.isExecutableFile(legacy) {
            binary = legacy
        } else {
            return broken(.binaryMissing, version: version, target: target)
        }
        if let package = Self.package(in: release), package.version != version || package.target != target {
            return broken(.packageMismatch, version: version, target: target)
        }
        let quarantined = isQuarantined(binary)
        let launcherOK = Self.points(launcher, at: [
            current.appendingPathComponent("bin/codex"), current.appendingPathComponent("codex"),
        ])
        return CodexInstall(
            path: launcher.path, root: root.path, version: version, target: target, binary: binary.path,
            quarantined: quarantined, problem: launcherOK ? nil : .launcherElsewhere)
    }

    /// `0.143.0-aarch64-apple-darwin` → (`0.143.0`, `aarch64-apple-darwin`).
    static func release(_ name: String) -> (version: String, target: String)? {
        for target in targets where name.hasSuffix("-" + target) {
            let version = String(name.dropLast(target.count + 1))
            return CodexRelease.isVersion(version) ? (version, target) : nil
        }
        return nil
    }

    /// `codex-package.json`'s `version` and `target`; nil when there is none, as
    /// in the legacy layout.
    static func package(in release: URL) -> (version: String?, target: String?)? {
        guard let data = try? Data(contentsOf: release.appendingPathComponent("codex-package.json")),
              data.count <= 64 * 1024
        else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (json?["version"] as? String, json?["target"] as? String)
    }

    /// The link's target, as written, is one of `expected` — the installer
    /// writes absolute paths.
    static func points(_ link: URL, at expected: [URL]) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return false
        }
        return expected.contains { $0.path == destination }
    }

    static func isExecutableFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
}
