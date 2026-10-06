import Foundation

/// Run blocking work on a Dispatch queue instead of on Swift concurrency's
/// cooperative pool, and await the result.
///
/// The cooperative pool is width-capped near the core count and does **not**
/// overcommit when one of its threads blocks. So a synchronous call that parks
/// its thread costs one of very few threads, and enough of them at once stops the
/// runtime scheduling anything at all — not slowly, not eventually: at all.
///
/// That is not hypothetical here. Measured on a 3-core GitHub runner
/// (#351, run 33959023008): three concurrent `SecStaticCodeCheckValidity` calls
/// put all three cooperative threads into `Dispatch::Group::wait()`, and two
/// samples sixty seconds apart showed the processes had accumulated 0.00s and
/// 0.01s of CPU in between. The whole test process emitted nothing for the rest
/// of the job.
///
/// This repository already reached the same conclusion once, from the other
/// direction — see `BrewFormulaReleaseService.brewInfoOffActor`, whose comment
/// measures the collateral stall that blocking the pool inflicts on unrelated
/// work and settles on Dispatch for the same reason: **Dispatch grows its pool
/// when a thread blocks, and the cooperative pool does not.** (Not every Dispatch
/// queue, though; see "Why the hop gets its own serial queue" below.)
/// `Task.detached` is not an alternative; a detached task still runs on the
/// cooperative pool.
///
/// ## What this does and does not fix
///
/// It frees the pool. Everything else in the process keeps running, and a call
/// that never returns becomes one stuck operation rather than a dead runtime.
///
/// It does **not** make a stuck call return. That case is not invisible:
/// `scripts/run-with-hang-report.sh` bounds the suite from outside the process
/// and prints stacks either way.
///
/// ## Why the hop gets its own serial queue
///
/// What the Security group above was waiting for was a thread. Its validation
/// work goes to a Dispatch queue that is not overcommit, and such a queue gets
/// no thread while every cooperative thread is parked at its QoS or above.
/// Measured 2026-10-07, release build, 14-core Mac, the pool parked by `.high`
/// tasks: one `SecStaticCodeCheckValidity` of FileMerge.app took 6.003 s instead
/// of 0.017 s, exactly as long as the pool was held; 14 at once, one per pool
/// thread, deadlocked (0.13 s of CPU in two minutes, every thread in
/// `Dispatch::Group::wait()`). That is #351.
///
/// `DispatchQueue.global(qos:)` is such a queue too, and this hop used to go
/// there. With the pool parked by `.high` tasks, a block on
/// `global(qos: .userInitiated)`, `.default` or `.utility` waited the whole 6 s
/// the pool was held; parked by `.medium` tasks, only `.utility` did. So the hop
/// meant to get blocking work off a parked pool could itself wait for that pool.
///
/// A serial queue defaults to overcommit (libdispatch `src/queue.c`: "Serial
/// queues default to overcommit!"), and an overcommit queue gets a thread
/// whatever else is running. In the same experiments, serial queues ran at once
/// every time. Each hop creates its own, so hops still run side by side: one
/// shared serial queue would put every blocking call in the process in a single
/// line. The price is that hops are not capped at the core count; the callers that
/// fan out bound themselves (`installInParallel(limit:)`), and the rest await
/// one hop at a time.
///
/// ## Not for child processes
///
/// A child process's wait used to be the commonest thing hopped through here
/// (`waitUntilExit()`, `readDataToEndOfFile()` on its pipes). It is not any more:
/// `ChildProcess` awaits the child on kqueue and parks no thread, so there is
/// nothing to hop. `scripts/check_offpool.py` refuses a bare `Process()`.
///
/// ## Not cancellable
///
/// `withCheckedThrowingContinuation` plus a Dispatch hop cannot be cancelled: the
/// work runs to completion even after `Task.cancel()`. That is exactly what the
/// synchronous call did before, so nothing regresses — but do not read this as
/// having made these gates interruptible, because it has not.
///
/// ## Public, and two of it
///
/// Public because the blocking calls are not all in this package: the menu-bar
/// app's scan (`AppScanner.scan()` with its TestFlight read) reaches the same
/// pool through the same async entry points. (The app's `lsappinfo` and
/// `osascript`, and `duo`'s synchronous subcommands, used to as well, until they
/// moved to `ChildProcess`.)
///
/// The second, non-throwing overload exists so a caller whose own signature
/// cannot throw does not have to write `(try? await …) ?? fallback` around work
/// that never throws — a fallback no input can reach, which reads as a handled
/// failure and is not one. Overload resolution picks the throwing one whenever
/// the closure body actually throws.
public func offCooperativePool<T: Sendable>(
    qos: DispatchQoS.QoSClass = .userInitiated,
    _ work: @escaping @Sendable () throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        hopQueue(qos).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

/// `offCooperativePool` for work that cannot throw. Same hop, same guarantees;
/// see the doc comment above.
public func offCooperativePool<T: Sendable>(
    qos: DispatchQoS.QoSClass = .userInitiated,
    _ work: @escaping @Sendable () -> T
) async -> T {
    await withCheckedContinuation { continuation in
        hopQueue(qos).async {
            continuation.resume(returning: work())
        }
    }
}

/// A queue of its own for one hop: serial, so overcommit. See "Why the hop gets
/// its own serial queue" above.
private func hopQueue(_ qos: DispatchQoS.QoSClass) -> DispatchQueue {
    DispatchQueue(label: "offCooperativePool", qos: DispatchQoS(qosClass: qos, relativePriority: 0))
}

/// `FileManager.removeItem(at:)` through `offCooperativePool`, best-effort like
/// the `try?` spelling it stands in for. For a path that can hold a whole bundle
/// copy or data directory, whose deletion is a long run of synchronous unlinks.
///
/// Resolve `url` before calling: a Dispatch thread has no task-locals, so a path
/// built from `BackupStore.root` inside the hop would ignore a test's override.
func removeItemOffCooperativePool(at url: URL) async {
    await offCooperativePool(qos: .userInitiated) {
        _ = try? FileManager.default.removeItem(at: url)
    }
}
