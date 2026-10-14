import Foundation

/// When to re-read the brew package list — `AppListModel.brewLane`'s policy,
/// on its inputs so it can be tested without the model.
public enum BrewRefreshPolicy {
    /// How long after a read an open or a focus asks for another. Each read is
    /// ~3.4 s of 9–10 `brew` runs (~5.7 s of CPU; `AppListModel.brewLane` has
    /// the measurement), and the list does not change by itself — what
    /// changes it is a `brew` run, ours (which re-reads regardless) or one in a
    /// terminal. Measured 2026-10-14: a popover flicked open and shut with the
    /// workbench up sends an open and a focus per flick, and without a spacing
    /// the lane read back to back for as long as the flicking went on.
    public static let spacing: Duration = .seconds(10)

    /// What a trigger calls for. `sinceLastRead` is the lane's
    /// `sinceLastPass`; `ourBrewRunGoing`, whether an upgrade or `brew update`
    /// of ours is running; `brewIsIdle`, that and no cask install either.
    public static func decide(
        _ trigger: RefreshTrigger, sinceLastRead: Duration?, ourBrewRunGoing: Bool, brewIsIdle: Bool
    ) -> RefreshDecision<Void> {
        let recent = sinceLastRead.flatMap { $0 < spacing ? $0 : nil }
        let spaced = recent.map { "read \(Log.seconds($0)) ago, under \(Log.seconds(spacing))" }
        switch trigger {
        case .popoverOpen, .workbenchOpen:
            if let spaced { return .skip(because: spaced) }
            return .run((), because: "an open shows the package list")
        case .workbenchFocus:
            if let spaced { return .skip(because: spaced) }
            // Brew is read again on focus because nothing watches its files: a
            // `brew trust` / `upgrade` / `update` run in a terminal (the unchecked
            // pane hands out the trust command to copy) stayed invisible until
            // the window was reopened. Not while one of our own brew runs is
            // going: each re-reads when it ends, and a read started mid-run could
            // land after that one with the half-done state.
            guard !ourBrewRunGoing else {
                return .skip(because: "a brew run of ours is going; it re-reads when it ends")
            }
            return .run((), because: "a terminal may have changed brew meanwhile")
        case .backgroundTick:
            // The focus rule, and an app row's cask install runs brew too. Not
            // spaced: the schedule spaces its ticks, and a tick may follow its own
            // `brew update`, after which the list has changed.
            guard brewIsIdle else { return .skip(because: "a brew run or install of ours is going") }
            return .run((), because: "the schedule's tick")
        case .afterAction:
            // Not spaced, and even after a failed run: brew carries on past a
            // formula that fails, so a failed run still upgrades what it can.
            return .run((), because: "our brew run changed the package list")
        case .manual:
            // The button asks for a fresh answer from everything: not spaced.
            // Still not on top of a brew run of ours, which holds brew's lock
            // and re-reads when it ends.
            guard !ourBrewRunGoing else {
                return .skip(because: "a brew run of ours is going; it re-reads when it ends")
            }
            return .run((), because: "the refresh button")
        case .diskChanged, .backstopTick:
            return .skip(because: "brew's list is read on opens, focuses and ticks, not on disk events")
        }
    }
}
