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
}

/// What a lane did with a trigger, as a test observes it (`RefreshLane.onEvent`).
/// The log says the same, with timings.
public enum RefreshLaneEvent: Sendable, Equatable {
    /// A pass was running: the trigger waits for it, then is decided.
    case joined(RefreshTrigger)
    case decided(RefreshTrigger, runs: Bool)
    /// A pass finished; these are the triggers it answered.
    case passFinished(answering: [RefreshTrigger])
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
/// - **Logged.** Every trigger's decision and every pass's duration, under
///   `refresh[<name>]` in the app category.
@MainActor
public final class RefreshLane<Plan: Sendable> {
    public let name: String
    private let decide: @MainActor (RefreshTrigger) async -> RefreshDecision<Plan>
    private let merge: @MainActor (Plan, Plan) -> Plan
    private let work: @MainActor (Plan) async -> Void
    private var running: Task<Void, Never>?
    /// Triggers not yet decided.
    private var queued: [RefreshTrigger] = []
    /// For tests.
    public var onEvent: (@MainActor (RefreshLaneEvent) -> Void)?

    public init(
        _ name: String,
        decide: @escaping @MainActor (RefreshTrigger) async -> RefreshDecision<Plan>,
        merge: @escaping @MainActor (Plan, Plan) -> Plan,
        work: @escaping @MainActor (Plan) async -> Void
    ) {
        self.name = name
        self.decide = decide
        self.merge = merge
        self.work = work
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
        let clock = ContinuousClock()
        let started = clock.now
        await work(plan)
        let took = Log.seconds(clock.now - started)
        let names = answering.map(\.description).joined(separator: ", ")
        Log.app.info("refresh[\(self.name, privacy: .public)] pass done in \(took, privacy: .public) (for \(names, privacy: .public))")
        onEvent?(.passFinished(answering: answering))
    }
}

extension RefreshLane where Plan == Void {
    /// A lane whose pass takes no plan: it runs, or it doesn't.
    public convenience init(
        _ name: String,
        decide: @escaping @MainActor (RefreshTrigger) async -> RefreshDecision<Void>,
        work: @escaping @MainActor () async -> Void
    ) {
        self.init(name, decide: decide, merge: { _, _ in () }, work: { _ in await work() })
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
