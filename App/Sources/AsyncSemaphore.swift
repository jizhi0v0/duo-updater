import Foundation

/// A minimal async counting semaphore for bounding concurrency of `await`-ing work
/// (e.g. capping how many background prewarm fetches hit the network at once).
/// Actor-isolated, so `wait`/`signal` are race-free without a lock.
///
/// Cancellation note: a task cancelled while suspended in `wait()` is not resumed
/// early — it resumes once a permit frees up, then its own `Task.isCancelled` check
/// short-circuits the work. Callers must always `signal()` after a `wait()` so
/// permits recycle even as tasks drain on cancellation; with finite producers this
/// never deadlocks.
///
/// `waitOrCancel()` is the form for a queue the user can walk away from (the
/// install gates): a task cancelled while queued leaves the queue at once and
/// throws `CancellationError` holding no permit, and one already cancelled throws
/// without taking one. Both forms share one FIFO queue.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [Waiter] = []
    private var lastTicket = 0

    /// One queued acquirer. `ticket` is how a cancellation handler — which runs
    /// outside the actor and can only hop back in later — finds its own entry; a
    /// `wait()` waiter has none, since nothing ever removes it early.
    private struct Waiter {
        enum Continuation {
            case plain(CheckedContinuation<Void, Never>)
            case cancellable(CheckedContinuation<Void, any Error>)
        }
        let ticket: Int?
        let continuation: Continuation
    }

    init(value: Int) { permits = max(0, value) }

    /// Free permits right now — for tests asserting what a cancelled waiter
    /// left behind.
    var availablePermits: Int { permits }

    /// Acquirers queued right now — for tests that need to know a waiter has
    /// parked (and in what order) without sleeping.
    var parkedWaiters: Int { waiters.count }

    /// Acquire a permit, suspending until one is available.
    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append(Waiter(ticket: nil, continuation: .plain($0))) }
    }

    /// Acquire a permit, or throw `CancellationError` holding none — at once if
    /// the task is already cancelled, or the moment it is cancelled while queued.
    /// A normal return means a permit IS held and must be `signal()`ed, even if
    /// the task was cancelled in the instant it was handed over (the `signal` won
    /// that race); callers check `Task.isCancelled` after this returns, as they
    /// already did after `wait()`.
    ///
    /// Why the hand-off can't leak or double-resume: the handler runs off the
    /// actor, so all it does is hop back on and remove the entry if it is still
    /// queued. Everything from the top of this function to the append runs in one
    /// actor turn — `withTaskCancellationHandler` and `withCheckedThrowingContinuation`
    /// are `nonisolated(nonsending)` (the SDK's `_Concurrency` interface), so
    /// neither leaves the actor — and the hop can only run after that turn: it
    /// finds the entry, or `signal` served it first. The `Task.isCancelled` check
    /// only spares a cancel that arrived mid-turn a trip through the queue.
    func waitOrCancel() async throws {
        try Task.checkCancellation()
        if permits > 0 {
            permits -= 1
            return
        }
        lastTicket += 1
        let ticket = lastTicket
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(ticket: ticket, continuation: .cancellable(cont)))
            }
        } onCancel: {
            Task { await self.leaveQueue(ticket) }
        }
    }

    /// The cancellation handler's half: take `ticket` out of the queue and resume
    /// it throwing. Not finding it means `signal` served it first — it holds the
    /// permit, and its caller's release path returns it — so there is nothing to do.
    /// The permit count is untouched either way: a queued waiter never held one.
    private func leaveQueue(_ ticket: Int) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        let waiter = waiters.remove(at: index)
        if case .cancellable(let cont) = waiter.continuation {
            cont.resume(throwing: CancellationError())
        }
    }

    /// Release a permit, waking the longest-waiting acquirer if any.
    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            switch waiters.removeFirst().continuation {
            case .plain(let cont): cont.resume()
            case .cancellable(let cont): cont.resume()
            }
        }
    }
}
