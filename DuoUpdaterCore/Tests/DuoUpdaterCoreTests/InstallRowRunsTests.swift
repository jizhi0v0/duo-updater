import Testing
@testable import DuoUpdaterCore

/// `InstallRowRuns`: a row's second run waits for its first to end, wrap-up
/// and all, and says it is waiting meanwhile.
@MainActor @Suite(.timeLimit(.minutes(1))) struct InstallRowRunsTests {

    @MainActor final class Flag { var value = false }

    /// The second run of one row starts only once the first has left, and is
    /// "waiting" until then; another row's run is not held up.
    /// Mutation: drop the `while running.contains(id)` wait in `enter` → the
    /// second run starts beside the first, red.
    @Test func aSecondRunOfARowWaitsForTheFirstToEnd() async {
        let runs = InstallRowRuns()
        await runs.enter("app")
        #expect(runs.isRunning("app"))

        let secondEntered = Flag()
        let second = Task { @MainActor in
            await runs.enter("app")
            secondEntered.value = true
        }
        while !runs.isWaiting("app") && !secondEntered.value { await Task.yield() }
        #expect(runs.isWaiting("app"))
        for _ in 0..<50 { await Task.yield() }
        #expect(!secondEntered.value, "the second run started while the first was still in flight")

        // Another row is not held up by this one.
        await runs.enter("other")
        runs.leave("other")

        runs.leave("app")
        await second.value
        #expect(secondEntered.value)
        #expect(!runs.isWaiting("app"))
        #expect(runs.isRunning("app"))
        runs.leave("app")
        #expect(!runs.isRunning("app"))
    }

    /// A run with nothing in flight before it starts at once and never reads
    /// as waiting.
    @Test func aFirstRunStartsAtOnce() async {
        let runs = InstallRowRuns()
        #expect(!runs.isRunning("app"))
        await runs.enter("app")
        #expect(!runs.isWaiting("app"))
        runs.leave("app")
        #expect(!runs.isRunning("app"))
    }
}
