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
/// when a thread blocks, and the cooperative pool does not.** `Task.detached` is
/// not an alternative; a detached task still runs on the cooperative pool.
///
/// ## What this does and does not fix
///
/// It frees the pool. Everything else in the process keeps running, and a call
/// that never returns becomes one stuck operation rather than a dead runtime.
///
/// It does **not** make a stuck call return. What the Security group above is
/// waiting for is still unknown — no thread in either process was doing
/// validation work — so if that wait is blocked on something other than a thread,
/// this moves the symptom rather than removing it. That case is not invisible:
/// `scripts/run-with-hang-report.sh` bounds the suite from outside the process
/// and prints stacks either way.
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
/// app (`lsappinfo`, the helper's `osascript`) and `duo` (its whole synchronous
/// subcommands) reach the same pool through the same async entry points.
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
        DispatchQueue.global(qos: qos).async {
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
        DispatchQueue.global(qos: qos).async {
            continuation.resume(returning: work())
        }
    }
}
