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
/// Signals go only to the groups of members found that way. `getsid`
/// answers for a process of another session on macOS:
/// `aDescendantInAGroupOfItsOwnIsStoppedAndWaitedFor` finds its grandchild
/// only through it, and fails with the session taken away. A session's id is
/// looked for only while it has members (`sessions`), so a number the kernel
/// has handed to someone else is never signalled; no start-time filter is
/// needed for that, and none is used (a wall clock stepped back would have
/// hidden real members — review).
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
    /// A session leaves this set once two scans in a row find none of its
    /// members and none of its groups is left (`misses`, `groups`), and is
    /// never looked for again: while it has a member the kernel gives its id
    /// to no one (XNU skips a pid still used by a process, a group or a
    /// session, `bsd/kern/kern_fork.c`), but once it is empty the id is free,
    /// and a scan by number could find a stranger (review: the ladder's
    /// SIGTERM at 30 s reached a session that reused the id).
    private var sessions: Set<pid_t> = []
    /// Scans in a row that found none of a session's members. One is not
    /// enough: a fork-and-exit chain can be missed by one, and a session
    /// dropped then is not looked for when its survivor moves to a group of
    /// its own — local adversarial review: it then ran on, writing, through
    /// the put-back (5 in 5 with a 2 ms relay).
    private var misses: [pid_t: Int] = [:]
    /// Every process group a member was seen in, until the group is empty.
    /// Reading the table and then each entry's session is not atomic: a
    /// process that forks and exits between the two leaves its child
    /// unlisted, and the scan reads empty (review: a fork-and-exit relay made
    /// `waitUntilGone` return with it running, 6 times in 6). The child stays
    /// in its parent's group, and `killpg(group, 0)` asks the kernel about the
    /// whole group at once. Each with the session it belongs to (a group is
    /// in one session): a session keeps its place while a group of it is left.
    private var groups: [pid_t: pid_t] = [:]
    /// Every session and group is gone: nothing more is signalled or waited
    /// for.
    private var gone = false
    private var finished = false

    /// The process table's reader: `processes`; a test's stands in for it.
    private let table: @Sendable () -> [Member]?

    init(termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
         giveUpAfter: Duration = ManagedStop.giveUpAfter,
         table: @escaping @Sendable () -> [Member]? = { ManagedStop.processes() }) {
        self.termAfter = termAfter
        self.killAfter = killAfter
        self.giveUpAfter = giveUpAfter
        self.table = table
    }

    /// The sessions still followed: for a test.
    var trackedSessions: Set<pid_t> { lock.withLock { sessions } }

    /// The child started (its session's id is its pid): a stop asked for
    /// before this lands now.
    func launched(_ pid: pid_t) {
        let stopNow = lock.withLock { () -> Bool in
            self.pid = pid
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
        guard let (all, known) = scan() else { return }
        let pids = Set(known.map(\.pid))
        let new = all.filter { pids.contains($0.ppid) && getsid($0.pid) == $0.pid }.map(\.pid)
        guard !new.isEmpty else { return }
        lock.withLock { if !gone { sessions.formUnion(new) } }
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
    /// child's or one a member started (`sessions`). Nil when the process
    /// table could not be read — which never reads as "none left".
    func members() -> [Member]? {
        scan().map(\.members)
    }

    /// The table and the sessions' members in it, dropping each session none
    /// is left in (see `sessions`); `gone` once none is left at all. Before
    /// the launch there is nothing to look for, and nothing is read, dropped
    /// or latched: a stop asked for then (Cancel between the runner's check
    /// and the spawn) must still reach the child (review round 4: a scan then
    /// latched `gone`, the child got no SIGINT and ran to its end, and the
    /// put-back ran at once). The followed sessions are read before the
    /// table, never after: a table read before a session was added (the
    /// launch, `adoptSessions`) does not list it, and would drop it (review
    /// round 5).
    private func scan() -> (all: [Member], members: [Member])? {
        let (tracked, launched) = lock.withLock { (sessions, pid != nil) }
        guard launched else { return ([], []) }
        guard let all = table() else { return nil }
        let found = all.compactMap { member -> (Member, pid_t)? in
            let sid = getsid(member.pid)
            return tracked.contains(sid) ? (member, sid) : nil
        }
        let live = Set(found.map(\.1))
        let seen = lock.withLock { () -> [pid_t] in
            if !gone { for (member, sid) in found { groups[member.pgid] = sid } }
            // Only the sessions this scan looked for: one added meanwhile
            // has not been looked for yet.
            for session in tracked { misses[session] = live.contains(session) ? 0 : misses[session, default: 0] + 1 }
            return Array(groups.keys)
        }
        // EPERM: a member is there, not ours to signal, or only zombies.
        let empty = seen.filter { killpg($0, 0) != 0 && errno == ESRCH }
        lock.withLock {
            for group in empty { groups[group] = nil }
            let held = Set(groups.values)
            let drop = tracked.filter { misses[$0, default: 0] >= 2 && !held.contains($0) }
            sessions.subtract(drop)
            for session in drop { misses[session] = nil }
            if sessions.isEmpty && groups.isEmpty { gone = true }
        }
        return (all, found.map(\.0))
    }

    /// Every process, from the kernel's process table (`KERN_PROC_ALL`, what
    /// `ps` reads). Not `proc_pidinfo`: for a process of another user — a
    /// setuid program such as `/usr/bin/top` or `/bin/ps` a vendor runs — it
    /// fails with EPERM (measured 2026-10-27 as uid 501 on launchd, syslogd,
    /// cfprefsd), and that member would go unseen; the sysctl answers for
    /// every process (review round 3).
    /// Nil when it cannot be read: a caller must not take that for an empty
    /// table (review: it read as "nothing left", and the put-back ran).
    static func processes() -> [Member]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for attempt in 0..<8 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            // Room for processes started between the two calls, more each time.
            size += size / 8 * (attempt + 1)
            var table = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
            var used = table.count * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &table, &used, nil, 0) == 0 {
                return table.prefix(used / MemoryLayout<kinfo_proc>.stride).map(member)
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
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
        guard !lock.withLock({ gone }) else { return }
        // An unreadable table: SIGTERM and SIGKILL still reach the groups
        // already seen (their ids are not reused while they hold anyone).
        let members = self.members() ?? []
        let reached = members.filter { signal != SIGINT || getsid($0.pid) == own }
        var groups = Set(reached.map(\.pgid))
        // SIGTERM and SIGKILL also reach the groups seen before and not yet
        // empty: what a fork-and-exit chain left unlisted in this scan.
        if signal != SIGINT { groups.formUnion(lock.withLock { self.groups.keys }) }
        if signal == SIGINT {
            groups = lock.withLock { groups.filter { interrupted.insert($0).inserted } }
        }
        for group in groups { _ = killpg(group, signal) }
    }

    /// SIGTERM, then SIGKILL, to whatever is left, at `termAfter` and
    /// `killAfter` after the stop — the child included, which a vendor that
    /// ignores SIGINT keeps alive.
    private func climb() {
        let (termAfter, killAfter, giveUpAfter) = (self.termAfter, self.killAfter, self.giveUpAfter)
        guard let start = lock.withLock({ stoppedAt }) else { return }
        // A thread of its own, not a task: a loaded cooperative pool can hold
        // a `Task.sleep` far past its deadline (a loaded test pool once ran a
        // SIGINT- and SIGTERM-proof command on to its 20 s deadline), and the
        // ladder is what ends such a command.
        let thread = Thread { [self] in
            let clock = ContinuousClock()
            func wait(until deadline: ContinuousClock.Instant) {
                while clock.now < deadline, !lock.withLock({ gone }) { usleep(20_000) }
            }
            wait(until: start + termAfter)
            guard !lock.withLock({ gone }), alive() else { return }
            signal(SIGTERM)
            wait(until: start + killAfter)
            // SIGKILL until nothing is left, every 100 ms: one can be lost to a
            // table that could not be read, or miss a child forked while it is
            // delivered.
            while !lock.withLock({ gone }), alive(), clock.now - start < giveUpAfter {
                signal(SIGKILL)
                usleep(100_000)
            }
        }
        thread.name = "ManagedStop ladder"
        thread.start()
    }

    /// Any member of the sessions left, the child itself included; an
    /// unreadable process table counts as yes.
    func alive() -> Bool {
        guard !lock.withLock({ gone }) else { return false }
        guard let members = members() else { return true }
        return !members.isEmpty || !lock.withLock({ groups.isEmpty })
    }

    /// Wait, after a stop (`interrupt`), until no member of the session is
    /// left; true when none is, false when some outlived `giveUpAfter` from
    /// the stop. The ladder (`climb`) does the signalling; a group found now
    /// that missed the SIGINT (it started after it) is sent one.
    func waitUntilGone() async -> Bool {
        guard lock.withLock({ self.pid }) != nil else { return true }
        let (giveUpAfter, killAfter) = (self.giveUpAfter, self.killAfter)
        // Unstructured: the caller is usually cancelled — that is why it
        // stopped the command — and a cancelled task's sleep returns at once.
        let gone = await Task { [self] in
            let start = lock.withLock { stoppedAt } ?? .now
            while true {
                adoptSessions()
                guard alive() else { return true }
                signal(SIGINT)
                let elapsed = ContinuousClock.now - start
                // Past the ladder's SIGKILL, again on every pass, in case one
                // misses a child forked while it is delivered — not seen to be
                // needed (the fork-and-exit relay test passes without it).
                if elapsed >= killAfter { signal(SIGKILL) }
                if elapsed >= giveUpAfter { return false }
                // cancel-ok: an unstructured task no cancel reaches; bounded by giveUpAfter
                try? await Task.sleep(for: .milliseconds(100))
            }
        }.value
        finish()
        return gone
    }

}
