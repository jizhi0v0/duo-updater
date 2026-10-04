import Foundation

/// The standalone Codex's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`CodexScanner`). The release `current`
///    names must be the one its `codex-package.json` says, and the launcher must
///    be the installer's.
/// 2. **Compared on `latest`**, the only channel the installer follows
///    (`CodexRelease`), and only ever toward a newer version: the installer
///    installs whatever `latest` names, so an alpha installed with
///    `--release` reads as `.ahead` and gets no click.
/// 3. **One-click is the vendor's documented update** — `codex update` on a
///    standalone install runs exactly
///    `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh`
///    (`UpdateAction::StandaloneUnix`, `rust-v0.160.0`). `CodexUpdater` runs its
///    equivalent without the pipe.
/// 4. **The trust rule** (`CLIToolTrust`): the installer runs the installed
///    binary (`version_from_binary` on `current`), so the click is offered only
///    when that binary carries OpenAI's Team ID and no quarantine flag.
/// 5. **Codex's own setting is respected**: `check_for_update_on_startup = false`
///    reports the update with the command; an installer already running is not
///    raced (`CodexActivity`).
public struct CodexCheck: Sendable {

    public static let installer = URL(string: "https://chatgpt.com/codex/install.sh")!

    typealias Latest = @Sendable (_ target: String) async throws -> String

    let latest: Latest

    public init(release: CodexRelease = CodexRelease()) {
        self.init(latest: { try await release.latest(target: $0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    /// What the one-click stands for: the vendor's command, spelled as `codex
    /// update` prints it. `CodexUpdater` fetches the script itself and runs
    /// `/bin/sh <file>`, never this text. `pathPrefix` is the launcher's
    /// directory: with it first on `PATH` the installer finds its own `codex` there
    /// and leaves the user's shell profile alone (`add_to_path`, which otherwise
    /// appends to `~/.zprofile` when `~/.local/bin` is not on `PATH` — and a GUI
    /// app's `PATH` never has it).
    static func command(launcher: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl", arguments: ["-fsSL", installer.absoluteString, "|", "CODEX_NON_INTERACTIVE=1", "sh"],
            pathPrefix: (launcher as NSString).deletingLastPathComponent)
    }

    public func status(of install: CodexInstall, settings: CodexSettings, busy: CodexActivity.Busy?) async -> CLIToolStatus {
        let channel = CodexRelease.channelName
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .codex, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: channel, state: state, oneClick: oneClick, withheld: withheld,
                note: note, manualCommand: manualCommand, detail: .codex(install))
        }

        switch install.problem {
        case .versionUnreadable:
            return verdict(.unknown, note: Self.describe(.versionUnreadable, install: install), withheld: .versionUnreadable)
        case .packageMismatch:
            return verdict(.unknown, note: Self.describe(.packageMismatch, install: install), withheld: .versionMismatch)
        case .noCurrent, .binaryMissing:
            return verdict(.unknown, note: Self.describe(install.problem!, install: install), withheld: .broken)
        case .launcherElsewhere, nil:
            break
        }
        guard let installed = install.version, let target = install.target else {
            return verdict(.unknown, note: "no release to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest(target)
        } catch {
            return verdict(.unknown, note: "could not read Codex's latest channel: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch CodexRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.problem == .launcherElsewhere {
            return verdict(state, latest: newest, note: Self.describe(.launcherElsewhere, install: install),
                           withheld: .unsupportedInstaller)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if install.signature != .vendor {
            return verdict(
                state, latest: newest,
                note: "not signed by OpenAI (Team \(CodexScanner.teamIdentifier)): "
                    + (install.signature?.rawValue ?? "unchecked"),
                withheld: .wrongSigner)
        }
        let command = Self.command(launcher: install.path)
        if !settings.checkForUpdates {
            return verdict(
                state, latest: newest, note: "check_for_update_on_startup is false: reported only",
                withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    static func describe(_ problem: CodexInstall.Problem, install: CodexInstall) -> String {
        switch problem {
        case .noCurrent: return "\(install.root)/current is missing or not a symlink"
        case .versionUnreadable: return "\(install.root)/current does not name a release"
        case .binaryMissing: return "the \(install.version ?? "?") release has no codex executable"
        case .packageMismatch:
            return "the \(install.version ?? "?") release's codex-package.json names another version or target"
        case .launcherElsewhere:
            return "\(install.path) does not point at \(install.root)/current"
        }
    }
}
