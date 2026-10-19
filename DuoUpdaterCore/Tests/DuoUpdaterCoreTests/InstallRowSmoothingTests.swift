import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InstallRowSmoothing`: what an install row draws. The sequences are the ones
/// the owner's capture showed on 2026-10-19 — "Queued" for ~20 ms and
/// "Checking" for ~150 ms before "0%", and "Cancelling…" for ~0.4 s before the
/// row read "Update" again.
@Suite struct InstallRowSmoothingTests {

    private typealias Smoothing = InstallRowSmoothing<String>
    private let t0 = ContinuousClock.now
    private func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }

    /// The click is answered at once, and the stages that follow inside the
    /// dwell wait; when it is up, the latest reported one shows, so a stage
    /// that came and went in between never does.
    ///
    /// Mutation: show every stage as it comes (drop the dwell branch) → red.
    @Test func aStageThatComesAndGoesWithinTheDwellIsNeverShown() {
        var s = Smoothing()
        #expect(s.update(stages: ["a": .queued], cancels: [:], now: at(0)).stages["a"] == .queued)

        let checking = s.update(stages: ["a": .checking], cancels: [:], now: at(20))
        #expect(checking.stages["a"] == .queued)
        #expect(checking.nextWake == at(300))

        let downloading = s.update(stages: ["a": .downloading(fraction: 0)], cancels: [:], now: at(170))
        #expect(downloading.stages["a"] == .queued)

        let due = s.update(stages: ["a": .downloading(fraction: 0)], cancels: [:], now: at(300))
        #expect(due.stages["a"] == .downloading(fraction: 0))
        #expect(due.nextWake == nil)
    }

    /// A download's fraction is progress within one stage: it moves as it
    /// comes, and does not restart the stage's time on the row.
    ///
    /// Mutation: restart `since` on a same-stage update → the last expectation
    /// waits until 700 ms, red.
    @Test func progressWithinAStageIsShownAsItComes() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .downloading(fraction: 0)], cancels: [:], now: at(0))
        let moved = s.update(stages: ["a": .downloading(fraction: 0.4)], cancels: [:], now: at(50))
        #expect(moved.stages["a"] == .downloading(fraction: 0.4))
        _ = s.update(stages: ["a": .downloading(fraction: 0.9)], cancels: [:], now: at(400))
        #expect(s.update(stages: ["a": .extracting], cancels: [:], now: at(410)).stages["a"] == .extracting)
    }

    /// An install that ended leaves its row at once, whatever was waiting.
    @Test func anEndedInstallLeavesTheRowAtOnce() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .queued], cancels: ["a": .available], now: at(0))
        _ = s.update(stages: ["a": .checking], cancels: ["a": .available], now: at(20))
        let ended = s.update(stages: [:], cancels: [:], now: at(40))
        #expect(ended.stages.isEmpty)
        #expect(ended.cancels.isEmpty)
        #expect(ended.nextWake == nil)
    }

    /// An accepted cancel keeps the row's progress and greys its Cancel until
    /// "Cancelling…" is due; one that lasts says so then.
    ///
    /// Mutation: pass `.cancelling` straight through → red.
    @Test func cancellingIsSaidOnlyOnceItHasLasted() {
        var s = Smoothing()
        let stage: [String: InstallStage] = ["a": .downloading(fraction: 0.1)]
        _ = s.update(stages: stage, cancels: ["a": .available], now: at(0))

        let clicked = s.update(stages: stage, cancels: ["a": .cancelling], now: at(1000))
        #expect(clicked.cancels["a"] == .available)
        #expect(clicked.cancelPending == ["a"])
        #expect(clicked.nextWake == at(1300))

        let due = s.update(stages: stage, cancels: ["a": .cancelling], now: at(1300))
        #expect(due.cancels["a"] == .cancelling)
        #expect(due.cancelPending.isEmpty)
    }

    /// A cancel that ended the install within the delay never says
    /// "Cancelling…": the row goes straight back.
    @Test func aQuickCancelNeverSaysCancelling() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .downloading(fraction: 0.1)], cancels: ["a": .available], now: at(0))
        _ = s.update(stages: ["a": .downloading(fraction: 0.1)], cancels: ["a": .cancelling], now: at(1000))
        let back = s.update(stages: [:], cancels: [:], now: at(1200))
        #expect(back.cancels["a"] == nil)
        #expect(back.cancelPending.isEmpty)

        // The next install of the row starts its own delay, not the old one's.
        _ = s.update(stages: ["a": .queued], cancels: ["a": .available], now: at(5000))
        let again = s.update(stages: ["a": .queued], cancels: ["a": .cancelling], now: at(5100))
        #expect(again.cancels["a"] == .available)
        #expect(again.nextWake == at(5400))
    }

    /// The other Cancel states are what the install says, at once: greyed for
    /// a commit is never late.
    @Test func otherCancelStatesPassThrough() {
        var s = Smoothing()
        let out = s.update(
            stages: ["a": .installing, "b": .installing],
            cancels: ["a": .committing, "b": .tooLate], now: at(0))
        #expect(out.cancels == ["a": .committing, "b": .tooLate])
        #expect(out.cancelPending.isEmpty)
    }

    /// Rows are smoothed each on its own.
    @Test func rowsAreSmoothedEachOnItsOwn() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .queued], cancels: [:], now: at(0))
        _ = s.update(stages: ["a": .queued, "b": .queued], cancels: [:], now: at(250))
        let out = s.update(stages: ["a": .checking, "b": .checking], cancels: [:], now: at(320))
        #expect(out.stages["a"] == .checking)
        #expect(out.stages["b"] == .queued)
        #expect(out.nextWake == at(550))
    }

    // MARK: Cancel All

    /// A clicked Cancel All follows the rows: greyed while a cancel has not
    /// lasted, "Cancelling…" once one has, "Finishing…" when only installs past
    /// their commit point are left.
    ///
    /// Mutation: drop the `cancelPending` rung → the first expectation reads
    /// `.finishing`, red.
    @Test func cancelAllFollowsTheRows() {
        var s = Smoothing()
        let stages: [String: InstallStage] = ["a": .downloading(fraction: 0.2), "b": .installing]
        _ = s.update(stages: stages, cancels: ["a": .available, "b": .committing], now: at(0))

        let clicked = s.update(stages: stages, cancels: ["a": .cancelling, "b": .tooLate], now: at(1000))
        #expect(clicked.cancelAllPhase == .pending)
        let slow = s.update(stages: stages, cancels: ["a": .cancelling, "b": .tooLate], now: at(1300))
        #expect(slow.cancelAllPhase == .cancelling)
        // "a" stopped; "b" is past its commit point and installs on.
        let left = s.update(stages: ["b": .installing], cancels: ["b": .tooLate], now: at(1500))
        #expect(left.cancelAllPhase == .finishing)
    }

    /// A cancel that ends its row within the delay never makes Cancel All say
    /// "Cancelling…": it goes from greyed straight to "Finishing…".
    ///
    /// Mutation: a pending cancel counts as cancelling
    /// (`|| !cancelPending.isEmpty` on the first rung) → `clicked` reads
    /// `.cancelling`, red.
    @Test func aQuickCancelGoesStraightToFinishing() {
        var s = Smoothing()
        let stages: [String: InstallStage] = ["a": .queued, "b": .installing]
        _ = s.update(stages: stages, cancels: ["a": .available, "b": .committing], now: at(0))
        let clicked = s.update(stages: stages, cancels: ["a": .cancelling, "b": .tooLate], now: at(500))
        #expect(clicked.cancelAllPhase == .pending)
        let ended = s.update(stages: ["b": .installing], cancels: ["b": .tooLate], now: at(600))
        #expect(ended.cancelAllPhase == .finishing)
    }

    // MARK: Lines

    /// A row whose line is text says the line of the stage it shows: "Queued"
    /// while "Starting…" waits out the dwell, then the newest line; the
    /// command's output moves as it comes.
    ///
    /// Mutation: `line` returns the newest text where it looks up the shown
    /// stage's → the second expectation reads "Starting…", red.
    @Test func aHeldStageKeepsItsLine() {
        var s = Smoothing()
        var lines = InstallRowLines<String>()
        func shown(_ now: Int) -> String? {
            lines.line("t", shown: s.update(stages: lines.stages, cancels: [:], now: at(now)).stages["t"])
        }
        lines.record("t", stage: .queued, text: "Queued")
        #expect(shown(0) == "Queued")
        lines.record("t", stage: .runningCommand(""), text: "Starting…")
        #expect(shown(20) == "Queued")
        lines.record("t", stage: .runningCommand("Downloading 1.2"), text: "Downloading 1.2")
        #expect(shown(150) == "Queued")
        #expect(shown(300) == "Downloading 1.2")
        lines.record("t", stage: .runningCommand("Linking"), text: "Linking")
        #expect(shown(310) == "Linking")
        lines.clear("t")
        #expect(shown(320) == nil)
    }
}
