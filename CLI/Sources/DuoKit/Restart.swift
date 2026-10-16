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
        guard !options.queries.isEmpty else {
            FileHandle.standardError.write(Data("duo: name an app to restart\n".utf8))
            return 2
        }

        let settings = await Settings.load()
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

        var anyFailed = false
        for app in selected.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            switch path(for: app, staged: staged[app.id]) {
            case .plain:
                let outcome = await AppRestarter.restart(app)
                print("\(app.name)  \(describe(outcome))")
                if isFailure(outcome) { anyFailed = true }
            case .staged(let build):
                let line = await applyStaged(app, build)
                print("\(app.name)  \(line.text)")
                if line.failed { anyFailed = true }
            }
        }
        return anyFailed ? 1 : 0
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

    /// Run the staged relaunch for one app and say what happened.
    static func applyStaged(_ app: InstalledApp, _ staged: StagedSelfUpdate) async -> (text: String, failed: Bool) {
        let to = UpdateResult(app: app, remote: nil, status: .unknown).stagedRelaunchLine(staged).to
        let running = AppRestarter.runningInstances(of: app)
        guard !running.isEmpty else {
            let when = staged.appliesOn == .launch ? "next launch" : "next quit"
            return ("not running — its own updater applies \(to) on its \(when)", false)
        }
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged, old: app.versionSide,
            wasFrontmost: AppRestarter.isFrontmost(running), system: .live(for: app))
        let disk = StagedRelaunch.diskVersionSide(app.path)
        return describe(ending, staged: to, disk: disk)
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
        }
    }

    /// The line printed for one app's outcome.
    static func describe(_ outcome: AppRestarter.Outcome) -> String {
        switch outcome {
        case .noBundleID:        return "skipped — no bundle identifier to match against"
        case .notRunning:        return "not running — nothing to restart"
        case .stillRunning:      return "still running — likely a save prompt, left it alone"
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
    static func isFailure(_ outcome: AppRestarter.Outcome) -> Bool {
        switch outcome {
        case .stillRunning, .relaunched(false), .nestedOnly(relaunched: false): return true
        case .noBundleID, .notRunning, .relaunched(true), .nestedOnly(relaunched: true): return false
        }
    }
}
