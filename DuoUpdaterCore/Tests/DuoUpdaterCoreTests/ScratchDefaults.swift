import Foundation

/// A preferences domain for tests that write settings, kept off any real domain.
///
/// The same helper as `CLI/Tests/DuoKitTests/ScratchDefaults.swift`, whose
/// comment has the measurements behind it; the two test targets cannot share a
/// file. In short: the name is a fixed label, never a fresh UUID, because a test
/// cannot take a preferences plist back once it exists — cfprefsd writes it out
/// again after the process exits — so the only lever on the file count is how
/// many names are ever asked for. `init` clears the domain on the way in, since
/// it outlives the process and a run that died mid-test would otherwise hand its
/// values to the next.
///
/// The label carries this process's `ScratchSlot`, because preferences are per
/// user and two test processes can run as the same user at once — the mini's two
/// CI runners do. With a bare fixed label, CI run 37875961124 failed when another
/// runner's suite flipped the same key mid-test. Slot 0 adds no suffix.
///
/// Two suites that could run concurrently in one process must not share a label.
struct ScratchDefaults {

    let label: String
    let defaults: UserDefaults

    init(_ label: String) {
        let slot = ScratchSlot.current
        self.label = "com.duoupdater.tests.\(label)" + (slot == 0 ? "" : ".\(slot)")
        // A fixed label: neither the global domain nor this process's own bundle
        // identifier, which are the two Apple's documentation says not to pass.
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
/// different environments still contend for the same files. The lock files are
/// the CLI helper's too, so a Core and a CLI process never share a slot.
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
