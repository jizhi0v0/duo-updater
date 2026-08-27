import Foundation
import DuoUpdaterCore

/// `duo restart` — quit and relaunch a running app so an in-place update it
/// already has on disk takes effect.
///
/// Runs the same `AppRestarter` the menu-bar app's Restart button runs, so the
/// quit/wait/relaunch dance (graceful-only quits, matching running instances by
/// bundle *path* so a channel sibling is never touched, restoring the
/// foreground state it started with) is not a second, drifting copy.
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

        let settings = Settings.load()
        let apps = await Inventory.scan(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo: \(failure)\n".utf8))
            return 2
        }

        var anyFailed = false
        for app in selected.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let outcome = await AppRestarter.restart(app)
            print("\(app.name)  \(describe(outcome))")
            if isFailure(outcome) { anyFailed = true }
        }
        return anyFailed ? 1 : 0
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
