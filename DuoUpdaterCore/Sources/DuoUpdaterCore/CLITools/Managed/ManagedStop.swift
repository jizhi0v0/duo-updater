import Darwin
import Foundation

/// Stops a vendor's command the way a terminal's Ctrl-C does, and says when
/// nothing of it is left running — what `ManagedSnapshot.restore` waits for,
/// since a build's `rustc` or `make` children outlive their parent's exit.
///
/// The child runs in a session of its own (`ChildProcess`'s `newSession`),
/// which makes it the leader of a new group too. A process group is not
/// enough to find everything it started: mise starts the `node` it has just
/// installed in a group of its own, and did so after the SIGINT had reached
/// mise (2026-10-27, on the Mac: `…/installs/node/20.20.2/bin/node`, pgid its
/// own pid, ppid 1 once mise had exited). A first fix listed the child's
/// descendants by parent link every 20 ms; under a loaded test pool the list
/// came too late, the parent was gone, and so was the link. A session id is
/// kept by every descendant that does not call `setsid` itself, whichever
/// group it starts and whoever its parent becomes, so the members are read
/// from the process table by session (`members`) whenever they are needed.
/// Each is also checked to have started no earlier than the child: a pid is
/// never taken for a member it merely shares a number with.
///
/// The ladder, from the moment of the stop, to every group a member leads or
/// sits in: SIGINT at once — the vendor's own interrupt handling (pipx's
/// `pipx_unfinished` mark, python-build's removal of the half-built version)
/// runs, and the snapshot puts back whatever it left — SIGTERM after
/// `termAfter`, SIGKILL after `killAfter`, whether or not the child itself has
/// exited yet; `waitUntilGone` gives up `giveUpAfter` after the stop.
final class ManagedStop: @unchecked Sendable {
    static let termAfter: Duration = .seconds(30)
    static let killAfter: Duration = .seconds(45)
    /// Past this, members still alive are reported, and nothing is put back
    /// under them.
    static let giveUpAfter: Duration = .seconds(60)

    /// A process of the session, by pid, group and start time.
    struct Member: Hashable, Sendable {
        let pid: pid_t
        let pgid: pid_t
        let started: UInt64
    }

    private let termAfter: Duration
    private let killAfter: Duration
    private let giveUpAfter: Duration
    private let lock = NSLock()
    private var pid: pid_t?
    /// The child's start time (`Member.started`'s units), read at launch.
    private var launchedAt: UInt64 = 0
    private var requested = false
    private var stoppedAt: ContinuousClock.Instant?
    /// Groups sent their SIGINT: one each, as one Ctrl-C — a second could cut
    /// the vendor's own clean-up short.
    private var interrupted: Set<pid_t> = []

    init(termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
         giveUpAfter: Duration = ManagedStop.giveUpAfter) {
        self.termAfter = termAfter
        self.killAfter = killAfter
        self.giveUpAfter = giveUpAfter
    }

    /// The child started (its session's id is its pid): a stop asked for
    /// before this lands now.
    func launched(_ pid: pid_t) {
        let started = Self.bsdInfo(pid).map(Self.start) ?? 0
        let stopNow = lock.withLock { () -> Bool in
            self.pid = pid
            launchedAt = started
            return requested
        }
        if stopNow { signal(SIGINT) }
    }

    /// The caller was cancelled: SIGINT to every group of the session, then
    /// the rest of the ladder.
    func interrupt() {
        let first = lock.withLock { () -> Bool in
            guard !requested else { return false }
            requested = true
            stoppedAt = ContinuousClock.now
            return true
        }
        guard first else { return }
        signal(SIGINT)
        climb()
    }

    var wasInterrupted: Bool { lock.withLock { requested } }
    var didLaunch: Bool { lock.withLock { pid != nil } }

    /// The session's processes now: every process whose session id is the
    /// child's pid and that started no earlier than the child.
    func members() -> [Member] {
        guard let (pid, since) = lock.withLock({ self.pid.map { ($0, launchedAt) } }) else { return [] }
        return Self.processes().filter { getsid($0.pid) == pid && $0.started >= since }
    }

    static func processes() -> [Member] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) })
        guard count > 0 else { return [] }
        return pids.prefix(min(count, capacity)).compactMap { pid in
            guard pid > 0, let info = bsdInfo(pid) else { return nil }
            return Member(pid: pid, pgid: pid_t(info.pbi_pgid), started: start(info))
        }
    }

    static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func start(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    /// `signal` to every group a member of the session sits in, the child's
    /// own included while it lives.
    private func signal(_ signal: Int32) {
        var groups = Set(members().map(\.pgid))
        if let pid = lock.withLock({ self.pid }) { groups.insert(pid) }
        if signal == SIGINT {
            groups = lock.withLock { groups.filter { interrupted.insert($0).inserted } }
        }
        for group in groups { _ = killpg(group, signal) }
    }

    /// SIGTERM, then SIGKILL, to whatever is left, at `termAfter` and
    /// `killAfter` after the stop — the child included, which a vendor that
    /// ignores SIGINT keeps alive.
    private func climb() {
        let (termAfter, killAfter) = (self.termAfter, self.killAfter)
        Task.detached { [self] in
            for (after, signal) in [(termAfter, SIGTERM), (killAfter, SIGKILL)] {
                guard let start = lock.withLock({ stoppedAt }) else { return }
                // cancel-ok: a detached task no cancel reaches; two steps, then done
                try? await Task.sleep(until: start + after, clock: .continuous)
                guard alive() else { return }
                self.signal(signal)
            }
        }
    }

    /// Any member of the session left, the child itself included.
    private func alive() -> Bool {
        guard let pid = lock.withLock({ self.pid }) else { return false }
        return Self.alive(pid) || !members().isEmpty
    }

    /// Wait, after a stop (`interrupt`), until no member of the session is
    /// left; true when none is, false when some outlived `giveUpAfter` from
    /// the stop. The ladder (`climb`) does the signalling; a group found now
    /// that missed the SIGINT (it started after it) is sent one.
    func waitUntilGone() async -> Bool {
        guard lock.withLock({ self.pid }) != nil else { return true }
        let giveUpAfter = self.giveUpAfter
        // Unstructured: the caller is usually cancelled — that is why it
        // stopped the command — and a cancelled task's sleep returns at once.
        return await Task { [self] in
            let start = lock.withLock { stoppedAt } ?? .now
            while true {
                guard alive() else { return true }
                signal(SIGINT)
                if ContinuousClock.now - start >= giveUpAfter { return false }
                // cancel-ok: an unstructured task no cancel reaches; bounded by giveUpAfter
                try? await Task.sleep(for: .milliseconds(100))
            }
        }.value
    }

    /// Any member of group `pid` left (EPERM: one is, and not ours to signal).
    static func alive(_ pid: pid_t) -> Bool {
        if killpg(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
