import Foundation
import Darwin

/// Is something already updating the standalone Codex right now?
///
/// Every path that changes the install runs the same `install.sh`: a user's
/// `curl … | sh`, `codex update` (which runs exactly that), the app-server
/// daemon's background updater (`pid-update-loop`, which pipes the script into
/// `/bin/sh -s` with `CODEX_INSTALL_IF_LATEST`), and DuoUpdater's own click. The
/// script takes `install.lock` before it touches anything (`acquire_install_lock`:
/// on macOS `exec 9<>install.lock; lockf 9`) and only after resolving the release;
/// where `lockf` is missing it makes `install.lock.d/` with its `pid` instead. So
/// the lock is asked, not the process table, and a lock whose holder died is
/// released by the kernel.
///
/// `/usr/bin/lockf <fd>` takes an `flock(2)` lock on the shell's descriptor (its
/// man page: "the -k option is implied when a file descriptor is in use"), held
/// while any process has that descriptor open. So the question is asked the way
/// `lockf` would meet it: a non-blocking `flock(LOCK_EX)` on a descriptor of our
/// own, released at once when it succeeds. `F_GETLK` is asked too, for a record
/// lock: on macOS 26.7 it also reported the `lockf` lock (`F_WRLCK`, `l_pid` -1,
/// measured 2026-10-04), but the same day a test holding the lock that way saw
/// no lock on the macOS 27.0 CI runner (#988's first run; why was not pinned
/// down), so it is not what the answer rests on.
///
/// A running Codex session is **not** a reason to wait: the installer writes a new
/// `releases/<version>-<target>` and swaps the `current` link by rename, and the
/// session keeps the release it started from.
public enum CodexActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// The installer holds `install.lock` (pid, when the kernel names it).
        case installer(pid_t?)

        public var description: String {
            switch self {
            case .installer(let pid?): return "the Codex installer is running (pid \(pid))"
            case .installer(nil): return "the Codex installer is running"
            }
        }
    }

    public static func busy(
        root: URL, isAlive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) -> Busy? {
        if let holder = lockHolder(root.appendingPathComponent("install.lock")) {
            return .installer(holder)
        }
        // The `mkdir` fallback: the installer writes its pid into the directory.
        let directory = root.appendingPathComponent("install.lock.d")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        let text = (try? String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)) ?? ""
        guard let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else {
            // Created, pid not written yet: the installer writes it right after.
            return .installer(nil)
        }
        return isAlive(pid) ? .installer(pid) : nil
    }

    /// Whether the file is locked: `.some(pid)` when it is — the pid nil when the
    /// kernel names none, as for an `flock(2)` lock — and nil when it is free or
    /// missing. Nothing is written, and the file is never created; the probe's
    /// own `flock` is released before this returns (an installer reaching
    /// `lockf` in that instant waits for it, as `lockf` without `-t` does).
    static func lockHolder(_ url: URL) -> pid_t?? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        if let holder = recordLockHolder(fd) { return .some(holder) }
        return isFlocked(fd) ? .some(nil) : nil
    }

    /// A record (`fcntl`) lock's holder — its pid, nil inside when the kernel
    /// names none — or nil when there is no such lock.
    static func recordLockHolder(_ fd: Int32) -> pid_t?? {
        var query = flock()
        query.l_type = Int16(F_WRLCK)
        query.l_whence = Int16(SEEK_SET)
        query.l_start = 0
        query.l_len = 0
        guard fcntl(fd, F_GETLK, &query) == 0, query.l_type != Int16(F_UNLCK) else { return nil }
        return .some(query.l_pid > 0 ? query.l_pid : nil)
    }

    /// Whether another open file holds an `flock(2)` lock: ours would block.
    static func isFlocked(_ fd: Int32) -> Bool {
        if lockFile(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = lockFile(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }
}

/// `flock(2)`. Swift imports the C function under the same name as `struct
/// flock`, and the struct's initializer wins the lookup.
@_silgen_name("flock")
func lockFile(_ fd: Int32, _ operation: Int32) -> Int32
