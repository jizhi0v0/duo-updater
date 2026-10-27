import Darwin
import Foundation

/// Stops a vendor's command the way a terminal's Ctrl-C does, and says when
/// nothing of it is left running — what `ManagedSnapshot.restore` waits for,
/// since a build's `rustc` or `make` children outlive their parent's exit.
///
/// The child is its own process group's leader (`ChildProcess`: pgid = its
/// pid), and its children stay in that group. While any member lives, no new
/// process can be given that number as its pid or group, so signalling the
/// group never reaches anyone else.
///
/// The ladder: SIGINT to the group at once — the vendor's own interrupt
/// handling (pipx's `pipx_unfinished` mark, python-build's removal of the
/// half-built version) runs, and the snapshot puts back whatever it left —
/// SIGTERM after `termAfter`, SIGKILL after `killAfter`.
final class ManagedStop: @unchecked Sendable {
    static let termAfter: Duration = .seconds(30)
    static let killAfter: Duration = .seconds(45)
    /// Past this, members still alive are reported, and nothing is put back
    /// under them.
    static let giveUpAfter: Duration = .seconds(60)

    private let termAfter: Duration
    private let killAfter: Duration
    private let giveUpAfter: Duration
    private let lock = NSLock()
    private var pid: pid_t?
    private var requested = false

    init(termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
         giveUpAfter: Duration = ManagedStop.giveUpAfter) {
        self.termAfter = termAfter
        self.killAfter = killAfter
        self.giveUpAfter = giveUpAfter
    }

    /// The child started: a stop asked for before this lands now.
    func launched(_ pid: pid_t) {
        let stopNow = lock.withLock { () -> Bool in
            self.pid = pid
            return requested
        }
        if stopNow { _ = killpg(pid, SIGINT) }
    }

    /// The caller was cancelled: SIGINT to the group, once.
    func interrupt() {
        let pid = lock.withLock { () -> pid_t? in
            guard !requested else { return nil }
            requested = true
            return self.pid
        }
        if let pid { _ = killpg(pid, SIGINT) }
    }

    var wasInterrupted: Bool { lock.withLock { requested } }
    var didLaunch: Bool { lock.withLock { pid != nil } }

    /// Signal the group up the ladder until no member is left; true when none
    /// is, false when some outlived `giveUpAfter`. For a run that was
    /// interrupted, or stopped by its deadline (whose SIGTERM reaches only
    /// the child itself).
    func waitUntilGone() async -> Bool {
        guard let pid = lock.withLock({ self.pid }) else { return true }
        let (termAfter, killAfter, giveUpAfter) = (self.termAfter, self.killAfter, self.giveUpAfter)
        // Unstructured: the caller is usually cancelled — that is why it
        // stopped the command — and a cancelled task's sleep returns at once.
        return await Task {
            let clock = ContinuousClock()
            let start = clock.now
            var sentTerm = false
            var sentKill = false
            while Self.alive(pid) {
                let elapsed = clock.now - start
                if elapsed >= giveUpAfter { return false }
                if elapsed >= killAfter, !sentKill {
                    sentKill = true
                    _ = killpg(pid, SIGKILL)
                } else if elapsed >= termAfter, !sentTerm {
                    sentTerm = true
                    _ = killpg(pid, SIGTERM)
                }
                // cancel-ok: an unstructured task no cancel reaches; bounded by giveUpAfter
                try? await Task.sleep(for: .milliseconds(100))
            }
            return true
        }.value
    }

    /// Any member of group `pid` left (EPERM: one is, and not ours to signal).
    static func alive(_ pid: pid_t) -> Bool {
        if killpg(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
