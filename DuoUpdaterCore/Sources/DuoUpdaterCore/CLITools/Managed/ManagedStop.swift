import Darwin
import Foundation

/// Stops a vendor's command the way a terminal's Ctrl-C does, and says when
/// nothing of it is left running — what `ManagedSnapshot.restore` waits for,
/// since a build's `rustc` or `make` children outlive their parent's exit.
///
/// The child is its own process group's leader (`ChildProcess`: pgid = its
/// pid), and most of its children stay in that group. While any member lives,
/// no new process can be given that number as its pid or group, so signalling
/// the group never reaches anyone else.
///
/// Not all of them: mise starts the `node` it has just installed in a group of
/// its own, and it did so after the SIGINT had reached mise (2026-10-27, on
/// the Mac: `…/installs/node/20.20.2/bin/node`, pgid its own pid, ppid 1 once
/// mise had exited). Such a process is out of the group's reach and, once its
/// parent has gone, out of its tree too. So the child's descendants are
/// listed while it runs (`track`), each kept by pid and start time; one that
/// leads a group of its own is signalled there too, and waited for.
///
/// The ladder: SIGINT at once — the vendor's own interrupt handling (pipx's
/// `pipx_unfinished` mark, python-build's removal of the half-built version)
/// runs, and the snapshot puts back whatever it left — SIGTERM after
/// `termAfter`, SIGKILL after `killAfter`.
final class ManagedStop: @unchecked Sendable {
    static let termAfter: Duration = .seconds(30)
    static let killAfter: Duration = .seconds(45)
    /// Past this, members still alive are reported, and nothing is put back
    /// under them.
    static let giveUpAfter: Duration = .seconds(60)

    /// A process, by pid and start time: a pid alone may be reused.
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
    private var requested = false
    private var finished = false
    /// Descendants seen in groups other than the child's, and whether each
    /// group has had its SIGINT.
    private var others: [Member: Bool] = [:]

    init(termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
         giveUpAfter: Duration = ManagedStop.giveUpAfter) {
        self.termAfter = termAfter
        self.killAfter = killAfter
        self.giveUpAfter = giveUpAfter
    }

    /// The child started: a stop asked for before this lands now, and its
    /// descendants are watched until `finish`.
    func launched(_ pid: pid_t) {
        let stopNow = lock.withLock { () -> Bool in
            self.pid = pid
            return requested
        }
        if stopNow { _ = killpg(pid, SIGINT) }
        track(pid)
    }

    /// The caller was cancelled: SIGINT to the group, and to every other group
    /// a descendant leads, once each.
    func interrupt() {
        let pid = lock.withLock { () -> pid_t? in
            guard !requested else { return nil }
            requested = true
            return self.pid
        }
        if let pid { _ = killpg(pid, SIGINT) }
        signalOthers()
    }

    /// The run is over and nothing is being waited for: stop watching.
    func finish() {
        lock.withLock { finished = true }
    }

    var wasInterrupted: Bool { lock.withLock { requested } }
    var didLaunch: Bool { lock.withLock { pid != nil } }

    /// The descendants of `root` now, by the process table's parent links.
    static func descendants(of root: pid_t) -> [Member] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) })
        guard count > 0 else { return [] }
        var children: [pid_t: [(Member)]] = [:]
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            guard let info = bsdInfo(pid) else { continue }
            children[pid_t(info.pbi_ppid), default: []].append(
                Member(pid: pid, pgid: pid_t(info.pbi_pgid), started: start(info)))
        }
        var found: [Member] = []
        var queue = [root]
        while let next = queue.popLast() {
            for child in children[next] ?? [] where !found.contains(child) {
                found.append(child)
                queue.append(child.pid)
            }
        }
        return found
    }

    static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func start(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    /// `member` still running: its pid now names a process started when it was.
    static func running(_ member: Member) -> Bool {
        guard let info = bsdInfo(member.pid) else { return false }
        return start(info) == member.started
    }

    /// Every 100 ms while the child runs, 20 ms once a stop is asked for:
    /// a descendant in another group is recorded, and signalled if the stop
    /// has been asked for.
    private func track(_ root: pid_t) {
        Task.detached { [self] in
            while !lock.withLock({ finished }) {
                for member in Self.descendants(of: root) where member.pgid != root {
                    lock.withLock { if others[member] == nil { others[member] = false } }
                }
                let stopping = lock.withLock { requested }
                if stopping { signalOthers() }
                // cancel-ok: a detached task no cancel reaches; ends with `finish`
                try? await Task.sleep(for: .milliseconds(stopping ? 20 : 100))
            }
        }
    }

    private func signalOthers() {
        let due = lock.withLock { () -> [Member] in
            guard requested else { return [] }
            let due = others.filter { !$0.value }.map(\.key)
            for member in due { others[member] = true }
            return due
        }
        for member in due where Self.running(member) { _ = killpg(member.pgid, SIGINT) }
    }

    /// Signal the group, and the other groups seen, up the ladder until no
    /// member of any is left; true when none is, false when some outlived
    /// `giveUpAfter`. For a run that was interrupted, or stopped by its
    /// deadline (whose SIGTERM reaches only the child itself).
    func waitUntilGone() async -> Bool {
        guard let pid = lock.withLock({ self.pid }) else { finish(); return true }
        let (termAfter, killAfter, giveUpAfter) = (self.termAfter, self.killAfter, self.giveUpAfter)
        // Unstructured: the caller is usually cancelled — that is why it
        // stopped the command — and a cancelled task's sleep returns at once.
        let gone = await Task { [self] in
            let clock = ContinuousClock()
            let start = clock.now
            var sentTerm = false
            var sentKill = false
            while true {
                let others = lock.withLock { Array(self.others.keys) }.filter(Self.running)
                guard Self.alive(pid) || !others.isEmpty else { return true }
                let elapsed = clock.now - start
                if elapsed >= giveUpAfter { return false }
                let signal: Int32? = elapsed >= killAfter && !sentKill ? SIGKILL
                    : elapsed >= termAfter && !sentTerm ? SIGTERM : nil
                if let signal {
                    if signal == SIGKILL { sentKill = true } else { sentTerm = true }
                    _ = killpg(pid, signal)
                    for member in others { _ = killpg(member.pgid, signal) }
                }
                // cancel-ok: an unstructured task no cancel reaches; bounded by giveUpAfter
                try? await Task.sleep(for: .milliseconds(100))
            }
        }.value
        finish()
        return gone
    }

    /// Any member of group `pid` left (EPERM: one is, and not ours to signal).
    static func alive(_ pid: pid_t) -> Bool {
        if killpg(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
