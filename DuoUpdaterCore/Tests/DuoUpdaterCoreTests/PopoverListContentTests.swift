import Testing
@testable import DuoUpdaterCore

@Suite("PopoverListContent")
struct PopoverListContentTests {
    private func decide(
        hasRows: Bool = true, visibleIsEmpty: Bool = true, isSearching: Bool = false,
        isRoundInFlight: Bool = false, answeredThisLaunch: Bool = true, failedCheckCount: Int = 0
    ) -> PopoverListContent {
        PopoverListContent.decide(
            hasRows: hasRows, visibleIsEmpty: visibleIsEmpty, isSearching: isSearching,
            isRoundInFlight: isRoundInFlight, answeredThisLaunch: answeredThisLaunch,
            failedCheckCount: failedCheckCount)
    }

    /// The cold launch as it was recorded: the scan has published every app as an
    /// unanswered row, none needs action, and the check is running. The list said
    /// "Everything is up to date" under "Checking 255 apps…".
    @Test("a cold launch's first round does not claim up to date")
    func firstRoundIsChecking() {
        #expect(decide(isRoundInFlight: true, answeredThisLaunch: false) == .checking)
    }

    /// Then the round's writes land one render at a time — the published updates,
    /// then a restart row, then a staged self-update — and each showed up as soon
    /// as it was written. Until the round is over, none of them is shown.
    @Test("rows written during the first round wait for it to finish")
    func firstRoundHoldsRows() {
        #expect(decide(visibleIsEmpty: false, isRoundInFlight: true, answeredThisLaunch: false) == .checking)
        // The round's end: every write is in, the list appears once.
        #expect(decide(visibleIsEmpty: false, isRoundInFlight: false, answeredThisLaunch: true) == .rows)
    }

    /// A later round carries the verdicts it had: its rows stay up, and an empty
    /// list is still the last round's answer.
    @Test("later rounds keep showing the last answer")
    func laterRoundsShowCarriedList() {
        #expect(decide(visibleIsEmpty: false, isRoundInFlight: true) == .rows)
        #expect(decide(isRoundInFlight: true) == .upToDate)
    }

    @Test("search is answered during the first round")
    func searchDuringFirstRound() {
        #expect(decide(visibleIsEmpty: false, isSearching: true, isRoundInFlight: true, answeredThisLaunch: false) == .rows)
        #expect(decide(isSearching: true, isRoundInFlight: true, answeredThisLaunch: false) == .noMatches)
    }

    @Test("the placeholders the view had keep their rules")
    func unchangedPlaceholders() {
        #expect(decide(hasRows: false, isRoundInFlight: true, answeredThisLaunch: false) == .scanning)
        #expect(decide(hasRows: false, answeredThisLaunch: false) == .noApps)
        #expect(decide() == .upToDate)
        #expect(decide(failedCheckCount: 3) == .noUpdatesFound)
        #expect(decide(isSearching: true) == .noMatches)
        #expect(decide(visibleIsEmpty: false) == .rows)
    }
}
