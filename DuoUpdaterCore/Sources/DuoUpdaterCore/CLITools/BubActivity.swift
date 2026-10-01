import Foundation

/// Is something already changing a bub venv right now?
///
/// The same question `ClaudeCodeActivity` asks, answered from the same process
/// table (`ClaudeCodeActivity.runningProcesses()`, argv by `KERN_PROCARGS2`). A
/// second `bub update` started while one runs would have two uv processes syncing
/// one venv.
///
/// What an update in flight looks like, sampled every 0.2 s from `ps` while
/// `bub update bub` ran in a scratch HOME (bub 0.4.4, uv 0.9.18, 2026-10-01):
///
///     <venv>/bin/python  <venv>/bin/bub     update bub      (run by its full path)
///     <venv>/bin/python3 ~/.local/bin/bub   update bub      (run through the link)
///     ~/.local/bin/uv add --active --no-sync bub             (child; creating the project)
///     ~/.local/bin/uv sync --active --inexact --upgrade-package bub   (child)
///
/// The uv children name no venv — bub hands it over in `VIRTUAL_ENV` — so they
/// are attributed through their parent, which is alive for as long as they are.
/// The official installer's own uv steps do name it (`uv venv … ~/.bub/.venv`,
/// `uv pip install --python ~/.bub/.venv/bin/python …`).
///
/// Not seen: a uv or pip the user runs by hand against an activated venv, whose
/// argv names nothing.
public enum BubActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// `bub update` / `bub install` / `bub uninstall` from this venv: each
        /// syncs or edits it through uv.
        case bubCommand(String, pid: pid_t)
        /// uv with this venv on its command line.
        case uv(pid_t)

        public var description: String {
            switch self {
            case .bubCommand(let command, let pid): return "bub \(command) is running (pid \(pid))"
            case .uv(let pid): return "uv is changing this environment (pid \(pid))"
            }
        }
    }

    static let changingCommands: Set<String> = ["update", "install", "uninstall"]

    /// The first sign of a change in flight for `install`'s venv, or nil.
    public static func busy(_ install: BubInstall, processes: [ClaudeCodeActivity.Process]) -> Busy? {
        let venv = URL(fileURLWithPath: install.path).standardizedFileURL
        let roots = Set([venv.path, venv.resolvingSymlinksInPath().path])
        let script = URL(fileURLWithPath: install.executable).resolvingSymlinksInPath().path
        for process in processes {
            if let command = bubCommand(process.arguments, roots: roots, script: script) {
                return .bubCommand(command, pid: process.pid)
            }
            if isUVTouching(process.arguments, roots: roots) {
                return .uv(process.pid)
            }
        }
        return nil
    }

    /// The subcommand, when `arguments` is this venv's bub changing it.
    ///
    /// The console script runs under its shebang, so argv is `<python> <script>
    /// <subcommand> …`; argv[0] is the script itself only when something exec'd
    /// it without the kernel's shebang handling. Either way the script is this
    /// venv's when it resolves to `bin/bub`, or when the interpreter running it
    /// is this venv's.
    static func bubCommand(_ arguments: [String], roots: Set<String>, script: String) -> String? {
        for index in 0..<min(2, arguments.count) where index + 1 < arguments.count {
            let candidate = arguments[index]
            guard (candidate as NSString).lastPathComponent == "bub",
                  changingCommands.contains(arguments[index + 1]) else { continue }
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            let interpreterIsOurs = index == 1 && isInside(arguments[0], roots: roots)
            if candidate.hasPrefix("/") && (resolved == script || interpreterIsOurs) {
                return arguments[index + 1]
            }
        }
        return nil
    }

    /// `uv …` with the venv, or something inside it, as an argument.
    static func isUVTouching(_ arguments: [String], roots: Set<String>) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "uv" else { return false }
        return arguments.dropFirst().contains { argument in
            // `--python=/…/bin/python` as well as `--python /…/bin/python`.
            let value = argument.split(separator: "=", maxSplits: 1).last.map(String.init) ?? argument
            return isInside(value, roots: roots)
        }
    }

    static func isInside(_ path: String, roots: Set<String>) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }
}
