import Foundation

/// When a button slot that just swapped its control takes clicks again.
///
/// Update and its Cancel share one slot: a click on Update puts the Cancel
/// where the pointer is, live from its first frame, and a click on Cancel can
/// put Update back as fast. A double-click's second click then lands on the
/// control the first one put there. Both seen on the dev Mac (2026-10-20,
/// HID double-clicks 120–200 ms apart): Update All then Cancel All on the
/// batch just started, 113 ms later; and a row's Cancel, whose job ended
/// 0.05 s after the click, then its Update again, restarting the download.
///
/// So for one double-click interval after the slot's occupant changes, the
/// slot swallows clicks. The first occupant seen arms nothing: a row scrolled
/// into view, or a popover opened on a running install, was not swapped under
/// the pointer, and a quick click on it is meant.
public struct SlotSwapClickGuard<Occupant: Equatable & Sendable>: Sendable {
    public typealias Instant = ContinuousClock.Instant

    private var occupant: Occupant?
    /// Until when clicks are swallowed; nil before the first swap.
    public private(set) var swallowsUntil: Instant?

    public init() {}

    /// The slot holds `occupant` at `now`. A change from the one seen last
    /// swallows clicks until `interval` from now — the system's double-click
    /// interval, "the time in which a second click must occur in order to be
    /// considered a doubleClick" (`NSEvent.doubleClickInterval`, AppKit's
    /// NSEvent.h).
    public mutating func observe(_ occupant: Occupant, now: Instant, interval: Duration) {
        defer { self.occupant = occupant }
        guard let previous = self.occupant, previous != occupant else { return }
        swallowsUntil = now + interval
    }

    /// Whether a click at `now` is swallowed.
    public func swallows(at now: Instant) -> Bool {
        guard let swallowsUntil else { return false }
        return now < swallowsUntil
    }
}
