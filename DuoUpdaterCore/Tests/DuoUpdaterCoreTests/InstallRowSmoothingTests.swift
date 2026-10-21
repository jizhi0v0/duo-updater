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

    /// An install that ended leaves its row at once, whatever was waiting —
    /// and a new install on that row, inside the dwell, starts from its own
    /// first stage, not the last one the ended install showed. (The row
    /// leaving holds by construction: what is drawn is built from the stages
    /// passed in. What the smoothing remembers of it is what can go wrong.)
    ///
    /// Mutation: keep the ended row's shown stage (drop the `shown` filter in
    /// `update`) → the restart reads `.checking` until 700 ms, red.
    @Test func anEndedInstallLeavesTheRowAtOnce() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .queued], cancels: ["a": .available], now: at(0))
        _ = s.update(stages: ["a": .checking], cancels: ["a": .available], now: at(400))
        let ended = s.update(stages: [:], cancels: [:], now: at(450))
        #expect(ended.stages.isEmpty)
        #expect(ended.cancels.isEmpty)
        #expect(ended.nextWake == nil)

        let again = s.update(stages: ["a": .queued], cancels: ["a": .available], now: at(500))
        #expect(again.stages["a"] == .queued)
        #expect(again.nextWake == nil)
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
        #expect(clicked.cancelAllPhase(holding: nil) == .pending)
        let slow = s.update(stages: stages, cancels: ["a": .cancelling, "b": .tooLate], now: at(1300))
        #expect(slow.cancelAllPhase(holding: nil) == .cancelling)
        // "a" stopped; "b" is past its commit point and installs on.
        let left = s.update(stages: ["b": .installing], cancels: ["b": .tooLate], now: at(1500))
        #expect(left.cancelAllPhase(holding: nil) == .finishing)
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
        #expect(clicked.cancelAllPhase(holding: nil) == .pending)
        let ended = s.update(stages: ["b": .installing], cancels: ["b": .tooLate], now: at(600))
        #expect(ended.cancelAllPhase(holding: nil) == .finishing)
    }

    /// Once no row is running the batch is only wrapping up: Cancel All keeps
    /// saying what it said — greyed after a quick cancel, "Cancelling…" after a
    /// slow one — instead of "Finishing…" over nothing, or a step back.
    ///
    /// Mutations: drop the `stages.isEmpty` rung → `.finishing`, red; return
    /// `.pending` there instead of `previous` → the `.cancelling` hold, red.
    @Test func aBatchWrappingUpKeepsWhatItSaid() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .downloading(fraction: 0.1)], cancels: ["a": .available], now: at(0))
        _ = s.update(stages: ["a": .downloading(fraction: 0.1)], cancels: ["a": .cancelling], now: at(100))
        let wrappingUp = s.update(stages: [:], cancels: [:], now: at(240))
        #expect(wrappingUp.cancelAllPhase(holding: nil) == .pending)
        #expect(wrappingUp.cancelAllPhase(holding: .pending) == .pending)
        #expect(wrappingUp.cancelAllPhase(holding: .cancelling) == .cancelling)
        #expect(wrappingUp.cancelAllPhase(holding: .finishing) == .finishing)
    }

    // MARK: One Cancel for several rows

    /// The popover's tools row stands for every copy it updates: its Cancel is
    /// live while any can still be cancelled, and counts those a click stops —
    /// not the ones past their commit, accepted already, or not the row's.
    ///
    /// Mutation: count every `.available` as live, pending included → `live`
    /// reads 2, red; iterate `cancels` instead of `ids` → "z" counted, red.
    @Test func aGroupCancelIsLiveWhileAnyRowCanBeCancelled() {
        var s = Smoothing()
        let stages: [String: InstallStage] = ["a": .queued, "b": .installing, "c": .queued, "z": .queued]
        _ = s.update(stages: stages, cancels: ["a": .available, "b": .committing, "c": .available, "z": .available], now: at(0))
        let two = s.update(stages: stages, cancels: ["a": .available, "b": .committing, "c": .available, "z": .available], now: at(10))
        #expect(two.groupCancel(of: ["a", "b", "c"]) == .init(state: .available, pending: false, live: 2))
        let one = s.update(stages: stages, cancels: ["a": .available, "b": .committing, "c": .cancelling, "z": .available], now: at(20))
        #expect(one.groupCancel(of: ["a", "b", "c"]) == .init(state: .available, pending: false, live: 1))
    }

    /// Nothing left to stop: greyed as the rows' Cancels are — pending first,
    /// for its 0.3 s, then one being stopped beside the rest, then past the
    /// commit, then refused there — and gone once every one says
    /// "Cancelling…", which the row's line says. One being stopped beside one
    /// past its commit says "Cancelling…", as Update All's header does, not
    /// "can't cancel now" (review, 2026-10-20, round 2).
    ///
    /// Mutations: drop the `pending` rung → `.cancelling`, red; drop the
    /// `cancelling` rung → `.committing`, red; swap the `committing` and
    /// `tooLate` rungs → `.tooLate`, red; take the `cancelling` rung alone →
    /// not nil, red.
    @Test func aGroupCancelGreysAsItsRowsDo() {
        var s = Smoothing()
        let stages: [String: InstallStage] = ["a": .queued, "b": .installing, "c": .installing]
        _ = s.update(stages: stages, cancels: ["a": .available, "b": .committing, "c": .committing], now: at(0))
        let clicked = s.update(stages: stages, cancels: ["a": .cancelling, "b": .committing, "c": .tooLate], now: at(100))
        #expect(clicked.groupCancel(of: ["a", "b", "c"]) == .init(state: .available, pending: true, live: 0))
        let shown = s.update(stages: stages, cancels: ["a": .cancelling, "b": .committing, "c": .tooLate], now: at(400))
        #expect(shown.groupCancel(of: ["a", "b", "c"]) == .init(state: .cancelling, pending: false, live: 0))
        #expect(shown.groupCancel(of: ["a", "c"]) == .init(state: .cancelling, pending: false, live: 0))
        #expect(shown.groupCancel(of: ["b", "c"]) == .init(state: .committing, pending: false, live: 0))
        #expect(shown.groupCancel(of: ["c"]) == .init(state: .tooLate, pending: false, live: 0))
        #expect(shown.groupCancel(of: ["a"]) == nil)
        #expect(shown.groupCancel(of: ["gone"]) == nil)
    }

    /// A Cancel beside a head that can no longer be stopped stops only what
    /// waits behind it, and says so; one that stops the head too, or beside a
    /// head that names nothing running ("Queued"), says what it always did.
    ///
    /// Mutations: drop `liveRunning == 0` → the live head reads queued-only,
    /// red; drop `!running.isEmpty` → the call without `running` reads
    /// queued-only, red.
    @Test func aGroupCancelSaysWhenItStopsOnlyTheQueued() {
        var s = Smoothing()
        let stages: [String: InstallStage] = ["go": .installing, "all": .queued]
        let committing = s.update(stages: stages, cancels: ["go": .committing, "all": .available], now: at(0))
        #expect(committing.groupCancel(of: ["all", "go"], running: ["go"])
            == .init(state: .available, pending: false, live: 1, queuedOnly: true))
        #expect(committing.groupCancel(of: ["all", "go"])
            == .init(state: .available, pending: false, live: 1, queuedOnly: false))

        let live = s.update(stages: stages, cancels: ["go": .available, "all": .available], now: at(10))
        #expect(live.groupCancel(of: ["all", "go"], running: ["go"])
            == .init(state: .available, pending: false, live: 2, queuedOnly: false))
    }

    // MARK: Lines

    /// A row whose line is text says the line of the stage it shows: "Queued"
    /// while "Starting…" waits out the dwell, then the newest line; each
    /// output line then stays up for the dwell before the next replaces it.
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
        #expect(shown(310) == "Downloading 1.2")
        #expect(shown(600) == "Linking")
        lines.clear("t")
        #expect(shown(620) == nil)
    }

    /// The flash measured 2026-10-21: the last output line, then "Checking…"
    /// a few frames later. The line stays up for the dwell, and so does the
    /// stage after it; lines arriving faster than that show the newest when
    /// the dwell is up, never one that came and went in between.
    ///
    /// Mutation: show a new output line as it comes (drop `isNewLine` from the
    /// same-stage test in `update`) → "helm installed…" gives way to
    /// "Checking…" at 2050, red.
    @Test func eachOutputLineStaysUpForTheDwell() {
        var s = Smoothing()
        var lines = InstallRowLines<String>()
        func shown(_ now: Int) -> String? {
            lines.line("t", shown: s.update(stages: lines.stages, cancels: [:], now: at(now)).stages["t"])
        }
        lines.record("t", stage: .runningCommand(""), text: "Starting…")
        #expect(shown(0) == "Starting…")
        // "Starting…" has had its dwell: the first line shows as it comes.
        lines.record("t", stage: .runningCommand("Downloading helm"), text: "Downloading helm")
        #expect(shown(2000) == "Downloading helm")
        lines.record("t", stage: .runningCommand("helm installed into /usr/local/bin/helm"),
                     text: "helm installed into /usr/local/bin/helm")
        #expect(shown(2010) == "Downloading helm")
        #expect(shown(2300) == "helm installed into /usr/local/bin/helm")
        lines.record("t", stage: .checking, text: "Checking…")
        #expect(shown(2350) == "helm installed into /usr/local/bin/helm")
        #expect(shown(2600) == "Checking…")
    }

    /// `stage` names the stage of the line `line` gives, at every step: a held
    /// "Queued" is `.queued` while "Starting…" waits, each output line its own
    /// `.runningCommand`, "Checking…" `.checking`.
    ///
    /// Mutation: `stage` returns the newest stage → at 20 it says
    /// `.runningCommand("")` while the line is "Queued", red.
    @Test func theLinesStageFollowsTheLine() {
        var s = Smoothing()
        var lines = InstallRowLines<String>()
        func shown(_ now: Int) -> (String?, InstallStage?) {
            let stage = s.update(stages: lines.stages, cancels: [:], now: at(now)).stages["t"]
            return (lines.line("t", shown: stage), lines.stage("t", shown: stage))
        }
        func expect(_ now: Int, _ text: String?, _ stage: InstallStage?) {
            let (shownText, shownStage) = shown(now)
            #expect(shownText == text)
            #expect(shownStage == stage)
        }
        lines.record("t", stage: .queued, text: "Queued")
        expect(0, "Queued", .queued)
        lines.record("t", stage: .runningCommand(""), text: "Starting…")
        expect(20, "Queued", .queued)
        expect(300, "Starting…", .runningCommand(""))
        lines.record("t", stage: .runningCommand("Downloading 1.2"), text: "Downloading 1.2")
        expect(600, "Downloading 1.2", .runningCommand("Downloading 1.2"))
        lines.record("t", stage: .runningCommand("Linking"), text: "Linking")
        expect(610, "Downloading 1.2", .runningCommand("Downloading 1.2"))
        lines.record("t", stage: .checking, text: "Checking…")
        expect(620, "Downloading 1.2", .runningCommand("Downloading 1.2"))
        expect(900, "Checking…", .checking)
        lines.clear("t")
        expect(920, nil, nil)
    }

    /// Lines faster than the dwell: the one shown when it is up is the newest,
    /// and the wake asks again at the right time.
    @Test func linesFasterThanTheDwellShowTheNewestWhenItIsUp() {
        var s = Smoothing()
        _ = s.update(stages: ["a": .runningCommand("one")], cancels: [:], now: at(0))
        let held = s.update(stages: ["a": .runningCommand("two")], cancels: [:], now: at(100))
        #expect(held.stages["a"] == .runningCommand("one"))
        #expect(held.nextWake == at(300))
        #expect(s.update(stages: ["a": .runningCommand("three")], cancels: [:], now: at(200)).stages["a"] == .runningCommand("one"))
        let due = s.update(stages: ["a": .runningCommand("three")], cancels: [:], now: at(300))
        #expect(due.stages["a"] == .runningCommand("three"))
        #expect(due.nextWake == nil)
    }
}
