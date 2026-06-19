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
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { permits = max(0, value) }

    /// Acquire a permit, suspending until one is available.
    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Release a permit, waking the longest-waiting acquirer if any.
    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
