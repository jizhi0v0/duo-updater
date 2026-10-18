import Foundation

/// The installs this process is running, by id (an app's or a CLI tool's), and
/// where each one stands relative to its point of no return.
///
/// Per process, not across processes: the menu-bar app and `duo` each keep
/// their own. A host registers a job with a closure that cancels its task, and
/// runs the job with `currentID` bound to its id; `InstallCommit` reads that
/// binding to move the job between phases. The registry never decides on its
/// own whether a cancel is still possible — the phase `InstallCommit` set does.
///
/// **Phases.** `.preparing` until a commit starts; `.committing` while one runs
/// AND after one returned — past the point of no return a job stays there
/// (the design's rule: cancellable up to the commit, never after it). A commit
/// that did NOT land puts the job back to `.preparing`: one that threw, or one
/// whose value its `landed` predicate rejected (`InstallCommit.run`). The
/// routes report "refused, nothing installed" one of those two ways — a swap
/// that did not land throws; a `mas install` attempt that exited non-zero, or
/// a vendor update command that exited with a failure status, returns that
/// status — so stopping then loses nothing. The backoff between two
/// `mas install` attempts, and a CLI runner's second try after a rejected
/// token, are exactly that window. A failed commit can still have changed
/// something on the way (a brew run that failed halfway); `.preparing` then
/// means only "this job will start nothing further".
///
/// **A truthful answer.** `cancel` answering `.cancelled` means no commit of
/// that job will start: the request is recorded under the lock that
/// `InstallCommit` takes to mark the job committing, and a commit that finds
/// it throws `CancellationError` before its body. That holds even when the
/// job's task has not seen `Task.cancel()` yet — or never will, because the
/// host registered before it had a task to cancel.
///
/// A host must register before the job can reach its first commit; a commit
/// for an id nobody registered runs as if there were no registry. `run` does
/// the registering, the binding and the task for a host.
public enum InstallJobs {

    /// The job the current task works for. Bound by the host around the whole
    /// install; inherited by child tasks and by `InstallCommit`'s body.
    @TaskLocal public static var currentID: String?

    public enum Phase: Sendable, Equatable {
        /// Before the commit: a cancel stops the job and nothing is changed.
        case preparing
        /// In or past the commit: a cancel is too late.
        case committing
    }

    public enum CancelResult: Sendable, Equatable {
        /// The job's cancel ran, and no commit of it will start.
        case cancelled
        /// The job is in or past its commit, labelled as `InstallCommit.run`
        /// was; nothing was done.
        case tooLate(committing: String)
        /// No job is registered under that id.
        case notFound
    }

    /// Register job `id`. `cancel` is called at most once, outside any lock,
    /// by `cancel(_:)` or `cancelAll()` — typically `{ task.cancel() }`.
    /// `phaseChanged`, when given, is called outside any lock, on whichever
    /// thread moved the job, each time its phase changes — what a window's
    /// Cancel button greys out on. Registering an id that is already
    /// registered replaces it.
    public static func register(
        _ id: String, cancel: @escaping @Sendable () -> Void,
        phaseChanged: (@Sendable (Phase) -> Void)? = nil
    ) {
        registry.withLock { $0[id] = Job(cancel: cancel, phaseChanged: phaseChanged) }
    }

    /// Run `body` as job `id`, for a host: registered for the whole of it, with
    /// `currentID` bound, in a task of its own whose only canceller is the
    /// registry.
    ///
    /// The caller's own cancellation reaches the job through `cancel(_:)`, so
    /// it is refused once the job is committing: a caller torn down past the
    /// commit point — a stopped batch, a closed window's task — cannot cut the
    /// job's wrap-up short (the re-check, the journal's finish), which the
    /// body runs after its commit returned. A `Task.cancel()` of the caller
    /// would have reached all of it.
    ///
    /// The body keeps its isolation (`@isolated(any)`): a main-actor host's
    /// install runs on the main actor, as it did when called directly.
    ///
    /// `isolation` is the caller's, so a main-actor host registers the job in
    /// the same turn it showed the row's Cancel: no suspension between the two
    /// for a click to land in ("guaranteed not to happen at the moments of call
    /// and return between functions with the same isolation", SE-0420).
    /// Nonisolated, the call hopped to the pool first, and a click in that hop
    /// found no job and was lost while the install went on.
    public static func run<T: Sendable>(
        _ id: String,
        phaseChanged: (@Sendable (Phase) -> Void)? = nil,
        isolation: isolated (any Actor)? = #isolation,
        _ body: @escaping @Sendable @isolated(any) () async -> T
    ) async -> T {
        let handle = TaskHandle()
        // Before the task exists: a cancel that comes first is applied the
        // moment it does, and no commit of the job can start unregistered.
        register(id, cancel: { handle.cancel() }, phaseChanged: phaseChanged)
        defer { unregister(id) }
        // Bound around the creation: an unstructured task inherits the
        // creator's task-locals.
        let task = $currentID.withValue(id) { Task(operation: body) }
        handle.set { task.cancel() }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            cancel(id)
        }
    }

    /// A task's cancel, for a closure registered before the task exists.
    private final class TaskHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelTask: (@Sendable () -> Void)?
        private var cancelled = false

        func set(_ cancelTask: @escaping @Sendable () -> Void) {
            let now = lock.withLock { () -> Bool in
                self.cancelTask = cancelTask
                return cancelled
            }
            if now { cancelTask() }
        }

        func cancel() {
            let toCall = lock.withLock { () -> (@Sendable () -> Void)? in
                cancelled = true
                return cancelTask
            }
            toCall?()
        }
    }

    /// Forget job `id`, whatever its phase. Call it when the job's task ends.
    public static func unregister(_ id: String) {
        registry.withLock { $0[id] = nil }
    }

    /// Where job `id` stands, or nil when it is not registered.
    public static func phase(of id: String) -> Phase? {
        registry.withLock { $0[id].map { $0.committing == nil ? .preparing : .committing } }
    }

    /// Whether any registered job is in or past its commit.
    public static var anyCommitting: Bool {
        registry.withLock { $0.values.contains { $0.committing != nil } }
    }

    /// Cancel job `id` if it has not reached its commit.
    @discardableResult
    public static func cancel(_ id: String) -> CancelResult {
        let (answer, toCall) = registry.withLock { jobs -> (CancelResult, (@Sendable () -> Void)?) in
            guard var job = jobs[id] else { return (.notFound, nil) }
            if let label = job.committing { return (.tooLate(committing: label), nil) }
            let first = !job.cancelRequested
            job.cancelRequested = true
            jobs[id] = job
            return (.cancelled, first ? job.cancel : nil)
        }
        // Outside the lock: the closure is the host's, and cancelling a task
        // runs its cancellation handlers inline.
        toCall?()
        // Not an error: the job finishes, which is the rule past the commit.
        if case .tooLate(let label) = answer {
            Log.install.notice(
                "cancel requested after commit point — ignored: \(id, privacy: .public) is in \(label, privacy: .public)")
        }
        return answer
    }

    /// `cancel` for every registered job; each id's answer.
    @discardableResult
    public static func cancelAll() -> [String: CancelResult] {
        let ids = registry.withLock { Array($0.keys) }
        var answers: [String: CancelResult] = [:]
        for id in ids { answers[id] = cancel(id) }
        return answers
    }

    // MARK: - InstallCommit's side

    /// Mark job `id` committing as `label`, or throw `CancellationError` if a
    /// cancel was already answered for it. No-op for nil or an unknown id.
    static func beginCommit(_ id: String?, label: String) throws {
        guard let id else { return }
        let changed = try registry.withLock { jobs -> (@Sendable (Phase) -> Void)? in
            guard var job = jobs[id] else { return nil }
            if job.cancelRequested { throw CancellationError() }
            let was = job.committing
            job.depth += 1
            job.committing = job.committing ?? label
            jobs[id] = job
            return was == nil ? job.phaseChanged : nil
        }
        changed?(.committing)
    }

    /// The commit `beginCommit` marked has ended. One that returned leaves the
    /// job committing for good; when the last one running threw and none had
    /// returned before, the job is preparing again.
    static func endCommit(_ id: String?, landed: Bool) {
        guard let id else { return }
        let changed = registry.withLock { jobs -> (@Sendable (Phase) -> Void)? in
            guard var job = jobs[id] else { return nil }
            job.depth -= 1
            if landed { job.landed = true }
            let was = job.committing
            if job.depth == 0 && !job.landed { job.committing = nil }
            jobs[id] = job
            return was != nil && job.committing == nil ? job.phaseChanged : nil
        }
        changed?(.preparing)
    }

    private struct Job {
        let cancel: @Sendable () -> Void
        let phaseChanged: (@Sendable (Phase) -> Void)?
        var cancelRequested = false
        /// The label of the commit that moved the job past preparing.
        var committing: String?
        /// Commits of this job running now (two can, from a task group).
        var depth = 0
        /// Whether any commit of this job returned.
        var landed = false
    }

    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var jobs: [String: Job] = [:]

        func withLock<R>(_ body: (inout [String: Job]) throws -> R) rethrows -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body(&jobs)
        }
    }
}
