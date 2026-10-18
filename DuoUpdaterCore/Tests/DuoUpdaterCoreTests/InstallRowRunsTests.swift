import Testing
@testable import DuoUpdaterCore

/// `InstallRowRuns`: a row's later claim waits for its earlier run to end,
/// wrap-up and all, and owns the row's Cancel from the moment it is made.
@MainActor @Suite(.timeLimit(.minutes(1))) struct InstallRowRunsTests {

    @MainActor final class Flag { var value = false }

    /// A claim made while an earlier run is in flight is behind it at once —
    /// before its own run gets to `enter`, which is the window a batch target
    /// spends between being started and its task running — and starts only
    /// once the earlier run has left. Another row is not held up.
    /// Mutations: `isBehindAnEarlierRun` always false → red at the first
    /// check; drop the `while running[id] != nil` wait in `enter` → the second
    /// run starts beside the first, red.
    @Test func aLaterClaimIsBehindTheEarlierRunUntilItEnds() async {
        let runs = InstallRowRuns()
        let first = runs.claim("app")
        await runs.enter("app", first)
        #expect(!runs.isBehindAnEarlierRun("app"))

        let second = runs.claim("app")
        #expect(runs.isBehindAnEarlierRun("app"))
        #expect(!runs.isLatest("app", first))
        #expect(runs.isLatest("app", second))

        let secondEntered = Flag()
        let task = Task { @MainActor in
            await runs.enter("app", second)
            secondEntered.value = true
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(!secondEntered.value, "the second run started while the first was still in flight")
        #expect(runs.isBehindAnEarlierRun("app"))

        let other = runs.claim("other")
        await runs.enter("other", other)
        #expect(!runs.isBehindAnEarlierRun("other"))
        runs.leave("other", other)

        runs.leave("app", first)
        await task.value
        #expect(secondEntered.value)
        #expect(!runs.isBehindAnEarlierRun("app"))
        runs.leave("app", second)
    }

    /// A claim that never runs — a batch target taken off the queue — leaves
    /// nothing in flight: the next claim starts at once. A `leave` for a claim
    /// that is not the one in flight changes nothing.
    @Test func aClaimThatNeverRanHoldsNothingUp() async {
        let runs = InstallRowRuns()
        _ = runs.claim("app")
        #expect(!runs.isBehindAnEarlierRun("app"))
        let next = runs.claim("app")
        await runs.enter("app", next)
        let stray = runs.claim("app")
        runs.leave("app", stray)
        #expect(runs.isBehindAnEarlierRun("app"))
        runs.leave("app", next)
        #expect(!runs.isBehindAnEarlierRun("app"))
    }
}
