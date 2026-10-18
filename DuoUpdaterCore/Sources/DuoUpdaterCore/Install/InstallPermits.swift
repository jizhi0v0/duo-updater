import Foundation

/// The two permits an install consumes at different stages, split out of the
/// old single install gate:
///
///  - a **download** permit, held only while fetching the update's bytes, and
///  - an **apply** permit, held while extracting, verifying, and swapping the
///    bundle in place.
///
/// Only the download stage is network-bound; everything after it is disk +
/// privileged work. One permit covering both meant 3 concurrent installs =
/// "at most 3 downloads AND at most 3 swaps" — the two resources coupled for
/// no reason, with a slot sitting idle on the network while its install
/// extracts and swaps. Splitting them lets the stages pipeline across apps:
/// while app A swaps, app B can already be downloading.
///
/// The permits are deliberately NOT nested: a caller must release the download
/// permit before acquiring the apply one, so a slow swap can never pin a
/// network slot, and a saturated network can never starve the apply stage.
///
/// `signal*` is synchronous on purpose: permits are released in `defer` blocks
/// (and on other non-`await` exit paths), which can't `await`. All state is
/// lock-guarded, so the type is safe to share across tasks without an actor.
///
/// Two ways to wait, sharing one FIFO queue per pool:
///
///  - `waitFor…OrCancel()` (and `with…Permit(cancellable: true)`) — what an
///    install uses. A task cancelled while queued leaves the queue at once and
///    throws `CancellationError`; one already cancelled throws without taking a
///    permit. Without this a cancelled queued install only noticed when some
///    other download or swap freed a slot, which could be minutes.
///  - `waitFor…()` (and `with…Permit()`) — never woken by cancellation. Kept for
///    `InPlaceSwap.elevationPanel`, where giving up the wait half-way through a
///    swap is exactly what must not happen.
///
/// Separate methods rather than one throwing method with a flag: the throwing
/// form is the one whose caller has to handle "never got a permit", and the
/// non-throwing form makes that path impossible at the type level.
public final class InstallPermits: @unchecked Sendable {

    private let lock = NSLock()
    private var downloads: Int
    private var applies: Int
    private var downloadWaiters: [Waiter] = []
    private var applyWaiters: [Waiter] = []

    /// One queued acquirer. A class so a cancellation handler can find and
    /// remove exactly its own entry; every field is read and written under
    /// `InstallPermits.lock`, which is what makes `@unchecked` honest.
    private final class Waiter: @unchecked Sendable {
        enum State {
            /// Created, not yet queued (the handler may still run first).
            case fresh
            case queuedPlain(CheckedContinuation<Void, Never>)
            case queuedCancellable(CheckedContinuation<Void, any Error>)
            /// Handed a permit by `release`; a later cancel changes nothing.
            case granted
            /// Cancelled before it was granted; it holds no permit.
            case cancelled
        }
        var state: State = .fresh
    }

    /// Which pool an acquire/release works on. A selector rather than `inout`
    /// parameters because the cancellation handler is a separate closure that
    /// runs later, on whatever thread called `cancel()`, and can't hold one.
    private enum Pool { case download, apply }

    public init(downloads: Int, applies: Int) {
        self.downloads = max(0, downloads)
        self.applies = max(0, applies)
    }

    /// Remaining free download permits — for tests asserting a pool is
    /// genuinely exhausted without racing a timed wait.
    internal var availableDownloadPermits: Int { lock.withLock { downloads } }

    /// Remaining free apply permits — see `availableDownloadPermits`.
    internal var availableApplyPermits: Int { lock.withLock { applies } }

    /// Acquirers queued on the download pool right now — for tests that need
    /// to know a waiter has parked (and in what order) without sleeping.
    internal var parkedDownloadWaiters: Int { lock.withLock { downloadWaiters.count } }

    /// Acquirers queued on the apply pool — see `parkedDownloadWaiters`.
    internal var parkedApplyWaiters: Int { lock.withLock { applyWaiters.count } }

    /// Acquire a download permit, suspending until one is free. NOT woken by
    /// cancellation: a task cancelled while suspended waits its turn and gets
    /// the permit like any other — use `waitForDownloadOrCancel` unless that is
    /// what you want. Callers must release on EVERY exit path (a
    /// `signalDownload` after a `waitForDownload`), or the pool leaks a permit.
    public func waitForDownload() async {
        await acquire(.download)
    }

    /// Acquire a download permit, or throw `CancellationError` — at once if the
    /// task is already cancelled, or the moment it is cancelled while queued —
    /// holding no permit. A normal return means a permit IS held and must be
    /// released like any other, even if the task was cancelled in the instant
    /// the permit was handed over (the release won that race); a caller that
    /// must not start work then checks `Task.checkCancellation()` after this
    /// returns, inside its release-on-every-exit path.
    public func waitForDownloadOrCancel() async throws {
        try await acquireOrCancel(.download)
    }

    /// Release a download permit, waking the longest-waiting acquirer if any.
    public func signalDownload() {
        release(.download)
    }

    /// Acquire an apply permit, not woken by cancellation — see
    /// `waitForDownload`.
    public func waitForApply() async {
        await acquire(.apply)
    }

    /// Acquire an apply permit or throw on cancellation — see
    /// `waitForDownloadOrCancel`.
    public func waitForApplyOrCancel() async throws {
        try await acquireOrCancel(.apply)
    }

    /// Release an apply permit — see `signalDownload`.
    public func signalApply() {
        release(.apply)
    }

    /// Run `body` while holding a download permit, releasing it on EVERY exit —
    /// including a thrown error, which a `defer` can't express for an async
    /// body. The permit is free again before `body`'s value is returned, so the
    /// caller can immediately acquire the apply permit without nesting them.
    ///
    /// `cancellable: true` waits with `waitForDownloadOrCancel`: cancelled
    /// while queued, it throws without running `body` or holding a permit. The
    /// default keeps the old non-cancellable wait. Either way `body` itself
    /// should check cancellation first — see `waitForDownloadOrCancel` on the
    /// permit handed over at the instant of a cancel.
    public func withDownloadPermit<T: Sendable>(
        cancellable: Bool = false,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        if cancellable { try await waitForDownloadOrCancel() } else { await waitForDownload() }
        do {
            let value = try await body()
            signalDownload()
            return value
        } catch {
            signalDownload()
            throw error
        }
    }

    /// Run `body` while holding an apply permit, releasing on every exit — see
    /// `withDownloadPermit`, including `cancellable`.
    public func withApplyPermit<T: Sendable>(
        cancellable: Bool = false,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        if cancellable { try await waitForApplyOrCancel() } else { await waitForApply() }
        do {
            let value = try await body()
            signalApply()
            return value
        } catch {
            signalApply()
            throw error
        }
    }

    /// Run `body` on one pool's count and queue, under the lock.
    private func locked<R>(_ pool: Pool, _ body: (inout Int, inout [Waiter]) -> R) -> R {
        lock.withLock {
            switch pool {
            case .download: body(&downloads, &downloadWaiters)
            case .apply: body(&applies, &applyWaiters)
            }
        }
    }

    /// Suspend until a permit frees, ignoring cancellation. Fast path takes a
    /// slot immediately; the slow path re-checks inside the continuation so a
    /// permit freed between the two checks is handed to this waiter, never lost.
    private func acquire(_ pool: Pool) async {
        let tookImmediately = locked(pool) { permits, _ in
            if permits > 0 {
                permits -= 1
                return true
            }
            return false
        }
        if tookImmediately { return }
        let waiter = Waiter()
        await withCheckedContinuation { cont in
            // Resume OUTSIDE the lock: resuming a waiter runs its code inline,
            // and it may immediately touch the same lock.
            let shouldResume = locked(pool) { permits, waiters in
                if permits > 0 {
                    permits -= 1
                    return true
                }
                waiter.state = .queuedPlain(cont)
                waiters.append(waiter)
                return false
            }
            if shouldResume { cont.resume() }
        }
    }

    /// Suspend until a permit frees, or throw `CancellationError` holding none.
    ///
    /// Every hand-off is decided under the lock by the waiter's `state`, so the
    /// cancellation handler and `release` can't both claim it:
    ///  - handler first, before the waiter queued (`fresh`): mark it
    ///    `cancelled`, and the continuation body throws instead of queueing.
    ///    This covers both a task cancelled before the call (the handler runs
    ///    before the operation) and a cancel landing between the two.
    ///  - handler first, while queued: take it out of the queue — the others
    ///    keep their order — and resume it throwing. The pool count is not
    ///    touched: it never held a permit.
    ///  - `release` first: the waiter is `granted` and owns the permit; the
    ///    handler finds nothing to do, and the caller's release path returns
    ///    it. No permit can be both handed over and thrown away.
    private func acquireOrCancel(_ pool: Pool) async throws {
        try Task.checkCancellation()
        let tookImmediately = locked(pool) { permits, _ in
            if permits > 0 {
                permits -= 1
                return true
            }
            return false
        }
        if tookImmediately { return }
        let waiter = Waiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                enum Next { case resume, cancel, wait }
                let next = locked(pool) { permits, waiters -> Next in
                    if case .cancelled = waiter.state { return .cancel }
                    if permits > 0 {
                        permits -= 1
                        waiter.state = .granted
                        return .resume
                    }
                    waiter.state = .queuedCancellable(cont)
                    waiters.append(waiter)
                    return .wait
                }
                // Outside the lock, as everywhere here.
                switch next {
                case .resume: cont.resume()
                case .cancel: cont.resume(throwing: CancellationError())
                case .wait: break
                }
            }
        } onCancel: {
            let cont = locked(pool) { _, waiters -> CheckedContinuation<Void, any Error>? in
                switch waiter.state {
                case .fresh:
                    waiter.state = .cancelled
                    return nil
                case .queuedCancellable(let cont):
                    waiters.removeAll { $0 === waiter }
                    waiter.state = .cancelled
                    return cont
                case .queuedPlain, .granted, .cancelled:
                    return nil
                }
            }
            cont?.resume(throwing: CancellationError())
        }
    }

    /// Free a permit, waking the longest-waiting acquirer if any. The waiter is
    /// resumed OUTSIDE the lock: resuming runs its code inline, and it may
    /// immediately touch the same lock. A cancelled waiter is never in the
    /// queue (its handler took it out under this lock), so the head is always
    /// one that still wants the permit.
    private func release(_ pool: Pool) {
        let next = locked(pool) { permits, waiters -> Waiter.State? in
            if waiters.isEmpty {
                permits += 1
                return nil
            }
            let waiter = waiters.removeFirst()
            let queued = waiter.state
            waiter.state = .granted
            return queued
        }
        switch next {
        case .queuedPlain(let cont): cont.resume()
        case .queuedCancellable(let cont): cont.resume()
        case .fresh, .granted, .cancelled, nil: break
        }
    }
}
