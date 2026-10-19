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
/// So every claim on a row — a click on Update, "Update All" taking it as a
/// target — is numbered (`claim`), and a run waits for the row's earlier run
/// to end before it starts (`enter`). The latest claim owns the row's Cancel
/// state: while an earlier run is still in flight the latest claim has no job
/// of its own yet (`isBehindAnEarlierRun`), so a Cancel is its own and never
/// the earlier run's job, and only the latest claim's run may clear the
/// row's Cancel when it ends (`isLatest`).
@MainActor
public final class InstallRowRuns {
    /// One claim on one row.
    public struct Claim: Equatable, Sendable {
        fileprivate let serial: Int
    }

    private var serial = 0
    /// The latest claim on each row.
    private var latest: [String: Claim] = [:]
    /// The claim whose run is in flight on each row, wrap-up included.
    private var running: [String: Claim] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    /// A new claim on row `id`, which is the row's latest from now on.
    public func claim(_ id: String) -> Claim {
        serial += 1
        let claim = Claim(serial: serial)
        latest[id] = claim
        return claim
    }

    /// Start the run of `claim`: at once when no run of row `id` is in flight,
    /// otherwise once that one has `leave`n.
    public func enter(_ id: String, _ claim: Claim) async {
        while running[id] != nil {
            await withCheckedContinuation { waiters[id, default: []].append($0) }
        }
        running[id] = claim
    }

    /// The run of `claim` has ended, wrap-up and all.
    public func leave(_ id: String, _ claim: Claim) {
        guard running[id] == claim else { return }
        running[id] = nil
        for waiter in waiters.removeValue(forKey: id) ?? [] { waiter.resume() }
    }

    /// Whether `claim` is still row `id`'s latest — no click or batch has
    /// claimed the row since.
    public func isLatest(_ id: String, _ claim: Claim) -> Bool {
        latest[id] == claim
    }

    /// Whether the run in flight on row `id` is an earlier claim's than the
    /// row's latest: the latest has not started, and the row's Cancel is its.
    public func isBehindAnEarlierRun(_ id: String) -> Bool {
        guard let inFlight = running[id] else { return false }
        return inFlight != latest[id]
    }

    /// What a click on row `id`'s Cancel stops.
    public enum RowCancel: Equatable, Sendable {
        /// A target of "Update All" not started yet: taken off its queue.
        case tookOffTheQueue
        /// A run waiting for the row's earlier run: it stops before it starts.
        case stopsBeforeItStarts
        /// The row's registered job (`InstallJobs.cancel`).
        case registeredJob
    }

    /// Row `id`'s Cancel, with `queue` the running "Update All"'s, if any.
    /// Off the queue comes first: a target there never gets to wait for the
    /// row's earlier run, so it need not sit out that run's wrap-up and the
    /// queue ahead of it under "Cancelling…".
    public func cancel(_ id: String, queue: InstallBatchQueue?) -> RowCancel {
        if queue?.remove(id) == true { return .tookOffTheQueue }
        if isBehindAnEarlierRun(id) { return .stopsBeforeItStarts }
        return .registeredJob
    }

    /// For Cancel All over a batch that made `claims`: the targets whose row
    /// was claimed again since (`reclaimed`) — the registered job is that
    /// click's run, or the batch's own finishing ahead of it, neither the
    /// batch's to cancel — and the targets still the batch's but waiting for
    /// an earlier run (`behind`), which their host stops before they start.
    public func batchCancel(
        _ claims: [String: Claim]
    ) -> (reclaimed: Set<String>, behind: Set<String>) {
        let reclaimed = Set(claims.filter { !isLatest($0.key, $0.value) }.keys)
        let behind = Set(claims.keys.filter { isBehindAnEarlierRun($0) }).subtracting(reclaimed)
        return (reclaimed, behind)
    }
}
