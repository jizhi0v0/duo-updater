import Foundation
import Security

/// One copy of fx — Vercel Labs' coding agent — on this Mac, identified by
/// **where it is**.
///
/// fx is one Zig executable with no Info.plist. The vendor's installer
/// (`curl -fsSL https://fx.sh/setup.sh | bash`) downloads
/// `releases.fx.sh/<v>/fx-macos-<arch>.tar.gz` and `mv`s the binary to
/// `${FX_INSTALL_DIR:-~/.local/bin}/fx`; `fx upgrade` and fx's background
/// auto-upgrade replace whatever file is running. What anchors it is the
/// signature: every stable release is Developer ID signed by Vercel, Inc (Team
/// `JW6Y669B67`) as `com.vercel.fx`, hardened and notarized (0.0.11 and 0.0.12
/// checked 2026-10-01; `release.yml` signs and notarizes every stable build).
///
/// Dev-channel builds are not: `dev-release.yml` publishes them unsigned by
/// Vercel, and the one `dev.json` named on 2026-10-01 (`d44cd84ae19c`) is ad hoc
/// and linker-signed, identifier `fx`, no team. So a copy that passes the
/// signature check is a stable build, and a dev build reads as `.otherSigner` —
/// it is never run (`FxScanner`).
///
/// Identity is the path. A symlink is followed to the file that runs, for the
/// signature and the version, but the row is the path the user knows.
public struct FxInstall: Sendable, Equatable, Codable {

    public enum Origin: String, Sendable, Codable {
        /// Where the vendor's installer puts it: `~/.local/bin/fx`.
        case conventional
        /// Added by hand.
        case userAdded
    }

    /// Whether the executable is Vercel's, checked against the code seal — not
    /// just what the signature claims.
    public enum Signature: String, Sendable, Codable {
        case vercel
        /// Sealed and intact, but not a Developer ID of Team `JW6Y669B67` signing
        /// as `com.vercel.fx` — an ad hoc dev build, or another program named fx.
        case otherSigner
        /// Unsigned, a broken seal, or not code at all.
        case invalid
    }

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or to an empty file.
        case executableMissing
    }

    public let path: String
    public let origin: Origin
    /// The file that runs, symlinks resolved; nil when there is none.
    public let executable: String?
    /// What `fx --version` printed, read only once the signature passed. nil when
    /// it was not run or printed nothing that is a version.
    public let version: String?
    public let signature: Signature?
    public let problem: Problem?
    /// The file carries `com.apple.quarantine`, so it was not run (`FxScanner`).
    public let quarantined: Bool

    public init(
        path: String, origin: Origin = .conventional, executable: String? = nil, version: String?,
        signature: Signature? = nil, problem: Problem? = nil, quarantined: Bool = false
    ) {
        self.path = path
        self.origin = origin
        self.executable = executable
        self.version = version
        self.signature = signature
        self.problem = problem
        self.quarantined = quarantined
    }
}

/// fx's user-wide settings that govern its updates, in `~/.fx/settings.json`: the
/// channel, which `fx upgrade` without `--channel` reads and the background
/// auto-upgrade follows, and whether that auto-upgrade runs at all.
///
/// From fx's source (`vercel-labs/fx` at `d44cd84`, read 2026-10-01):
/// - the file is `$HOME/.fx/settings.json` (`profile_paths.settingsPath`), key
///   `update_channel`, a string parsed case-insensitively as `stable` or `dev`
///   (`update_target.Channel.parse`); absent means `stable`
///   (`app_lifecycle`: `settings.update_channel orelse .stable`);
/// - `fx upgrade --channel <c>` stores the choice there; a workspace override or
///   a project `.fx.json` cannot set it (`config_runtime` clears it);
/// - a user settings file fx cannot parse is dropped **whole**, with a
///   diagnostic (`mergeDetailedSettingsLayer`) — so a malformed file, or an
///   `update_channel` that is not one of the two, means `stable`.
///
/// - `auto_upgrade`, a bool, absent means on (`app_lifecycle`:
///   `settings.auto_upgrade orelse true`); any other type is an error that drops
///   the file whole like a bad channel (`config_runtime`:
///   `InvalidAutoUpgradeType`).
///
/// What this does not see: a workspace's own settings, which may set
/// `auto_upgrade` for sessions in that workspace (the channel they may not);
/// `FX_AUTO_UPGRADE=0`, an environment variable in the user's shell that a GUI
/// process never sees; the other keys' validity (a bad `model` value also
/// makes fx drop the file, and so fall back to `stable`) and the
/// `.preference-migration.update_channel.json` journal beside the file, which fx
/// writes while it saves a preference and folds back on its next load.
public struct FxSettings: Sendable, Equatable, Codable {

    public enum Channel: String, Sendable, Codable {
        case stable
        case dev
    }

    public var channel: Channel = .stable
    /// fx's background auto-upgrade. Off means the update is the user's to take:
    /// reported with the command, never run (`FxCheck`) — Claude Code's rule.
    public var autoUpgrade: Bool = true

    public init() {}

    public init(channel: Channel, autoUpgrade: Bool = true) {
        self.channel = channel
        self.autoUpgrade = autoUpgrade
    }

    public static var standardLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".fx/settings.json")
    }

    /// Blocking file read: keep it off the cooperative pool.
    public static func read(from file: URL = standardLocation) -> FxSettings {
        guard let data = try? Data(contentsOf: file) else { return FxSettings() }
        return parse(data)
    }

    static func parse(_ data: Data) -> FxSettings {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return FxSettings() }
        var settings = FxSettings()
        if let raw = root["update_channel"] {
            guard let text = raw as? String, let channel = Channel(rawValue: text.lowercased()) else {
                // fx drops the whole file over this, and so runs on its defaults.
                return FxSettings()
            }
            settings.channel = channel
        }
        if let raw = root["auto_upgrade"] {
            // A JSON bool only: `JSONSerialization` hands `1` and `true` back as the
            // same NSNumber, and fx rejects the number (dropping the file).
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                return FxSettings()
            }
            settings.autoUpgrade = number.boolValue
        }
        return settings
    }
}

/// Finds fx installs: `~/.local/bin/fx`, where the vendor's installer puts it by
/// default, plus any paths the user added.
///
/// Network-free. Unlike Claude Code, nothing on disk says which version a copy
/// is — no versioned directory, no manifest — so the version comes from running
/// `<executable> --version`, and only after the signature has passed: an fx that
/// fails the check is never run.
public struct FxScanner: Sendable {

    public static let teamIdentifier = "JW6Y669B67"
    public static let signingIdentifier = "com.vercel.fx"

    /// Checks a file's signature. Injected so tests build fake installs out of
    /// plain files.
    public typealias SignatureCheck = @Sendable (URL) -> FxInstall.Signature
    /// Runs a verified executable's `--version`. Injected so tests never run
    /// anything.
    public typealias VersionReader = @Sendable (URL) async -> String?
    /// Whether a file carries `com.apple.quarantine`.
    public typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let checkSignature: SignatureCheck
    let readVersion: VersionReader
    let isQuarantined: QuarantineCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = FxScanner.verifyVercelSignature,
        readVersion: @escaping VersionReader = FxScanner.runVersion,
        isQuarantined: @escaping QuarantineCheck = FxScanner.hasQuarantine
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.readVersion = readVersion
        self.isQuarantined = isQuarantined
    }

    var conventionalPath: URL { home.appendingPathComponent(".local/bin/fx") }

    /// Every install found, the conventional one first, each path at most once.
    /// The file-system and Security work runs off the cooperative pool; each
    /// verified copy is then run once for its version.
    public func scan(userPaths: [String] = []) async -> [FxInstall] {
        let found = await offCooperativePool { self.locate(userPaths: userPaths) }
        var installs: [FxInstall] = []
        for install in found {
            installs.append(await withVersion(install))
        }
        return installs
    }

    /// The install at the same path, read again from disk with the same rules —
    /// after an update, or right before one runs. The path goes in as a user
    /// path so a user-added install is found too; a conventional one is found
    /// first and the duplicate dropped.
    public func reread(_ install: FxInstall) async -> FxInstall? {
        let path = install.path
        let located = await offCooperativePool { self.locate(userPaths: [path]).first { $0.path == path } }
        guard let located else { return nil }
        return await withVersion(located)
    }

    /// Everything but the version: blocking.
    func locate(userPaths: [String]) -> [FxInstall] {
        var found: [FxInstall] = []
        if let conventional = conventionalInstall() { found.append(conventional) }
        var seen = Set(found.map(\.path))
        for raw in userPaths {
            guard let install = userInstall(at: raw), seen.insert(install.path).inserted else { continue }
            found.append(install)
        }
        // A copy inside an `.app` ships and updates with that app; updating it
        // would break the bundle's seal. Neither checked nor updated, even when
        // the user adds it by hand. `owningApp` looks at the path as given and
        // once resolved, which covers a link into a bundle.
        return found.filter { ClaudeCodeScanner.owningApp(of: $0.path) == nil }
    }

    /// The signature is the gate: `--version` runs only for a Vercel-signed file
    /// with no quarantine flag.
    func withVersion(_ install: FxInstall) async -> FxInstall {
        guard install.signature == .vercel, !install.quarantined, let executable = install.executable else {
            return install
        }
        let version = await readVersion(URL(fileURLWithPath: executable))
        return FxInstall(
            path: install.path, origin: install.origin, executable: executable, version: version,
            signature: install.signature, problem: install.problem, quarantined: install.quarantined)
    }

    /// `~/.local/bin/fx`, whatever is there: a copy that is not Vercel's is still
    /// reported, as not Vercel's, since this is where the user's fx would be.
    func conventionalInstall() -> FxInstall? {
        let launcher = conventionalPath
        let fm = FileManager.default
        guard (try? fm.attributesOfItem(atPath: launcher.path)) != nil else { return nil }
        let resolved = launcher.resolvingSymlinksInPath()
        guard nonEmptyFile(resolved) else {
            return FxInstall(path: launcher.path, origin: .conventional, version: nil, problem: .executableMissing)
        }
        return FxInstall(
            path: launcher.path, origin: .conventional, executable: resolved.path, version: nil,
            signature: checkSignature(resolved), quarantined: isQuarantined(resolved))
    }

    /// A path the user pointed at. Nothing says it is fx but the signature, so a
    /// file that is not Vercel's is not reported at all.
    func userInstall(at raw: String) -> FxInstall? {
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        guard nonEmptyFile(resolved) else { return nil }
        let signature = checkSignature(resolved)
        guard signature == .vercel else { return nil }
        return FxInstall(
            path: url.path, origin: .userAdded, executable: resolved.path, version: nil,
            signature: signature, quarantined: isQuarantined(resolved))
    }

    func nonEmptyFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else { return false }
        return (attributes[.size] as? Int ?? 0) > 0
    }

    // MARK: - The host

    /// The seal must be intact **and** satisfy fx's own designated requirement —
    /// Developer ID (the two certificate-extension markers), Team `JW6Y669B67`,
    /// identifier `com.vercel.fx`; `codesign -d -r-` on 0.0.11 and 0.0.12 prints
    /// exactly this (2026-10-01) — before anything about the file is believed.
    public static func verifyVercelSignature(_ url: URL) -> FxInstall.Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return .invalid
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { return .invalid }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(designatedRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return .invalid }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess ? .vercel : .otherSigner
    }

    static let designatedRequirement = "identifier \"\(signingIdentifier)\" and anchor apple generic"
        + " and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */"
        + " and certificate leaf[subject.OU] = \(teamIdentifier)"

    /// A quarantined file is not run, even when it is Vercel's: launching one can
    /// put a Gatekeeper dialog on the user's screen from a background scan. The
    /// vendor's installer fetches with `curl`, which sets no quarantine (the
    /// 0.0.11 install measured 2026-10-01 carried only `com.apple.provenance`);
    /// a binary dragged out of a browser download would.
    public static func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// `--version` is answered before fx loads any settings: it prints the
    /// compiled `version` constant and a newline (`cli_surface`, `isVersionFlag`)
    /// — `0.0.11`, with no `v`, and the same bare version for a dev build, whose
    /// `v0.0.12-d44cd84 [dev]` label exists only in the TUI header.
    ///
    /// Measured 2026-10-01 on 0.0.11 under `sandbox-exec` denying all network and
    /// file writes, with an empty `HOME` and `TMPDIR`: printed `0.0.11`, exit 0,
    /// 0.04 s, no file created, and the only sandbox denial logged was the
    /// launch-time write to `/dev/dtracehelper`; with no environment at all it
    /// printed the same. So the child gets only a
    /// `PATH`, and a deadline far above that.
    public static func runVersion(_ executable: URL) async -> String? {
        guard let outcome = try? await ChildProcess.run(
            executable.path, ["--version"], environment: ["PATH": CLIToolCommandRunner.systemPath],
            standardOutput: .capture, standardError: .discard,
            deadline: versionDeadline, onCancel: .terminateChild),
              outcome.succeeded, !outcome.timedOut
        else { return nil }
        return parseVersion(String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    static let versionDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5), killAfter: .seconds(6))

    /// fx's own rule for a version (`update_target.isValidVersion`): three
    /// dot-separated runs of digits, after an optional leading `v`.
    static func parseVersion(_ output: String) -> String? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        return FxRelease.isVersion(text) ? text : nil
    }
}
