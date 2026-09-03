import Foundation

/// How many consecutive check failures make a row "chronic" — worth suppressing
/// from `AppListModel`'s *aggregate* opinions about the whole list, never from a
/// row's own account of itself.
///
/// `AppListModel.failedCheckResults` uses this to drop a row from the failed-check
/// banner, the header's "N of M apps not checked" line, and the bulk-retry target
/// list: a vendor that retired its feed fails identically forever (Alfred's
/// appcast 404'd for weeks), and left counted there it pins a banner permanently
/// with a Retry that just re-runs the same 404.
///
/// `RowActionState`/`RowAction.state(for:)` deliberately does NOT read this. A
/// chronic streak does not make "this check failed" stop being true of the row,
/// and the row's own Failed badge — with its own per-row Retry that re-checks
/// only this app, unlike the banner's Retry which re-runs every failed check —
/// stays exactly as informative whether the streak is one round old or thirty.
/// Suppressing it would make a chronically failing app in the workbench (which
/// shows every row unconditionally, with no "Show all" gate) render as nothing,
/// which reads as "up to date" in a window that otherwise reserves blank for
/// exactly that — see issue #264.
public enum CheckFailureRules {
    /// Three rounds of a check interval (an hour by default) is long past the
    /// point where "retry" is the useful advice — for the banner. See the type
    /// doc for why a row's own state does not use this at all.
    public static let chronicThreshold = 3

    /// Whether a row this many consecutive rounds deep should stop driving the
    /// aggregate surfaces built from `AppListModel.failedCheckResults`.
    public static func isChronic(consecutiveFailures: Int) -> Bool {
        consecutiveFailures >= chronicThreshold
    }
}
