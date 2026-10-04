import Foundation

/// Is a `boat self-update` running right now?
///
/// Boat replaces its file by rename (a new inode after each update measured on
/// 2026-10-04), with bytes it checked against the release's `SHA256SUMS`, so two
/// updates at once leave the same verified file either way. A click still does
/// not start a second one beside an explicit `self-update`, to keep its outcome
/// its own.
///
/// Not seen: the update check every other `boat` command makes at startup
/// (`--no-update` skips it; it is throttled by `last_update_check` in Boat's
/// config — a first `boat status` updated 1.0.37 to 1.0.38, the `boat list`
/// right after did not). It is a moment inside an ordinary command, not a
/// process of its own, and it ends in the same verified rename.
public enum BoatActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case selfUpdate(pid_t)

        public var description: String {
            switch self {
            case .selfUpdate(let pid): return "boat self-update is running (pid \(pid))"
            }
        }
    }

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes where isSelfUpdate(process.arguments) {
            return .selfUpdate(process.pid)
        }
        return nil
    }

    /// `boat … self-update`, however boat was named on the command line; a global
    /// option before the subcommand (`boat --json self-update`) is looked past.
    static func isSelfUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "boat" else { return false }
        return arguments.dropFirst().contains("self-update")
    }
}
