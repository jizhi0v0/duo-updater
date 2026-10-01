import Foundation

/// Is rustup already changing something right now?
///
/// rustup takes no lock of its own (rust-lang/rustup#731, open on 2026-10-01).
/// Two `rustup update` runs started together on one toolchain were measured
/// that day: one failed, and the toolchain was left with `cargo-…` listed twice
/// in `lib/rustlib/components`. So every Rust row shares one gate — a toolchain
/// and rustup itself live under the same `~/.rustup` and `~/.cargo/bin` — asked
/// of the process table (`ClaudeCodeActivity.runningProcesses()`) at the check
/// and again at the click.
///
/// What counts: `rustup` or `rustup-init` with a subcommand that installs,
/// updates or removes — `update`/`upgrade`, `install`/`uninstall`, `default`
/// (installs a missing toolchain), `toolchain`/`component`/`target` with
/// `install`/`add`/`uninstall`/`remove`/`link`/`update`, `self update`/`self
/// uninstall` — and any `rustup-init` at all: the installer, and the second half
/// of every self-update (`rustup-init --self-replace`). Options before the
/// subcommand (`rustup -v update`, `rustup +nightly …`) are looked past.
///
/// Not seen: a proxy (`cargo +nightly build`) installing a missing toolchain on
/// its own, whose argv names `cargo`, not rustup.
public enum RustActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// A rustup command that changes the install (the command, pid).
        case rustup(String, pid: pid_t)
        /// A rustup command DuoUpdater itself started and is still waiting on.
        case ours

        public var description: String {
            switch self {
            case .rustup(let command, let pid): return "\(command) is running (pid \(pid))"
            case .ours: return "DuoUpdater is already running a rustup command"
            }
        }
    }

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if let command = changingCommand(process.arguments) { return .rustup(command, pid: process.pid) }
        }
        return nil
    }

    static let changing: Set<String> = ["update", "upgrade", "install", "uninstall", "default"]
    static let grouped: Set<String> = ["toolchain", "component", "target", "self"]
    static let groupedChanging: Set<String> = ["install", "add", "uninstall", "remove", "link", "update"]

    /// The command line as the row names it ("rustup update"), or nil when it
    /// changes nothing.
    static func changingCommand(_ arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let program = (first as NSString).lastPathComponent
        if program == "rustup-init" { return "rustup-init" }
        guard program == "rustup" else { return nil }
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") && !$0.hasPrefix("+") }
        guard let command = words.first else { return nil }
        if changing.contains(command) { return "rustup \(command)" }
        if grouped.contains(command), let sub = words.dropFirst().first, groupedChanging.contains(sub) {
            return "rustup \(command) \(sub)"
        }
        return nil
    }

    /// DuoUpdater never runs two rustup commands at once, whichever rows they
    /// come from: the app runs its own "Update all" one at a time, but two rows
    /// clicked in quick succession each start their own update, and the second
    /// can look at the process table before the first one's rustup is in it.
    final class RunLock: @unchecked Sendable {
        private let lock = NSLock()
        private var held = false

        init() {}

        static let shared = RunLock()

        func tryAcquire() -> Bool {
            lock.withLock {
                guard !held else { return false }
                held = true
                return true
            }
        }

        func release() {
            lock.withLock { held = false }
        }
    }
}
