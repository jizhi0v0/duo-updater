import Foundation

/// A blocking call run under a wall-clock bound, for the one shape in this
/// package that cannot be cancelled: `AppScanner().scan()`.
///
/// **Why anything bounds it.** `AppScanner` reads TestFlight's SQLite database,
/// which lives behind macOS's app-data privacy gate. On a machine with someone at
/// the keyboard that surfaces a consent prompt; on a headless runner nothing ever
/// answers it and the `open()` syscall simply never returns. The first CI sweep
/// sat in `guarded_open_np` until the job timed out.
///
/// **Why a `Thread` and not a task group.** The blocked thread cannot be
/// cancelled — it is stuck in a syscall — so this abandons it rather than waiting
/// on it. A group looks like it would work (race the scan against a sleep, take
/// whichever lands first) but `withTaskGroup` does not return until *every* child
/// has finished, and `cancelAll()` cannot touch a thread parked in
/// `guarded_open_np`. Both call sites shipped that version: the warning printed on
/// time and the command hung anyway — 2026-08-15 the sweep sat there for ten
/// minutes at 0.03s of CPU.
///
/// **Why the wait is off the cooperative pool.** A blocking wait there occupies
/// one of about as many threads as the machine has cores, and the pool does not
/// grow to compensate; that is how #351 stopped a whole test process.
///
/// One implementation, because there were two and they had already drifted — one
/// converted the sub-second part of its `Duration`, the other silently floored it,
/// so the same argument meant different things depending on which copy you
/// reached.
enum BoundedScan {

    /// How long to wait for a local app scan before giving up on it.
    ///
    /// A scan that takes this long is a permission wall, not a slow disk. Both
    /// callers treat the result as a bonus signal — the sweep loses one class of
    /// finding, `duo list` shows nothing — and both would otherwise lose the whole
    /// run.
    static let timeout = Duration.seconds(20)

    /// Run `body` on a detached thread, returning its value, or nil if `timeout`
    /// elapsed first. A nil is "we gave up", never "it answered with nothing":
    /// the caller decides what to say about that.
    static func result<T: Sendable>(
        within timeout: Duration, _ body: @escaping @Sendable () -> T
    ) async -> T? {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let worker = Thread {
            box.set(body())
            done.signal()
        }
        worker.start()

        let timedOut = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                cont.resume(returning: done.wait(timeout: .now() + seconds(timeout)) == .timedOut)
            }
        }
        guard !timedOut else { return nil }
        return box.take()
    }

    /// A `Duration` as seconds, for `DispatchTime`.
    ///
    /// Both components, because one of the two copies this replaced took only
    /// `components.seconds` — which floors any sub-second `Duration` to zero and
    /// turns the bound into "do not wait at all". Neither production caller
    /// passes one, so nothing would have caught it there; a test that wants a
    /// timeout it can actually reach passes milliseconds.
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    /// A slot the worker thread fills and the caller reads, for the case where the
    /// caller has already given up on it.
    private final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ v: T) {
            lock.lock(); defer { lock.unlock() }
            value = v
        }
        func take() -> T? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}
