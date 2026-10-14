import Foundation

/// What a pass of the apps lane does (`AppListModel.appsLane`): a full round —
/// a disk scan and every app's networked check, `refresh(intent:)` — or a
/// network-free local rescan that re-reads disk against the remotes already
/// fetched (`refreshLocal`).
public enum AppsRefreshPlan: Sendable, Equatable {
    case full(RefreshIntent)
    /// `unattended`: nothing the user aimed at us asked for it (a watcher event,
    /// a timer). It picks the TestFlight gate the rescan uses and whether an
    /// install in flight defers it (`backgroundLocalRescan`).
    case local(unattended: Bool)

    /// One pass for two triggers. A full round re-reads disk too, so it covers
    /// a local rescan; two rounds take the intent that does more; two rescans
    /// are attended if either was — the user was there for one of them.
    public func merged(with other: AppsRefreshPlan) -> AppsRefreshPlan {
        switch (self, other) {
        case let (.full(a), .full(b)): return .full(a.merged(with: b))
        case (.full, .local): return self
        case (.local, .full): return other
        case let (.local(a), .local(b)): return .local(unattended: a && b)
        }
    }
}

/// When the app list is checked or re-read — the apps lane's policy, on its
/// inputs so it can be tested without the model.
///
/// An open used to decide this in each view, at the moment it was triggered:
/// a popover opened while the launch's round ran found the list empty, joined
/// that round and then, its intent doing more, ran a whole second one. Decided
/// here after the round in flight — against the list it left — the open is a
/// local rescan.
public enum AppsRefreshPolicy {
    /// `hasResults`: the list has rows. `owesTestFlightRead`: no round this
    /// launch has read TestFlight's store and one the user is present for may
    /// (`AppListModel.owesTestFlightRead`).
    public static func decide(
        _ trigger: RefreshTrigger, hasResults: Bool, owesTestFlightRead: Bool
    ) -> RefreshDecision<AppsRefreshPlan> {
        switch trigger {
        case .popoverOpen, .workbenchOpen:
            // First open with no data: a full check. If no round has read
            // TestFlight yet this launch and one may, one full round: the
            // scheduler's tick doesn't read it without Full Disk Access to ask
            // about, and this open is the user-present round that may. Otherwise
            // a cheap rescan that catches background self-updates and Restart.
            guard hasResults else { return .run(.full(.userPresent), because: "no results yet") }
            if owesTestFlightRead {
                return .run(.full(.userPresent), because: "no round has read TestFlight this launch")
            }
            return .run(.local(unattended: false), because: "an open re-reads disk")
        case .workbenchFocus:
            // Coming back to the window — from a terminal, from System Settings
            // after a grant — re-reads disk, never the network for its own sake.
            guard hasResults else { return .skip(because: "no results yet; the open checks") }
            return .run(.local(unattended: false), because: "a focus re-reads disk")
        case .diskChanged:
            guard hasResults else { return .skip(because: "no results yet") }
            return .run(.local(unattended: true), because: "a watched folder changed")
        case .backstopTick:
            guard hasResults else { return .skip(because: "no results yet") }
            return .run(.local(unattended: true), because: "the backstop's tick")
        case .backgroundTick(let interval):
            // A tick already under way when the user chose "Only when I check"
            // must not start a round (`CLIToolsModel.onTick`'s rule).
            guard interval != nil else { return .skip(because: "Only when I check") }
            return .run(.full(.scheduled), because: "the schedule's tick")
        case .manual:
            return .run(.full(.userRequested), because: "the refresh button")
        case .afterAction:
            // A folder added to the scan, TestFlight's store just granted: both
            // change what a full round finds.
            return .run(.full(.userPresent), because: "our action changed what the list holds")
        }
    }
}
