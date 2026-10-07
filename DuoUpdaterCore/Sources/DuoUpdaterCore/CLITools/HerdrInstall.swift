import Foundation

/// herdr — herdr.dev's terminal workspace and agent runtime — as its installer
/// leaves it, identified by **its path**, `~/.local/bin/herdr`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://herdr.dev/install.sh
/// | sh`, `distribution/install.sh` on `master`, read 2026-10-07):
/// - it reads `https://herdr.dev/latest.json`, downloads the raw binary its
///   `assets["macos-aarch64"]` (or `macos-x86_64`) names — the GitHub release
///   asset `herdr-macos-<arch>`, no archive — checks it against the manifest's
///   `sha256`, and `mv`s it to `${HERDR_INSTALL_DIR:-$HOME/.local/bin}/herdr`.
///   A GUI app does not see `HERDR_INSTALL_DIR`, so only the default is read.
///   No shell profile is touched: the installer only prints the `PATH` line.
/// - `herdr update` (`src/update.rs`) replaces the same file by `rename` from a
///   `.herdr-update-<pid>.tmp` beside it, so every update leaves a new inode.
/// - Every build is Rust, ad hoc and linker-signed (`Signature=adhoc`,
///   `Identifier=herdr-<hash>`, no Team), so it is trusted by its published
///   sha256 alone (`CLIToolTrust`, `HerdrRelease.identify`).
/// - The version is **not read out of the file**. The literals around it move
///   from build to build — `herdr 0.1.0` in 0.1.0's default config, nothing of the
///   kind in 0.7.5, `plugin_requires_newer_herdr0.9.3` from 0.7.5 on but not in
///   the 0.6.8 preview (all measured 2026-10-07) — so a scan of the bytes would
///   be a guess. The file's sha256 is looked up instead, which names the build
///   and proves it in one step; the scan sees only that the file is there, and
///   which file it is (`identity`).
/// - Homebrew's `herdr` formula, mise and Nix own their copies, and `herdr
///   update` refuses to touch them; a `~/.local/bin/herdr` that links into one of
///   them is theirs and is not looked at.
public struct HerdrInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty regular file.
        case executableMissing
        /// A symlink to a file somewhere else — not what the installer leaves,
        /// and `herdr update` would rename the new build over the link itself.
        case linkedElsewhere
    }

    /// `~/.local/bin/herdr`: the row's identity.
    public let path: String
    /// The file's CPU in herdr's target spelling, `macos-aarch64` or
    /// `macos-x86_64`; nil when it is neither.
    public let target: String?
    public let quarantined: Bool
    /// Inode, size and modification time: which file this is, without reading it.
    /// `herdr update` renames a new file into place, so an update in a terminal
    /// changes it.
    public let identity: String?
    /// Where the link points, for `.linkedElsewhere`.
    public let linkTarget: String?
    public let settings: HerdrSettings
    public let problem: Problem?

    public init(
        path: String, target: String? = "macos-aarch64", quarantined: Bool = false, identity: String? = nil,
        linkTarget: String? = nil, settings: HerdrSettings = HerdrSettings(), problem: Problem? = nil
    ) {
        self.path = path
        self.target = target
        self.quarantined = quarantined
        self.identity = identity
        self.linkTarget = linkTarget
        self.settings = settings
        self.problem = problem
    }
}

/// What herdr's own config says about its updates: the `[update]` table of
/// `config.toml` (`src/config/model.rs`, `UpdateConfig`).
///
/// - `channel = "stable" | "preview"`, `stable` when absent. `herdr channel set
///   preview` writes exactly `channel = "preview"` under `[update]`.
/// - `version_check = false` turns off herdr's background check, which only
///   ever tells the user an update is out ("Check herdr.dev for new Herdr
///   versions in the background", its config reference); herdr never installs on
///   its own. The user has asked not to hear about updates, so DuoUpdater
///   reports one with the command instead of offering it, as for Codex's
///   `check_for_update_on_startup`.
///
/// The file is `$HERDR_CONFIG_PATH`, else `$XDG_CONFIG_HOME/herdr/config.toml`,
/// else `~/.config/herdr/config.toml` (`src/config/io.rs`). The environment read
/// is the one the update runs with (`HerdrUpdater`), so the child reads the same
/// file.
///
/// Only those two keys are read, by a small reader that knows tables, dotted
/// keys and inline tables. A file herdr cannot parse at all makes herdr fall
/// back to its defaults, which this reader does not detect; the click asks the
/// channel again and the result is checked, so the most that can follow is an
/// update named as the wrong build.
public struct HerdrSettings: Sendable, Equatable, Codable {
    public static let defaultChannel = "stable"
    public static let channels: Set<String> = ["stable", "preview"]

    /// As written; one herdr does not know is reported, not guessed at.
    public let channel: String
    public let versionCheck: Bool

    public init(channel: String = HerdrSettings.defaultChannel, versionCheck: Bool = true) {
        self.channel = channel
        self.versionCheck = versionCheck
    }

    public var channelIsKnown: Bool { Self.channels.contains(channel) }

    public static func location(home: URL, environment: [String: String]) -> URL {
        if let path = environment["HERDR_CONFIG_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        if let dir = environment["XDG_CONFIG_HOME"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("herdr/config.toml")
        }
        return home.appendingPathComponent(".config/herdr/config.toml")
    }

    /// Blocking.
    public static func read(home: URL, environment: [String: String]) -> HerdrSettings {
        guard let data = try? Data(contentsOf: location(home: home, environment: environment)) else {
            return HerdrSettings()
        }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// `[update]`'s `channel` and `version_check`, wherever TOML lets them be
    /// written: under the table header, as `update.channel` at the top level, or
    /// in `update = { … }`.
    static func parse(_ text: String) -> HerdrSettings {
        var channel: String?
        var versionCheck: Bool?
        func take(_ key: String, _ value: String) {
            switch key {
            case "channel": if let string = string(value) { channel = string }
            case "version_check": if let bool = bool(value) { versionCheck = bool }
            default: break
            }
        }
        var table: String? = ""
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = stripComment(String(raw)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[[") {
                table = nil
                continue
            }
            if line.hasPrefix("[") {
                table = line.hasSuffix("]") ? key(String(line.dropFirst().dropLast())) : nil
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = key(String(line[..<equals]))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch table {
            case "update":
                take(name, value)
            case "":
                if name.hasPrefix("update.") {
                    take(String(name.dropFirst("update.".count)), value)
                } else if name == "update", value.hasPrefix("{"), value.hasSuffix("}") {
                    for pair in value.dropFirst().dropLast().split(separator: ",") {
                        guard let inner = pair.firstIndex(of: "=") else { continue }
                        take(key(String(pair[..<inner])),
                             pair[pair.index(after: inner)...].trimmingCharacters(in: .whitespaces))
                    }
                }
            default:
                break
            }
        }
        return HerdrSettings(channel: channel ?? defaultChannel, versionCheck: versionCheck ?? true)
    }

    /// A bare or quoted key, its dotted parts joined without the spaces TOML
    /// allows around the dots.
    private static func key(_ s: String) -> String {
        s.split(separator: ".", omittingEmptySubsequences: false)
            .map { part -> String in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                return string(trimmed) ?? trimmed
            }
            .joined(separator: ".")
    }

    private static func string(_ value: String) -> String? {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return nil
    }

    private static func bool(_ value: String) -> Bool? {
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
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

/// Finds herdr: `~/.local/bin/herdr`, where its installer puts it.
///
/// Network-free, and nothing is run or hashed: which build the file is, is the
/// check's question (`HerdrCheck`).
public struct HerdrScanner: Sendable {

    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The CPU of an executable's first bytes. Injected so tests can stand a
    /// script in for the Mach-O file.
    typealias TargetRead = @Sendable (Data) -> String?

    let home: URL
    /// The environment the config path is read from — and the update runs with.
    let environment: [String: String]
    let isQuarantined: QuarantineCheck
    let readTarget: TargetRead

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine
    ) {
        self.init(home: home, environment: environment, isQuarantined: isQuarantined,
                  readTarget: HerdrScanner.target)
    }

    init(
        home: URL, environment: [String: String], isQuarantined: @escaping QuarantineCheck,
        readTarget: @escaping TargetRead
    ) {
        self.home = home
        self.environment = environment
        self.isQuarantined = isQuarantined
        self.readTarget = readTarget
    }

    var location: URL { home.appendingPathComponent(".local/bin/herdr") }

    public func scan() async -> [HerdrInstall] {
        await offCooperativePool { self.locate() }.map { [$0] } ?? []
    }

    /// The install read again with the same rules — right before an update runs,
    /// and after it.
    public func reread() async -> HerdrInstall? {
        await offCooperativePool { self.locate() }
    }

    /// Blocking.
    func locate() -> HerdrInstall? {
        let url = location
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let settings = HerdrSettings.read(home: home, environment: environment)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            let resolved = url.resolvingSymlinksInPath().path
            if Self.isPackageManaged(resolved) { return nil }
            return HerdrInstall(path: url.path, target: nil, linkTarget: resolved, settings: settings,
                                problem: fm.fileExists(atPath: resolved) ? .linkedElsewhere : .executableMissing)
        }
        // Read, never mapped (`ExecutableBytes`).
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let head = ExecutableBytes.head(of: url)
        else {
            return HerdrInstall(path: url.path, target: nil, settings: settings, problem: .executableMissing)
        }
        return HerdrInstall(
            path: url.path, target: readTarget(head), quarantined: isQuarantined(url),
            identity: Self.identity(attributes), settings: settings)
    }

    static func identity(_ attributes: [FileAttributeKey: Any]) -> String {
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(inode):\(size):\(modified)"
    }

    /// Where `herdr update` itself says the copy belongs to a package manager
    /// (`is_package_manager_managed_exe_path`, following links): a Homebrew
    /// keg's `Cellar/herdr/<version>/bin/herdr`, mise's
    /// `installs/herdr/<version>/bin/herdr`, or anything under `/nix/store`.
    static func isPackageManaged(_ path: String) -> Bool {
        if path.hasPrefix("/nix/store/") { return true }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[parts.count - 1] == "herdr", parts[parts.count - 2] == "bin",
              parts[parts.count - 4] == "herdr"
        else { return false }
        return parts[parts.count - 5] == "Cellar" || parts[parts.count - 5] == "installs"
    }

    /// herdr ships thin executables: `macos-aarch64` or `macos-x86_64`.
    static func target(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data.prefix(8))
        // MH_MAGIC_64, little-endian: cf fa ed fe.
        guard bytes[0...3] == [0xCF, 0xFA, 0xED, 0xFE] else { return nil }
        let cpu = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        switch cpu {
        case 0x0100_000C: return "macos-aarch64"  // CPU_TYPE_ARM64
        case 0x0100_0007: return "macos-x86_64"   // CPU_TYPE_X86_64
        default: return nil
        }
    }
}
