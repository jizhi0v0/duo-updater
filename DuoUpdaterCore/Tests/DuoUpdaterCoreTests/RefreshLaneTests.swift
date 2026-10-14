import Testing
import Foundation
@testable import DuoUpdaterCore

/// `RefreshLane`: each trigger decided by the lane's own policy, one pass at a
/// time, triggers that arrive during a pass decided after it. Each case names
/// the mutation it fails under; each was applied and watched go red.
@MainActor
struct RefreshLaneTests {

    /// Suspends callers until opened. Counts arrivals, so a test can wait for the
    /// code under test to reach it.
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var arrived = 0

        func wait() async {
            arrived += 1
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    /// What the lane did, in order.
    final class Record: @unchecked Sendable {
        var plans: [Set<String>] = []
        var events: [String] = []
        var laneEvents: [RefreshLaneEvent] = []
        var cancelledInPass: [Bool] = []
        /// What `decide` answers for a trigger; run by default.
        var skip: Set<String> = []
    }

    /// Poll until `condition` holds. The deadline only turns a hang into a failure.
    func until(_ condition: () async -> Bool) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("condition never became true")
    }

    /// A settable clock for `sinceLastPass`.
    final class Clock: @unchecked Sendable {
        var now = ContinuousClock.now
    }

    /// A lane whose plan is the set of triggers that said run, and whose first
    /// pass waits at `first`.
    func lane(_ record: Record, first: Gate, passTimeout: Duration = .seconds(60),
              clock: Clock? = nil) -> RefreshLane<Set<String>> {
        let lane = RefreshLane<Set<String>>(
            "test",
            passTimeout: passTimeout,
            clock: { clock?.now ?? ContinuousClock.now },
            decide: { trigger in
                record.skip.contains(trigger.description)
                    ? .skip(because: "told to") : .run([trigger.description], because: "told to")
            },
            merge: { $0.union($1) },
            work: { plan in
                record.plans.append(plan)
                let n = record.plans.count
                record.events.append("pass \(n) start")
                if n == 1 { await first.wait() }
                record.cancelledInPass.append(Task.isCancelled)
                record.events.append("pass \(n) end")
            })
        lane.onEvent = { record.laneEvents.append($0) }
        return lane
    }

    /// Triggers arriving during a pass are decided after it, together, and
    /// their plans merged into one more pass — five opens cost two passes.
    ///
    /// Mutations: `pass()` taking one trigger instead of the whole queue — one
    /// pass per trigger; `running` never cleared — the lane never goes idle.
    @Test func triggersDuringAPassShareOneMorePass() async {
        let record = Record()
        let gate = Gate()
        let lane = lane(record, first: gate)

        let first = Task { await lane.handle(.workbenchOpen) }
        await until { await gate.arrived == 1 }
        let burst = [Task { await lane.handle(.popoverOpen) },
                     Task { await lane.handle(.workbenchFocus) },
                     Task { await lane.handle(.popoverOpen) }]
        // Let the three reach the lane while pass 1 still waits.
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await first.value
        for request in burst { await request.value }

        #expect(record.plans == [["workbench open"], ["popover open", "workbench focus"]])
        #expect(!lane.isRunning)
    }

    /// A trigger that joins a running pass returns only after it was decided
    /// and its own pass finished — never on the earlier pass, which began before
    /// it (and before whatever change its caller made).
    ///
    /// Mutations: a joining trigger returning without awaiting the running
    /// task; a joining trigger starting a pass of its own (no `running` check).
    @Test func aJoiningTriggerWaitsForItsOwnPass() async {
        let record = Record()
        let gate = Gate()
        let lane = lane(record, first: gate)

        let first = Task { await lane.handle(.workbenchOpen) }
        await until { await gate.arrived == 1 }
        let joined = Task {
            await lane.handle(.afterAction("brew upgrade"))
            record.events.append("joined returned")
        }
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await joined.value
        await first.value

        #expect(record.events == ["pass 1 start", "pass 1 end", "pass 2 start", "pass 2 end", "joined returned"])
    }

    /// A trigger its policy skips runs no pass; when every trigger of a burst
    /// is skipped, no second pass runs at all.
    ///
    /// Mutation: a skipped trigger reported as run (`runs: false` → `true`).
    @Test func aSkippedTriggerRunsNothing() async {
        let record = Record()
        record.skip = ["popover open"]
        let gate = Gate()
        let lane = lane(record, first: gate)

        let first = Task { await lane.handle(.workbenchOpen) }
        await until { await gate.arrived == 1 }
        let skipped = Task { await lane.handle(.popoverOpen) }
        try? await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await first.value
        await skipped.value

        #expect(record.plans == [["workbench open"]])
        #expect(record.laneEvents == [
            .decided(.workbenchOpen, runs: true),
            .joined(.popoverOpen),
            .passFinished(answering: [.workbenchOpen]),
            .decided(.popoverOpen, runs: false),
        ])
    }

    /// Cancelling the caller that started a pass — the popover closing under its
    /// `.task` — does not cancel the pass.
    ///
    /// Mutation: forwarding the caller's cancellation into the lane's task
    /// (`withTaskCancellationHandler { … } onCancel: { task.cancel() }`).
    @Test func cancellingTheCallerDoesNotCancelThePass() async {
        let record = Record()
        let gate = Gate()
        let lane = lane(record, first: gate)

        let caller = Task { await lane.handle(.popoverOpen) }
        await until { await gate.arrived == 1 }
        caller.cancel()
        await gate.open()
        await caller.value

        #expect(record.cancelledInPass == [false])
    }

    /// Triggers that do not overlap are each decided and run: the lane collapses
    /// triggers in flight; it is not a cache.
    ///
    /// Mutation: `running` never cleared — the second trigger joins a finished
    /// task and returns with nothing decided.
    @Test func triggersThatDoNotOverlapEachRun() async {
        let record = Record()
        let gate = Gate()
        await gate.open()
        let lane = lane(record, first: gate)

        await lane.handle(.popoverOpen)
        await lane.handle(.popoverOpen)

        #expect(record.plans == [["popover open"], ["popover open"]])
    }

    /// A pass still running after `passTimeout` no longer holds the lane: its
    /// caller returns, and the next trigger runs a pass of its own while the
    /// hung one is left to finish — not cancelled.
    ///
    /// Mutation: `finishes(_:within:)` awaiting the pass with no deadline.
    @Test func aHungPassDoesNotHoldLaterTriggers() async {
        let record = Record()
        let hung = Gate()
        let lane = lane(record, first: hung, passTimeout: .milliseconds(50))

        let first = Task { await lane.handle(.popoverOpen) }
        await until { record.laneEvents.contains(.passTimedOut(answering: [.popoverOpen])) }
        // Without a deadline the first caller would wait on the gate for good:
        // open it, so the test fails instead of hanging.
        if !record.laneEvents.contains(.passTimedOut(answering: [.popoverOpen])) { await hung.open() }
        await first.value
        await lane.handle(.workbenchFocus)

        #expect(record.plans == [["popover open"], ["workbench focus"]])
        #expect(record.events == ["pass 1 start", "pass 2 start", "pass 2 end"])
        await hung.open()
        await until { record.events.count == 4 }
        #expect(record.cancelledInPass == [false, false])
    }

    /// `sinceLastPass` counts from when the last pass's work finished — what a
    /// policy that spaces passes out reads (brew's ten seconds).
    ///
    /// Mutation: `lastPassFinished` never set.
    @Test func sinceLastPassCountsFromTheEndOfTheLastPass() async {
        let record = Record()
        let open = Gate()
        await open.open()
        let clock = Clock()
        let lane = lane(record, first: open, clock: clock)
        #expect(lane.sinceLastPass == nil)

        await lane.handle(.popoverOpen)
        clock.now += .seconds(7)

        #expect(lane.sinceLastPass == .seconds(7))
    }

    /// `handle(_:waitingFor:)` hands the trigger to every lane but returns as
    /// soon as the one named has dealt with it, the others still running.
    ///
    /// Mutations: waiting for every lane; not handing the trigger to the others.
    @Test func lanesCanWaitForOneLaneOnly() async {
        let fast = Record(), slow = Record()
        let open = Gate(), held = Gate()
        await open.open()
        let lanes = RefreshLanes()
        let awaited = lane(fast, first: open)
        lanes.add(awaited)
        lanes.add(lane(slow, first: held))

        let call = Task { await lanes.handle(.workbenchOpen, waitingFor: awaited) }
        await until { await held.arrived == 1 }
        await until { fast.plans.count == 1 && !awaited.isRunning }
        // Bounded so a wrong implementation fails rather than hangs: the call must
        // already be done while `slow`'s pass still waits at its gate.
        let returned = Task { await call.value; return true }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(slow.events == ["pass 1 start"])
        await held.open()
        #expect(await returned.value)
        await until { slow.events.count == 2 }
    }

    /// `RefreshLanes` hands a trigger to every lane added, and returns when all
    /// of them have dealt with it.
    ///
    /// Mutation: `handle` returning before the group's tasks finish (tasks
    /// started unstructured, not awaited).
    @Test func lanesHandEveryLaneTheTrigger() async {
        let a = Record(), b = Record()
        let open = Gate()
        await open.open()
        let lanes = RefreshLanes()
        lanes.add(lane(a, first: open))
        lanes.add(lane(b, first: open))

        await lanes.handle(.workbenchFocus)

        #expect(a.plans == [["workbench focus"]])
        #expect(b.plans == [["workbench focus"]])
    }
}
