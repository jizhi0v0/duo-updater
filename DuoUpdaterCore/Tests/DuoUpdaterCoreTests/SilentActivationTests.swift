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
        private var restoreCalls = 0
        func nextRestoreCode(_ codes: [Int32]) -> Int32 {
            lock.lock(); defer { lock.unlock() }
            defer { restoreCalls += 1 }
            return restoreCalls < codes.count ? codes[restoreCalls] : codes.last ?? 0
        }
        var restoreAttempts: Int { log.filter { $0 == "restoreFront" }.count }
        var saveAttempts: Int { log.filter { $0 == "saveFront" }.count }
        var frontWasTaken: Bool { log.contains("makeFront") }
        var frontWasRestored: Bool { log.contains("restoreFront") }
    }

    private static func activation(
        available: Bool = true,
        secureInput: Bool = false,
        pid: pid_t? = 4242,
        active: Bool = false,
        hidden: Bool = false,
        saveFails: Int32? = nil,
        restoreCodes: [Int32] = [0],
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
            saveFront: {
                spy.note("saveFront")
                if let saveFails { return .unreadable(code: saveFails) }
                return .saved(SilentActivation.FrontProcess(hi: 0, lo: 99))
            },
            makeFront: { _ in spy.note("makeFront"); return frontCode },
            restoreFront: { front in
                spy.note("restoreFront")
                #expect(front == SilentActivation.FrontProcess(hi: 0, lo: 99))
                return spy.nextRestoreCode(restoreCodes)
            },
            sleep: { _ in spy.note("sleep") },
            // Inline rather than a real Dispatch hop: the cases assert on ordering,
            // and production's hop is pinned separately by `theProductionHopIsOffPool`.
            offPool: { work in work() })
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
        // Optional-compared rather than force-unwrapped, so a mutation that removes
        // one of these fails the case instead of trapping and killing the run.
        let order = ["makeFront", "sleep", "restoreFront"].map { spy.log.firstIndex(of: $0) }
        #expect(order.allSatisfy { $0 != nil })
        #expect(order == order.compactMap { $0 }.sorted().map { Optional($0) })
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
        let outcome = await Self.activation(saveFails: -1, spy: spy).run()
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

    /// A failed restore is retried once and then reported. Leaving someone's focus
    /// where they did not put it is the worst thing this type can do, so it is the
    /// one failure that must not be folded into the success case.
    ///
    /// Mutation: write `_ = restoreFront(previousFront)` and return `.activated`
    /// unconditionally (the shape this file shipped with first) — the outcome and
    /// the retry count both change, and this fails on both.
    @Test func aFailedRestoreIsRetriedAndThenReported() async {
        let spy = Spy()
        let outcome = await Self.activation(restoreCodes: [-1, -1], spy: spy)
            .run(hold: .milliseconds(1))
        #expect(outcome == .frontNotRestored(code: -1))
        #expect(spy.restoreAttempts == 2)
    }

    /// ...and a restore that succeeds on the retry is an ordinary success, not a
    /// reported failure.
    ///
    /// Mutation: drop the retry — the outcome becomes `.frontNotRestored` and this
    /// fails. Without this case the retry could be deleted and the suite stay green.
    @Test func aRestoreThatSucceedsOnTheRetryIsStillASuccess() async {
        let spy = Spy()
        let outcome = await Self.activation(restoreCodes: [-1, 0], spy: spy)
            .run(hold: .milliseconds(1))
        #expect(outcome == .activated(heldFor: .milliseconds(1)))
        #expect(spy.restoreAttempts == 2)
    }

    /// The front process is read **once**. The first version of this asked twice —
    /// once in the `guard`, once in its `else` — so a transient failure followed by a
    /// success returned `.failed(code: -1)`, a code the API never produced, and threw
    /// away a perfectly good snapshot.
    ///
    /// ⚠️ This case exists because the *mutation was run and nothing went red*: every
    /// other case stubs `saveFront` as a constant, so the correct implementation and
    /// the double-reading one give identical answers for every input. Counting the
    /// calls is the only thing that separates them.
    ///
    /// Mutation: read `saveFront()` a second time in the failure path — `saveAttempts`
    /// becomes 2 and this fails.
    @Test func theFrontProcessIsReadExactlyOnce() async {
        for failing in [true, false] {
            let spy = Spy()
            _ = await Self.activation(saveFails: failing ? -1 : nil, spy: spy)
                .run(hold: .milliseconds(1))
            #expect(spy.saveAttempts == 1)
        }
    }

    /// A `makeFront` that reports failure still gets a restore. A non-zero return
    /// from a symbol with no contract is not evidence that nothing moved, and that
    /// is the one premise whose failure costs the user their focus silently.
    ///
    /// Mutation: return `.refused(.failed(code:))` without the `restoreFront` /
    /// `setHidden` pair — `restoreAttempts` drops to 0 and this fails.
    @Test func aFrontChangeThatReportedFailureIsStillPutBack() async {
        let spy = Spy()
        let outcome = await Self.activation(hidden: true, frontCode: -600, spy: spy).run()
        #expect(outcome == .failed(code: -600))
        #expect(spy.restoreAttempts == 1)
        #expect(spy.hiddenWrites == [true])
    }

    /// The three symbols really do resolve on a Mac. Everything else in this file
    /// stubs `Live` out entirely, so without this the whole live side — the dlopen,
    /// the three dlsym names, `GetProcessForPID` coming from the `import Carbon`
    /// rather than an explicit handle — could be replaced with `return 0` and the
    /// suite would stay green.
    ///
    /// ⚠️ Vacuity: this asserts the symbols exist, not that they do anything. It is a
    /// smoke test for the resolution step, and it is expected to start failing on
    /// some future macOS — that failure is the signal, and the product degrades to
    /// `.unavailable` rather than misbehaving.
    @Test func theLiveSymbolsResolveOnThisMac() {
        #expect(SilentActivation.Live.available())
    }

    /// Production must hop off the cooperative pool: `dlopen`, XPC to LaunchServices,
    /// and Mach IPC to the WindowServer all block, and this repository has already
    /// lost a whole test process to blocking that pool.
    ///
    /// Mutation: change the default to `{ work in work() }` — this fails. Pinned in
    /// the source text because the default closure is otherwise opaque.
    @Test func theProductionHopIsOffPool() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/DuoUpdaterCore/Support/SilentActivation.swift"),
            encoding: .utf8)
        #expect(source.contains("try? await offCooperativePool { work() }"))
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
