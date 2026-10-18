import Foundation

/// What one install attempt actually did to the machine.
///
/// A `Bool` could not say it. Three outcomes reach the caller and only one of
/// them is an app that is now updated:
///
///   * `installed` — a bundle was replaced (or the store finished an install).
///   * `handedOffToSystemInstaller` — a vendor `.pkg` was staged and opened in
///     macOS's Installer. Nothing is installed yet: the user drives that window,
///     and a later rescan settles the row. It is not a failure either, so the row
///     keeps its staged-package bookkeeping and gets no error.
///   * `notInstalled` — an early-out (already current, missing id) or a
///     failure. Which one it was lives in the row's error, not here.
///   * `cancelled(at:)` — stopped by a cancel before its commit point
///     (`InstallCommit`), at the stage it had reached. Not a failure: no error,
///     no failure report, no notification. A cancel that lands after the commit
///     point is no outcome of its own — that install runs to its end.
///
/// The distinction is load-bearing for the batch summary: "Update All" counts
/// these to post "N apps were updated". While the hand-off returned `true`, a
/// batch of two vendor-pkg apps announced "2 apps were updated" while both
/// Installer windows were still open and nothing had been replaced.
public enum InstallAttemptOutcome: Equatable, Sendable {
    case installed
    case handedOffToSystemInstaller
    case notInstalled
    case cancelled(at: InstallStage)

    /// Whether this attempt may be counted into "N apps were updated".
    ///
    /// Only a real install may. A hand-off is deliberately excluded rather than
    /// folded in with the failures: it is the one non-failure that has not
    /// updated anything *yet*. A cancelled one updated nothing.
    public var countsAsUpdatedApp: Bool {
        self == .installed
    }

    /// `.cancelled(at: stage)` for `app`, with the log line that pairs with the
    /// coordinator's `install start` / `install returned`. The one way the hosts
    /// make this outcome, so every cancelled install leaves that line.
    public static func cancelled(_ app: InstalledApp, at stage: InstallStage) -> InstallAttemptOutcome {
        Log.install.notice(
            "install cancelled at \(stage.name, privacy: .public): \(app.name, privacy: .public) [\(app.bundleID ?? "?", privacy: .public)]")
        return .cancelled(at: stage)
    }
}

/// The stage one install has reached, for naming where a cancel stopped it.
///
/// The hosts' own copy of the stage cannot say: the menu-bar app hops every
/// progress tick onto the main actor un-awaited, so its row can trail the
/// install, and `duo` keeps none. This is written in the progress callback
/// itself, before it is forwarded, and by the host for the stages it runs
/// itself (`.backingUp`).
public final class InstallStageTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current: InstallStage

    public init(_ stage: InstallStage) { current = stage }

    /// The last stage entered.
    public var stage: InstallStage { lock.withLock { current } }

    public func enter(_ stage: InstallStage) { lock.withLock { current = stage } }

    /// `progress`, entering each stage it is handed first.
    public func recording(
        _ progress: @escaping @Sendable (InstallStage) -> Void
    ) -> @Sendable (InstallStage) -> Void {
        { [self] stage in
            enter(stage)
            progress(stage)
        }
    }
}

/// What "Update All" counts for its summary: the apps it updated and the ones
/// a cancel stopped. Every other outcome — a failure, a skip, a hand-off to
/// Installer — is in neither.
public struct InstallBatchSummary: Sendable, Equatable {
    public private(set) var updated = 0
    public private(set) var cancelled = 0
    /// Attempts recorded, whatever they came to.
    public private(set) var attempted = 0

    public init() {}

    public mutating func record(_ outcome: InstallAttemptOutcome) {
        attempted += 1
        if outcome.countsAsUpdatedApp { updated += 1 }
        if case .cancelled = outcome { cancelled += 1 }
    }

    /// Targets the batch never started because it was cancelled first.
    public mutating func recordCancelledBeforeStart(_ count: Int) {
        cancelled += max(0, count)
    }
}
