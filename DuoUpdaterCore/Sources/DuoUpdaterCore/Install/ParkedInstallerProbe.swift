import Darwin
import Foundation

/// Whether an app's own installer is still at work after we quit the app for a
/// staged Relaunch — what `InstallerExitWatch` is fed each tick.
///
/// The two updaters need different answers, because launchd treats their jobs
/// differently:
///
///   - **Sparkle**: `Autoupdate`'s job is gone once it exits — on ChatGPT
///     2026-10-06 launchd logged "removing service" for both installer jobs
///     right after the failed install. So its pids are the whole answer
///     (`SparkleStagingClearance.parkedInstallerPIDs`).
///   - **ShipIt**: Squirrel submits it with `KeepAlive = {SuccessfulExit: NO}`
///     and `ThrottleInterval = 2` (`Squirrel/SQRLShipItLauncher.m`, master, read
///     2026-10-06), so a ShipIt that exits with an install error is run again —
///     the "Resuming installation attempt 2/3" in Claude's `ShipIt_stderr.log`.
///     Its pid going away is not the end. Nor is the job staying loaded: it
///     declares a Mach service, so launchd keeps it loaded on demand after any
///     exit — VS Code 2026-10-06, after "Too many attempts to install, aborting
///     update", still listed with `"LastExitStatus" = 0;` and no PID. What
///     tells the two apart is that exit status. ShipIt exits successfully on a
///     finished install, on the "App Still Running" abort and on running out
///     of attempts (`ShipIt-main.m`), and KeepAlive only runs it again after a
///     failed one. loginwindow unloads the job outright when macOS 27 stops the
///     app's background activity. Alive is therefore: the last pid seen still
///     runs, or the job is loaded and either running or last exited with a
///     failure — the pid half because an unloaded job's process lingers until
///     SIGKILL.
///
/// Found before the quit or not at all: nothing found (an installer in the
/// system domain, which this user's `launchctl` cannot see; a label Squirrel
/// spells differently) means no probe, and the caller keeps the full wait.
public struct ParkedInstallerProbe: Sendable, Equatable {

    public enum Target: Sendable, Equatable {
        case sparkle(pids: [pid_t])
        case shipIt(label: String)
    }

    /// A loaded launchd job, as `launchctl list <label>` describes it.
    public struct LoadedJob: Sendable, Equatable {
        /// Nil while the job is loaded but not running.
        public let pid: pid_t?
        /// The raw wait status of its last exit (`launchctl` prints 256 for
        /// `exit(1)`, 9 for SIGKILL); nil before it has exited once.
        public let lastExitStatus: Int32?
        public init(pid: pid_t?, lastExitStatus: Int32? = nil) {
            self.pid = pid
            self.lastExitStatus = lastExitStatus
        }
    }

    /// The system calls, injectable for tests.
    public struct System: Sendable {
        public var isAlive: @Sendable (pid_t) -> Bool
        /// Nil when no job with this label is loaded in this user's domain.
        public var loadedJob: @Sendable (String) async -> LoadedJob?
        public var sparkleInstallerPIDs: @Sendable (InstalledApp) async -> [pid_t]

        public init(
            isAlive: @escaping @Sendable (pid_t) -> Bool,
            loadedJob: @escaping @Sendable (String) async -> LoadedJob?,
            sparkleInstallerPIDs: @escaping @Sendable (InstalledApp) async -> [pid_t]
        ) {
            self.isAlive = isAlive
            self.loadedJob = loadedJob
            self.sparkleInstallerPIDs = sparkleInstallerPIDs
        }

        public static let live = System(
            isAlive: SparkleStagingClearance.System.live.isAlive,
            loadedJob: { label in
                guard let outcome = try? await ChildProcess.run(
                    "/bin/launchctl", ["list", label],
                    standardOutput: .capture, standardError: .discard, onCancel: .runToCompletion),
                      outcome.succeeded
                else { return nil }
                let text = String(decoding: outcome.standardOutput, as: UTF8.self)
                return LoadedJob(
                    pid: ParkedInstallerProbe.field("PID", inJobDescription: text),
                    lastExitStatus: ParkedInstallerProbe.field("LastExitStatus", inJobDescription: text))
            },
            sparkleInstallerPIDs: { await SparkleStagingClearance.parkedInstallerPIDs(for: $0) })
    }

    public let target: Target
    /// The ShipIt process last seen running for the job.
    public private(set) var shipItPID: pid_t?

    /// The installer parked on `app`'s quit, found while the app still runs.
    ///
    /// - Parameter staged: the build the Relaunch applies. A ShipIt staging
    ///   selects ShipIt; anything else, including nil (an armed Sparkle installer
    ///   whose staging cannot be read — ChatGPT's case), falls to Sparkle when
    ///   the app has a Sparkle updater.
    public static func find(
        for app: InstalledApp, staged: StagedSelfUpdate?, system: System = .live
    ) async -> ParkedInstallerProbe? {
        if staged?.updater == .shipIt {
            // `SQRLShipItLauncher.shipItJobLabel`: the application identifier
            // plus ".ShipIt" — observed as `com.anthropic.claudefordesktop.ShipIt`.
            guard let bundleID = app.bundleID else { return nil }
            let label = bundleID + ".ShipIt"
            guard let job = await system.loadedJob(label) else { return nil }
            return ParkedInstallerProbe(target: .shipIt(label: label), shipItPID: job.pid)
        }
        guard app.hasSparkleUpdater else { return nil }
        let pids = await system.sparkleInstallerPIDs(app)
        return pids.isEmpty ? nil : ParkedInstallerProbe(target: .sparkle(pids: pids), shipItPID: nil)
    }

    /// Whether the installer may still move the bundle.
    public mutating func isAlive(system: System = .live) async -> Bool {
        switch target {
        case .sparkle(let pids):
            return pids.contains(where: system.isAlive)
        case .shipIt(let label):
            // The cheap check first: no `launchctl` while the process runs.
            if let pid = shipItPID, system.isAlive(pid) { return true }
            guard let job = await system.loadedJob(label) else { return false }
            if let pid = job.pid {
                shipItPID = pid
                return true
            }
            // Loaded, not running: launchd runs it again only after a failed
            // exit. Never exited (nil) is not "finished".
            return job.lastExitStatus != 0
        }
    }

    /// An integer line of `launchctl list <label>` — `"PID" = 123;` (absent
    /// while the job is not running) or `"LastExitStatus" = 256;`.
    static func field(_ key: String, inJobDescription text: String) -> Int32? {
        guard let range = text.range(of: "\"\(key)\" = -?[0-9]+;", options: .regularExpression)
        else { return nil }
        let value = text[range].split(separator: "=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
        return value.flatMap { Int32($0) }
    }
}
