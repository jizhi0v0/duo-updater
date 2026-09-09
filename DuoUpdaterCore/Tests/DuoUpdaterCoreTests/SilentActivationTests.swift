import Testing
import Foundation
@testable import DuoUpdaterCore

/// The ordering rules of `SilentActivation`, with SkyLight and the front process
/// replaced by spies so no case takes anyone's focus.
///
/// Almost everything here asserts on what did **not** happen. That is the shape of
/// the type: it moves the user's front process for 120ms, and every rule in it
/// exists to make sure that move is skipped, or undone, in some state where it
/// would be wrong.
struct SilentActivationTests {

    /// Records the effects in the order they were asked for, so a case can pin
    /// ordering and not merely occurrence.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var log: [String] = []
        private(set) var hiddenWrites: [Bool] = []
        func note(_ s: String) { lock.lock(); log.append(s); lock.unlock() }
        func wroteHidden(_ v: Bool) { lock.lock(); hiddenWrites.append(v); lock.unlock() }
        var frontWasTaken: Bool { log.contains("makeFront") }
        var frontWasRestored: Bool { log.contains("restoreFront") }
    }

    private static func activation(
        available: Bool = true,
        secureInput: Bool = false,
        pid: pid_t? = 4242,
        active: Bool = false,
        hidden: Bool = false,
        saveCode: Int32 = 0,
        frontCode: Int32 = 0,
        spy: Spy
    ) -> SilentActivation {
        SilentActivation(
            available: { available },
            secureInputActive: { secureInput },
            runningPID: { spy.note("runningPID"); return pid },
            isActive: { spy.note("isActive"); return active },
            isHidden: { spy.note("isHidden"); return hidden },
            setHidden: { spy.note("setHidden"); spy.wroteHidden($0) },
            saveFront: { spy.note("saveFront"); return saveCode },
            makeFront: { _ in spy.note("makeFront"); return frontCode },
            restoreFront: { spy.note("restoreFront"); return 0 },
            sleep: { _ in spy.note("sleep") })
    }

    /// A password field owns the keyboard, so the 120ms window would send the
    /// user's typing somewhere they cannot see and macOS will not report.
    ///
    /// Mutation: move the `secureInputActive` guard below `makeFront(pid)`, or drop
    /// it — `frontWasTaken` becomes true and this fails.
    @Test func aSecureInputSessionIsRefusedWithoutTakingTheFront() async {
        let spy = Spy()
        let outcome = await Self.activation(secureInput: true, spy: spy).run()
        #expect(outcome == .refusedSecureInput)
        #expect(!spy.frontWasTaken)
    }

    /// A macOS that no longer exports the SkyLight symbols is an ordinary answer,
    /// not a failure — and nothing at all may be touched on the way to saying so.
    ///
    /// Mutation: return `.failed(code:)` instead of `.unavailable`, or move the
    /// `available()` guard below `saveFront()` — the outcome or the log changes.
    @Test func aMacWithoutTheSymbolsIsNotAFailureToReport() async {
        let spy = Spy()
        let outcome = await Self.activation(available: false, spy: spy).run()
        #expect(outcome == .unavailable)
        #expect(spy.log.isEmpty)
    }

    /// Mutation: move the `runningPID()` guard below `makeFront` — this fails,
    /// because there is no pid to front and the front would move for nothing.
    @Test func anAppThatIsNotRunningIsNeverFronted() async {
        let spy = Spy()
        let outcome = await Self.activation(pid: nil, spy: spy).run()
        #expect(outcome == .notRunning)
        #expect(!spy.frontWasTaken)
    }

    /// The front process is restored on the way out, always.
    ///
    /// Mutation: delete the `defer` block, or turn it into a plain trailing
    /// statement after an early `return` — `frontWasRestored` becomes false.
    @Test func theFrontProcessIsAlwaysRestored() async {
        let spy = Spy()
        let outcome = await Self.activation(spy: spy).run(hold: .milliseconds(1))
        #expect(outcome == .activated(heldFor: .milliseconds(1)))
        #expect(spy.frontWasRestored)
        // Ordering is the point: restore comes after the hold, not before it.
        #expect(spy.log.firstIndex(of: "makeFront")! < spy.log.firstIndex(of: "sleep")!)
        #expect(spy.log.firstIndex(of: "sleep")! < spy.log.firstIndex(of: "restoreFront")!)
    }

    /// An app the user had hidden goes back to hidden: activating unhides it, and
    /// that side effect appeared on one live trial and not on the other, so this
    /// covers a coin flip rather than a known behaviour.
    ///
    /// Mutation: drop the `if wasHidden { setHidden(true) }` line — `hiddenWrites`
    /// is empty and this fails.
    @Test func anAppThatWasHiddenIsHiddenAgain() async {
        let spy = Spy()
        _ = await Self.activation(hidden: true, spy: spy).run(hold: .milliseconds(1))
        #expect(spy.hiddenWrites == [true])
    }

    /// ...and an app the user had **open** is not hidden behind their back.
    ///
    /// Mutation: make the restore unconditional (`setHidden(true)` with no `if`) —
    /// `hiddenWrites` becomes `[true]` and this fails. This is the half that a
    /// single "state is restored" case would silently lose.
    @Test func anAppThatWasNotHiddenIsLeftAlone() async {
        let spy = Spy()
        _ = await Self.activation(hidden: false, spy: spy).run(hold: .milliseconds(1))
        #expect(spy.hiddenWrites.isEmpty)
    }

    /// Without a saved front process there is nothing to restore, so the front must
    /// not move at all — a "restore" that puts the user somewhere they did not
    /// choose is worse than never having activated.
    ///
    /// Mutation: ignore `saveFront()`'s return value — `frontWasTaken` becomes true.
    @Test func aFrontProcessThatCannotBeSavedIsNeverReplaced() async {
        let spy = Spy()
        let outcome = await Self.activation(saveCode: -1, spy: spy).run()
        #expect(outcome == .failed(code: -1))
        #expect(!spy.frontWasTaken)
    }

    /// A refused activation is reported with the code, and does not report a hold
    /// that never happened.
    ///
    /// Mutation: `_ = makeFront(pid)` — this returns `.activated` and fails.
    @Test func aRefusedActivationIsNotReportedAsAHold() async {
        let spy = Spy()
        let outcome = await Self.activation(frontCode: -600, spy: spy).run()
        #expect(outcome == .failed(code: -600))
        #expect(spy.log.last != "sleep")
    }

    /// Swapping the front process to the app that already holds it cannot fire the
    /// activation, so it is pure cost — and reporting it as a hold would claim a
    /// nudge that never landed. Measured 2026-09-10 with TestFlight frontmost: zero
    /// network connections, against 2 for the same call on a background instance.
    ///
    /// Mutation: drop the `isActive()` guard — the outcome becomes `.activated` and
    /// `frontWasTaken` becomes true; this fails on both.
    @Test func anAppThatIsAlreadyActiveIsLeftCompletelyAlone() async {
        let spy = Spy()
        let outcome = await Self.activation(active: true, spy: spy).run()
        #expect(outcome == .alreadyActive)
        #expect(!spy.frontWasTaken)
        #expect(spy.hiddenWrites.isEmpty)
    }

    /// The hold is a measured value, not a guess: 50ms produced a single store
    /// write where 120ms produced the full burst. A case pins it because the
    /// temptation to "just make it shorter" is exactly what the measurement
    /// forbids.
    ///
    /// Mutation: change `defaultHold` to 50ms — this fails and says why.
    @Test func theDefaultHoldIsTheMeasuredValue() {
        #expect(SilentActivation.defaultHold == .milliseconds(120))
    }
}
