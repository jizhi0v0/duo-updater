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
/// One failure cannot be undone: removal is per job, so a survivor can be left
/// beside a job already removed. `.notCleared(touchedInstaller: true)` says so —
/// the installer is then no longer the intact thing a "will apply when you quit"
/// note describes, and the caller must not say that.
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
        public var sleep: @Sendable (Duration) async -> Void

        public init(
            listJobs: @escaping @Sendable () async -> [Job]?,
            executablePath: @escaping @Sendable (pid_t) -> String?,
            removeJob: @escaping @Sendable (String) async -> Bool,
            isAlive: @escaping @Sendable (pid_t) -> Bool,
            sleep: @escaping @Sendable (Duration) async -> Void
        ) {
            self.listJobs = listJobs
            self.executablePath = executablePath
            self.removeJob = removeJob
            self.isAlive = isAlive
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
        // Where Sparkle runs its installer pieces from: the progress agent is
        // copied into the cache's `Launcher/` up to 2.9.6 and runs from the host's
        // framework after it; `Autoupdate` runs from the framework (observed:
        // `TinyWeb.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate`).
        // The framework, not all of `Frameworks/`: an app's own helpers live there
        // too, and removing one of those is not ours to do.
        let homes = [sparkleRoot, app.path.appendingPathComponent("Contents/Frameworks/Sparkle.framework", isDirectory: true)]
            .map { $0.resolvingSymlinksInPath().path }
        let installerJobs = jobs.filter { job in
            guard let path = system.executablePath(job.pid) else { return false }
            return homes.contains { AppRestarter.isExecutable(path, insideBundlePath: $0) }
        }
        guard !installerJobs.isEmpty
        else { return .notCleared(reason: "no installer job found for \(bundleID)", touchedInstaller: false) }

        let described = installerJobs.map { "\($0.label) [\($0.pid)]" }.joined(separator: ", ")
        Log.install.notice("sparkle staging: removing \(app.name, privacy: .public)'s installer jobs \(described, privacy: .public) (staged \(staged.version, privacy: .public))")
        // Every job, whatever each answers: what decides is whether the processes
        // are gone afterwards, not the exit status — a job that exited by itself
        // between the list and the removal fails `remove` and is exactly as gone.
        var refused: [Job] = []
        for job in installerJobs where !(await system.removeJob(job.label)) {
            refused.append(job)
        }
        let touched = refused.count < installerJobs.count
        // `launchctl remove` sends SIGTERM; the measured exits took under 10 ms.
        var survivors = installerJobs
        for _ in 0..<30 {
            survivors = survivors.filter { system.isAlive($0.pid) }
            if survivors.isEmpty { break }
            await system.sleep(.milliseconds(100))
        }
        guard survivors.isEmpty
        else {
            return .notCleared(
                reason: "installer still running after removal: \(survivors.map(\.label))"
                    + (refused.isEmpty ? "" : ", launchd refused \(refused.map(\.label))"),
                touchedInstaller: touched)
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
