import AppKit
import Darwin
import Foundation

/// Clears a Sparkle update an app staged for its next quit, so ours can replace
/// it instead of standing aside.
///
/// Why this exists: Sparkle's parked installer never looks at the appcast again.
/// While one is armed, every background check only resumes it
/// (`SPUUpdater.m`, `installerInProgress` → `resumeInstallingUpdate`, read at tag
/// 2.9.6), so an app left running for a day keeps the build it staged first. And
/// the swap on quit is not version-checked — the downgrade check runs once, when
/// the installer starts (`SUPlainInstaller performInitialInstallation`), never in
/// `performFinalInstallation` — so a build we install over it is replaced by the
/// staged one on quit. TinyWeb, 2026-09-21/22: 27.0.3 staged at 20:04, 27.0.4 to
/// 27.1.3 released after it, the app never quit; every Update click yielded.
///
/// Clearing is what Sparkle itself does before submitting an installer: remove
/// the launchd jobs (`SUInstallerLauncher.m`, `SMJobRemove` of the same labels).
/// Measured on TinyWeb (Sparkle 2.9.6) 2026-09-22 with the app running: both jobs
/// left, no error surfaced in the app, nothing re-staged within two minutes, and
/// the build we then installed survived the next quit.
///
/// **Fails closed.** Every step is checked, and anything unexpected — no job
/// found, a process that survives removal, staging that is still there — answers
/// `.notCleared` and nothing is deleted. The jobs are found by what their
/// processes run, not by label: a label Sparkle renames is then a job this cannot
/// find, which is the safe outcome.
///
/// Removal is in two phases, the progress agent last (see `attempt`), so an
/// installer that survives never loses the agent the staged-install gates see.
/// One failure is still past undoing: the installer gone, the agent refusing to
/// go. `.notCleared(touchedInstaller: true)` says so — nothing then applies on
/// quit, and the caller must not say it will.
public enum SparkleStagingClearance {

    public enum Outcome: Equatable, Sendable {
        case cleared
        /// `touchedInstaller`: at least one of the installer's jobs was removed
        /// before the failure, so it may no longer apply anything on quit.
        case notCleared(reason: String, touchedInstaller: Bool)
    }

    /// One row of `launchctl list`: a job in this user's domain with a live pid.
    public struct Job: Equatable, Sendable {
        public let pid: pid_t
        public let label: String
        public init(pid: pid_t, label: String) {
            self.pid = pid
            self.label = label
        }
    }

    /// The system calls, injectable so the fail-closed branches can be tested.
    public struct System: Sendable {
        public var listJobs: @Sendable () async -> [Job]?
        public var executablePath: @Sendable (pid_t) -> String?
        public var removeJob: @Sendable (String) async -> Bool
        public var isAlive: @Sendable (pid_t) -> Bool
        public var bundleIdentifier: @Sendable (pid_t) -> String?
        public var sleep: @Sendable (Duration) async -> Void

        public init(
            listJobs: @escaping @Sendable () async -> [Job]?,
            executablePath: @escaping @Sendable (pid_t) -> String?,
            removeJob: @escaping @Sendable (String) async -> Bool,
            isAlive: @escaping @Sendable (pid_t) -> Bool,
            bundleIdentifier: @escaping @Sendable (pid_t) -> String?,
            sleep: @escaping @Sendable (Duration) async -> Void
        ) {
            self.listJobs = listJobs
            self.executablePath = executablePath
            self.removeJob = removeJob
            self.isAlive = isAlive
            self.bundleIdentifier = bundleIdentifier
            self.sleep = sleep
        }

        public static let live = System(
            listJobs: { await launchctl(["list"]).map(parseJobList) },
            executablePath: { pid in
                var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
                guard length > 0 else { return nil }
                return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            },
            removeJob: { label in await launchctl(["remove", label]) != nil },
            isAlive: { pid in kill(pid, 0) == 0 || errno != ESRCH },
            // A fresh instance per pid: `NSWorkspace.runningApplications` can be a
            // stale snapshot off the main run loop, this lookup is not.
            bundleIdentifier: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
            sleep: { try? await Task.sleep(for: $0) })
    }

    /// Remove the installer parked on `app`'s quit and delete what it staged.
    ///
    /// - Parameter staged: the build `SelfUpdaterStaging.sparkleStagedBundle`
    ///   found. Its path must sit inside this app's own Sparkle cache — anything
    ///   else is refused rather than deleted.
    ///
    /// Logged at `.notice` / `.error`, not `.info`: this removes another app's
    /// launchd jobs and deletes files, and `.info` from a third-party subsystem is
    /// not persisted — an afterwards question ("why did TinyWeb's update prompt
    /// go away?") would find nothing.
    public static func clear(
        for app: InstalledApp,
        staged: StagedSelfUpdate,
        cachesDirectory: URL? = nil,
        system: System = .live,
        fileManager: FileManager = .default
    ) async -> Outcome {
        let outcome = await attempt(
            for: app, staged: staged, cachesDirectory: cachesDirectory,
            system: system, fileManager: fileManager)
        if case .notCleared(let reason, _) = outcome {
            Log.install.error("sparkle staging not cleared: \(app.name, privacy: .public) \(staged.version, privacy: .public) — \(reason, privacy: .public)")
        }
        return outcome
    }

    private static func attempt(
        for app: InstalledApp,
        staged: StagedSelfUpdate,
        cachesDirectory: URL?,
        system: System,
        fileManager: FileManager
    ) async -> Outcome {
        guard staged.updater == .sparkle, let bundleID = app.bundleID,
              let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return .notCleared(reason: "not a Sparkle staging this can locate", touchedInstaller: false) }
        let sparkleRoot = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)
        let installation = sparkleRoot.appendingPathComponent("Installation", isDirectory: true)
        guard let stagingDirectory = topLevelEntry(of: staged.stagedBundlePath, under: installation)
        else { return .notCleared(reason: "staged bundle is outside this app's Sparkle cache", touchedInstaller: false) }

        guard let jobs = await system.listJobs()
        else { return .notCleared(reason: "could not list launchd jobs", touchedInstaller: false) }
        let installerJobs = installerJobs(
            in: jobs, for: app, sparkleRoot: sparkleRoot, system: system)
        guard !installerJobs.isEmpty
        else { return .notCleared(reason: "no installer job found for \(bundleID)", touchedInstaller: false) }

        let described = installerJobs.map { "\($0.label) [\($0.pid)]" }.joined(separator: ", ")
        Log.install.notice("sparkle staging: removing \(app.name, privacy: .public)'s installer jobs \(described, privacy: .public) (staged \(staged.version, privacy: .public))")

        // Two phases, the progress agent LAST. The agent is the only thing every
        // staged-install gate can see (`SelfUpdaterStaging.hasParkedSparkleInstaller`
        // finds installers by its bundle identifier; `Autoupdate` has none). Removed
        // while `Autoupdate` survives, the gates would go blind to an installer that
        // still applies the stale build on quit — over whatever we install next.
        // So the agent goes only once everything else is confirmed gone, and while
        // an installer survives, the agent keeps the gates honest.
        let isAgent: (Job) -> Bool = { job in
            system.bundleIdentifier(job.pid).map(SelfUpdaterStaging.sparkleInstallerBundleIDs.contains) ?? false
        }
        let installers = installerJobs.filter { !isAgent($0) }
        let agents = installerJobs.filter(isAgent)

        if let failed = await removeInPhases(installers: installers, agents: agents, system: system) {
            return failed
        }

        // Only now, with nothing left to act on it.
        do {
            try fileManager.removeItem(at: stagingDirectory)
        } catch {
            return .notCleared(
                reason: "could not delete \(stagingDirectory.path): \(error.localizedDescription)",
                touchedInstaller: true)
        }
        guard !fileManager.fileExists(atPath: staged.stagedBundlePath.path)
        else { return .notCleared(reason: "staged bundle still on disk", touchedInstaller: true) }
        Log.install.notice("sparkle staging cleared: \(app.name, privacy: .public) — jobs gone, deleted \(stagingDirectory.path, privacy: .public)")
        return .cleared
    }

    /// Remove an installer parked on `app`'s quit whose staged build is gone
    /// (`SelfUpdaterStaging.sparkleInstallerOrphaned`). There is nothing to
    /// delete; what this buys is that the dead installer is not woken by the quit
    /// our install makes, and that the app's own Sparkle, which only resumes a
    /// parked installer, can check and stage again.
    ///
    /// Fails closed like `clear`: staging that is back, no `Autoupdate` job in this
    /// user's domain (a root installer is not ours to judge dead), or a process
    /// that survives removal all answer `.notCleared`.
    public static func clearOrphanedInstaller(
        for app: InstalledApp,
        cachesDirectory: URL? = nil,
        system: System = .live,
        fileManager: FileManager = .default
    ) async -> Outcome {
        let outcome = await attemptOrphaned(
            for: app, cachesDirectory: cachesDirectory, system: system, fileManager: fileManager)
        if case .notCleared(let reason, _) = outcome {
            Log.install.error("orphaned sparkle installer not cleared: \(app.name, privacy: .public) — \(reason, privacy: .public)")
        }
        return outcome
    }

    private static func attemptOrphaned(
        for app: InstalledApp,
        cachesDirectory: URL?,
        system: System,
        fileManager: FileManager
    ) async -> Outcome {
        guard let bundleID = app.bundleID,
              let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return .notCleared(reason: "no Sparkle cache this can locate", touchedInstaller: false) }
        let sparkleRoot = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)
        guard SelfUpdaterStaging.sparkleStagingIsGone(sparkleRoot: sparkleRoot, fileManager: fileManager)
        else { return .notCleared(reason: "its staging is not gone", touchedInstaller: false) }

        guard let jobs = await system.listJobs()
        else { return .notCleared(reason: "could not list launchd jobs", touchedInstaller: false) }
        let installerJobs = installerJobs(
            in: jobs, for: app, sparkleRoot: sparkleRoot, system: system)
        let isAgent: (Job) -> Bool = { job in
            system.bundleIdentifier(job.pid).map(SelfUpdaterStaging.sparkleInstallerBundleIDs.contains) ?? false
        }
        let installers = installerJobs.filter { !isAgent($0) }
        let agents = installerJobs.filter(isAgent)
        guard !installers.isEmpty
        else { return .notCleared(reason: "no installer job found for \(bundleID) in this user's domain", touchedInstaller: false) }

        let described = installerJobs.map { "\($0.label) [\($0.pid)]" }.joined(separator: ", ")
        Log.install.notice("sparkle installer orphaned: removing \(app.name, privacy: .public)'s installer jobs \(described, privacy: .public) — its staged build is gone")
        if let failed = await removeInPhases(installers: installers, agents: agents, system: system) {
            return failed
        }
        Log.install.notice("orphaned sparkle installer cleared: \(app.name, privacy: .public)")
        return .cleared
    }

    /// `installers` first, `agents` only once those are confirmed gone — why, in
    /// `attempt`. nil when every job is gone.
    private static func removeInPhases(
        installers: [Job], agents: [Job], system: System
    ) async -> Outcome? {
        let first = await removeAndWait(installers, system: system)
        guard first.survivors.isEmpty
        else {
            // The agent is untouched, so the gates still see an armed installer
            // and "will apply it when you quit it" is still what they say.
            return .notCleared(reason: first.reason, touchedInstaller: false)
        }
        let second = await removeAndWait(agents, system: system)
        guard second.survivors.isEmpty
        else {
            return .notCleared(reason: second.reason, touchedInstaller: !installers.isEmpty)
        }
        return nil
    }

    /// The pids of the installer `Autoupdate` processes parked on `app`'s quit —
    /// not the progress agent. Empty when none can be found, including when the
    /// jobs cannot be listed.
    ///
    /// For `relaunchStagedUpdate`'s wait: `Autoupdate` is the process that does
    /// the swap, so once every one of these has exited, nothing is left to move
    /// the bundle. The agent is left out because its exit is not that signal:
    /// on TablePlus's own successful install (2026-10-06 03:13:08) its
    /// `-sparkle-progress` job went inactive 60 ms BEFORE `-sparkle-updater`.
    ///
    /// Same-user installers only. One that needs administrator rights runs in
    /// the system domain (`SUInstallerLauncher.m`), which this user's
    /// `launchctl list` does not show — so that case finds nothing here, and the
    /// caller must read "empty" as "unknown", never as "already gone".
    public static func parkedInstallerPIDs(
        for app: InstalledApp,
        cachesDirectory: URL? = nil,
        system: System = .live,
        fileManager: FileManager = .default
    ) async -> [pid_t] {
        guard let bundleID = app.bundleID,
              let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let jobs = await system.listJobs()
        else { return [] }
        let sparkleRoot = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)
        return installerJobs(in: jobs, for: app, sparkleRoot: sparkleRoot, system: system)
            .filter { job in
                !(system.bundleIdentifier(job.pid).map(SelfUpdaterStaging.sparkleInstallerBundleIDs.contains) ?? false)
            }
            .map(\.pid)
    }

    /// The jobs in `jobs` running one of `app`'s Sparkle installer pieces.
    ///
    /// Where Sparkle runs them from: the progress agent is copied into the
    /// cache's `Launcher/` up to 2.9.6 and runs from the host's framework after
    /// it; `Autoupdate` runs from the framework (observed:
    /// `TinyWeb.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate`).
    /// The framework, not all of `Frameworks/`: an app's own helpers live there
    /// too, and removing one of those is not ours to do.
    private static func installerJobs(
        in jobs: [Job], for app: InstalledApp, sparkleRoot: URL, system: System
    ) -> [Job] {
        let homes = [sparkleRoot, app.path.appendingPathComponent("Contents/Frameworks/Sparkle.framework", isDirectory: true)]
            .map { $0.resolvingSymlinksInPath().path }
        return jobs.filter { job in
            guard let path = system.executablePath(job.pid) else { return false }
            return homes.contains { AppRestarter.isExecutable(path, insideBundlePath: $0) }
        }
    }

    /// Remove `jobs` and wait for their processes to go. Every job is attempted,
    /// whatever each answers: what decides is whether the processes are gone
    /// afterwards, not the exit status — a job that exited by itself between the
    /// list and the removal fails `remove` and is exactly as gone.
    private static func removeAndWait(
        _ jobs: [Job], system: System
    ) async -> (survivors: [Job], reason: String) {
        var refused: [Job] = []
        for job in jobs where !(await system.removeJob(job.label)) {
            refused.append(job)
        }
        // `launchctl remove` sends SIGTERM; the measured exits took under 10 ms.
        var survivors = jobs
        for _ in 0..<30 {
            survivors = survivors.filter { system.isAlive($0.pid) }
            if survivors.isEmpty { break }
            await system.sleep(.milliseconds(100))
        }
        return (survivors,
                "still running after removal: \(survivors.map(\.label))"
                    + (refused.isEmpty ? "" : ", launchd refused \(refused.map(\.label))"))
    }

    /// `Installation/<random>` for a bundle staged at
    /// `Installation/<random>/<random>/<Name>.app` — the directory one staging
    /// run owns, beside the archive it came from. Nil unless `path` is below
    /// `installation`.
    static func topLevelEntry(of path: URL, under installation: URL) -> URL? {
        let root = installation.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let target = path.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard target.count > root.count + 1, Array(target.prefix(root.count)) == root
        else { return nil }
        return installation.appendingPathComponent(target[root.count], isDirectory: true)
    }

    /// `launchctl list`: a header, then `PID\tStatus\tLabel`, PID `-` when the job
    /// is not running. Only running jobs can be an armed installer.
    static func parseJobList(_ output: String) -> [Job] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let pid = pid_t(fields[0]), pid > 0 else { return nil }
            return Job(pid: pid, label: String(fields[2]))
        }
    }

    /// stdout of `/bin/launchctl`, or nil if it did not exit 0.
    private static func launchctl(_ arguments: [String]) async -> String? {
        guard let outcome = try? await ChildProcess.run(
            "/bin/launchctl", arguments,
            standardOutput: .capture, standardError: .discard, onCancel: .runToCompletion),
              outcome.succeeded
        else { return nil }
        return String(decoding: outcome.standardOutput, as: UTF8.self)
    }
}
