import Foundation

/// A blocking call run under a wall-clock bound, for the one shape in this
/// package that cannot be cancelled: `AppScanner().scan()`.
///
/// **Why anything bounds it.** `AppScanner` reads TestFlight's SQLite database,
/// which lives behind macOS's app-data privacy gate. When this was written, that
/// gate surfaced a consent prompt to someone at the keyboard; on a headless runner
/// nothing ever answered it and the `open()` syscall simply never returned. The
/// first CI sweep sat in `guarded_open_np` until the job timed out.
///
/// ⚠️ **That is history, not the cause of a timeout today.** `TestFlightInventory`
/// now bounds its own open to seconds, and macOS 27 refuses another team's
/// container without asking (release note 161835690): measured 2026-09-13 on
/// 27.0 (26A428) from a `launchctl submit` job, a plain `open(2)` of the TestFlight
/// store failed with `EPERM`, and `duo check` on one beta, which reads that store
/// twice, finished in about a second — inside the store's own 5-second bound. So
/// nothing here knows what a scan that still hits this bound was waiting on, and
/// `gaveUpMessage` does not name a cause.
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
    /// A scan that takes this long is not a slow disk: something it reads is not
    /// answering. Both callers treat the result as a bonus signal — the sweep loses
    /// one class of finding, `duo list` shows nothing — and both would otherwise
    /// lose the whole run.
    static let timeout = Duration.seconds(20)

    /// What both callers say when they give up, minus what each does next.
    ///
    /// One sentence in one place because there were two copies, and both named a
    /// cause — "a privacy prompt" on the TestFlight database — that macOS 27 no
    /// longer produces (see the type's note). The thread is abandoned, not
    /// inspected, so which read stalled is genuinely unknown here, and the sentence
    /// says exactly that rather than a better-sounding guess.
    /// `BoundedScanMessageTests` fails if a caller spells its own again.
    static func gaveUpMessage(after timeout: Duration) -> String {
        "the app scan did not finish within \(timeout) and was abandoned; "
            + "duo cannot tell which read it was waiting on"
    }

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

    /// `result`, for a synchronous caller that cannot await — a `static let`
    /// initialiser. Same abandoned-thread shape; the difference is that the wait
    /// is on the calling thread, so it is bounded but not off the pool. Keep the
    /// timeout short.
    static func blockingResult<T: Sendable>(
        within timeout: Duration, _ body: @escaping @Sendable () -> T
    ) -> T? {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        Thread {
            box.set(body())
            done.signal()
        }.start()
        guard done.wait(timeout: .now() + seconds(timeout)) == .success else { return nil }
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
