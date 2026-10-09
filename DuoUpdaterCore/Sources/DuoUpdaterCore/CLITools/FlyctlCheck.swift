import Foundation

/// One flyctl install's verdict.
///
/// The rules:
/// 1. **Read from disk, never run** (`FlyctlScanner`).
/// 2. **Compared on the `latest` track** (`FlyctlRelease`), what `flyctl version
///    upgrade` reads for the installer's `shell` channel. An install whose
///    `~/.fly/state.yml` names `pre` would be upgraded from the `pre` track
///    instead; it is reported against `latest` with the command, not run.
/// 3. **The update is flyctl's own `flyctl version upgrade`**, on the install's
///    own file. It re-runs `curl -L https://fly.io/install.sh | sh`.
/// 4. **The trust rule** (`CLIToolTrust`): flyctl is only ever ad hoc signed, so
///    it is run only when it is byte for byte its version's published build
///    (`FlyctlVerifier`).
/// 5. **flyctl's own auto-update is respected**: `auto_update: false` in
///    `~/.fly/config.yml` reports the update with the command, as Junie's and
///    Lorca's own switches do.
/// 6. **Never race a change already running** (`FlyctlActivity`).
public struct FlyctlCheck: Sendable {

    typealias Latest = @Sendable (_ target: String) async throws -> String
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    let latest: Latest
    let knownVerdict: KnownVerdict

    public init(release: FlyctlRelease = FlyctlRelease()) {
        let verifier = FlyctlVerifier()
        self.init(latest: { try await release.latest(target: $0) },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
    }

    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict) {
        self.latest = latest
        self.knownVerdict = knownVerdict
    }

    public func status(of install: FlyctlInstall, busy: FlyctlActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .flyctl, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .flyctl(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no flyctl build version in the file", withheld: .versionUnreadable)
        case .unknownLocation, nil:
            break
        }
        guard let installed = install.version, let binary = install.binary else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        guard let target = install.target else {
            return verdict(.unknown, note: "not an arm64 or x86_64 flyctl", withheld: .unverified)
        }
        let newest: String
        do {
            newest = try await latest(target)
        } catch {
            return verdict(.unknown, note: "could not read flyctl's latest release: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.updateCommand(binary: binary)
        if install.problem == .unknownLocation {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(binary), outside ~/.fly: flyctl version upgrade refuses it",
                           withheld: .unsupportedInstaller)
        }
        if install.followsPrerelease {
            return verdict(state, latest: newest,
                           note: "~/.fly/state.yml follows the pre channel: reported only",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        if !install.autoUpdate {
            return verdict(state, latest: newest, note: "auto_update is off in ~/.fly/config.yml: reported only",
                           withheld: .autoUpdateOff, manualCommand: command)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if !install.writable {
            return verdict(state, latest: newest, note: "~/.fly/bin is not writable", withheld: .unsupportedInstaller)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the flyctl \(installed) Fly.io published: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// `<binary> version upgrade`, flyctl's documented update
    /// (fly.io/docs/flyctl/version-upgrade). `FlyctlUpdater` gives the child its
    /// own `PATH`, `SHELL` and `FLYCTL_INSTALL`.
    static func updateCommand(binary: String) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: ["version", "upgrade"], pathPrefix: nil)
    }
}
