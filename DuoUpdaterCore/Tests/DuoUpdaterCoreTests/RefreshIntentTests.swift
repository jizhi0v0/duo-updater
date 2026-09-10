import Testing
@testable import DuoUpdaterCore

@Suite("RefreshIntent")
struct RefreshIntentTests {

    /// The silent tick is the one that must never raise the TCC prompt; both
    /// kinds of refresh the user is present for may.
    @Test func onlyTheScheduledRefreshSkipsTestFlight() {
        #expect(RefreshIntent.userRequested.readsTestFlight)
        #expect(RefreshIntent.userPresent.readsTestFlight)
        #expect(!RefreshIntent.scheduled.readsTestFlight)
    }

    /// A refresh the user is present for starts the notes over; the scheduled
    /// one keeps what is on screen. This is #228.
    @Test func onlyTheScheduledRefreshKeepsChangelogs() {
        #expect(RefreshIntent.userRequested.restartsChangelogs)
        #expect(RefreshIntent.userPresent.restartsChangelogs)
        #expect(!RefreshIntent.scheduled.restartsChangelogs)
    }

    /// Which entries each kind of refresh drops before re-prewarming. The
    /// scheduled row is the one that matters: loaded and loading survive the
    /// hourly tick, failed does not — because nothing else ever retries a
    /// failed prewarm.
    @Test func userPresentDropsEveryEntryAndScheduledDropsOnlyFailures() {
        #expect(RefreshIntent.userRequested.dropsChangelogEntry(failed: false))
        #expect(RefreshIntent.userRequested.dropsChangelogEntry(failed: true))
        #expect(RefreshIntent.userPresent.dropsChangelogEntry(failed: false))
        #expect(RefreshIntent.userPresent.dropsChangelogEntry(failed: true))
        #expect(!RefreshIntent.scheduled.dropsChangelogEntry(failed: false))
        #expect(RefreshIntent.scheduled.dropsChangelogEntry(failed: true))
    }

    /// Starting TestFlight belongs to the button alone. Mutation: answer `true`
    /// for `.userPresent` — then merely opening the menu starts TestFlight in the
    /// background, which is what this property exists to prevent.
    @Test func onlyTheButtonSyncsTestFlight() {
        #expect(RefreshIntent.userRequested.refreshesTestFlight)
        #expect(!RefreshIntent.userPresent.refreshesTestFlight)
        #expect(!RefreshIntent.scheduled.refreshesTestFlight)
    }

    /// Every pairing, spelled out. The row that matters most is the button
    /// landing on a pass the menu's opening started: that pass syncs nothing, so
    /// the click owes its own. Mutation: restore the old
    /// `self == .userPresent && inFlight == .scheduled` — the button's two
    /// `true` rows go red. The diagonal is all `false`, which is what bounds the
    /// follow-up's recursion.
    @Test(arguments: [
        (RefreshIntent.userRequested, RefreshIntent.userRequested, false),
        (.userRequested, .userPresent, true),
        (.userRequested, .scheduled, true),
        (.userPresent, .userRequested, false),
        (.userPresent, .userPresent, false),
        (.userPresent, .scheduled, true),
        (.scheduled, .userRequested, false),
        (.scheduled, .userPresent, false),
        (.scheduled, .scheduled, false),
    ])
    func aFollowUpIsOwedWhenThePassInFlightDoesLess(
        caller: RefreshIntent, inFlight: RefreshIntent, owes: Bool
    ) {
        #expect(caller.owesFollowUp(afterCoalescingOnto: inFlight) == owes)
    }
}
