import Foundation

/// The point of no return of an install, made explicit: everything before it
/// may be cancelled and leaves nothing behind but the install's own scratch
/// directory; everything inside it runs to its end whoever asks it to stop.
///
/// Every route has exactly one such section — the swap, the hand-off to brew,
/// to Installer, to `mas`, to App Store's offer button, to a vendor's update
/// command, the quit of a Relaunch — and each is wrapped in `run` where it
/// starts. The cancel signal itself is the Swift task's own; there is no
/// separate token, so every existing check point, `withTaskCancellationHandler`
/// and `.terminateChild` child keeps working before the commit, and stops
/// mattering inside it.
///
/// `run` does three things:
///
/// 1. **Asks once more, last.** A caller already cancelled throws
///    `CancellationError` and the body never starts. If the caller is part of
///    a registered job (`InstallJobs.currentID`), the job is checked too —
///    under the same lock that marks it committing, so a cancel the registry
///    answered `.cancelled` can never be followed by this commit starting.
/// 2. **Shields the body.** The body runs in an unstructured `Task { }` whose
///    value is awaited. `Task.cancel()` reaches only child tasks and task
///    groups ("…cancels the task and all of its child tasks",
///    developer.apple.com/documentation/swift/task/cancel()), and an
///    unstructured task is no one's child, so the caller's cancellation never
///    gets in. Awaiting `.value` does not forward it either.
///
///    `Task { }`, NOT `Task.detached`: "Detached tasks do not inherit
///    task-local values, however tasks created using the `Task { ... }`
///    initializer do inherit task-locals"
///    (developer.apple.com/documentation/swift/tasklocal). This repository
///    redirects real locations through `@TaskLocal` overrides in its tests
///    (`BackupStore.rootOverride`, `destinationOverride`, …); a detached body
///    would silently write to the real ones.
///
///    SE-0504's `withTaskCancellationShield` is the language's own way of
///    saying this, and would replace the task below — but it needs runtime
///    support and is not back-deployed, and this ships to macOS 15.
/// 3. **Is counted.** `activeCount` / `isAnyActive` say, synchronously, whether
///    any commit is running anywhere in the process — what a quit or a signal
///    handler must wait for rather than cut short.
///
/// A `run` inside a running commit is the same commit: it passes straight
/// through, uncounted and unchecked (nothing inside a commit can be cancelled
/// anyway). That lets an installer wrap its own swap while a caller further out
/// wraps a larger section, without either knowing about the other.
///
/// The child-process policies inside a commit stay as they are —
/// `.runToCompletion` where a kill would leave a half-written bundle. Belt and
/// braces: a commit cannot be cancelled, and neither can those children.
public enum InstallCommit {

    /// True inside a commit's body, and in every task it creates that inherits
    /// task-locals — which is what makes a nested `run` a pass-through.
    @TaskLocal static var isInside = false

    /// The running commit's "handed over" mark (`handedOver()`), nil outside one.
    @TaskLocal private static var handOver: HandOver?

    /// Say, from inside a commit's body, that the install is the third party's
    /// from here: App Store's offer button is pressed, brew has run. A throw
    /// after this no longer means "nothing changed" — the job stays committing
    /// (`InstallJobs`), so the row's Cancel stays greyed through the wrap-up and
    /// a click is answered "too late". Without it a throw puts the job back to
    /// preparing, which is right for a swap that rolled itself back. Outside a
    /// commit it does nothing.
    public static func handedOver() { handOver?.mark() }

    private final class HandOver: @unchecked Sendable {
        private let lock = NSLock()
        private var marked = false
        func mark() { lock.withLock { marked = true } }
        var isMarked: Bool { lock.withLock { marked } }
    }

    /// Run `body` as the commit labelled `label` (a short noun for the log and
    /// for `InstallJobs.CancelResult.tooLate`: "swap", "brew upgrade", …).
    ///
    /// Throws `CancellationError` without running `body` when the caller (or
    /// its registered job) is already cancelled; otherwise returns what `body`
    /// returns, or throws what it throws, however the caller's cancellation
    /// changes meanwhile.
    ///
    /// `landed` says whether the value `body` returned means the hand-over
    /// took: false for a body that reports "refused, nothing changed" by value
    /// rather than by throwing — a `mas install` that exited non-zero, a vendor
    /// command that exited with a failure status. For the job's phase such a
    /// value counts like a throw (`InstallJobs`: back to `.preparing`, so a
    /// cancel before the caller's retry is still a cancel); the value is
    /// returned to the caller either way.
    ///
    /// A throw lands only when the body said `handedOver()` before it.
    public static func run<T: Sendable>(
        _ label: String,
        landed isLanded: @escaping @Sendable (T) -> Bool = { _ in true },
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        if isInside { return try await body() }
        try Task.checkCancellation()
        let job = InstallJobs.currentID
        // Throws if the registry already answered a cancel for this job, and
        // marks it committing in the same critical section otherwise.
        try InstallJobs.beginCommit(job, label: label)
        // Written down (fsync'd) before the body touches the app: an install
        // that ends with its app missing was the cause only if it got here
        // (`InstallJournal.Recording.finish`).
        InstallJournal.current?.noteCommitted()
        counter.begin(label)
        Log.install.debug("commit start: \(label, privacy: .public)")
        // SE-0504 `withTaskCancellationShield { … }` belongs here once the
        // deployment target allows it (see the type's comment).
        let task = Task {
            var landed = false
            // In the task, not after `.value`: the count and the job's phase
            // follow the body itself.
            defer {
                counter.end(label)
                InstallJobs.endCommit(job, landed: landed)
                Log.install.debug("commit end: \(label, privacy: .public) landed=\(landed, privacy: .public)")
            }
            let handOver = HandOver()
            do {
                let value = try await $isInside.withValue(true) {
                    try await $handOver.withValue(handOver) { try await body() }
                }
                landed = isLanded(value)
                return value
            } catch {
                landed = handOver.isMarked
                throw error
            }
        }
        return try await task.value
    }

    /// Commits running now, process-wide.
    public static var activeCount: Int { counter.total }

    /// Whether any commit is running now, process-wide.
    public static var isAnyActive: Bool { counter.total > 0 }

    /// Commits labelled `label` running now — for tests, which run in parallel
    /// with other suites' commits and so cannot read the total.
    static func activeCount(label: String) -> Int { counter.count(label) }

    private static let counter = Counter()

    /// Lock-guarded like `InstallPermits`: read synchronously from places that
    /// cannot `await` (a signal handler's follow-up, `applicationShouldTerminate`).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var byLabel: [String: Int] = [:]
        private var all = 0

        func begin(_ label: String) {
            lock.withLock {
                byLabel[label, default: 0] += 1
                all += 1
            }
        }

        func end(_ label: String) {
            lock.withLock {
                let left = (byLabel[label] ?? 1) - 1
                byLabel[label] = left > 0 ? left : nil
                all -= 1
            }
        }

        var total: Int { lock.withLock { all } }
        func count(_ label: String) -> Int { lock.withLock { byLabel[label] ?? 0 } }
    }
}
