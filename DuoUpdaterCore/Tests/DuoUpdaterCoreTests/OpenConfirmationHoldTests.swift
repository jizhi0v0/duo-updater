import Testing
@testable import DuoUpdaterCore

/// `OpenConfirmationHold` — an app held at macOS's first-open prompt reads as
/// not finished launching AND owning no window (measured 2026-10-22). Either
/// signal alone misreads normal apps: ImageOptim had a window before it
/// finished launching, and a hidden or windowless app has none at all.
@Suite struct OpenConfirmationHoldTests {

    /// Mutation: drop either condition → one of the last three goes red.
    @Test func heldOnlyWhenNotFinishedAndWindowless() {
        #expect(OpenConfirmationHold.isHeld(finishedLaunching: false, windows: 0))
        #expect(!OpenConfirmationHold.isHeld(finishedLaunching: true, windows: 0))
        #expect(!OpenConfirmationHold.isHeld(finishedLaunching: false, windows: 1))
        #expect(!OpenConfirmationHold.isHeld(finishedLaunching: true, windows: 7))
    }

    /// One held instance stops the restart: its quit would reach that one too.
    @Test func anyHeldInstanceCounts() {
        let held = OpenConfirmationHold.Reading(finishedLaunching: false, windows: 0)
        let up = OpenConfirmationHold.Reading(finishedLaunching: true, windows: 3)
        #expect(OpenConfirmationHold.anyHeld([up, held]))
        #expect(!OpenConfirmationHold.anyHeld([up, up]))
        #expect(!OpenConfirmationHold.anyHeld([OpenConfirmationHold.Reading]()))
    }
}
