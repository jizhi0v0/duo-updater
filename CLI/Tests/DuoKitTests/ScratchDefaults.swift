import Foundation

/// A preferences domain for tests that write settings, kept off the real
/// `com.duoupdater.app` domain.
///
/// The name is fixed per `label` rather than a fresh UUID per test. A UUID domain
/// is a new plist in `~/Library/Preferences`, and a test cannot take it back:
/// `removePersistentDomain(forName:)` empties the domain but leaves the file, and
/// unlinking the file afterwards does not stick — removing the domain marks it
/// dirty, so cfprefsd writes it back out when the process exits. Measured
/// 2026-09-18 on Darwin 27, 40 suites per recipe, counted after exit:
/// remove + synchronize + unlink left 40/40. (Unlinking without removing the
/// domain first left 0/40 — but that is not cleanup: the values stay live in
/// cfprefsd, and it is the dirty flag, not the file, that decides.)
///
/// So the only lever is how many *names* the suite ever asks for: one per label
/// costs one file however often the suite runs. One per test had reached 9,976
/// files by 2026-09-18, when they were swept by hand; with 117 more left by a
/// since-deleted harness, the two together were about 90% of that directory.
/// This suite alone opened seven of them per run, one per test.
///
/// That also means the file count is bounded whether or not `clear()` runs.
/// Cleanup still matters for a different reason: the domain outlives the
/// process, so a run that died before its teardown would otherwise hand its
/// values to the next run. `init` clears on the way in for exactly that case —
/// verified by killing a run mid-test, where the next one read the dead run's
/// value without it. `clear()` on the way out leaves the domain empty.
///
/// Callers give the label; two suites that could run concurrently must not share
/// one, since Swift Testing parallelises across suites.
///
/// Two test *processes* can run concurrently as well — the mini's two CI runners
/// are the same user, as are worktrees on one Mac — and preferences domains are
/// per user, so a fixed label alone is shared between them: CI run 37875961124
/// failed when another runner's suite flipped the same key mid-test. Each process
/// therefore suffixes the label with its `ScratchSlot`, which is 0 — no suffix,
/// the same file as before — unless another test process already holds 0. The
/// file count stays bounded, now by labels × the most test processes ever run at
/// once rather than by labels alone.
struct ScratchDefaults {

    let label: String
    let defaults: UserDefaults

    init(_ label: String) {
        let slot = ScratchSlot.current
        self.label = "com.duoupdater.tests.\(label)" + (slot == 0 ? "" : ".\(slot)")
        // `!` as at the call sites this replaces. The name is a fixed label —
        // neither the global domain nor this process's own bundle identifier,
        // which are the two Apple's documentation says not to pass.
        self.defaults = UserDefaults(suiteName: self.label)!
        clear()
    }

    /// Empties the domain. Safe to call more than once, and on a domain that was
    /// never written.
    func clear() {
        defaults.removePersistentDomain(forName: label)
        defaults.synchronize()
    }
}

/// The lowest slot no other running test process holds, taken for the life of
/// this process.
///
/// A slot is an exclusive `flock` on a lock file in the per-user temporary
/// directory. The kernel drops the lock when the process exits, however it
/// exits, so a crashed run never strands a slot, and slots are reused from 0 up:
/// a machine that never runs two test processes at once only ever uses slot 0.
/// The directory comes from `confstr`, not `$TMPDIR`, so that two processes with
/// different environments still contend for the same files.
enum ScratchSlot {

    static let current: Int = {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        precondition(confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0,
                     "no per-user temporary directory for the scratch-defaults slots")
        let directory = String(cString: buffer)
        var slot = 0
        while true {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("com.duoupdater.tests.slot\(slot).lock").path
            let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            precondition(fd >= 0, "could not open \(path): errno \(errno)")
            // Never closed: closing the descriptor would release the lock.
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return slot }
            close(fd)
            slot += 1
        }
    }()
}
