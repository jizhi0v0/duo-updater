import Foundation

/// Is a bun already changing itself, or its global install, right now?
///
/// bun documents no lock for either. `bun upgrade` replaces its own file by
/// rename; `bun add -g` rewrites `~/.bun/install/global`'s `package.json`,
/// `bun.lock` and `node_modules`, so two of them race. A bun process is told by
/// what it executes — `proc_pidpath` is the bun binary — and by its argv, which
/// bun leaves as it was started (unlike npm, it sets no process title).
///
/// The rule is coarse in one direction, like npm's: any `bun add -g` from this
/// bun holds back every package row, and a `bun upgrade` the bun row.
public enum BunActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case bun(String, pid: pid_t)

        public var description: String {
            switch self {
            case .bun(let command, let pid): return "\(command) is running (pid \(pid))"
            }
        }
    }

    /// bun's subcommands that write the global install, with their aliases
    /// (`bun --help`, 1.3.10).
    static let changingCommands: Set<String> = [
        "add", "a", "install", "i", "remove", "rm", "uninstall", "update", "link", "unlink",
    ]

    /// `bun upgrade` from this bun.
    public static func upgrading(bun: String, processes: [NpmActivity.Process]) -> Busy? {
        for process in processes where isBun(process, bun: bun) {
            if let command = command(process.arguments), command == "upgrade" {
                return .bun("bun upgrade", pid: process.pid)
            }
        }
        return nil
    }

    /// A `bun <add|remove|…> -g` from this bun, or — through `NpmActivity` — the
    /// package's own updater (`openclaw update`, which runs `bun add -g`).
    public static func busy(_ install: NpmInstall, processes: [NpmActivity.Process]) -> NpmActivity.Busy? {
        if let bun = install.bun?.path {
            for process in processes where isBun(process, bun: bun) {
                guard let command = command(process.arguments), changingCommands.contains(command),
                      process.arguments.contains(where: { $0 == "-g" || $0 == "--global" })
                else { continue }
                return .ownUpdater("bun \(command) -g", pid: process.pid)
            }
        }
        return NpmActivity.busy(install, processes: processes)
    }

    static func isBun(_ process: NpmActivity.Process, bun: String) -> Bool {
        guard let executable = process.executable else { return false }
        return URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: bun).resolvingSymlinksInPath().path
    }

    /// The first argument after the executable that is not a flag.
    static func command(_ arguments: [String]) -> String? {
        arguments.dropFirst().first { !$0.hasPrefix("-") }
    }
}
