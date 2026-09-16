#if os(macOS)
import Foundation
import Testing
@testable import DuoUpdaterCore

/// When the App Store gives up on a download, and how that is told apart from a
/// download that is merely slow, restarting, or waiting on the user.
///
/// Both failures replayed here are from the mini on 2026-09-16, and both ended the
/// same way before this rule existed: the route watched a button that had already
/// gone back to offering the update until its poll budget ran out, then reported a
/// timeout. The evidence for each is in `abandonWatchdog`'s documentation.
struct AppStoreAbandonedDownloadTests {

    private typealias AX = AppStoreAXInstaller
    private typealias Reading = AppStoreAXInstaller.OfferReading

    /// Feed a sequence of readings through the watchdog the way the loop does, and
    /// answer at which step (1-based) it declared the download abandoned.
    private func firstAbandonedStep(
        _ readings: [Reading], sawProgress: [Bool]? = nil, awaitingUser: [Bool]? = nil
    ) -> Int? {
        var offering = 0
        for (i, reading) in readings.enumerated() {
            let step = AX.abandonWatchdog(
                reading: reading,
                sawProgress: sawProgress?[i] ?? true,
                awaitingUser: awaitingUser?[i] ?? false,
                offeringPolls: offering)
            offering = step.offeringPolls
            if step.abandoned { return i + 1 }
        }
        return nil
    }

    // MARK: - Reading a title

    /// The two title shapes App Store draws while a download runs. Both were read off
    /// the real button during the Xcode run: `"Loading"` at the press, then percentages.
    ///
    /// Mutation: have `offerReading` return `.offering` for a percentage — every replay
    /// below then fires on its first poll.
    @Test func aDownloadingButtonReadsAsWorking() {
        #expect(AX.offerReading(buttonTitle: "Loading") == .working)
        #expect(AX.offerReading(buttonTitle: "0% loaded") == .working)
        #expect(AX.offerReading(buttonTitle: "50.5% loaded") == .working)
        #expect(AX.offerReading(buttonTitle: "Opening") == .working)
        #expect(AX.offerReading(buttonTitle: "Waiting") == .working)
    }

    /// A title that is neither is the store offering the update again — matched by what
    /// it is *not*, so a non-English store reads the same way.
    ///
    /// Mutation: make `.offering` require the literal word "Update"; the localized
    /// cases below stop being recognised.
    @Test func anythingElseReadsAsAnOffer() {
        for title in ["Update", "更新", "Aktualisieren", "Обновить", "GET"] {
            #expect(AX.offerReading(buttonTitle: title) == .offering, "\(title) is an offer")
        }
    }

    /// No button is not a verdict. On the Updates-list route this is what *every* poll
    /// reads once the swap starts, so treating it as a re-offer would fail healthy
    /// installs; `button=nil` also covers three other states that say nothing.
    ///
    /// Mutation: map a missing title to `.offering`.
    @Test func aMissingButtonIsNotAnOffer() {
        #expect(AX.offerReading(buttonTitle: nil) == .absent)
    }

    // MARK: - Xcode, 2026-09-16 — the disk ran out

    /// Replays the shape of that run: a climb, the mid-flight restart at 00:01:51 that
    /// went through `"Loading"` (not through an offer), a second climb, then the revert
    /// that followed `appstoreagent`'s `Code=706` by 336 ms and never went back.
    ///
    /// Asserts both halves: nothing fires during either climb or across the restart,
    /// and the revert ends the install exactly one grace window later.
    ///
    /// Mutation: have `.offering` accumulate but never reach a verdict
    /// (`return (next, false)`), or move the threshold off by one
    /// (`next > abandonedGracePolls`).
    @Test func theRunThatRanOutOfDiskEndsWhenTheStoreReOffers() {
        let climb = [Reading](repeating: .working, count: 120)
        let healthy = climb + [.working] + climb   // 50% → "Loading" → 0% → 50%
        #expect(firstAbandonedStep(healthy) == nil, "a restarting download is not an abandoned one")

        let gaveUp = healthy + [Reading](repeating: .offering, count: AX.abandonedGracePolls)
        #expect(firstAbandonedStep(gaveUp) == healthy.count + AX.abandonedGracePolls)
    }

    /// A revert the download comes back from is not a verdict, and this is the case the
    /// grace window is *for*: two near-full windows of an actionable button with the
    /// download resuming in between must not add up to one. It is also why `.working`
    /// clears the count outright rather than decaying it.
    ///
    /// No run has been observed flickering this way — the Xcode restart went through
    /// `"Loading"`, never through an offer. It is pinned because the whole rule rests on
    /// "an offer that does not go away", and nothing else here would notice if a
    /// recovered one started counting.
    ///
    /// Mutation: have `.working` hold the count instead of resetting it.
    @Test func aFlickerTheDownloadRecoversFromIsNotAbandonment() {
        let nearlyFull = [Reading](repeating: .offering, count: AX.abandonedGracePolls - 1)
        let resumed = [Reading](repeating: .working, count: 5)
        #expect(firstAbandonedStep(nearlyFull + resumed + nearlyFull) == nil)
    }

    /// The page went to `button=nil` at 00:04:29.933, a minute into a revert that was
    /// already permanent. A gap in what we can read must not clear a verdict that is
    /// accumulating, or a flapping page postpones the answer forever.
    ///
    /// Mutation: have `.absent` reset the count to 0 — this never reaches a verdict.
    @Test func aBlindPollDoesNotClearAnAccumulatingRevert() {
        var readings = [Reading]()
        for _ in 0..<(AX.abandonedGracePolls / 2) { readings += [.offering, .absent] }
        readings += [Reading](repeating: .offering, count: AX.abandonedGracePolls / 2)
        #expect(firstAbandonedStep(readings) != nil)
    }

    /// …and it cannot reach one on its own either.
    ///
    /// Mutation: have `.absent` advance the count like `.offering`.
    @Test func blindPollsAloneNeverDeclareAnythingAbandoned() {
        #expect(firstAbandonedStep([Reading](repeating: .absent, count: 900)) == nil)
    }

    // MARK: - Nowdex, 2026-09-16 — the server answered 500

    /// The press latched `sawProgress` on a momentary `"Loading"`, then Apple's
    /// `updateProduct` answered 500 and the page offered the update again. That latch
    /// is what keeps the idle fail-fast branch from firing, so this rule is the only
    /// one left that can end the run.
    ///
    /// Mutation: drop the `sawProgress` gate — the pre-press poll below then fires too.
    @Test func aServerRefusalRightAfterTheLoadingFlashIsCaught() {
        let run: [Reading] = [.working] + [Reading](repeating: .offering, count: AX.abandonedGracePolls)
        #expect(firstAbandonedStep(run) == run.count)
    }

    /// Before any download has started, a button reading "Update" is just the button we
    /// are about to press, or one whose press did not take. That is the idle fail-fast
    /// branch's business — this rule must stay silent, however long it lasts.
    ///
    /// Mutation: drop the `sawProgress` gate.
    @Test func anOfferBeforeAnyDownloadIsNotAnAbandonedOne() {
        let readings = [Reading](repeating: .offering, count: 900)
        #expect(firstAbandonedStep(readings, sawProgress: [Bool](repeating: false, count: 900)) == nil)
    }

    // MARK: - Windows where the button is not the store's verdict

    /// While our quit prompt or App Store's own sheet is up, the budget must not run:
    /// a person taking half a minute to answer would otherwise fail their own update.
    ///
    /// Mutation: drop the `awaitingUser` gate.
    @Test func timeSpentWaitingOnTheUserDoesNotCount() {
        let n = AX.abandonedGracePolls * 3
        #expect(firstAbandonedStep(
            [Reading](repeating: .offering, count: n),
            awaitingUser: [Bool](repeating: true, count: n)) == nil)
    }

    /// The grace window is wide on purpose: the button turns actionable ("Open") the
    /// moment a swap finishes, while the loop learns the install landed from the bundle
    /// on disk, which can trail it. A window this side of that gap would report a
    /// successful update as a failure.
    ///
    /// Mutation: lower `abandonedGracePolls` to 1 — a single actionable poll ends the
    /// install, and so would the one that follows a completed swap.
    @Test func oneActionablePollIsNotEnough() {
        #expect(AX.abandonedGracePolls >= 30, "the window must outlast a completed swap's own button")
        #expect(firstAbandonedStep([Reading](repeating: .offering, count: AX.abandonedGracePolls - 1)) == nil)
    }

    // MARK: - What the spent budget says about itself

    /// The line logged when the poll budget runs out reports the time it measured. Its
    /// predecessor said "6-min poll cap reached" for the Xcode run's 973 s.
    ///
    /// Mutation: go back to a fixed string, or drop `elapsed` from the note.
    @Test func aSpentBudgetReportsTheTimeItActuallyTook() {
        let note = AX.budgetExhaustedNote(polls: 900, elapsed: 973)
        #expect(note.contains("973"))
        #expect(!note.contains("6-min"))
        #expect(AX.budgetExhaustedNote(polls: 900, elapsed: 61) != note,
                "two runs of different length must not read the same")
    }
}
#endif
