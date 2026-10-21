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

    /// The cold launch recorded on 2026-10-21, step by step, as the model's state
    /// stood at each render (`base.mp4`, frames at 0.5 s, 10.29 s, 10.49 s,
    /// 10.61 s): what the list area showed then, and what it shows now. The list
    /// changes from the placeholder to the rows exactly once, at the end.
    @Test("the recorded cold launch shows the list once")
    func recordedColdLaunch() {
        struct Step { let name: String; let visibleIsEmpty: Bool; let inFlight: Bool; let answered: Bool }
        let steps = [
            Step(name: "scan published, every row .unknown", visibleIsEmpty: true, inFlight: true, answered: false),
            Step(name: "round results published", visibleIsEmpty: false, inFlight: true, answered: false),
            Step(name: "restart sweep re-sorted (Zed Preview on top)", visibleIsEmpty: false, inFlight: true, answered: false),
            Step(name: "staging sweep re-sorted (Spotify on top)", visibleIsEmpty: false, inFlight: true, answered: false),
            Step(name: "round recorded as finished", visibleIsEmpty: false, inFlight: true, answered: true),
            Step(name: "round over", visibleIsEmpty: false, inFlight: false, answered: true),
        ]
        let shown = steps.map {
            decide(visibleIsEmpty: $0.visibleIsEmpty, isRoundInFlight: $0.inFlight, answeredThisLaunch: $0.answered)
        }
        #expect(shown == [.checking, .checking, .checking, .checking, .rows, .rows])
        #expect(!shown.contains(.upToDate))
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
