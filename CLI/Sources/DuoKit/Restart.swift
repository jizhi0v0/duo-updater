import Foundation
import DuoUpdaterCore

/// `duo restart` — quit and relaunch a running app so an in-place update it
/// already has on disk takes effect.
///
/// Runs the same `AppRestarter` the menu-bar app's Restart button runs, so the
/// quit/wait/relaunch dance (graceful-only quits, matching running instances by
/// bundle *path* so a channel sibling is never touched, restoring the
/// foreground state it started with) is not a second, drifting copy. An app
/// whose own updater has staged a build gets the Relaunch's `StagedRelaunch`
/// instead, for the same reason.
public enum Restart {

    public struct Options: Sendable {
        public var queries: [String] = []
        public init() {}
    }

    public static func run(_ options: Options) async -> Int32 {
        await run(options, lock: .shared)
    }

    /// `run`, with the install lock launch processing takes passed in — a
    /// test's own, so it never contends for the machine's.
    static func run(_ options: Options, lock: ProcessInstallLock) async -> Int32 {
        guard !options.queries.isEmpty else {
            FileHandle.standardError.write(Data("duo: name an app to restart\n".utf8))
            return 2
        }

        let settings = await Settings.load()
        // What an earlier `duo` or app process killed mid-install left, as
        // `duo install` does first: without it a dead install no launch has
        // looked at keeps its app `.interrupted`, and the rollback point below
        // is skipped with a line saying the app may be damaged — about an app
        // that may be intact. Skipped when another process holds the lock.
        await InstallJournal.processLeftovers(lock: lock)
        // And the backups such a run left pending (`sweepPendingBackups`).
        await InstallCoordinator.sweepPendingBackups(lock: lock)
        let apps = await Inventory.scanIfFinished(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo: \(failure)\n".utf8))
            return 2
        }

        // The detector `duo install` hands `UpdatePolicy` (`Install.stagedSelfUpdates`).
        // No remote check here: `duo restart` stays offline, so a staged build is
        // judged only against what is installed — see `path(for:staged:)`.
        let staged = Install.stagedSelfUpdates(
            for: selected.map { UpdateResult(app: $0, remote: nil, status: .unknown) })

        // Someone at a terminal can answer a save prompt that holds up the quit,
        // so the staged path waits for them; a script gets the menu-bar app's
        // ~5 s and the `.wontQuit` line. See `StagedRelaunch.QuitPatience`.
        let waitsForAnswer = isatty(STDIN_FILENO) != 0

        let anyFailed = await restartEach(
            selected, staged: staged, keepBackups: settings.keepBackups, waitsForAnswer: waitsForAnswer)
        return anyFailed ? 1 : 0
    }

    /// The restarts, in name order; whether any failed.
    ///
    /// Once the task is cancelled (`SignalGate`'s first signal) no further app is
    /// started — it would be sent its quit and then given up on at once — and the
    /// one in flight runs to its end in `SignalGate.finishing`, out of reach of
    /// that cancellation. In the cancelled task itself it would not: the quit
    /// wait (`AppRestarter`) and the swap wait (`StagedRelaunch`) poll with
    /// `try? await Task.sleep`, which returns at once when cancelled, so a plain
    /// restart would leave the app quit and never reopened, and a staged one
    /// would reopen it while its updater is still swapping — the early reopen
    /// that makes ShipIt abort. One part of the staged step still ends on a
    /// signal: its wait for an app that has not quit after ~5 s, before
    /// anything has changed (`patience`).
    ///
    /// `restart` is the plain path's restarter, a seam for the tests.
    static func restartEach(
        _ apps: [InstalledApp], staged: [String: StagedSelfUpdate], keepBackups: Bool,
        waitsForAnswer: Bool, print: (String) -> Void = { Swift.print($0) },
        restart: @escaping @Sendable (InstalledApp) async -> AppRestarter.Outcome = { await AppRestarter.restart($0) }
    ) async -> Bool {
        var anyFailed = false
        for app in apps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            if Task.isCancelled { break }
            let build = staged[app.id]
            let (text, failed) = await SignalGate.finishing { () -> (String, Bool) in
                switch path(for: app, staged: build) {
                case .plain:
                    let outcome = await restart(app)
                    return (describe(outcome), isFailure(outcome))
                case .staged(let build):
                    let line = await applyStaged(
                        app, build, keepBackups: keepBackups, waitsForAnswer: waitsForAnswer)
                    return (line.text, line.failed)
                }
            }
            print("\(app.name)  \(text)")
            if failed { anyFailed = true }
        }
        return anyFailed
    }

    /// Which restart an app gets.
    enum Path: Equatable {
        /// `AppRestarter.restart`: quit, reopen at once.
        case plain
        /// The app's own updater has this build staged: quit and let it apply,
        /// the way the menu-bar app's Relaunch does (`StagedRelaunch`). A plain
        /// restart there reopens the app under its updater — ShipIt then aborts
        /// with "App Still Running Error" and the reopened old build stages again.
        case staged(StagedSelfUpdate)
    }

    /// The staged path exactly when the GUI's row would offer Relaunch-to-apply
    /// for it (`UpdatePolicy.actionableStaged`), minus the remote half of that
    /// test: without a check there is no latest to compare against, so a staged
    /// build newer than the installed one is taken even if it trails the latest
    /// release. Applying it still moves the app forward, which a plain restart
    /// would not. Mozilla's test needs the remote, so it falls to `.plain` —
    /// whose quit-and-reopen is the launch that applies a Mozilla staging anyway.
    static func path(for app: InstalledApp, staged: StagedSelfUpdate?) -> Path {
        guard app.bundleID != nil,
              let build = UpdatePolicy.actionableStaged(
                UpdateResult(app: app, remote: nil, status: .unknown), staged: staged)
        else { return .plain }
        return .staged(build)
    }

    /// Run the staged relaunch for one app and say what happened. Progress
    /// lines (the rollback point, a quit held up by a prompt) are printed as it
    /// goes; the returned line is the last.
    static func applyStaged(
        _ app: InstalledApp, _ staged: StagedSelfUpdate, keepBackups: Bool, waitsForAnswer: Bool
    ) async -> (text: String, failed: Bool) {
        let to = UpdateResult(app: app, remote: nil, status: .unknown).stagedRelaunchLine(staged).to
        var running = AppRestarter.runningInstances(of: app)
        guard !running.isEmpty else {
            // Nothing to quit, and nothing we can do to make the vendor's updater
            // apply it now — the GUI's Relaunch stands down here too.
            return ("not running — nothing to restart; its own updater has \(to) staged", false)
        }
        // The rollback point the menu-bar app's Relaunch takes, honouring the
        // same preference — while the bundle on disk is still the running build.
        let taken = await StagedRelaunchBackup.take(
            app, keepBackups: keepBackups, old: app.versionSide,
            runningBefore: Set(running.map(\.processIdentifier)),
            system: .live(for: app, backUp: { await InstallCoordinator.backUp(app, route: .sparkle) }))
        if case .standDown(let discarded) = taken {
            // Lets go of the claim the copy took; a copy left there (none was
            // discarded) is the backup now if the app's updater swapped.
            await InstallCoordinator.settlePendingBackup(for: app)
            let copy = discarded ? " (the copy taken meanwhile was discarded)" : ""
            return ("quit while it was being backed up — its own updater is applying \(to) on its own; left it alone\(copy)", false)
        }
        if let note = describe(
            taken, version: app.shortVersion ?? "current", wayBack: InstallJournal.wayBack(for: app.path)) {
            print("\(app.name)  \(note)")
        }
        // Re-read after the copy, which can take seconds: which window is in
        // front is a question about now.
        running = AppRestarter.runningInstances(of: app)
        let patience = patience(for: app, to: to, waitsForAnswer: waitsForAnswer)
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged, old: app.versionSide,
            wasFrontmost: AppRestarter.isFrontmost(running), quitPatience: patience,
            system: .live(for: app))
        // The copy taken above waited in the pending slot; it is the backup
        // now only if the app changed — what the menu-bar app's Relaunch does.
        await InstallCoordinator.settlePendingBackup(for: app)
        let disk = StagedRelaunch.diskVersionSide(app.path)
        return describe(ending, staged: to, disk: disk)
    }

    /// How long a staged relaunch waits for the app to quit.
    ///
    /// In a terminal, up to the menu-bar app's 10-minute hand-off, and a signal
    /// (`stopWaiting`, the gate's first) ends that wait within a tick as
    /// `.wontQuit` — the "(Ctrl-C to stop waiting)" this prints. The step runs in
    /// `SignalGate.finishing`, so cancellation would not reach the wait; the
    /// flag does, and only while the app has not quit: nothing is changed on
    /// disk until it has, and from then on the swap wait and the reopen run out.
    ///
    /// Only from the point this line is printed (`quitGraceTicks`, ~5 s), not
    /// before. A signal during the rollback copy or just after the quit request
    /// is held until then: an app that quits meanwhile was quitting normally,
    /// and gets its swap wait and reopen ("quit — its own updater applied …");
    /// one still up there ends as `.wontQuit` without this line — the ~5 s and
    /// the "likely a save prompt" a script gets (`.grace`), so neither line
    /// offers a wait that is not going to happen. The early signal has to be the
    /// one honoured: later ones change nothing in the gate (its "still
    /// finishing"), so a user who pressed Ctrl-C at 2 s could not otherwise stop
    /// the 10-minute wait at all.
    ///
    /// The plain path gets no such check, on purpose. `AppRestarter`'s quit wait
    /// is ~30 s, and cutting it short is the harm itself: the app was already
    /// asked to quit, so leaving early means a quit landing a moment later is
    /// never followed by the reopen — quit, and not brought back.
    static func patience(
        for app: InstalledApp, to: String, waitsForAnswer: Bool,
        stopWaiting: @escaping @Sendable () -> Bool = { SignalGate.process.stopRequested }
    ) -> StagedRelaunch.QuitPatience {
        let minutes = Int(StagedRelaunch.quitHandoffMaxAge / 60)
        return waitsForAnswer
            ? .handoff(onSlowQuit: {
                print("\(app.name)  hasn't quit yet — likely a save prompt. Answer it and its own updater applies \(to); waiting up to \(minutes) min (Ctrl-C to stop waiting)")
                fflush(stdout)
            }, stopWaiting: stopWaiting)
            : .grace
    }

    /// The line printed for a staged relaunch, and whether it fails the run.
    static func describe(
        _ ending: StagedRelaunch.Ending, staged to: String, disk: VersionSide
    ) -> (text: String, failed: Bool) {
        let reopen = ending.reopenFailed ? ", but reopening it failed" : ""
        switch ending.outcome {
        case .applied:
            let now = disk.isEmpty ? to : disk.text(withBuild: true)
            return ("quit — its own updater applied \(now)\(reopen)", ending.reopenFailed)
        case .wontQuit:
            return ("still running — likely a save prompt, left \(to) staged", true)
        case .swapDidNotLand:
            return ("quit, but its own updater didn't apply \(to) in time\(reopen)", true)
        case .restartedWithoutUpdate:
            return ("restarted without applying \(to)", true)
        case .awaitingOpenConfirmation:
            return ("hasn't finished opening, left \(to) staged — \(openPromptHint)", true)
        }
    }

    /// The progress line for the rollback point, or nil when there is nothing
    /// to say. Worded as `duo install` words its own backup step. `wayBack`
    /// is what an earlier, interrupted install of the app would be restored
    /// from (`InstallJournal.wayBack`), for the line that says it is kept.
    static func describe(
        _ taken: StagedRelaunchBackup.Taken, version: String,
        wayBack: InstallJournal.RestoreSource? = nil
    ) -> String? {
        switch taken {
        case .skipped, .standDown:
            return nil
        case .lockRefused:
            return "no restore point: another install holds the install lock — restarting without one"
        case .attempted(.saved):
            return "backed up \(version)"
        case .attempted(.savedWithoutRuntimeState(let omitted)):
            return "backed up \(version) — without \(omitted) file(s) the app wrote inside its own"
                + " bundle, which it will recreate"
        case .attempted(.unreadable(let path)):
            return "no restore point: \(path) is not readable by you"
        case .attempted(.insufficientSpace):
            return "no restore point: this Mac is low on space"
        case .attempted(.cancelled):
            return "no restore point: the backup was cancelled"
        case .attempted(.skippedForEarlierInstall(let standing)):
            return Install.earlierInstallBackupNote(standing, wayBack: wayBack)
        case .attempted(.failed):
            return "could not back up — restarting without a restore point"
        }
    }

    /// Both paths' line for an app held at macOS's first-open prompt
    /// (`OpenConfirmationHold`): nothing was quit. Hedged — "not finished and no
    /// window" is the prompt's reading, but a slow normal launch reads the same
    /// for a moment.
    static let awaitingOpenConfirmation = "hasn't finished opening — \(openPromptHint)"
    static let openPromptHint = "if macOS is asking whether to open it, click Open, then run duo restart again"

    /// The line printed for one app's outcome.
    static func describe(_ outcome: AppRestarter.Outcome) -> String {
        switch outcome {
        case .noBundleID:        return "skipped — no bundle identifier to match against"
        case .notRunning:        return "not running — nothing to restart"
        case .stillRunning:      return "still running — likely a save prompt, left it alone"
        case .awaitingOpenConfirmation: return awaitingOpenConfirmation
        case .relaunched(true):  return "restarted"
        case .relaunched(false): return "quit, but the relaunch failed"
        case .nestedOnly(relaunched: true):
            return "wasn't running itself — its nested app(s) were cleared and came back"
        case .nestedOnly(relaunched: false):
            return "wasn't running itself — its nested app(s) were cleared, but didn't come back"
        }
    }

    /// Whether this outcome should push the process exit code to 1. Only the
    /// shapes where the app is left worse off than a clean restart count: still up
    /// when it should have quit, quit but never came back, or a nested app that
    /// was quit for the swap and never came back either.
    ///
    /// `.awaitingOpenConfirmation` counts too, as `.stillRunning` does: nothing
    /// was changed, but the restart that was asked for did not happen.
    static func isFailure(_ outcome: AppRestarter.Outcome) -> Bool {
        switch outcome {
        case .stillRunning, .awaitingOpenConfirmation, .relaunched(false), .nestedOnly(relaunched: false):
            return true
        case .noBundleID, .notRunning, .relaunched(true), .nestedOnly(relaunched: true): return false
        }
    }
}
