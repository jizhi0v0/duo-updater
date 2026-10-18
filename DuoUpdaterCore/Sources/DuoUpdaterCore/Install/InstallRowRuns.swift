import Foundation

/// One install run per row at a time, for a host whose row frees itself
/// before its run has ended.
///
/// The menu-bar app's install clears the row's claim (`installing[id]`) when
/// the install itself is over, so the row reads "Update" again — but its run
/// still has a wrap-up to finish (the journal, the locks, a deferred rescan)
/// inside its `InstallJobs` job. A second click in that tail used to start a
/// run beside it under the same job id and the same Cancel state: after a
/// cancel the new click was answered "cancelled" and installed nothing, after
/// a failure the old run's end unregistered the new job and took its Cancel.
///
/// So a run that finds its row's previous run still in flight waits for it
/// (`enter`) — the row shows it queued meanwhile — and while it waits its
/// Cancel is its own (`isWaiting`), never the previous run's job.
@MainActor
public final class InstallRowRuns {
    private var running: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var waitingIDs: Set<String> = []

    public init() {}

    /// Start the run of row `id`: at once when none is in flight, otherwise
    /// once the one in flight has `leave`n.
    public func enter(_ id: String) async {
        while running.contains(id) {
            waitingIDs.insert(id)
            await withCheckedContinuation { waiters[id, default: []].append($0) }
        }
        waitingIDs.remove(id)
        running.insert(id)
    }

    /// The run of row `id` has ended, wrap-up and all.
    public func leave(_ id: String) {
        running.remove(id)
        for waiter in waiters.removeValue(forKey: id) ?? [] { waiter.resume() }
    }

    /// Whether a run of row `id` is in flight, wrap-up included.
    public func isRunning(_ id: String) -> Bool {
        running.contains(id)
    }

    /// Whether a run of row `id` is waiting for the previous one to end — the
    /// row's Cancel then belongs to the waiting run.
    public func isWaiting(_ id: String) -> Bool {
        waitingIDs.contains(id)
    }
}
