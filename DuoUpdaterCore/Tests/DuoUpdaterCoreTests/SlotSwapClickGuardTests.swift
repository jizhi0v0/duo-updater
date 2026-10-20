import Foundation
import Testing
@testable import DuoUpdaterCore

/// `SlotSwapClickGuard`: a slot whose Update just became Cancel (or back)
/// swallows the rest of the double-click that swapped it.
@Suite struct SlotSwapClickGuardTests {

    private enum Slot: Equatable, Sendable { case update, cancel }
    private let t0 = ContinuousClock.now
    private func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }
    private let interval = Duration.milliseconds(500)

    /// Update → Cancel: a second click inside the interval is swallowed, one
    /// at its end is taken.
    ///
    /// Mutation: never arm in `observe` → the first expectation is red.
    @Test func theSecondClickOfTheDoubleClickThatSwappedTheSlotIsSwallowed() {
        var guardrail = SlotSwapClickGuard<Slot>()
        guardrail.observe(.update, now: at(0), interval: interval)
        guardrail.observe(.cancel, now: at(1000), interval: interval)
        #expect(guardrail.swallows(at: at(1150)))
        #expect(guardrail.swallows(at: at(1499)))
        #expect(!guardrail.swallows(at: at(1500)))
        #expect(!guardrail.swallows(at: at(2000)))
    }

    /// Cancel → Update, a cancel answered before its install started: the same.
    @Test func theReverseSwapIsGuardedToo() {
        var guardrail = SlotSwapClickGuard<Slot>()
        guardrail.observe(.cancel, now: at(0), interval: interval)
        guardrail.observe(.update, now: at(40), interval: interval)
        #expect(guardrail.swallows(at: at(200)))
        #expect(!guardrail.swallows(at: at(540)))
    }

    /// The first occupant seen — a row scrolled into view, a popover opened —
    /// was not swapped under the pointer: a quick click on it is taken.
    ///
    /// Mutation: arm on the first observation → red.
    @Test func theFirstOccupantSeenArmsNothing() {
        var guardrail = SlotSwapClickGuard<Slot>()
        guardrail.observe(.cancel, now: at(0), interval: interval)
        #expect(!guardrail.swallows(at: at(10)))
        #expect(guardrail.swallowsUntil == nil)
    }

    /// Seeing the same occupant again — a redraw, a progress tick — neither
    /// arms nor extends the window.
    ///
    /// Mutation: arm on every observation → red.
    @Test func theSameOccupantAgainChangesNothing() {
        var guardrail = SlotSwapClickGuard<Slot>()
        guardrail.observe(.update, now: at(0), interval: interval)
        guardrail.observe(.update, now: at(100), interval: interval)
        #expect(!guardrail.swallows(at: at(150)))

        guardrail.observe(.cancel, now: at(1000), interval: interval)
        guardrail.observe(.cancel, now: at(1400), interval: interval)
        #expect(guardrail.swallowsUntil == at(1500))
    }

    /// A swap inside the window starts it again from the latest swap: Cancel
    /// answered at once puts Update back, and that Update is new under the
    /// pointer too.
    @Test func aSwapInsideTheWindowRestartsIt() {
        var guardrail = SlotSwapClickGuard<Slot>()
        guardrail.observe(.update, now: at(0), interval: interval)
        guardrail.observe(.cancel, now: at(100), interval: interval)
        guardrail.observe(.update, now: at(400), interval: interval)
        #expect(guardrail.swallows(at: at(800)))
        #expect(!guardrail.swallows(at: at(900)))
    }
}
