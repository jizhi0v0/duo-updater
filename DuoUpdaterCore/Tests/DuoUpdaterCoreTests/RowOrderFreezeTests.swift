import Foundation
import Testing
@testable import DuoUpdaterCore

/// When the frozen row order may be released.
///
/// The failure this guards is silent by construction: a release term that stops
/// firing leaves the list permanently frozen, and from outside that is
/// indistinguishable from a freeze that never engaged — both are "the list
/// stopped re-sorting". Nothing executed it before.
struct RowOrderFreezeTests {

    private func hold(
        installs: Int = 0, batch: Bool = false, relaunches: Int = 0, justUpdated: Int = 0
    ) -> String? {
        RowOrderFreeze.holdReason(
            installCount: installs, isInstallingAll: batch,
            relaunchCount: relaunches, justUpdatedCount: justUpdated)
    }

    /// Nothing in flight: release.
    ///
    /// Mutation: return a reason unconditionally.
    @Test func anIdleListMayBeReleased() {
        #expect(hold() == nil)
    }

    /// Each of the four conditions holds the freeze ON ITS OWN. Asserted one at a
    /// time, because a fixture with several set at once measures only whichever
    /// is reported first — the shape that let a whole branch set go unmeasured
    /// twice already in this series.
    ///
    /// Mutations: delete any one of the four terms.
    @Test func eachConditionHoldsTheFreezeByItself() {
        #expect(hold(installs: 1) != nil)
        #expect(hold(batch: true) != nil)
        #expect(hold(relaunches: 1) != nil)
        #expect(hold(justUpdated: 1) != nil)
    }

    /// The reported reason is part of the answer, not decoration: it is the only
    /// thing that tells the two indistinguishable states apart in a live log.
    /// Each condition names itself, and the counted ones carry their count.
    ///
    /// Mutations: swap any two reason strings; drop a count from one.
    @Test func eachConditionNamesItself() {
        #expect(hold(installs: 3) == "installing (3)")
        #expect(hold(batch: true) == "batch install")
        #expect(hold(relaunches: 2) == "relaunching (2)")
        #expect(hold(justUpdated: 1) == "just-updated confirmation")
    }

    /// With more than one condition true, the most specific wins — a reader
    /// watching the log wants the row-level cause, not the batch flag that is
    /// true for the whole run.
    ///
    /// Mutation: reorder the `if`s.
    @Test func theMostSpecificReasonIsReported() {
        #expect(hold(installs: 2, batch: true, relaunches: 1, justUpdated: 1)
            == "installing (2)")
        #expect(hold(batch: true, relaunches: 1, justUpdated: 1) == "batch install")
        #expect(hold(relaunches: 1, justUpdated: 1) == "relaunching (1)")
    }

    /// A zero count must not be mistaken for a condition — and specifically must
    /// not SHADOW a later term that is true, which is the only thing this can add
    /// over the idle case above. Written as `hold(installs: 0, relaunches: 0,
    /// justUpdated: 0)` it was the same call as `hold()` after defaults, so it
    /// killed nothing the first case had not already killed.
    ///
    /// Mutation: `installCount >= 0` (or any counted term testing for presence
    /// rather than for a positive count).
    @Test func aZeroCountDoesNotShadowALaterCondition() {
        #expect(hold(installs: 0, batch: true) == "batch install")
        #expect(hold(installs: 0, relaunches: 1) == "relaunching (1)")
        #expect(hold(relaunches: 0, justUpdated: 1) == "just-updated confirmation")
    }
}

/// How an install-progress tick is folded into what a row shows.
struct InstallProgressCoalescingTests {

    /// A tick for a row whose install is over is dropped. Resurrecting it would
    /// re-show a phantom row and wedge the re-entrancy guard, which keys on this
    /// very absence.
    ///
    /// Mutation: delete the `guard current != nil`.
    @Test func aTickForAFinishedInstallIsIgnored() {
        #expect(InstallProgressCoalescing.fold(
            current: nil, incoming: .downloading(fraction: 0.5)) == nil)
        // …including a terminal stage: nil means the install is over, whatever
        // the tick says.
        #expect(InstallProgressCoalescing.fold(current: nil, incoming: .done) == nil)
    }

    /// A download tick that does not move the whole percent is dropped. The
    /// stage table invalidates as a whole, so writing it re-renders every row —
    /// dozens of times a second during a download.
    ///
    /// Mutation: delete the same-percent branch.
    @Test func aDownloadTickWithinTheSamePercentIsIgnored() {
        #expect(InstallProgressCoalescing.fold(
            current: .downloading(fraction: 0.5),
            incoming: .downloading(fraction: 0.5049)) == nil)
    }

    /// …but crossing into the next percent is written.
    ///
    /// What this actually kills is the skip swallowing EVERY download tick — the
    /// raw-fraction mutation it used to name is killed by the two cases around
    /// it, not by this one, since `0.5 != 0.51` under either rule.
    ///
    /// Mutation: `if case .downloading = incoming, case .downloading? = current`
    /// with no percent test; or returning `current` instead of `incoming`.
    @Test func aDownloadTickThatCrossesAPercentIsWritten() {
        #expect(InstallProgressCoalescing.fold(
            current: .downloading(fraction: 0.5),
            incoming: .downloading(fraction: 0.51)) == .downloading(fraction: 0.51))
    }

    /// The percent is TRUNCATED, not rounded — what the user reads is
    /// `Int(fraction * 100)`, so two fractions that display the same number are
    /// the same tick however they round. 0.504 and 0.506 both display as 50%,
    /// but they round to 50 and 51, so a rounding version writes a tick that
    /// changes nothing on screen.
    ///
    /// The earlier fixtures could not see this: 0.5 → 0.5049 and 0.5 → 0.51 give
    /// the same answer under either rule.
    ///
    /// ⚠️ These two literals are load-bearing. As doubles the products are
    /// 50.3999999999999985… and 50.6000000000000014…, so they truncate to the
    /// same 50 and round to 50 and 51. Tidying them to rounder numbers silently
    /// retires the case.
    ///
    /// Mutation: `(fraction * 100).rounded() == (previous * 100).rounded()`.
    @Test func thePercentIsTruncatedNotRounded() {
        #expect(InstallProgressCoalescing.fold(
            current: .downloading(fraction: 0.504),
            incoming: .downloading(fraction: 0.506)) == nil)
    }

    /// The coalescing is for downloads only. A different stage always writes,
    /// even while a download is showing — otherwise an install that moved on to
    /// verifying would keep rendering a progress bar.
    ///
    /// Mutation: widen the same-percent branch to any incoming stage.
    @Test func aStageChangeIsAlwaysWritten() {
        #expect(InstallProgressCoalescing.fold(
            current: .downloading(fraction: 0.5),
            incoming: .verifyingSignature) == .verifyingSignature)
        #expect(InstallProgressCoalescing.fold(
            current: .queued, incoming: .downloading(fraction: 0.5))
            == .downloading(fraction: 0.5))
    }

    /// The coalescing is percent-based AND download-only: an identical
    /// non-download stage still writes. `.runningCommand` is the only stage
    /// carrying a payload, and Homebrew repeats output lines verbatim, so it is
    /// the case a "let us just dedupe identical stages" edit would break.
    ///
    /// Writing the same value again is close to unobservable on screen, so this
    /// is hardening rather than a live defect — but the widened dedupe survived
    /// every other case here, and this is `.runningCommand`'s only appearance in
    /// the suite.
    ///
    /// Mutation: `if current == incoming { return nil }`.
    @Test func anIdenticalNonDownloadStageIsStillWritten() {
        #expect(InstallProgressCoalescing.fold(
            current: .runningCommand("==> Downloading"),
            incoming: .runningCommand("==> Downloading"))
            == .runningCommand("==> Downloading"))
    }

    /// The percent test needs BOTH sides to be downloads. Arriving at a download
    /// from any other stage must write, or the first progress tick of every
    /// install would be swallowed.
    ///
    /// Mutation: drop the `case .downloading(let previous)? = current` pattern
    /// so the incoming fraction is compared against a default.
    /// ⚠️ `0.0` is load-bearing: it is the only fraction for which "compare the
    /// incoming percent against a default of zero" — the mutation below — gives
    /// the same answer as the real rule for the wrong reason. With 0.5 here the
    /// case stops killing it.
    @Test func theFirstDownloadTickAfterAnotherStageIsWritten() {
        for stage in [InstallStage.queued, .checking, .installing, .extracting] {
            #expect(InstallProgressCoalescing.fold(
                current: stage, incoming: .downloading(fraction: 0.0))
                == .downloading(fraction: 0.0), "\(stage) swallowed the first tick")
        }
    }
}
