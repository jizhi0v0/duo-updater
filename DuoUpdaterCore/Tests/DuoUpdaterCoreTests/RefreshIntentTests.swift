import Testing
@testable import DuoUpdaterCore

@Suite("RefreshIntent")
struct RefreshIntentTests {

    /// The silent tick is the one that must never raise the TCC prompt.
    @Test func onlyAUserPresentRefreshReadsTestFlight() {
        #expect(RefreshIntent.userPresent.readsTestFlight)
        #expect(!RefreshIntent.scheduled.readsTestFlight)
    }

    /// A user-present refresh starts the notes over; the scheduled one keeps
    /// what is on screen. This is #228.
    @Test func onlyAUserPresentRefreshRestartsChangelogs() {
        #expect(RefreshIntent.userPresent.restartsChangelogs)
        #expect(!RefreshIntent.scheduled.restartsChangelogs)
    }

    /// Which entries each kind of refresh drops before re-prewarming. The
    /// scheduled row is the one that matters: loaded and loading survive the
    /// hourly tick, failed does not — because nothing else ever retries a
    /// failed prewarm.
    @Test func userPresentDropsEveryEntryAndScheduledDropsOnlyFailures() {
        #expect(RefreshIntent.userPresent.dropsChangelogEntry(failed: false))
        #expect(RefreshIntent.userPresent.dropsChangelogEntry(failed: true))
        #expect(!RefreshIntent.scheduled.dropsChangelogEntry(failed: false))
        #expect(RefreshIntent.scheduled.dropsChangelogEntry(failed: true))
    }

    /// Coalescing: a user-present caller that lands on a scheduled tick still
    /// owes its own pass; every other pairing is already served by the pass in
    /// flight. The follow-up is itself user-present, so it can never owe again
    /// against itself — the recursion is bounded by construction.
    @Test func onlyUserPresentOntoScheduledOwesAFollowUp() {
        #expect(RefreshIntent.userPresent.owesFollowUp(afterCoalescingOnto: .scheduled))
        #expect(!RefreshIntent.userPresent.owesFollowUp(afterCoalescingOnto: .userPresent))
        #expect(!RefreshIntent.scheduled.owesFollowUp(afterCoalescingOnto: .scheduled))
        #expect(!RefreshIntent.scheduled.owesFollowUp(afterCoalescingOnto: .userPresent))
    }
}
