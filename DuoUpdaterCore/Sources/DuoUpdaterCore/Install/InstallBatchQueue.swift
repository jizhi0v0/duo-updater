import Foundation

/// The targets of one "Update All", for its Cancel All: which it has not
/// started yet, and the cancel of the ones it has.
///
/// A target the batch has claimed but not started is the batch's alone — no
/// job is registered for it — so only the batch can take it off the queue. A
/// started one is an `InstallJobs` job, and its cancel is the registry's: a
/// cancel there is refused once the job is committing, which is what lets a
/// committing install finish (and run its wrap-up) under a Cancel All.
public final class InstallBatchQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var unstarted: Set<String>
    private var started: Set<String> = []
    private var stopped = false
    private var removed = 0

    public init(_ ids: [String]) {
        unstarted = Set(ids)
    }

    /// The batch is about to start `id`. False when a cancel took it off the
    /// queue first — the row's own, or Cancel All: do not start it.
    public func start(_ id: String) -> Bool {
        lock.withLock {
            guard unstarted.remove(id) != nil else { return false }
            started.insert(id)
            return true
        }
    }

    /// The row's own Cancel for a target not started yet: off the queue. False
    /// when the batch already started it (its cancel is `InstallJobs.cancel`)
    /// or it is no target of this batch.
    public func remove(_ id: String) -> Bool {
        lock.withLock {
            guard unstarted.remove(id) != nil else { return false }
            removed += 1
            return true
        }
    }

    /// Whether Cancel All was pressed: start nothing more.
    public var isCancelled: Bool { lock.withLock { stopped } }

    /// Targets a cancel took off the queue before the batch started them.
    public var cancelledBeforeStart: Int { lock.withLock { removed } }

    /// Cancel All: nothing more starts, every target not started is taken off
    /// the queue (`removed`), and every started one is cancelled through the
    /// registry (`answers`) — `.cancelled` for one still preparing,
    /// `.tooLate` for one committing, which finishes; `.notFound` for one
    /// that already ended.
    ///
    /// A started target in `sparing` is not sent to the registry but
    /// returned in `spared`: its row's registered job is an earlier run still
    /// wrapping up, not this target's (`InstallRowRuns`), and its host stops
    /// the target itself.
    public func cancelAll(
        sparing: Set<String> = []
    ) -> (removed: [String], answers: [String: InstallJobs.CancelResult], spared: [String]) {
        let (taken, running) = lock.withLock { () -> ([String], [String]) in
            stopped = true
            let taken = Array(unstarted)
            removed += taken.count
            unstarted = []
            return (taken, Array(started))
        }
        // Outside the lock: a cancel runs the job's cancellation handlers inline.
        var answers: [String: InstallJobs.CancelResult] = [:]
        var spared: [String] = []
        for id in running {
            if sparing.contains(id) { spared.append(id) } else { answers[id] = InstallJobs.cancel(id) }
        }
        return (taken.sorted(), answers, spared.sorted())
    }
}
