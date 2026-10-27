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
/// never taken for a member it merely shares a number with. Signals go only
/// to the groups of members found that way — never to the child's pid as a
/// number, which once the child is gone could name someone else's group
/// (review round 2). `getsid` answers for a process of another session on
/// macOS: `aDescendantInAGroupOfItsOwnIsStoppedAndWaitedFor` finds its
/// grandchild only through it, and fails with the session taken away.
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

    /// A process of the session, by pid, parent, group and start time.
    struct Member: Hashable, Sendable {
        let pid: pid_t
        let ppid: pid_t
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
    /// The child's session, then every session a member started of its own
    /// (`track`): pipx 1.18.4 starts its uv or pip in a new session
    /// (`start_new_session=True`, `pipx/util.py`), so that a terminal's
    /// Ctrl-C reaches pipx alone and pipx stops that group itself — and its
    /// own comment says a grandchild can outlive the group's leader
    /// (`fanout.stop_process_group`). Measured 2026-10-27: pipx's `uv` had
    /// `sid == pid`, outside pipx's session. Those sessions are followed by
    /// id from the moment they are seen, whoever their parent becomes.
    private var sessions: Set<pid_t> = []
    private var finished = false

    init(termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
         giveUpAfter: Duration = ManagedStop.giveUpAfter) {
        self.termAfter = termAfter
        self.killAfter = killAfter
        self.giveUpAfter = giveUpAfter
    }

    /// The child started (its session's id is its pid): a stop asked for
    /// before this lands now.
    func launched(_ pid: pid_t) {
        let started = Self.process(pid)?.started ?? 0
        let stopNow = lock.withLock { () -> Bool in
            self.pid = pid
            launchedAt = started
            sessions = [pid]
            return requested
        }
        if stopNow { signal(SIGINT) }
        track()
    }

    /// The run has ended and nothing is being waited for: stop following.
    func finish() {
        lock.withLock { finished = true }
    }

    /// Every 100 ms while the command runs (20 ms once stopping): a process
    /// whose parent is a member and that leads a session of its own adds that
    /// session. Seen while its parent waits on it — pipx waits on its uv for
    /// the whole upgrade — and followed by id from then on.
    private func track() {
        Task.detached { [self] in
            while !lock.withLock({ finished }) {
                adoptSessions()
                let stopping = lock.withLock { requested }
                // cancel-ok: a detached task no cancel reaches; ends with `finish`
                try? await Task.sleep(for: .milliseconds(stopping ? 20 : 100))
            }
        }
    }

    private func adoptSessions() {
        let all = Self.processes()
        let known = Set(members(of: all).map(\.pid))
        let since = lock.withLock { launchedAt }
        let new = all.filter { known.contains($0.ppid) && $0.started >= since && getsid($0.pid) == $0.pid }.map(\.pid)
        guard !new.isEmpty else { return }
        lock.withLock { sessions.formUnion(new) }
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

    /// The sessions' processes now: every process whose session is the
    /// child's or one a member started (`sessions`), and that started no
    /// earlier than the child.
    func members() -> [Member] {
        members(of: Self.processes())
    }

    private func members(of all: [Member]) -> [Member] {
        let (sessions, since) = lock.withLock { (self.sessions, launchedAt) }
        guard !sessions.isEmpty else { return [] }
        return all.filter { $0.started >= since && sessions.contains(getsid($0.pid)) }
    }

    /// Every process, from the kernel's process table (`KERN_PROC_ALL`, what
    /// `ps` reads). Not `proc_pidinfo`: for a process of another user — a
    /// setuid program such as `/usr/bin/top` or `/bin/ps` a vendor runs — it
    /// fails with EPERM (measured 2026-10-27 as uid 501 on launchd, syslogd,
    /// cfprefsd), and that member would go unseen; the sysctl answers for
    /// every process (review round 3).
    static func processes() -> [Member] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
            // Room for processes started between the two calls.
            size += size / 8
            var table = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
            var used = table.count * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &table, &used, nil, 0) == 0 {
                return table.prefix(used / MemoryLayout<kinfo_proc>.stride).map(member)
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    /// One process, as `processes` reads it; nil when there is none.
    static func process(_ pid: pid_t) -> Member? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return member(info)
    }

    private static func member(_ info: kinfo_proc) -> Member {
        let start = info.kp_proc.p_starttime
        return Member(
            pid: info.kp_proc.p_pid, ppid: info.kp_eproc.e_ppid, pgid: info.kp_eproc.e_pgid,
            started: UInt64(start.tv_sec) &* 1_000_000 &+ UInt64(start.tv_usec))
    }

    /// `signal` to every group a member sits in (the child is a member while
    /// it lives). SIGINT goes to the child's own session only, as a
    /// terminal's Ctrl-C would: a session a member started of its own is that
    /// member's to stop (pipx stops its uv itself), and gets only the
    /// ladder's SIGTERM and SIGKILL.
    private func signal(_ signal: Int32) {
        let own = lock.withLock { pid }
        let reached = members().filter { signal != SIGINT || getsid($0.pid) == own }
        var groups = Set(reached.map(\.pgid))
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
        !members().isEmpty
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
        let gone = await Task { [self] in
            let start = lock.withLock { stoppedAt } ?? .now
            while true {
                adoptSessions()
                guard alive() else { return true }
                signal(SIGINT)
                if ContinuousClock.now - start >= giveUpAfter { return false }
                // cancel-ok: an unstructured task no cancel reaches; bounded by giveUpAfter
                try? await Task.sleep(for: .milliseconds(100))
            }
        }.value
        finish()
        return gone
    }

}
