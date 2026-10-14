import Foundation

/// Something that happened which may call for a refresh. Callers say only this;
/// whether anything runs is each lane's call (`RefreshLane`).
///
/// Every lane's policy switches over it with no `default`, so a new case does
/// not compile until every lane has said what it does on it.
public enum RefreshTrigger: Sendable, Equatable, CustomStringConvertible {
    case popoverOpen
    case workbenchOpen
    /// The workbench became key again.
    case workbenchFocus
    /// A tick of the background schedule. `interval` is the user's check
    /// interval; nil is "Only when I check".
    case backgroundTick(interval: TimeInterval?)
    /// One of our own actions changed what a lane reads: a `brew upgrade`, a
    /// `brew update`. Named for the log.
    case afterAction(String)

    public var description: String {
        switch self {
        case .popoverOpen: return "popover open"
        case .workbenchOpen: return "workbench open"
        case .workbenchFocus: return "workbench focus"
        case .backgroundTick(let interval):
            return interval.map { "background tick (every \(Int($0))s)" } ?? "background tick (manual)"
        case .afterAction(let action): return "after \(action)"
        }
    }
}

/// A lane's answer to a trigger: run, with what (`Plan`) and why, or not, and why.
/// The why is for the log, which is what tuning reads.
public enum RefreshDecision<Plan: Sendable>: Sendable {
    case run(Plan, because: String)
    case skip(because: String)

    public var runs: Bool {
        if case .run = self { return true }
        return false
    }
}

/// What a lane did with a trigger, as a test observes it (`RefreshLane.onEvent`).
/// The log says the same, with timings.
public enum RefreshLaneEvent: Sendable, Equatable {
    /// A pass was running: the trigger waits for it, then is decided.
    case joined(RefreshTrigger)
    case decided(RefreshTrigger, runs: Bool)
    /// A pass finished; these are the triggers it answered.
    case passFinished(answering: [RefreshTrigger])
    /// A pass ran past `passTimeout`: the lane stopped waiting for it and went
    /// on to the triggers after it. The pass itself was left to finish.
    case passTimedOut(answering: [RefreshTrigger])
}

/// One thing the app refreshes (the brew package list, the CLI tools' checks…),
/// with its own policy and one pass at a time.
///
/// - **Policy.** `decide` answers each trigger, from the lane's own state: run
///   (and with what) or skip. It lives with the thing refreshed, not with the
///   callers, because callers multiply (each new window, button and event) and
///   a guard repeated at each of them is the one a new caller forgets.
/// - **One pass at a time.** A trigger that arrives while a pass runs waits for
///   it, and is decided after it — against the state that pass left. A burst of
///   triggers during a pass is decided together and costs at most one more
///   pass (their plans merged with `merge`). A caller returns once its trigger
///   was decided and, if it ran, its pass finished: one that has just changed
///   what the lane reads (a `brew upgrade`) is never answered by a pass that
///   began before the change.
/// - **Not the caller's task.** Decisions and passes run in a task of the
///   lane's own. A caller cancelled midway — a SwiftUI `.task` whose popover
///   closed — neither cancels the pass others wait on nor lands its
///   cancellation as the refreshed thing's answer (2026-10-14: a cancelled CLI
///   check put "Couldn't reach … release channel" on 26 tools).
/// - **Never stuck.** A pass still running after `passTimeout` (60 s) is no
///   longer waited for: the lane logs it and goes on to the triggers queued
///   behind it. A provider whose request or child process hangs without a
///   deadline of its own would otherwise hold every later trigger for the rest
///   of the session. The late pass is not cancelled — a cancelled read lands
///   its failures as answers, the bug above — so it may overlap the next one;
///   each lane's work guards its own state against a pass that started
///   earlier landing later (the generation counters).
/// - **Logged.** Every trigger's decision and every pass's duration, under
///   `refresh[<name>]` in the app category.
@MainActor
public final class RefreshLane<Plan: Sendable> {
    public let name: String
    private let decide: @MainActor (RefreshTrigger) async -> RefreshDecision<Plan>
    private let merge: @MainActor (Plan, Plan) -> Plan
    private let work: @MainActor (Plan) async -> Void
    private let passTimeout: Duration
    private let clock: @MainActor () -> ContinuousClock.Instant
    private var running: Task<Void, Never>?
    /// When the last pass's work finished, late ones included.
    private var lastPassFinished: ContinuousClock.Instant?
    /// Triggers not yet decided.
    private var queued: [RefreshTrigger] = []
    /// For tests.
    public var onEvent: (@MainActor (RefreshLaneEvent) -> Void)?

    /// How long a pass is waited for before the lane goes on without it.
    public static var defaultPassTimeout: Duration { .seconds(60) }

    /// `passTimeout` and `clock` are injected so tests need not wait out a minute.
    public init(
        _ name: String,
        passTimeout: Duration = RefreshLane.defaultPassTimeout,
        clock: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        decide: @escaping @MainActor (RefreshTrigger) async -> RefreshDecision<Plan>,
        merge: @escaping @MainActor (Plan, Plan) -> Plan,
        work: @escaping @MainActor (Plan) async -> Void
    ) {
        self.name = name
        self.passTimeout = passTimeout
        self.clock = clock
        self.decide = decide
        self.merge = merge
        self.work = work
    }

    /// How long ago the last pass's work finished, or nil before the first.
    /// For a policy that spaces its passes out (`AppListModel.brewDecision`).
    public var sinceLastPass: Duration? {
        lastPassFinished.map { clock() - $0 }
    }

    /// Whether a pass, or the decisions before one, is under way.
    public var isRunning: Bool { running != nil }

    /// Have the lane decide `trigger`, and run a pass if it says so. Returns
    /// once that is done.
    public func handle(_ trigger: RefreshTrigger) async {
        queued.append(trigger)
        if let running {
            Log.app.info("refresh[\(self.name, privacy: .public)] \(trigger.description, privacy: .public) → joins the pass in flight")
            onEvent?(.joined(trigger))
            await running.value
            return
        }
        let task = Task { @MainActor in
            while !queued.isEmpty {
                await pass()
            }
            // Cleared inside the task, before `value` resolves, and with no
            // await since the last `queued` check: a trigger can neither find a
            // finished task here nor slip in between the check and this line.
            running = nil
        }
        running = task
        await task.value
    }

    /// Decide every queued trigger, then run their merged plan if any said run.
    private func pass() async {
        let triggers = queued
        queued = []
        var plan: Plan?
        var answering: [RefreshTrigger] = []
        for trigger in triggers {
            switch await decide(trigger) {
            case .skip(let why):
                Log.app.info("refresh[\(self.name, privacy: .public)] \(trigger.description, privacy: .public) → skip: \(why, privacy: .public)")
                onEvent?(.decided(trigger, runs: false))
            case .run(let next, let why):
                Log.app.info("refresh[\(self.name, privacy: .public)] \(trigger.description, privacy: .public) → run: \(why, privacy: .public)")
                onEvent?(.decided(trigger, runs: true))
                plan = plan.map { merge($0, next) } ?? next
                answering.append(trigger)
            }
        }
        guard let plan else { return }
        let started = clock()
        let names = answering.map(\.description).joined(separator: ", ")
        let pass = Task { @MainActor in
            await work(plan)
            lastPassFinished = clock()
        }
        if await Self.finishes(pass, within: passTimeout) {
            let took = Log.seconds(clock() - started)
            Log.app.info("refresh[\(self.name, privacy: .public)] pass done in \(took, privacy: .public) (for \(names, privacy: .public))")
            onEvent?(.passFinished(answering: answering))
            return
        }
        let limit = Log.seconds(passTimeout)
        Log.app.error("refresh[\(self.name, privacy: .public)] pass still running after \(limit, privacy: .public) (for \(names, privacy: .public)) — no longer waited for; later triggers go ahead")
        onEvent?(.passTimedOut(answering: answering))
        Task { @MainActor in
            await pass.value
            let took = Log.seconds(clock() - started)
            Log.app.notice("refresh[\(self.name, privacy: .public)] late pass finished after \(took, privacy: .public) (for \(names, privacy: .public))")
        }
    }

    /// Whether `pass` finishes within `timeout`. Neither outcome cancels it.
    /// A continuation rather than a task group: a group waits for every child
    /// at its end, and a child awaiting `pass.value` does not stop for
    /// cancellation, so it would wait out the hung pass after all.
    private static func finishes(_ pass: Task<Void, Never>, within timeout: Duration) async -> Bool {
        await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
            var answered = false
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !answered, !Task.isCancelled else { return }
                answered = true
                answer.resume(returning: false)
            }
            Task { @MainActor in
                await pass.value
                deadline.cancel()
                guard !answered else { return }
                answered = true
                answer.resume(returning: true)
            }
        }
    }
}

extension RefreshLane where Plan == Void {
    /// A lane whose pass takes no plan: it runs, or it doesn't.
    public convenience init(
        _ name: String,
        passTimeout: Duration = RefreshLane.defaultPassTimeout,
        clock: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        decide: @escaping @MainActor (RefreshTrigger) async -> RefreshDecision<Void>,
        work: @escaping @MainActor () async -> Void
    ) {
        self.init(name, passTimeout: passTimeout, clock: clock,
                  decide: decide, merge: { _, _ in () }, work: { _ in await work() })
    }
}

/// A lane as `RefreshLanes` holds it, whatever its plan.
@MainActor
public protocol RefreshHandling: AnyObject, Sendable {
    func handle(_ trigger: RefreshTrigger) async
}

extension RefreshLane: RefreshHandling {}

/// The lanes a trigger from the UI goes to. A view says what happened
/// (`handle(.popoverOpen)`); every lane decides for itself, all at once.
@MainActor
public final class RefreshLanes {
    private var lanes: [any RefreshHandling] = []

    public init() {}

    public func add(_ lane: any RefreshHandling) {
        lanes.append(lane)
    }

    /// Hand `trigger` to every lane, and return when every one has dealt with it.
    public func handle(_ trigger: RefreshTrigger) async {
        await withTaskGroup(of: Void.self) { group in
            for lane in lanes {
                group.addTask { await lane.handle(trigger) }
            }
        }
    }
}
