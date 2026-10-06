import Foundation

/// `tasks` tasks that each block a cooperative-pool thread until released.
///
/// For tests of code that has to keep working while the pool is all blocked, as
/// it was on CI when several tests sat in `SecStaticCodeCheckValidity` at once.
/// With more tasks than the pool has threads, some stay queued, and that is how a
/// test can tell the pool really was full.
final class BlockedCooperativePool: @unchecked Sendable {
    let tasks: Int
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = 0

    init(tasks: Int) {
        self.tasks = tasks
        for _ in 0..<tasks {
            Task.detached(priority: .high) { [self] in block() }
        }
    }

    private func block() {
        lock.withLock { started += 1 }
        gate.wait()
    }

    /// On a plain `Thread`, which needs neither a cooperative nor a Dispatch
    /// thread to run: wait for `condition()` to turn true, or for `seconds`, then
    /// let every blocked task go. `saturated` is whether some tasks were still
    /// queued at that moment.
    func release(
        within seconds: Double, until condition: @escaping @Sendable () -> Bool
    ) -> Promise<(conditionMet: Bool, saturated: Bool)> {
        let promise = Promise<(conditionMet: Bool, saturated: Bool)>()
        Thread.detachNewThread { [self] in
            let deadline = Date().addingTimeInterval(seconds)
            while !condition(), Date() < deadline { usleep(1_000) }
            let met = condition()
            let saturated = lock.withLock { started } < tasks
            for _ in 0..<tasks { gate.signal() }
            promise.fulfill((met, saturated))
        }
        return promise
    }

    /// A value set once from any thread and awaited from a task.
    final class Promise<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: T?
        private var waiter: CheckedContinuation<T, Never>?

        func fulfill(_ value: T) {
            lock.lock()
            result = value
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume(returning: value)
        }

        var value: T {
            get async {
                await withCheckedContinuation { cont in
                    lock.lock()
                    if let result {
                        lock.unlock()
                        cont.resume(returning: result)
                    } else {
                        waiter = cont
                        lock.unlock()
                    }
                }
            }
        }
    }
}
