import Foundation

/// OpenCode's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`OpencodeScanner`).
/// 2. **Compared on `latest`**, the channel the installer and OpenCode's own
///    update follow (`OpencodeRelease`), and only toward a newer version — the
///    click installs exactly the version it checked (`--version`).
/// 3. **One-click is the vendor's installer** — the documented `curl -fsSL
///    https://opencode.ai/install | bash`, which is also what `opencode upgrade`
///    runs for a curl install (`Installation.upgrade`, `v1.18.34`), with
///    `--version <the checked version>` and `--no-modify-path`, so it neither
///    picks another version nor edits a shell rc file. `OpencodeUpdater` runs its
///    equivalent without the pipe. OpenCode is never run, so an ad hoc copy
///    (every release before 1.18.34) is offered the installer too; the file the
///    installer leaves must then carry Anomaly's Developer ID.
/// 4. **OpenCode's own setting is respected**: `"autoupdate": false` reports the
///    update with the command; an installer already running is not raced
///    (`OpencodeActivity`).
public struct OpencodeCheck: Sendable {

    public static let installer = URL(string: "https://opencode.ai/install")!

    typealias Latest = @Sendable (_ architecture: String) async throws -> String

    let latest: Latest

    public init(release: OpencodeRelease = OpencodeRelease()) {
        self.init(latest: { try await release.latest(architecture: $0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    /// What the one-click stands for, spelled as the vendor documents it.
    static func command(version: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", installer.absoluteString, "|", "bash", "-s", "--", "--version", version, "--no-modify-path"],
            pathPrefix: nil)
    }

    public func status(of install: OpencodeInstall, settings: OpencodeSettings, busy: OpencodeActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .opencode, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: "latest", state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .opencode(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no version is compiled into the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version, let architecture = install.architecture else {
            return verdict(.unknown, note: "not an arm64 or x86_64 executable", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest(architecture)
        } catch {
            return verdict(.unknown, note: "could not read OpenCode's latest release: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch OpencodeRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.command(version: newest)
        if !settings.autoUpdate {
            return verdict(state, latest: newest, note: "autoupdate is false in OpenCode's config: reported only",
                           withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }
}
