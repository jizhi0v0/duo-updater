import Testing
@testable import DuoUpdaterCore

@Suite("ListActivity")
struct ListActivityTests {
    // MARK: - #253: the gap between a refresh's two legs

    /// The bug, stated as the state the UI was actually in.
    ///
    /// A user-present refresh suspends twice with `isScanning` and `isChecking` BOTH
    /// false — at `invalidateAll()` before the scan, and at the TestFlight read
    /// between the legs. SwiftUI renders at both. Before the fix this state was
    /// indistinguishable from "idle", so Update All flashed back into the header and
    /// Refresh un-greyed, mid-refresh.
    ///
    /// This is the case that pins the fix: it fails if `!isRefreshing` is dropped
    /// from `isIdle`, because every other flag here is already false.
    @Test("mid-refresh suspension is not idle")
    func refreshGapIsBusy() {
        let midRefresh = ListActivity(
            isRefreshing: true,
            isScanning: false,
            isChecking: false,
            isInstallingAll: false,
            rowInstallCount: 0)
        #expect(midRefresh.isIdle == false)
        #expect(midRefresh.canRefresh == false)
        #expect(midRefresh.canInstallAll == false)
        // The visible symptom: plenty of targets, button still must not appear.
        #expect(midRefresh.canOfferUpdateAll(targetCount: 7) == false)
    }

    /// `isRefreshing` alone is what closes the gap — the other four flags cannot,
    /// because the gap is defined by all of them being false. Guards against the fix
    /// being "restored" by leaning on a flag that isn't held for the whole refresh.
    @Test("only isRefreshing covers the whole refresh")
    func refreshingIsTheOnlyWholeRoundFlag() {
        #expect(ListActivity(isRefreshing: true).isIdle == false)
        // Each leg's own flag covers only its leg.
        #expect(ListActivity(isScanning: true).isIdle == false)
        #expect(ListActivity(isChecking: true).isIdle == false)
    }

    // MARK: - Each flag independently means "busy"

    /// Mutation coverage: every flag must be load-bearing on its own, so dropping
    /// any one term from `isIdle` fails a case here.
    @Test("every flag alone blocks whole-list actions", arguments: [
        ListActivity(isRefreshing: true),
        ListActivity(isScanning: true),
        ListActivity(isChecking: true),
        ListActivity(isInstallingAll: true),
        ListActivity(rowInstallCount: 1),
    ])
    func eachFlagBlocks(_ activity: ListActivity) {
        #expect(activity.isIdle == false)
        #expect(activity.canRefresh == false)
        #expect(activity.canInstallAll == false)
        #expect(activity.canOfferUpdateAll(targetCount: 7) == false)
    }

    // MARK: - The settled state still works

    @Test("idle permits every whole-list action")
    func idleIsPermissive() {
        let idle = ListActivity()
        #expect(idle.isIdle)
        #expect(idle.canRefresh)
        #expect(idle.canInstallAll)
    }

    /// The batch button is offered only for MORE than one target: with exactly one,
    /// the row's own Update button is already the same control.
    @Test("Update All needs more than one target", arguments: [
        (0, false), (1, false), (2, true), (130, true),
    ])
    func updateAllNeedsTwo(count: Int, offered: Bool) {
        #expect(ListActivity().canOfferUpdateAll(targetCount: count) == offered)
    }

    /// Target count never overrides busy — the two conditions are AND, not OR.
    @Test("a big target count cannot unblock a busy list")
    func countDoesNotOverrideBusy() {
        #expect(ListActivity(isRefreshing: true).canOfferUpdateAll(targetCount: 130) == false)
        #expect(ListActivity(isInstallingAll: true).canOfferUpdateAll(targetCount: 130) == false)
    }
}

@Suite("ListActivity.isRoundInFlight")
struct ListActivityRoundTests {
    /// The spinner must be up for the WHOLE refresh, gaps included — the #253
    /// window, where it used to revert to the refresh arrow while the status line
    /// beside it still read "Checking N apps…".
    @Test("a refresh shows the spinner end to end", arguments: [
        ListActivity(isRefreshing: true),                     // a gap between legs
        ListActivity(isRefreshing: true, isScanning: true),   // scan leg
        ListActivity(isRefreshing: true, isChecking: true),   // check leg
    ])
    func spinnerCoversWholeRefresh(_ activity: ListActivity) {
        #expect(activity.isRoundInFlight)
    }

    /// A standalone retry of failed rows sets `isChecking` without `isRefreshing`,
    /// and is a round too.
    @Test("a standalone re-check is a round")
    func standaloneRecheckIsARound() {
        #expect(ListActivity(isChecking: true).isRoundInFlight)
    }

    /// An install makes the list busy but is NOT a round: the Refresh control must
    /// stay an arrow rather than becoming a progress spinner while a download runs.
    /// This is what stops `isRoundInFlight` from decaying into `!isIdle`.
    @Test("an install is busy but not a round", arguments: [
        ListActivity(isInstallingAll: true),
        ListActivity(rowInstallCount: 1),
    ])
    func installIsNotARound(_ activity: ListActivity) {
        #expect(activity.isIdle == false)
        #expect(activity.isRoundInFlight == false)
    }

    @Test("an idle list shows no spinner")
    func idleHasNoSpinner() {
        #expect(ListActivity().isRoundInFlight == false)
    }
}

@Suite("ListActivity.canOfferUpdateAll cost")
struct ListActivityShortCircuitTests {
    /// The target count is expensive to compute — it filters every row through the
    /// per-row install policy — and `MenuContentView` reads it on every render,
    /// which during a batch download means every progress callback.
    ///
    /// So it MUST NOT be evaluated when the list is already busy. This pins the
    /// `@autoclosure`: written as a plain `Int` parameter the argument is evaluated
    /// before the call, and this test fails.
    @Test("a busy list never evaluates the target count", arguments: [
        ListActivity(isInstallingAll: true),
        ListActivity(rowInstallCount: 1),
        ListActivity(isRefreshing: true),
        ListActivity(isScanning: true),
        ListActivity(isChecking: true),
    ])
    func busyListSkipsTheCount(_ activity: ListActivity) {
        var evaluations = 0
        let offered = activity.canOfferUpdateAll(targetCount: { evaluations += 1; return 7 }())
        #expect(offered == false)
        #expect(evaluations == 0, "the target count was computed for a list that cannot act on it")
    }

    /// The other half: an idle list DOES need the count, so the autoclosure must
    /// actually be called (exactly once — it is not memoised anywhere).
    @Test("an idle list evaluates the target count once")
    func idleListEvaluatesOnce() {
        var evaluations = 0
        let offered = ListActivity().canOfferUpdateAll(targetCount: { evaluations += 1; return 7 }())
        #expect(offered)
        #expect(evaluations == 1)
    }

    /// The inversion that used to live in `AppListModel` as `!installing.isEmpty`.
    /// Held here so a slip cannot flip the whole gate unnoticed.
    @Test("row-install count sets hasRowInstalls", arguments: [
        (0, false), (1, true), (5, true),
    ])
    func rowInstallCountPolarity(count: Int, busy: Bool) {
        let activity = ListActivity(rowInstallCount: count)
        #expect(activity.hasRowInstalls == busy)
        #expect(activity.isIdle == !busy)
    }
}
