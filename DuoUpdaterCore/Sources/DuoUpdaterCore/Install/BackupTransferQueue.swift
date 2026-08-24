import Foundation

/// Moves backups from the local outbox onto the configured external disk, one at
/// a time, in the background.
///
/// The queue exists so that an install never waits on a cable. `BackupStore.save`
/// always writes to the boot volume — fast, local, and the same operation it has
/// always been — and the copy to the external disk happens afterwards, out of the
/// install's way. What the user sees is unchanged install latency; what they get
/// is the boot volume reclaimed a minute later.
///
/// **One at a time, deliberately.** The destination is a single slow pipe, so
/// running two copies concurrently makes both slower and neither finish sooner;
/// and compression is CPU-bound, so parallel transfers would compete there too.
///
/// **An absent disk is not a failure.** Every attempt re-asks
/// `BackupStore.availability()` first, and an unreachable destination suspends
/// the queue rather than consuming a retry: a disk that is in a bag is going to
/// stay in a bag for longer than five exponential backoffs, and burning the
/// budget on it would mean the transfer had permanently "failed" by the time it
/// was plugged back in. Retries are for the transfer genuinely going wrong while
/// the disk is right there.
public actor BackupTransferQueue {

    public static let shared = BackupTransferQueue()

    public enum State: Sendable, Equatable {
        case idle
        /// `completed` and `total` count backups, not bytes. Bytes would be the
        /// truer bar, but knowing them means walking every bundle in the outbox
        /// before starting — minutes of stat calls on a big store, spent to
        /// improve a bar rather than to move anything.
        case copying(name: String, completed: Int, total: Int)
        /// Work is owed but the destination is not reachable.
        case waitingForDisk(pending: Int)
        case failed(name: String, message: String, pending: Int)
    }

    public private(set) var state: State = .idle

    /// Keys owed a copy, in the order they were asked for. An array rather than
    /// a set because the oldest backup is the one most likely to be wanted back.
    private var pending: [String] = []
    /// The key being copied right now. `BackupStore.sweepStaleScratch` must skip
    /// it: its `.partial` is minutes old by design on a slow disk, and mtime
    /// alone cannot tell that apart from abandoned scratch.
    private var inFlight: String?
    private var draining = false
    private var napAssertion: NSObjectProtocol?

    /// Matches `Downloader`'s shape — `(attempt + 1) * 500ms`, five attempts.
    /// Injectable so tests do not actually sleep, the way `MASInstaller` does it.
    private let maxAttempts: Int
    private let backoffUnitNanos: UInt64

    public init(maxAttempts: Int = 5, backoffUnitNanos: UInt64 = 500_000_000) {
        self.maxAttempts = maxAttempts
        self.backoffUnitNanos = backoffUnitNanos
    }

    /// Keys the sweeper must leave alone.
    public var protectedKeys: Set<String> { inFlight.map { [$0] } ?? [] }

    /// How much is still owed, from the queue's own memory. The settings page
    /// polls this rather than rescanning the store every second.
    public var pendingCount: Int { pending.count + (inFlight == nil ? 0 : 1) }

    // MARK: - Enqueuing

    public func enqueue(_ key: String) {
        guard !pending.contains(key), inFlight != key else { return }
        pending.append(key)
    }

    /// Pick up everything the store says is still owed — at launch, and whenever
    /// a disk appears.
    ///
    /// Reads from the sidecars rather than from memory on purpose: the backup
    /// that most needs collecting is the one taken in a previous run, while the
    /// disk was elsewhere, and an in-memory queue would have forgotten it.
    public func resumePending() {
        for key in BackupStore.pendingTransferKeys() { enqueue(key) }
    }

    // MARK: - Draining

    /// Work the queue until it is empty or the disk goes away. Returns when
    /// there is nothing further it can do right now.
    public func drain() async {
        guard !draining else { return }
        draining = true
        defer {
            draining = false
            endActivity()
        }

        var completed = 0
        var failures: [(name: String, message: String)] = []
        while !pending.isEmpty {
            if Task.isCancelled { break }
            // Ask before every item, not once per drain: a disk can be unplugged
            // between two transfers, and the next one must suspend rather than
            // fail.
            guard case .ready = BackupStore.availability() else {
                state = .waitingForDisk(pending: pending.count)
                return
            }
            beginActivity()
            let total = completed + pending.count
            let key = pending.removeFirst()
            inFlight = key
            state = .copying(
                name: BackupStore.displayName(forKey: key) ?? key,
                completed: completed, total: total)
            let outcome = await attempt(key)
            inFlight = nil

            switch outcome {
            case .done:
                completed += 1
                continue
            case .diskGone:
                // Put it back at the front — it is still owed, and it was next.
                pending.insert(key, at: 0)
                state = .waitingForDisk(pending: pending.count)
                return
            case .failed(let message):
                // Skip it and keep going. Stopping the run for one item meant a
                // single backup that could never transfer — a remnant `save`
                // left behind, say — held every remaining backup on the boot
                // volume indefinitely, which is the opposite of what moving the
                // store is for. The failure is reported once the rest are done.
                failures.append((BackupStore.displayName(forKey: key) ?? key, message))
                continue
            }
        }
        if let first = failures.first {
            state = .failed(
                name: first.name, message: first.message, pending: failures.count)
        } else {
            state = .idle
        }
    }

    private enum Outcome {
        case done
        case diskGone
        case failed(String)
    }

    private func attempt(_ key: String) async -> Outcome {
        var lastMessage = ""
        for attempt in 0..<maxAttempts {
            if Task.isCancelled { return .diskGone }
            do {
                try BackupStore.transferToDestination(forKey: key)
                return .done
            } catch {
                // A destination that has gone away is not a transfer failure and
                // must not spend an attempt; re-asking the store is what tells
                // the two apart, since the tool underneath reports only an exit
                // code and cannot.
                if case .ready = BackupStore.availability() {
                    lastMessage = error.localizedDescription
                    Log.install.error(
                        "backup transfer: \(key, privacy: .public) failed (attempt \(attempt + 1, privacy: .public)) — \(lastMessage, privacy: .public)")
                } else {
                    return .diskGone
                }
            }
            if attempt + 1 < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * backoffUnitNanos)
            }
        }
        return .failed(lastMessage)
    }

    // MARK: - Interruptions

    /// Drop everything queued, for a disk that is about to be unmounted or a
    /// machine about to sleep. Nothing on disk is undone: an interrupted
    /// transfer leaves the local copy intact — it is only removed after the
    /// destination copy is complete — so the work is simply owed again.
    public func suspend() {
        state = pending.isEmpty ? .idle : .waitingForDisk(pending: pending.count)
    }

    // MARK: - App Nap

    /// Held only while a transfer is actually running. A copy to a slow disk can
    /// outlast the idle timer, and letting the system nap mid-transfer is how a
    /// `.partial` ends up sitting on the destination until the next sweep.
    private func beginActivity() {
        guard napAssertion == nil else { return }
        napAssertion = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Copying rollback backups to the backup disk")
    }

    private func endActivity() {
        if let napAssertion { ProcessInfo.processInfo.endActivity(napAssertion) }
        napAssertion = nil
    }
}
