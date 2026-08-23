import Foundation

/// A whole-machine mutex around "something is replacing an app bundle right
/// now", held by whichever of the menu-bar app and the `duo` CLI got there
/// first.
///
/// Both processes swap bundles in `/Applications` through the same staging
/// dance, and both write the same backup store. Two of them on the same app is
/// a corrupted install; two of them on different apps still race on the backup
/// index. `flock(2)` is advisory — it binds only the processes that ask — which
/// is exactly right here: everything that installs goes through this type, and
/// nothing else should be blocked from touching the directory.
///
/// **Never blocks.** A CLI that waits for a lock the menu-bar app holds during a
/// 400 MB download looks hung, and the honest answer ("the app is installing;
/// pid 5123") is more useful than a spinner. The holder's pid is written into
/// the lock file so a refusal can name it.
public final class InstallLock: @unchecked Sendable {

    public enum Failure: Error, CustomStringConvertible, LocalizedError {
        /// Another process holds it. `pid` is nil when the file was locked but
        /// its contents were unreadable or not yet written — the lock is still
        /// held, we just cannot say by whom.
        case heldByAnother(pid: pid_t?)
        case unavailable(String)

        /// The diagnostic form: English, and it names the pid. This is what
        /// `duo` prints and what the log carries — a terminal is where a pid is
        /// worth having, because `ps` is right there.
        public var description: String {
            switch self {
            case .heldByAnother(let pid):
                let who = pid.map { "process \($0)" } ?? "another process"
                return "another DuoUpdater install is in progress (\(who))"
            case .unavailable(let reason):
                return "could not take the install lock: \(reason)"
            }
        }

        /// The form shown in an app row, which is a different audience: it needs
        /// translating, and a bare pid there is a number with nothing to do —
        /// the row cannot act on it and the reader cannot look it up. What the
        /// user needs is what to do next, which is the same either way.
        ///
        /// Kept separate from `description` rather than replacing it: `duo`
        /// prints the error with `"\(error)"`, so folding the two together would
        /// have translated the CLI's stderr into the GUI user's language and
        /// dropped the pid a terminal can actually use.
        public var errorDescription: String? {
            switch self {
            case .heldByAnother:
                return String(localized: "Another update is being installed right now — by Duo Updater or by `duo` in a terminal. Try again once it finishes.")
            case .unavailable(let reason):
                return String(localized: "Couldn’t take the install lock: \(reason)")
            }
        }
    }

    /// -1 once released. Guarded by `state` because `release()` can arrive from a
    /// caller and from `deinit` on different threads.
    private var descriptor: Int32
    private let state = NSLock()
    private let url: URL

    private init(descriptor: Int32, url: URL) {
        self.descriptor = descriptor
        self.url = url
    }

    public static var defaultURL: URL {
        DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("install.lock")
    }

    /// Take the lock, or fail immediately saying who has it.
    ///
    /// The file is never deleted on release. Unlinking it opens a window where
    /// two processes hold locks on two different inodes that share a path and
    /// both believe they are exclusive; a stale empty file costs nothing.
    public static func acquire(at url: URL = defaultURL) throws -> InstallLock {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw Failure.unavailable("open \(url.path): \(String(cString: strerror(errno)))")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            // Capture errno before anything else runs: `holderPID` reads a file and
            // `close` is a syscall, either of which can overwrite it. Reading it
            // afterwards turned the common "another process has it" case into the
            // generic failure, losing the pid the message exists to report.
            let reason = errno
            let holder = holderPID(at: url)
            close(descriptor)
            if reason == EWOULDBLOCK { throw Failure.heldByAnother(pid: holder) }
            throw Failure.unavailable(String(cString: strerror(reason)))
        }

        // Record who we are, for the next process's error message. Truncate
        // first: a shorter pid must not leave digits of a longer one behind.
        ftruncate(descriptor, 0)
        lseek(descriptor, 0, SEEK_SET)
        let line = "\(getpid())\n"
        _ = line.withCString { write(descriptor, $0, strlen($0)) }

        return InstallLock(descriptor: descriptor, url: url)
    }

    /// Read the pid out of a lock file we could not take. Best-effort: the
    /// holder may not have written it yet.
    private static func holderPID(at url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Who currently holds the lock, or nil if it is free. Racy by nature — a
    /// caller that intends to install should just try to `acquire`. This exists
    /// for `duo doctor`, which reports rather than acts.
    public static func currentHolder(at url: URL = defaultURL) -> pid_t? {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) != 0 else {
            flock(descriptor, LOCK_UN)
            return nil
        }
        return holderPID(at: url)
    }

    /// Idempotent, and it has to be: `deinit` calls this too, and every real caller
    /// releases explicitly first (`ProcessInstallLock.release` does `lock?.release()`
    /// then `lock = nil`). Closing twice does not just waste a syscall — by the
    /// second call the number has usually been handed to whatever the process opened
    /// next, so `close` shuts a descriptor we do not own and `flock(LOCK_UN)` unlocks
    /// a lock that is not ours. In an app running several downloads at once that is
    /// somebody else's socket.
    public func release() {
        state.lock()
        let fd = descriptor
        descriptor = -1
        state.unlock()

        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }

    deinit { release() }
}

/// This process's claim on the machine-wide install lock, reference-counted.
///
/// Necessary because `flock` is exclusive *per open file description*, not per
/// process: two installs in the same app taking the lock separately would block
/// each other, and the menu-bar app deliberately runs up to four downloads and
/// two applies at once. So the first install in a process takes the lock, the
/// rest join it, and it is released when the last one finishes.
///
/// What it still excludes is the thing it was built for: a second *process*
/// swapping bundles and writing the backup index at the same time.
public actor ProcessInstallLock {

    public static let shared = ProcessInstallLock()

    private var lock: InstallLock?
    private var holders = 0
    private let url: URL

    public init(url: URL = InstallLock.defaultURL) {
        self.url = url
    }

    /// Join this process's claim, taking the machine-wide lock if we are the
    /// first. Throws `InstallLock.Failure` when another process holds it.
    ///
    /// Deliberately not a `withLock { }` closure: the menu-bar app's caller is
    /// `@MainActor`-isolated and non-`Sendable`, so handing a closure to this
    /// actor is a data-race error. Callers pair `claim()` with `release()`
    /// instead.
    public func claim() throws {
        if holders == 0 {
            lock = try InstallLock.acquire(at: url)
        }
        holders += 1
    }

    /// Drop one claim, releasing the machine-wide lock when it was the last.
    /// Balanced with `claim()`; calling it without one is a no-op rather than an
    /// underflow, so an over-eager cleanup path cannot free a live lock.
    public func release() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 {
            lock?.release()
            lock = nil
        }
    }
}
