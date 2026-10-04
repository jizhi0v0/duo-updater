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
/// the lock is asked, not the process table: `F_GETLK` sees it without taking it,
/// and a lock whose holder died is released by the kernel.
///
/// Measured 2026-10-04: `/usr/bin/lockf <fd>` takes an `flock(2)` lock on the
/// shell's descriptor, held until the shell exits. `F_GETLK` from another process
/// reports it as `F_WRLCK` with `l_pid` -1 — a lock, but no pid to name.
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
    /// missing. Read-only: nothing is locked or written.
    static func lockHolder(_ url: URL) -> pid_t?? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var query = flock()
        query.l_type = Int16(F_WRLCK)
        query.l_whence = Int16(SEEK_SET)
        query.l_start = 0
        query.l_len = 0
        guard fcntl(fd, F_GETLK, &query) == 0, query.l_type != Int16(F_UNLCK) else { return nil }
        return .some(query.l_pid > 0 ? query.l_pid : nil)
    }
}
