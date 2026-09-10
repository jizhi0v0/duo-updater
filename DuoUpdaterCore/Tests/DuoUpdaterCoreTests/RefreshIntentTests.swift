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

    /// With Full Disk Access the read is silent, so every round takes it — the
    /// launch's tick included. Mutation: answer `readsTestFlight` for `.granted`
    /// — the tick skips it again, and a launch shows question marks on
    /// TestFlight rows until the menu is opened.
    @Test func withFullDiskAccessEveryRoundReadsTestFlight() {
        for intent in [RefreshIntent.userRequested, .userPresent, .scheduled] {
            #expect(intent.readsTestFlight(fullDiskAccess: .granted))
        }
    }

    /// Mutation: answer `true` for `.denied` — every round then reads a store
    /// it cannot open, and on macOS 27 each read posts a system notice.
    @Test func withoutFullDiskAccessNoRoundReadsTestFlight() {
        for intent in [RefreshIntent.userRequested, .userPresent, .scheduled] {
            #expect(!intent.readsTestFlight(fullDiskAccess: .denied))
            #expect(!intent.readsTestFlight(fullDiskAccess: .notDetermined))
        }
    }

    /// A grant that cannot be asked about keeps the old rule. Mutation: answer
    /// `true` for `.unknown` — the tick could then raise a prompt nobody asked
    /// for; answer `false` — a user-present round stops reading TestFlight on
    /// any system where the SPI is gone.
    @Test func anUnknownGrantKeepsTheTickAwayFromTestFlight() {
        #expect(RefreshIntent.userRequested.readsTestFlight(fullDiskAccess: .unknown))
        #expect(RefreshIntent.userPresent.readsTestFlight(fullDiskAccess: .unknown))
        #expect(!RefreshIntent.scheduled.readsTestFlight(fullDiskAccess: .unknown))
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
