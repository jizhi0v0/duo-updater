import Foundation

/// Is a `mise self-update` already replacing this mise right now?
///
/// `mise self-update` takes no lock (`src/cli/self_update.rs`, v2026.10.6); only
/// mise's opt-in automatic update (`self_update.auto`, off by default) takes
/// `$MISE_CACHE_DIR/…/auto-update`, through a hashed lock-file name that is
/// mise's internal detail and not read here. A mise process is told by what it
/// executes and its argv, as bun's are (`BunActivity`).
public enum MiseActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case selfUpdate(pid: pid_t)

        public var description: String {
            switch self {
            case .selfUpdate(let pid): return "mise self-update is running (pid \(pid))"
            }
        }
    }

    /// `mise self-update` from this mise. Its subcommand is the first argument
    /// that is not a flag; a global option with a value before it (`mise -C dir
    /// self-update`) is looked past by finding `self-update` anywhere.
    public static func selfUpdating(mise: String, processes: [NpmActivity.Process]) -> Busy? {
        for process in processes where BunActivity.isBun(process, bun: mise) {
            if process.arguments.dropFirst().contains("self-update") { return .selfUpdate(pid: process.pid) }
        }
        return nil
    }
}
