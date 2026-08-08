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
public final class InstallPermits: @unchecked Sendable {

    private let lock = NSLock()
    private var downloads: Int
    private var applies: Int
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    private var applyWaiters: [CheckedContinuation<Void, Never>] = []

    public init(downloads: Int, applies: Int) {
        self.downloads = max(0, downloads)
        self.applies = max(0, applies)
    }

    /// Remaining free download permits — for tests asserting a pool is
    /// genuinely exhausted without racing a timed wait.
    internal var availableDownloadPermits: Int { lock.withLock { downloads } }

    /// Remaining free apply permits — see `availableDownloadPermits`.
    internal var availableApplyPermits: Int { lock.withLock { applies } }

    /// Acquire a download permit, suspending until one is free. A task
    /// cancelled while suspended is not resumed early — it wakes when a permit
    /// frees and its own `Task.isCancelled` check short-circuits. Callers must
    /// release on EVERY exit path (a `signalDownload` after a
    /// `waitForDownload`), or the pool leaks a permit.
    public func waitForDownload() async {
        await acquire(&downloads, &downloadWaiters)
    }

    /// Release a download permit, waking the longest-waiting acquirer if any.
    public func signalDownload() {
        release(&downloads, &downloadWaiters)
    }

    /// Acquire an apply permit — see `waitForDownload`.
    public func waitForApply() async {
        await acquire(&applies, &applyWaiters)
    }

    /// Release an apply permit — see `signalDownload`.
    public func signalApply() {
        release(&applies, &applyWaiters)
    }

    /// Run `body` while holding a download permit, releasing it on EVERY exit —
    /// including a thrown error, which a `defer` can't express for an async
    /// body. The permit is free again before `body`'s value is returned, so the
    /// caller can immediately acquire the apply permit without nesting them.
    public func withDownloadPermit<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        await waitForDownload()
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
    /// `withDownloadPermit`.
    public func withApplyPermit<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        await waitForApply()
        do {
            let value = try await body()
            signalApply()
            return value
        } catch {
            signalApply()
            throw error
        }
    }

    /// Suspend until a permit frees. Fast path takes a slot immediately; the
    /// slow path re-checks inside the continuation so a permit freed between
    /// the two checks is handed to this waiter, never lost.
    private func acquire(
        _ permits: inout Int,
        _ waiters: inout [CheckedContinuation<Void, Never>]
    ) async {
        let tookImmediately = lock.withLock {
            if permits > 0 {
                permits -= 1
                return true
            }
            return false
        }
        if tookImmediately { return }
        await withCheckedContinuation { cont in
            // Resume OUTSIDE the lock: resuming a waiter runs its code inline,
            // and it may immediately touch the same lock.
            let shouldResume = lock.withLock {
                if permits > 0 {
                    permits -= 1
                    return true
                }
                waiters.append(cont)
                return false
            }
            if shouldResume { cont.resume() }
        }
    }

    /// Free a permit, waking the longest-waiting acquirer if any. The waiter is
    /// resumed OUTSIDE the lock: resuming runs its code inline, and it may
    /// immediately touch the same lock.
    private func release(
        _ permits: inout Int,
        _ waiters: inout [CheckedContinuation<Void, Never>]
    ) {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if waiters.isEmpty {
                permits += 1
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }
}
