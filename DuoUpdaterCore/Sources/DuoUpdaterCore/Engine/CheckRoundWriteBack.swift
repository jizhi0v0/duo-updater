import Foundation

/// Publishing a finished check round's rows without discarding what landed
/// underneath it while it ran.
///
/// A refresh captures the on-disk scan ONCE, up front, and everything it publishes
/// afterwards is derived from that snapshot. The network check between the two
/// takes minutes, and the list does not hold still for it: the per-row "Update"
/// button stays live in both the popover and the workbench, an app's own updater
/// can swap a bundle, a staged relaunch can land, the user can flip a release
/// channel. Each of those writes the row it touched. The round then finishes and
/// republishes the whole list from its now-stale snapshot, reverting them — an app
/// updated mid-round goes back to offering the update it just took.
///
/// Two dead ends, both of which look right:
///
///  - **"Skip rows with an install in flight."** Fixes the harmless case and misses
///    the harmful one. If the install is still running, the round's revert is
///    transient — the install's own write lands afterwards and corrects it. The
///    revert that STICKS is the one that overtakes an install which already
///    finished, and by then the claim is released. The claim is the wrong clock.
///
///  - **"Mark the rows that our install paths touched."** Enumerates the writers,
///    and the writers are not enumerable: a staged relaunch can begin BEFORE the
///    round (nothing gates a refresh on it), a quit-handoff swap lands up to three
///    minutes later on an `NSWorkspace` notification, a channel-switch recheck runs
///    off an FS watcher, and an app's own updater is not our code at all. Every
///    path missed is silently unprotected, and a path added later is unprotected on
///    the day it is written.
///
/// So don't ask who wrote the row. Ask whether the row moved: compare the live list
/// against a baseline taken when the round's snapshot was still true. A row that
/// differs changed under the round, whoever changed it, and the round has nothing
/// newer to say about it. A row that matches did not, and takes the round's fresh
/// verdict — which is the entire reason the check ran.
///
/// This also settles the case where the round IS the fresher of the two: an install
/// that was clicked but failed, or applied nothing, leaves the row untouched, so it
/// diffs to nothing and the round wins. Intent to change is not change.
public enum CheckRoundWriteBack {
    /// - Parameters:
    ///   - rows: what the round wants to publish, derived from its scan snapshot.
    ///   - baseline: the list as it stood when that snapshot was still accurate —
    ///     captured after the round's own pre-check writes and before the check.
    ///   - live: the list right now, carrying anything written since.
    ///
    /// A row present in `live` and different from its `baseline` counterpart is
    /// published from `live`. Everything else is published from `rows`.
    ///
    /// A row that is missing from `baseline` but present in `live` counts as
    /// changed: it appeared during the round, so the round's snapshot never
    /// described it. A row missing from `live` keeps the round's version rather
    /// than vanishing — dropping it would make the app disappear from the list,
    /// which is worse than showing it stale.
    public static func publishing(
        _ rows: [UpdateResult],
        changedSince baseline: [UpdateResult],
        live: [UpdateResult]
    ) -> [UpdateResult] {
        guard !baseline.isEmpty || !live.isEmpty else { return rows }
        let liveByID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let baseByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return rows.map { row in
            guard let now = liveByID[row.id] else { return row }
            return baseByID[row.id] == now ? row : now
        }
    }
}
