import Foundation

/// mise — jdx's tool-version manager — as its installer leaves it, identified by
/// **its path**, `~/.local/bin/mise`.
///
/// The layout, from the vendor's installer (`curl https://mise.run | sh`, read
/// 2026-10-09, v2026.10.6) and `src/cli/self_update.rs` / `src/upgrade_hint.rs`
/// at the same tag:
/// - The installer picks the newest release at least a day old from
///   `https://mise.jdx.dev/releases.tsv`, downloads
///   `mise-v<version>-macos-<arm64|x64>.<tar.gz|tar.zst>`, checks it against the
///   release's `SHASUMS256.txt`, and moves the archive's `mise/bin/mise` to
///   `${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}`. It edits no shell profile and
///   writes no receipt. `MISE_INSTALL_PATH` set in a shell is not in a GUI
///   app's environment, so only the default is looked at.
/// - Every build looked at (2025.6.0, 2026.3.0, 2026.9.0, 2026.10.3, 2026.10.5,
///   2026.10.6, arm64) is Developer ID signed by "Jeffrey Dickey", Team
///   `4993Y37DX6`, `Identifier=dev.jdx.mise`. That Team ID is what the trust rule
///   rests on, before an update and after it.
/// - **The version** has no literal every build carries: 2026.9.0 and later hold
///   `mise/<version>` once, 2026.3.0 and 2025.6.0 nothing anchored at all. So a
///   file signed by that Team and not quarantined is run once for `--version`,
///   which mise answers before loading any tool (`print_version_if_requested`):
///   `2026.10.5 macos-arm64 (2026-10-08)`. The installer reads it the same way.
/// - **Self-update can be turned off by whoever packaged mise**: a
///   `.disable-self-update` marker or a `mise-self-update-instructions.toml` in
///   `lib/`, `lib/mise/` or `lib64/mise/` two levels above the resolved binary
///   (`MISE_SELF_UPDATE_DISABLED_PATH`, `MISE_SELF_UPDATE_INSTRUCTIONS`), or
///   `MISE_SELF_UPDATE_AVAILABLE=false` in its environment, which a GUI app
///   cannot see. With a marker, `mise self-update` refuses ("mise is installed
///   via a package manager, cannot update"); the copy is reported only.
///
/// A copy whose path resolves into a Homebrew Cellar, an app bundle, the Nix
/// store, cargo's bin, an npm `node_modules` or mise's own installs belongs to
/// that package manager — the mise docs say such installs update through it —
/// and is skipped. Homebrew's own link, `/opt/homebrew/bin/mise`, is not
/// looked at.
public struct MiseInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
    }

    /// `~/.local/bin/mise`: the row's identity.
    public let path: String
    /// What `mise --version` printed, nil when it was not run or printed nothing
    /// readable.
    public let version: String?
    public let signature: CLIToolTrust.Signature?
    public let quarantined: Bool
    /// Whether this user may create and rename files in the directory holding
    /// the file — what `mise self-update` needs to swap it.
    public let writable: Bool
    /// The packager's marker that turns `mise self-update` off, when there is one.
    public let selfUpdateDisabledBy: String?
    public let problem: Problem?

    public init(
        path: String, version: String?, signature: CLIToolTrust.Signature? = .vendor, quarantined: Bool = false,
        writable: Bool = true, selfUpdateDisabledBy: String? = nil, problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.signature = signature
        self.quarantined = quarantined
        self.writable = writable
        self.selfUpdateDisabledBy = selfUpdateDisabledBy
        self.problem = problem
    }
}

/// Finds mise where its installer puts it. Network-free. A file signed by mise's
/// Team, with no quarantine, is run once for `--version`; nothing else is.
public struct MiseScanner: Sendable {

    /// Jeffrey Dickey.
    public static let teamIdentifier = "4993Y37DX6"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// Runs a vendor-signed executable's `--version`. Injected so tests never run
    /// one.
    public typealias VersionReader = @Sendable (URL) async -> String?

    let home: URL
    let checkSignature: SignatureCheck
    let isQuarantined: QuarantineCheck
    let readVersion: VersionReader

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: MiseScanner.teamIdentifier)
        },
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine,
        readVersion: @escaping VersionReader = MiseScanner.runVersion
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.isQuarantined = isQuarantined
        self.readVersion = readVersion
    }

    var location: String { home.path + "/.local/bin/mise" }

    /// mise, or nothing. Blocking work runs off the cooperative pool.
    public func scan() async -> MiseInstall? {
        let path = location
        let checkSignature = self.checkSignature
        let isQuarantined = self.isQuarantined
        let found: MiseInstall? = await offCooperativePool {
            // `lstat`: a dangling link is still an install, a broken one.
            guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
            guard let binary = LuvusScanner.canonicalPath(path) else {
                return MiseInstall(path: path, version: nil, signature: nil, problem: .executableMissing)
            }
            if Self.isOwnedElsewhere(binary) { return nil }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? Int ?? 0) > 0
            else {
                return MiseInstall(path: path, version: nil, signature: nil, problem: .executableMissing)
            }
            let url = URL(fileURLWithPath: binary)
            let directory = (binary as NSString).deletingLastPathComponent
            return MiseInstall(
                path: path, version: nil, signature: checkSignature(url), quarantined: isQuarantined(url),
                writable: access(directory, W_OK) == 0, selfUpdateDisabledBy: Self.disableMarker(binary: binary))
        }
        guard let found, found.problem == nil, found.signature == .vendor, !found.quarantined else { return found }
        let binary = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let version = await readVersion(binary)
        return MiseInstall(
            path: found.path, version: version, signature: found.signature, quarantined: found.quarantined,
            writable: found.writable, selfUpdateDisabledBy: found.selfUpdateDisabledBy)
    }

    /// A path inside a Homebrew Cellar, an app bundle, the Nix store, cargo's
    /// bin, an npm package or mise's own installs: that owner updates it.
    static func isOwnedElsewhere(_ binary: String) -> Bool {
        // `DenoScanner`'s owners, mise's own installs (`mise use -g mise`:
        // `…/mise/installs/mise/<v>/bin/mise`) among them, plus npm's.
        DenoScanner.isOwnedElsewhere(binary) || binary.split(separator: "/").contains("node_modules")
    }

    /// The packager's marker `mise` itself looks for (`mise_install_base`: the
    /// resolved binary's grandparent), or nil. Blocking.
    static func disableMarker(binary: String) -> String? {
        let base = ((binary as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let candidates = [
            "lib/.disable-self-update", "lib/mise/.disable-self-update", "lib64/mise/.disable-self-update",
            "lib/mise-self-update-instructions.toml", "lib/mise/mise-self-update-instructions.toml",
            "lib64/mise/mise-self-update-instructions.toml",
        ]
        return candidates.map { base + "/" + $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - The host

    /// `mise --version` alone is answered before mise loads tools or asks the
    /// network (`print_version_if_requested`, v2026.10.6). The child gets only a
    /// `PATH`, so no configuration of the user's is in its environment.
    public static func runVersion(_ executable: URL) async -> String? {
        guard let outcome = try? await ChildProcess.run(
            executable.path, ["--version"], environment: ["PATH": CLIToolCommandRunner.systemPath, "NO_COLOR": "1"],
            standardOutput: .capture, standardError: .discard,
            deadline: versionDeadline, onCancel: .terminateChild),
              outcome.succeeded, !outcome.timedOut
        else { return nil }
        return parseVersion(String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    static let versionDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10), killAfter: .seconds(11))

    /// `2026.10.5 macos-arm64 (2026-10-08)` → `2026.10.5`: the first word of the
    /// last non-empty line, when it is a release version (a `-DEBUG` build is not).
    static func parseVersion(_ output: String) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { !$0.allSatisfy(\.isWhitespace) }),
              let word = line.split(separator: " ").first
        else { return nil }
        let version = String(word)
        return MiseRelease.isVersion(version) ? version : nil
    }
}
