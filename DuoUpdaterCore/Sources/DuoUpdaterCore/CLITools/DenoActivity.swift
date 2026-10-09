import Foundation

/// Is a `deno upgrade` already replacing this Deno right now?
///
/// Deno documents no lock for it (`docs.deno.com/runtime/reference/cli/upgrade`,
/// read 2026-10-09). `deno upgrade` downloads into a temporary directory, runs
/// the new file's `-V`, then renames it over its own path; two at once would
/// race that rename. A deno process is told by what it executes —
/// `proc_pidpath` is the deno binary — and its argv, as bun's are
/// (`BunActivity`).
public enum DenoActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case upgrade(pid: pid_t)

        public var description: String {
            switch self {
            case .upgrade(let pid): return "deno upgrade is running (pid \(pid))"
            }
        }
    }

    /// `deno upgrade` from this deno, whatever its flags.
    public static func upgrading(deno: String, processes: [NpmActivity.Process]) -> Busy? {
        for process in processes where BunActivity.isBun(process, bun: deno) {
            if BunActivity.command(process.arguments) == "upgrade" { return .upgrade(pid: process.pid) }
        }
        return nil
    }
}
