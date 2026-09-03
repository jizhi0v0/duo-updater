import Foundation
import Testing
@testable import DuoUpdaterCore

/// The order rows appear in.
///
/// A sort cannot fail loudly: reorder two clauses and it still compiles, still
/// renders, and the list is merely wrong in a way no assertion about a single
/// row can see. It lived in `AppListModel`, where nothing executed it.
struct RowOrderTests {

    private func row(
        _ name: String, latest: String? = nil, path: String? = nil
    ) -> UpdateResult {
        let id = path ?? "/Applications/\(name).app"
        let app = InstalledApp(
            name: name, bundleID: "com.example.\(name.lowercased())",
            shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: id),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
        guard let latest else {
            return UpdateResult(app: app, remote: nil, status: .upToDate)
        }
        return UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: latest, version: nil, downloadURL: nil, sourceName: "GitHub"),
            status: .updateAvailable(latest: latest))
    }

    private func sorted(
        _ list: [UpdateResult],
        needsRestart: Set<String> = [],
        staged: [String: StagedSelfUpdate] = [:],
        pinned: [String: Int] = [:]
    ) -> [String] {
        RowOrder.sorted(
            list, needsRestart: needsRestart, stagedSelfUpdates: staged,
            pinnedOrder: pinned
        ).map(\.app.name)
    }

    private func staged(_ version: String) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: version, buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"))
    }

    // MARK: the three tiers

    /// Rows waiting on a relaunch come first, then rows with an update, then the
    /// rest — and each tier is alphabetical inside itself.
    ///
    /// Mutations: swap any two `return` values in `rank`; drop the
    /// `localizedCaseInsensitiveCompare` tie-break.
    @Test func rowsAreRankedRestartThenUpdateThenTheRest() {
        let rows = [
            row("Zulu"),                       // tier 2
            row("Alpha", latest: "2.0"),       // tier 1
            row("Bravo"),                      // tier 0 via needsRestart
            row("Yankee", latest: "2.0"),      // tier 1
            row("Charlie"),                    // tier 2
        ]

        #expect(sorted(rows, needsRestart: ["/Applications/Bravo.app"])
            == ["Bravo", "Alpha", "Yankee", "Charlie", "Zulu"])
    }

    /// A staged build that IS the latest is one relaunch from live, so it ranks
    /// with needs-restart rather than as a pending update.
    ///
    /// Mutation: `if relaunchable.contains(r.id) { return 1 }`.
    @Test func aStagedLatestBuildRanksWithTheRestartTier() {
        let rows = [row("Alpha", latest: "2.0"), row("Zulu", latest: "2.0")]

        #expect(sorted(rows, staged: ["/Applications/Zulu.app": staged("2.0")])
            == ["Zulu", "Alpha"])
    }

    /// …but a staged build that TRAILS the latest is an ordinary pending update:
    /// it will show Update, not Relaunch. `actionableStaged` is what draws that
    /// line, and the sort has to go through it rather than test the raw table.
    ///
    /// Mutation: rank on `stagedSelfUpdates[r.id] != nil` instead of
    /// `UpdatePolicy.actionableStaged(...)`.
    @Test func aStagedBuildThatTrailsTheLatestDoesNotJumpTheQueue() {
        let rows = [row("Alpha", latest: "3.0"), row("Zulu", latest: "3.0")]

        #expect(sorted(rows, staged: ["/Applications/Zulu.app": staged("2.0")])
            == ["Alpha", "Zulu"])
    }

    /// Names sort case-insensitively, so a lowercase app does not fall to the
    /// bottom of its tier.
    ///
    /// Mutation: `a.app.name < b.app.name`.
    @Test func namesSortCaseInsensitively() {
        #expect(sorted([row("beta"), row("Alpha"), row("Charlie")])
            == ["Alpha", "beta", "Charlie"])
    }

    // MARK: the frozen order

    /// While frozen, pinned rows hold their recorded slot regardless of rank —
    /// that is the whole point: the list must not reshuffle under the pointer.
    ///
    /// Mutation: delete the `if !pinnedOrder.isEmpty` block.
    @Test func pinnedRowsHoldTheirSlotAgainstTheirRank() {
        let rows = [row("Alpha", latest: "2.0"), row("Zulu")]
        let pinned = ["/Applications/Zulu.app": 0, "/Applications/Alpha.app": 1]

        #expect(sorted(rows, pinned: pinned) == ["Zulu", "Alpha"])
    }

    /// A row that appeared since the freeze goes AFTER every pinned row.
    /// Inserting it into the middle would push the pinned rows down, which is
    /// exactly what freezing prevents — even when its rank says it belongs first.
    ///
    /// Asserted in BOTH input orders, which is not belt-and-braces: with two
    /// elements Swift's sort calls the comparator exactly once, as
    /// `(list[1], list[0])`, so one input order reaches only ONE arm of the
    /// pinned/new switch. The first line below lands on `(nil, _?)` and the
    /// second on `(_?, nil)`; with only the first, the other arm could be
    /// `fatalError()` and every case here would still pass.
    ///
    /// Mutations: `case (_?, nil): return false`; or `case (nil, _?): return true`.
    @Test func aRowNewSinceTheFreezeGoesAfterEveryPinnedRow() {
        let pinned = ["/Applications/Zulu.app": 0]
        let zulu = row("Zulu")                    // pinned, lowest rank
        let alpha = row("Alpha", latest: "2.0")   // NEW, and would rank first

        #expect(sorted([zulu, alpha], pinned: pinned) == ["Zulu", "Alpha"])
        #expect(sorted([alpha, zulu], pinned: pinned) == ["Zulu", "Alpha"])
    }

    /// Two rows that are both new fall through to the ordinary order rather than
    /// keeping whatever order they arrived in.
    ///
    /// Mutation: `case (nil, nil): return false` in place of the `break`.
    @Test func twoRowsNewSinceTheFreezeUseTheOrdinaryOrder() {
        let rows = [row("Zulu"), row("Alpha", latest: "2.0")]
        let pinned = ["/Applications/Other.app": 0]

        #expect(sorted(rows, pinned: pinned) == ["Alpha", "Zulu"])
    }

    /// An empty pin table means the order is live, not that everything is new.
    ///
    /// No mutation: the `!pinnedOrder.isEmpty` guard is provably a no-op — with
    /// no pins every lookup is `(nil, nil)`, which falls through anyway — so it
    /// saves two dictionary reads and nothing else. This case is the positive
    /// pole for the frozen ones above, not a guard on that line.
    @Test func anEmptyPinTableSortsNormally() {
        #expect(sorted([row("Zulu"), row("Alpha", latest: "2.0")]) == ["Alpha", "Zulu"])
    }
}

/// When the next background check runs.
struct CheckScheduleTests {

    private let now = Date(timeIntervalSince1970: 10_000)

    /// A cold launch with nothing in memory checks immediately, whatever the
    /// persisted `lastCheck` says — otherwise the menu bar shows the empty
    /// zero-badge icon until the floor expires.
    ///
    /// Mutation: drop the `isFirstCheck && !hasResults` early return.
    @Test func aColdLaunchWithAnEmptyListChecksImmediately() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: now, interval: 6 * 3600,
            isFirstCheck: true, hasResults: false) == 0)
    }

    /// The first check after launch is capped at the floor, not the full
    /// interval. A relaunch that inherited a recent `lastCheck` would otherwise
    /// sleep up to six hours.
    ///
    /// Mutation: `let effectiveInterval = interval`.
    @Test func theFirstCheckIsCappedAtTheLaunchFloor() {
        let wait = CheckSchedule.nextWait(
            now: now, lastCheck: now, interval: 6 * 3600,
            isFirstCheck: true, hasResults: true)

        // Literals on both sides. Written as `wait == CheckSchedule.launchFloor`
        // the assertion is self-referential: change the constant to fifty
        // minutes and it still passes, so the number — a product decision about
        // how long after a relaunch the user may wait — was pinned by nothing.
        #expect(wait == 5 * 60)
        #expect(CheckSchedule.launchFloor == 5 * 60)
    }

    /// Later checks use the full interval — the floor is a launch concession, not
    /// the schedule.
    ///
    /// Mutation: `min(interval, launchFloor)` unconditionally.
    @Test func laterChecksUseTheFullInterval() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: now, interval: 6 * 3600,
            isFirstCheck: false, hasResults: true) == 6 * 3600)
    }

    /// The wait is measured from the LAST check, not from now, so a check that
    /// is already overdue runs at once instead of sleeping another interval.
    ///
    /// Mutation: `return effectiveInterval` instead of the due-time difference.
    @Test func anOverdueCheckRunsAtOnce() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: now.addingTimeInterval(-7 * 3600),
            interval: 6 * 3600, isFirstCheck: false, hasResults: true) == 0)
    }

    /// A partially elapsed interval waits only the remainder.
    ///
    /// Mutation: ignore `lastCheck` and return the whole interval.
    @Test func aPartlyElapsedIntervalWaitsOnlyTheRemainder() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: now.addingTimeInterval(-3600),
            interval: 6 * 3600, isFirstCheck: false, hasResults: true) == 5 * 3600)
    }

    /// The run-now shortcut is for a COLD launch only. A later tick that happens
    /// to find the list empty — a scan that matched nothing, everything filtered
    /// out — must still wait out the interval. Without the `isFirstCheck` half of
    /// that condition it answers zero forever, and because a deferred tick leaves
    /// `isFirstCheck` and `lastCheck` untouched, the loop becomes an unthrottled
    /// run of network checks behind nothing but the caller's 60s back-off.
    ///
    /// Every other case here passes `hasResults: true`, so that conjunct was
    /// constant across the whole suite and dropping it passed all six.
    ///
    /// Mutation: `if !hasResults { return 0 }`.
    @Test func aLaterTickWithAnEmptyListStillWaitsTheInterval() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: now, interval: 6 * 3600,
            isFirstCheck: false, hasResults: false) == 6 * 3600)
    }

    /// Never checked before: run now rather than treating a missing date as
    /// "just checked".
    ///
    /// Mutation: `(lastCheck ?? now)`.
    @Test func neverHavingCheckedRunsNow() {
        #expect(CheckSchedule.nextWait(
            now: now, lastCheck: nil, interval: 6 * 3600,
            isFirstCheck: false, hasResults: true) == 0)
    }
}
