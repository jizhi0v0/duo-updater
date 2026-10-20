import Testing
@testable import DuoUpdaterCore

/// Every CLI-tab click waits its turn, one run at a time (`CLIRunQueue`).
@MainActor @Suite struct CLIRunQueueTests {

    /// Held open until the test lets the run finish.
    @MainActor final class Hold {
        private var waiter: CheckedContinuation<Void, Never>?
        private var released = false
        private(set) var entered = false

        func wait() async {
            entered = true
            if released { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func release() {
            released = true
            waiter?.resume()
            waiter = nil
        }
    }

    /// What the runs did, as the test reads it after.
    @MainActor final class Record {
        var order: [String] = []
        var runs = 0
        var concurrent = 0
        var maxConcurrent = 0
    }

    func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("condition never became true")
    }

    /// Nothing running: the click runs at once, and the queue is empty after.
    @Test func aClickWithNothingRunningRunsAtOnce() async {
        let queue = CLIRunQueue<String>()
        let record = Record()
        let started = await queue.perform("a") { record.runs += 1 }
        #expect(started)
        #expect(record.runs == 1)
        #expect(queue.running == nil)
        #expect(queue.waiting.isEmpty)
    }

    /// Clicks behind a run wait, and run one at a time in the order made.
    ///
    /// Mutation: `advance` takes `waiting.removeLast()` → the order is c, b.
    @Test func clicksBehindARunWaitAndRunInOrder() async {
        let queue = CLIRunQueue<String>()
        let hold = Hold()
        let record = Record()
        let first = Task { @MainActor in await queue.perform("a") { record.order.append("a"); await hold.wait() } }
        await until { hold.entered }
        let second = Task { @MainActor in await queue.perform("b") { record.order.append("b") } }
        await until { queue.waiting == ["b"] }
        let third = Task { @MainActor in await queue.perform("c") { record.order.append("c") } }
        await until { queue.waiting == ["b", "c"] }
        #expect(queue.running == "a")
        #expect(record.order == ["a"])

        hold.release()
        _ = await (first.value, second.value, third.value)
        #expect(record.order == ["a", "b", "c"])
        #expect(queue.running == nil)
        #expect(queue.waiting.isEmpty)
    }

    /// The same click while it waits or runs is taken once.
    @Test func theSameClickTwiceIsTakenOnce() async {
        let queue = CLIRunQueue<String>()
        let hold = Hold()
        let record = Record()
        let first = Task { @MainActor in await queue.perform("a") { record.runs += 1; await hold.wait() } }
        await until { hold.entered }
        #expect(await queue.perform("a") { record.runs += 1 } == false)
        let waiting = Task { @MainActor in await queue.perform("b") {} }
        await until { queue.isWaiting("b") }
        #expect(await queue.perform("b") {} == false)
        #expect(queue.waiting == ["b"])

        hold.release()
        _ = await (first.value, waiting.value)
        #expect(record.runs == 1)
    }

    /// A waiting click taken back never runs, its caller returns at once, and
    /// the ones behind it move up.
    ///
    /// Mutation: `cancel` removes it from `waiting` without resuming its turn →
    /// its caller never returns, red. (Watched with `until`, not awaited: a
    /// case stuck awaiting is not ended by `.timeLimit`.)
    @Test func aCancelledClickNeverRuns() async {
        let queue = CLIRunQueue<String>()
        let hold = Hold()
        let record = Record()
        let first = Task { @MainActor in await queue.perform("a") { record.order.append("a"); await hold.wait() } }
        await until { hold.entered }
        var returned: Bool?
        Task { @MainActor in returned = await queue.perform("b") { record.order.append("b") } }
        let third = Task { @MainActor in await queue.perform("c") { record.order.append("c") } }
        await until { queue.waiting.count == 2 }

        #expect(queue.cancel("b"))
        await until { returned != nil }
        #expect(returned == false)
        #expect(queue.waiting == ["c"])

        hold.release()
        _ = await (first.value, third.value)
        #expect(record.order == ["a", "c"])
    }

    /// Only a waiting click can be taken back: not the running one, nor one
    /// never made.
    @Test func onlyAWaitingClickCanBeCancelled() async {
        let queue = CLIRunQueue<String>()
        let hold = Hold()
        let first = Task { @MainActor in await queue.perform("a") { await hold.wait() } }
        await until { hold.entered }
        #expect(!queue.cancel("a"))
        #expect(!queue.cancel("z"))
        #expect(queue.running == "a")
        hold.release()
        _ = await first.value
    }

    /// The turn passes straight to the next waiting click: a click made before
    /// that one's task has resumed queues behind it rather than starting.
    ///
    /// Mutation: `advance` leaves `running` nil for the next click to set →
    /// "late" starts alongside "b".
    @Test func aClickDuringTheHandOverQueuesBehind() async {
        let queue = CLIRunQueue<String>()
        let hold = Hold()
        let record = Record()
        @MainActor func body() async {
            record.concurrent += 1
            record.maxConcurrent = max(record.maxConcurrent, record.concurrent)
            await Task.yield()
            record.concurrent -= 1
        }
        var late: Task<Bool, Never>?
        // The late click is made at the very end of "a"'s run: its task is
        // enqueued before "a" hands the turn to "b", so it runs between that
        // hand-over and "b"'s task resuming.
        let first = Task { @MainActor in
            await queue.perform("a") {
                await hold.wait()
                late = Task { @MainActor in await queue.perform("late") { await body() } }
            }
        }
        await until { hold.entered }
        let second = Task { @MainActor in await queue.perform("b") { await body() } }
        await until { queue.isWaiting("b") }
        hold.release()
        _ = await (first.value, second.value)
        await until { late != nil }
        _ = await late?.value
        #expect(record.maxConcurrent == 1)
    }
}
