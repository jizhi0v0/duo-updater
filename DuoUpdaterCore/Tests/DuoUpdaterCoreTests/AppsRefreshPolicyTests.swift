import Testing
import Foundation
@testable import DuoUpdaterCore

/// `AppsRefreshPolicy` and `AppsRefreshPlan`: which triggers run a full round,
/// which a local rescan, and how two plans answered by one pass combine. Each
/// case names the mutation it fails under.
struct AppsRefreshPolicyTests {

    func plan(_ trigger: RefreshTrigger, results: Bool = true, owes: Bool = false) -> AppsRefreshPlan? {
        guard case .run(let plan, _) = AppsRefreshPolicy.decide(
            trigger, hasResults: results, owesTestFlightRead: owes) else { return nil }
        return plan
    }

    /// An open checks when the list is empty or no round has read TestFlight
    /// yet, and otherwise only re-reads disk — the rule both views carried.
    ///
    /// Mutations: drop the `hasResults` guard; drop the `owesTestFlightRead`
    /// branch; an open's rescan marked unattended.
    @Test(arguments: [RefreshTrigger.popoverOpen, .workbenchOpen])
    func anOpenChecksOnlyWhatItMust(_ open: RefreshTrigger) {
        #expect(plan(open, results: false) == .full(.userPresent))
        #expect(plan(open, owes: true) == .full(.userPresent))
        #expect(plan(open) == .local(unattended: false))
    }

    /// Focus, disk events and backstop ticks never touch the network; disk
    /// events and ticks are unattended, a focus is not. None runs before the
    /// first round has filled the list.
    ///
    /// Mutations: `.diskChanged` or `.backstopTick` attended; a focus with no
    /// results run.
    @Test func diskEventsAndTicksOnlyReReadDisk() {
        #expect(plan(.workbenchFocus) == .local(unattended: false))
        #expect(plan(.diskChanged) == .local(unattended: true))
        #expect(plan(.backstopTick) == .local(unattended: true))
        for trigger in [RefreshTrigger.workbenchFocus, .diskChanged, .backstopTick] {
            #expect(plan(trigger, results: false) == nil, "\(trigger)")
        }
    }

    /// The button, the schedule and our own actions each run a full round of
    /// their own intent; a tick under "Only when I check" runs nothing.
    ///
    /// Mutations: the button at `.userPresent`; the tick at `.userPresent`;
    /// drop the `interval != nil` guard.
    @Test func fullRoundsCarryTheirIntent() {
        #expect(plan(.manual) == .full(.userRequested))
        #expect(plan(.backgroundTick(interval: 300)) == .full(.scheduled))
        #expect(plan(.backgroundTick(interval: nil)) == nil)
        #expect(plan(.afterAction("scan folders changed")) == .full(.userPresent))
    }

    /// One pass for several triggers: a full round covers a rescan, two rounds
    /// take the stronger intent, two rescans are attended if either was.
    ///
    /// Mutations: `merged` keeping `self`; `a || b` for the rescans;
    /// `RefreshIntent.merged` keeping the weaker.
    @Test func plansMergeToWhatCoversBoth() {
        #expect(AppsRefreshPlan.local(unattended: true).merged(with: .full(.scheduled)) == .full(.scheduled))
        #expect(AppsRefreshPlan.full(.scheduled).merged(with: .local(unattended: false)) == .full(.scheduled))
        #expect(AppsRefreshPlan.full(.scheduled).merged(with: .full(.userRequested)) == .full(.userRequested))
        #expect(AppsRefreshPlan.full(.userRequested).merged(with: .full(.userPresent)) == .full(.userRequested))
        #expect(AppsRefreshPlan.local(unattended: true).merged(with: .local(unattended: false)) == .local(unattended: false))
        #expect(AppsRefreshPlan.local(unattended: true).merged(with: .local(unattended: true)) == .local(unattended: true))
    }

    /// The merged intent does everything either does — checked against the
    /// properties that make an intent, not its name.
    ///
    /// Mutation: a rank order that puts `.userPresent` above `.userRequested`.
    @Test func aMergedIntentDoesWhatEitherDoes() {
        let all: [RefreshIntent] = [.scheduled, .userPresent, .userRequested]
        for a in all {
            for b in all {
                let m = a.merged(with: b)
                #expect(m.readsTestFlight == (a.readsTestFlight || b.readsTestFlight), "\(a) \(b)")
                #expect(m.restartsChangelogs == (a.restartsChangelogs || b.restartsChangelogs), "\(a) \(b)")
                #expect(m.refreshesTestFlight == (a.refreshesTestFlight || b.refreshesTestFlight), "\(a) \(b)")
            }
        }
    }
}
