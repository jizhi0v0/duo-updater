import Foundation

/// Is something already upgrading fx right now?
///
/// What fx does while it upgrades, from its source (`d44cd84`, read 2026-10-01)
/// and measured the same day:
/// - `fx upgrade` downloads into `$TMPDIR/fx-upgrade-<16 hex>` and replaces its
///   own resolved executable with `rename(2)` (a copy only when the rename
///   fails), then removes the directory;
/// - a running session's auto-upgrade downloads into
///   `$TMPDIR/fx-auto-upgrade-<16 hex>` and installs with a sibling
///   `<exe>.tmp.<ns>` file renamed over the executable.
///
/// Both installs are a single rename of a complete, checksum-verified file, so
/// two at once do not corrupt anything: measured with two `fx upgrade` started
/// together on one 0.0.11 install — both exited 0, both printed "upgraded to
/// v0.0.12", the file was 0.0.12 and still Vercel-signed. The cost of a race is
/// one duplicate download of ~4 MB. So the gate stays as small as Claude Code's:
/// an `fx upgrade` in the process table. The temporary directories are not
/// read — their names carry no pid, and `fx-upgrade-*` is left behind for good
/// by a killed upgrade, so they cannot tell a live upgrade from a dead one; a
/// session's auto-upgrade runs on a thread, invisible in the process table.
public enum FxActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// `fx upgrade` is running (pid).
        case upgradeCommand(pid_t)

        public var description: String {
            switch self {
            case .upgradeCommand(let pid): return "fx upgrade is running (pid \(pid))"
            }
        }
    }

    public static func busy(_ install: FxInstall, processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes where isUpgradeCommand(process.arguments, install: install) {
            return .upgradeCommand(process.pid)
        }
        return nil
    }

    /// `fx upgrade [--channel …] [--json]`, however fx was named on the command
    /// line — or this install's own path, whatever its file name. Global launch
    /// options before the subcommand (`fx --fast upgrade`) are not looked past: a
    /// missed one costs a duplicate download, nothing more (above).
    static func isUpgradeCommand(_ arguments: [String], install: FxInstall) -> Bool {
        guard arguments.count >= 2, arguments[1] == "upgrade" else { return false }
        let invoked = arguments[0]
        return (invoked as NSString).lastPathComponent == "fx"
            || invoked == install.path || invoked == install.executable
    }
}

/// Runs the one-click update an fx status offers — `<fx> upgrade`, fx's own
/// command on its own file — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `FxCheck`'s
/// decision. Two gates are asked again here, because both can change between the
/// check and the click: an upgrade already running, and the file itself — it is
/// re-verified (signature, quarantine) before it is run, since fx's own
/// auto-upgrade, or anything else, may have replaced it since.
public struct FxUpdater: Sendable {

    typealias BusyCheck = @Sendable (FxInstall) -> FxActivity.Busy?

    let busy: BusyCheck
    /// Re-verifies the file before the run and re-reads the version after it.
    let scanner: FxScanner
    /// The child's environment before `PATH` is set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// A release archive is ~4 MB (0.0.12 `fx-macos-aarch64.tar.gz`: 4,248,845
    /// bytes, 2026-10-01) and fx gives up on any read that stalls for 30 s
    /// (`upgrade_helpers.recv_timeout_sec`); ten minutes is ~60 kbit/s for the
    /// whole file. The deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    public init() {
        self.init(
            busy: { FxActivity.busy($0, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: FxScanner(),
            // fx itself takes no proxy from the environment (`FxRelease`), so the
            // system proxy changes nothing for it today; passed the same way as
            // to every other updater, so a later fx that reads `https_proxy` sees
            // what a terminal would.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: FxScanner,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = FxUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.environment = environment
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .fx(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        // Rule 1 holds at the click too: never run an fx that fails the check.
        guard let current = await scanner.reread(install), current.signature == .vercel, !current.quarantined,
              current.executable == command.executable
        else {
            return .failed(
                message: "not run: \(install.path) is no longer the Vercel-signed fx that was checked",
                output: "")
        }

        var environment = self.environment()
        // `fx upgrade` runs `tar` by name to unpack the archive.
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        let run = await CLIToolCommandRunner.run(command, environment: environment, deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run \(command.executable): \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(run.lines, outcome, deadline: deadline), output: run.text)
        }
        // Re-verified before its version is believed, like any copy: an upgrade
        // on the dev channel would leave an ad hoc signed file, which reads nil.
        return .updated(version: await scanner.reread(install)?.version)
    }

    /// The line the row shows when the command failed.
    ///
    /// fx's text output ends on its reason: a failed upgrade prints
    /// `error: <reason>` and exits 1 (`UpgradeSnapshot.renderText`), the reason
    /// one of the fixed sentences of `upgrade_runtime.failureMessage`. Measured
    /// 2026-10-01 with the CDN pointed at a dead `127.0.0.1:9`:
    ///
    ///     error: failed to fetch latest version from CDN
    ///
    /// So the shared rule (last line with a letter) finds it, and only the
    /// `error: ` prefix is taken off. `--json` was not used: its failure is the
    /// same sentence (`{"kind":"upgrade","error":"…"}`), and text mode also
    /// streams `fx 0.0.11 -> 0.0.12` and the download percentage to stderr,
    /// which the row shows while it runs.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        return line.hasPrefix("error: ") ? String(line.dropFirst("error: ".count)) : line
    }
}
