import Foundation

/// Run synchronous work that can block **forever** on a thread we are willing to
/// abandon, and stop waiting for it after a deadline.
///
/// ## Why this exists next to `offCooperativePool`
///
/// `offCooperativePool` is the right tool when the caller is `async`: it hops the
/// blocking call onto Dispatch, which overcommits when a thread parks, and awaits
/// the result. It cannot help a caller that is not `async`, and it never gives
/// up — a call that never returns still never returns, it just strands a Dispatch
/// worker instead of one of the very few cooperative threads.
///
/// Both of those matter on the app-scan path. `AppScanner.scan()` is synchronous
/// all the way down (`scan` → `admit` → `readApp` → `ChannelBinding.resolve`), and
/// it is reached from `async` contexts on both hosts, so the blocking work it does
/// lands on whatever thread the caller happened to be on — a cooperative one in
/// the test suite and in `Task.detached` (a detached task still runs on the
/// cooperative pool). And the specific way these reads fail is not "slow": macOS
/// gates another app's data behind a consent prompt, and while that prompt sits
/// unanswered `open(2)` does not fail, it does not time out, and it is not a
/// cancellation point. It simply never returns.
///
/// Measured 2026-09-09: a `make test` run was killed at
/// `scripts/run-with-hang-report.sh`'s 1800s timeout with two CPU samples 60s
/// apart showing 0.00s burned in between, and `sample(1)` put a
/// `com.apple.root.default-qos.cooperative` thread inside `__open` on
/// `~/Library/Containers/com.coteditor.CotEditor/Data/Library/Preferences/com.coteditor.CotEditor.plist`,
/// reached from `AppScanner.scan()` via `ChannelBinding.resolve`. Once the pending
/// consent dialog was answered the identical suite finished in 15.5s.
/// `TestFlightInventory` hit the same wall from the other direction on 2026-08-15
/// (ten minutes in `guarded_open_np` at 0.03s of CPU) and grew the first copy of
/// this pattern; this type is that copy, extracted so there is one of it.
///
/// ## What it buys, and what it does not
///
/// It bounds the *caller*. The abandoned thread is still stuck — nothing can
/// un-stick a syscall that is not a cancellation point — so the guarantee is
/// "this call returns", not "that read completed". A `Thread`, not a Dispatch
/// item, precisely because it is abandoned: a stranded Dispatch worker is drawn
/// from a pool with a per-QoS ceiling, and stranding those is how you convert one
/// gated file into a process-wide outage a second time.
///
/// ## One stranded thread per key, not one per call
///
/// A long-running host scans on a timer, so without the memo every pass would
/// strand another thread and pay the deadline again. Once a key is known stuck we
/// stop starting work for it and answer immediately; the worker clears the mark if
/// it ever does return, so granting the permission mid-session recovers on the
/// next pass without a restart. Keyed, so one gated file cannot silence an
/// unrelated one.
final class BoundedBlockingWork: @unchecked Sendable {
    /// Names this instance in the log line a give-up emits. One instance per
    /// subsystem, so the key namespaces cannot collide across callers.
    private let label: String
    private let lock = NSLock()
    private var stuck: Set<String> = []

    init(label: String) {
        self.label = label
    }

    /// Whether `key` is currently being waited on by a thread that never came
    /// back. Callers that want to distinguish "gave up" from "answered nothing"
    /// can ask; `run` consults it itself.
    func isStuck(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stuck.contains(key)
    }

    /// Force the mark. Exists for tests, which need a key to be stuck without
    /// having to hang a real syscall to get it there.
    func mark(_ key: String, stuck isStuck: Bool) {
        lock.lock(); defer { lock.unlock() }
        if isStuck { stuck.insert(key) } else { stuck.remove(key) }
    }

    /// Run `work`, giving up after `timeout`.
    ///
    /// Returns nil for both failure modes — the deadline passed, or `key` was
    /// already known stuck from an earlier call. Callers must treat nil as "no
    /// answer", never as an answer: what makes these reads dangerous is exactly
    /// that a missing answer and a denied one are indistinguishable from here.
    func run<T: Sendable>(
        key: String,
        timeout: TimeInterval,
        _ work: @escaping @Sendable () -> T
    ) -> T? {
        guard !isStuck(key) else { return nil }

        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let worker = Thread { [self] in
            box.value = work()
            mark(key, stuck: false)
            done.signal()
        }
        // Small on purpose: these are file reads, not deep recursion, and a
        // stranded thread's stack is memory we never get back.
        worker.stackSize = 512 * 1024
        worker.start()

        if done.wait(timeout: .now() + timeout) == .timedOut {
            mark(key, stuck: true)
            Log.scan.error("""
                \(self.label, privacy: .public): \(key, privacy: .public) did not return within \
                \(timeout, privacy: .public)s — abandoning it (app-data privacy gate?)
                """)
            return nil
        }
        return box.value
    }

    /// A slot one thread fills and another reads. Needed rather than a captured
    /// `var` because the reader can give up before the writer stores anything.
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        var value: T? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }
}
