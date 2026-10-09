import Foundation

/// Atuin — atuinsh's shell history tool — as its standalone installer leaves it,
/// identified by **its path**: `~/.atuin/bin/atuin`, or the file in the directory
/// the installer's receipt names.
///
/// The layout, from the vendor's installers (read 2026-10-09):
/// - `curl … https://setup.atuin.sh | sh` is a wrapper: it pipes the latest
///   release's `atuin-installer.sh` (cargo-dist 0.31.0) to `sh`, then appends
///   `atuin init` lines to the shell rc files, runs `atuin hook install` for the
///   coding agents it finds (`~/.claude`, `~/.codex`, …) and asks about sync.
///   None of that is ever run here.
/// - `atuin-installer.sh` puts the one file `atuin` in `$ATUIN_INSTALL_DIR`, else
///   `~/.atuin/bin`, and writes the receipt
///   `${XDG_CONFIG_HOME:-$HOME/.config}/atuin/atuin-receipt.json`:
///
///       {"binaries":["atuin"],"install_layout":"flat",
///        "install_prefix":"/Users/ann/.atuin/bin","modify_path":true,
///        "provider":{"source":"cargo-dist","version":"0.31.0"},
///        "source":{"app_name":"atuin","name":"atuin","owner":"atuinsh","release_type":"github"},
///        "version":"18.22.0"}
///
///   (written by 18.22.0's own installer in a scratch HOME, 2026-10-09). A GUI
///   process has no `XDG_CONFIG_HOME`, so the receipt is read from `~/.config`.
/// - `atuin update` (axoupdater 0.10.0) refuses a copy without that receipt, and
///   one whose canonical directory is not the receipt's prefix
///   (`check_receipt_is_for_this_executable`, the rule `UvReceipt.isFor` already
///   implements).
/// - The binary is Rust, **ad hoc and linker-signed** (`Identifier=atuin-<hash>`,
///   no Team) in 18.22.0 and 18.23.0, so it is trusted by its release's
///   published sha256 alone (`AtuinVerifier`).
/// - The version is the receipt's, as uv's unsigned copies are (`UvInstall`):
///   nothing of an unverified file is run to ask it, and the click checks the
///   file against that version's published build before anything runs.
///
/// A copy whose canonical path lies in a Homebrew Cellar, `/nix/store` or an
/// app bundle is that owner's and is not looked at.
public struct AtuinInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No receipt, or one `atuin update` would not take: it refuses the copy.
        case noReceipt
        /// The receipt names another directory: `atuin update` refuses the copy
        /// ("Are multiple copies of atuin installed?").
        case receiptElsewhere
    }

    /// `~/.atuin/bin/atuin`, or the receipt's: the row's identity.
    public let path: String
    /// The file `path` resolves to (`realpath`); nil when it could not be resolved.
    public let binary: String?
    /// The receipt's version, nil when there is no receipt for this copy.
    public let version: String?
    /// The release target the file was built for, from its Mach-O header.
    public let target: String?
    /// The directory the installer `atuin update` runs writes into, from the
    /// receipt as written (its `install_prefix`, with `bin` for a non-flat layout).
    public let installDirectory: String?
    public let quarantined: Bool
    /// Whether this user may create and rename files in the directory holding
    /// `binary`, as the installer does.
    public let writable: Bool
    public let settings: AtuinSettings
    public let problem: Problem?

    public init(
        path: String, binary: String? = nil, version: String?, target: String? = "aarch64-apple-darwin",
        installDirectory: String? = nil, quarantined: Bool = false, writable: Bool = true,
        settings: AtuinSettings = AtuinSettings(), problem: Problem? = nil
    ) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.installDirectory = installDirectory
        self.quarantined = quarantined
        self.writable = writable
        self.settings = settings
        self.problem = problem
    }
}

/// What Atuin's own config says about its updates: the top-level
/// `update_channel` and `update_check` of `~/.config/atuin/config.toml`
/// (`crates/atuin-client/src/settings.rs` at v18.23.0, `Settings`). Not on the
/// docs page; the code's defaults are `"stable"` and the `check-update` feature
/// (on in release builds).
///
/// - `update_channel = "stable" | "nightly"`. `atuin update` asks axoupdater for
///   the latest release on `stable` and for the latest release *including
///   prereleases* on `nightly` (`crates/atuin/src/command/client/update.rs`).
///   A value it does not know fails Atuin's own settings load, so it is
///   reported rather than guessed at.
/// - `update_check = false` turns off Atuin's background check, which only ever
///   tells the user an update is out; Atuin never installs on its own. The user
///   asked not to hear about updates, so DuoUpdater reports one with the command
///   instead of running it, as for Herdr's `version_check` and Codex's
///   `check_for_update_on_startup`.
///
/// Only the top level is read, before the first table header, as TOML scopes
/// it. `ATUIN_CONFIG_DIR` and `ATUIN_UPDATE_CHANNEL` would point Atuin
/// elsewhere; a GUI process has neither, and the update's child gets neither
/// (`AtuinUpdater`).
public struct AtuinSettings: Sendable, Equatable, Codable {
    public static let channels: Set<String> = ["stable", "nightly"]

    /// As written; one Atuin does not know is reported, not guessed at.
    public let channel: String
    public let updateCheck: Bool

    public init(channel: String = "stable", updateCheck: Bool = true) {
        self.channel = channel
        self.updateCheck = updateCheck
    }

    public var channelIsKnown: Bool { Self.channels.contains(channel) }
    var includesPrereleases: Bool { channel == "nightly" }

    static func location(home: URL) -> URL {
        home.appendingPathComponent(".config/atuin/config.toml")
    }

    /// Blocking.
    static func read(home: URL) -> AtuinSettings {
        guard let data = try? Data(contentsOf: location(home: home)) else { return AtuinSettings() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ toml: String) -> AtuinSettings {
        var channel: String?
        var updateCheck: Bool?
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard let equals = line.firstIndex(of: "=") else { continue }
            var key = line[..<equals].trimmingCharacters(in: .whitespaces)
            if key.count >= 2, key.hasPrefix("\""), key.hasSuffix("\"") { key = String(key.dropFirst().dropLast()) }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "update_channel":
                for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
                    channel = String(value.dropFirst().dropLast())
                }
                if channel == nil { channel = value }
            case "update_check":
                if value == "true" { updateCheck = true } else if value == "false" { updateCheck = false }
            default:
                break
            }
        }
        return AtuinSettings(channel: channel ?? "stable", updateCheck: updateCheck ?? true)
    }

    /// The line up to a `#` that is not inside a string.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let c = line[index]
            if let open = quote {
                if c == open { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                return String(line[..<index])
            }
        }
        return line
    }
}

/// The standalone installer's receipt, as `atuin update` reads it: uv's receipt
/// rules (`UvReceipt`, the same axoupdater), with Atuin's own source.
struct AtuinReceipt: Sendable, Equatable {
    let receipt: UvReceipt
    /// `install_layout`: `flat` puts the file in the prefix itself; the others in
    /// its `bin`.
    let layout: String?

    static func location(home: URL) -> URL {
        home.appendingPathComponent(".config/atuin/atuin-receipt.json")
    }

    /// Blocking file read.
    static func read(home: URL) -> AtuinReceipt? {
        (try? Data(contentsOf: location(home: home))).flatMap(parse)
    }

    /// nil unless it is the official receipt — `atuinsh/atuin` on GitHub — that
    /// `atuin update` would update from.
    static func parse(_ data: Data) -> AtuinReceipt? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prefix = json["install_prefix"] as? String, !prefix.isEmpty,
              let version = json["version"] as? String, AtuinRelease.isVersion(version),
              let source = json["source"] as? [String: Any],
              source["release_type"] as? String == "github", source["owner"] as? String == "atuinsh",
              source["name"] as? String == "atuin", source["app_name"] as? String == "atuin"
        else { return nil }
        let provider = (json["provider"] as? [String: Any]).flatMap { p -> (String, String)? in
            guard let source = p["source"] as? String, let version = p["version"] as? String else { return nil }
            return (source, version)
        }
        return AtuinReceipt(
            receipt: UvReceipt(installPrefix: prefix, version: version, isOfficial: true, provider: provider),
            layout: json["install_layout"] as? String)
    }

    var version: String { receipt.version }
    var installPrefix: String { receipt.installPrefix }

    /// Where the installer put `atuin` for this receipt.
    var binaryPath: String {
        let prefix = URL(fileURLWithPath: installPrefix)
        let directory = layout == "flat" || layout == "unspecified" || layout == nil || prefix.lastPathComponent == "bin"
            ? prefix : prefix.appendingPathComponent("bin")
        return directory.appendingPathComponent("atuin").path
    }

    func isFor(executable: String) -> Bool { receipt.isFor(executable: executable) }
}

/// Finds Atuin where its installer puts it. Network-free, and nothing is run:
/// the version is the receipt's.
public struct AtuinScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The release target of an executable. Injected so tests can stand a script
    /// in for the Mach-O file. Blocking.
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

    var defaultLocation: String { home.appendingPathComponent(".atuin/bin/atuin").path }

    /// The default place, then the receipt's when it is another; a path that
    /// resolves to a file already listed is the same install. Blocking.
    public func scan() -> [AtuinInstall] {
        let receipt = AtuinReceipt.read(home: home)
        let settings = AtuinSettings.read(home: home)
        var paths = [defaultLocation]
        if let named = receipt?.binaryPath, named != defaultLocation { paths.append(named) }
        var installs: [AtuinInstall] = []
        for path in paths {
            guard let install = read(path, receipt: receipt, settings: settings) else { continue }
            if install.binary != nil, installs.contains(where: { $0.binary == install.binary }) { continue }
            installs.append(install)
        }
        return installs
    }

    /// The install at `path` as it is now, or nil when it is gone. Blocking.
    func reread(_ path: String) -> AtuinInstall? {
        scan().first { $0.path == path }
    }

    /// Blocking.
    func read(_ path: String, receipt: AtuinReceipt?, settings: AtuinSettings) -> AtuinInstall? {
        // `lstat`: a dangling link is still an install, a broken one.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return AtuinInstall(path: path, version: nil, target: nil, settings: settings, problem: .executableMissing)
        }
        if Self.belongsElsewhere(binary) { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return AtuinInstall(path: path, binary: binary, version: nil, target: nil, settings: settings,
                                problem: .executableMissing)
        }
        let url = URL(fileURLWithPath: binary)
        let problem: AtuinInstall.Problem?
        if receipt == nil {
            problem = .noReceipt
        } else if receipt?.isFor(executable: binary) != true {
            problem = .receiptElsewhere
        } else {
            problem = nil
        }
        let directory = (binary as NSString).deletingLastPathComponent
        let named = problem == nil ? receipt : nil
        return AtuinInstall(
            path: path, binary: binary, version: named?.version, target: readTarget(url),
            installDirectory: named.map { ($0.binaryPath as NSString).deletingLastPathComponent },
            quarantined: isQuarantined(url), writable: access(directory, W_OK) == 0, settings: settings,
            problem: problem)
    }

    /// Homebrew's, Nix's or an app's own copy: not this group's.
    static func belongsElsewhere(_ binary: String) -> Bool {
        binary.contains("/Cellar/") || binary.hasPrefix("/nix/store/") || binary.contains(".app/")
    }
}
