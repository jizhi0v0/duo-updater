import Foundation

/// OpenCode's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// OpenCode is two lines, and they are two products (`OpencodeRelease`):
/// - **OpenCode 1**, the line `~/.opencode/bin/opencode` is on, is installed by
///   `curl -fsSL https://opencode.ai/install | bash` and upgraded by
///   `opencode upgrade`.
/// - **OpenCode 2** ships as `@opencode/cli` with its own installer
///   (`https://opencode.ai/v2/install`); the 1.x installer refuses to install it
///   ("… is not an OpenCode 1 release", exit 1), and the vendor's way across is
///   `opencode upgrade --major`, which also removes OpenCode 1. Its three breaking
///   changes are the plugin API, the server API and `tui.json(c)` → `cli.json`
///   (`https://opencode.ai/v2/docs/migrate-v1/`).
///
/// The rules:
/// 1. **Read from disk, never run** (`OpencodeScanner`).
/// 2. **Compared on the line the install is on** — 1.x with 1.x, 2.x with 2.x —
///    and only toward a newer version: the click installs exactly the version it
///    checked (`--version`).
/// 3. **One-click is the vendor's 1.x installer** — the documented `curl -fsSL
///    https://opencode.ai/install | bash`, which is also what `opencode upgrade`
///    runs for a curl install, with `--version <the checked version>` and
///    `--no-modify-path`, so it neither picks another version nor edits a shell rc
///    file. `OpencodeUpdater` runs its equivalent without the pipe. OpenCode is
///    never run, so an ad hoc copy (every release before 1.18.34) is offered the
///    installer too; the file it leaves must then carry Anomaly's Developer ID.
/// 4. **OpenCode 2 is reported, never clicked**: a new major with breaking
///    changes, its own installer, and a migration that removes 1.x — and the
///    vendor's command for it runs the installed binary, which this app never
///    does. The row names the version and hands over `opencode upgrade --major`
///    (`CLIToolWithheld.ownUpgrade`).
/// 5. **OpenCode's own setting is respected**: `"autoupdate": false` reports the
///    update with the command; an installer already running is not raced
///    (`OpencodeActivity`).
public struct OpencodeCheck: Sendable {

    public static let installer = URL(string: "https://opencode.ai/install")!
    /// The vendor's migration guide, shown beside the OpenCode 2 notice.
    public static let migrationGuide = URL(string: "https://opencode.ai/v2/docs/migrate-v1/")!

    typealias Latest = @Sendable () async throws -> String
    /// OpenCode 2's newest, nil when there is none to report.
    typealias Second = @Sendable () async -> String?

    let latest: Latest
    let second: Second

    public init(release: OpencodeRelease = OpencodeRelease()) {
        self.init(latest: { try await release.latest() }, second: { await release.second() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, second: @escaping Second = { nil }) {
        self.latest = latest
        self.second = second
    }

    /// What the one-click stands for, spelled as the vendor documents it.
    static func command(version: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", installer.absoluteString, "|", "bash", "-s", "--", "--version", version, "--no-modify-path"],
            pathPrefix: nil)
    }

    /// The vendor's own way along or across the major line, which DuoUpdater hands
    /// over instead of running: `opencode upgrade --major` installs OpenCode 2 and
    /// removes OpenCode 1 (its own flag description), and plain `opencode upgrade`
    /// is OpenCode 2's update. Both run the installed binary, which this app never
    /// does.
    static func upgradeCommand(major: Bool) -> CLIToolCommand {
        CLIToolCommand(executable: "opencode", arguments: major ? ["upgrade", "--major"] : ["upgrade"], pathPrefix: nil)
    }

    /// Whether `version` is OpenCode 2's line: what decides which channel a row
    /// is compared with, and which notice the detail pane explains.
    public static func isOpenCodeTwo(_ version: String) -> Bool {
        OpencodeRelease.major(of: version) >= 2
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
        guard let installed = install.version, install.architecture != nil else {
            return verdict(.unknown, note: "not an arm64 or x86_64 executable", withheld: .versionUnreadable)
        }

        // An install already on OpenCode 2 is compared with 2.x's own channel: the
        // 1.x one would read as "ahead" forever, and its installer cannot carry it.
        if Self.isOpenCodeTwo(installed) {
            guard let newest = await second() else {
                return verdict(.unknown, note: "could not read OpenCode 2's release channel", withheld: .channelUnreadable)
            }
            let state = Self.state(installed, newest)
            guard state == .updateAvailable else { return verdict(state, latest: newest) }
            let command = Self.upgradeCommand(major: false)
            guard settings.autoUpdate else {
                return verdict(state, latest: newest, note: "autoupdate is false in OpenCode's config: reported only",
                               withheld: .autoUpdateOff, manualCommand: command)
            }
            return verdict(state, latest: newest, withheld: .ownUpgrade, manualCommand: command)
        }

        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read OpenCode's latest release: \(error)",
                           withheld: .channelUnreadable)
        }
        let state = Self.state(installed, newest)
        guard state == .updateAvailable else {
            // Current on OpenCode 1, or ahead of it: OpenCode 2's arrival is the
            // update this row has to report.
            guard let two = await second() else { return verdict(state, latest: newest) }
            let note = "OpenCode 2 is a separate major release with breaking changes — migration guide: "
                + Self.migrationGuide.absoluteString
            guard settings.autoUpdate else {
                return verdict(.updateAvailable, latest: two,
                               note: note + "; autoupdate is false in OpenCode's config: reported only",
                               withheld: .autoUpdateOff, manualCommand: Self.upgradeCommand(major: true))
            }
            return verdict(.updateAvailable, latest: two, note: note, withheld: .ownUpgrade,
                           manualCommand: Self.upgradeCommand(major: true))
        }

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

    static func state(_ installed: String, _ newest: String) -> CLIToolState {
        switch OpencodeRelease.compare(installed, newest) {
        case .orderedAscending: return .updateAvailable
        case .orderedSame: return .upToDate
        case .orderedDescending: return .ahead
        }
    }
}
