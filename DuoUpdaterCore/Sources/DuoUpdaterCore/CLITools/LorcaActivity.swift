import Foundation

/// Is something already replacing the Lorca CLI?
///
/// `lorca update` takes no lock across processes (`update.rs` at cli-v0.1.11):
/// it stages `.lorca-<version>-<pid>` beside the binary and renames it into
/// place, keeping the old one as `.lorca-previous`. A click does not start a
/// second one beside a running `lorca update`, to keep its outcome its own. The
/// install script downloads the release archive with `curl` before it renames
/// the file into place, so a `curl` fetching a Lorca release asset is busy too.
///
/// Not seen: a running `lorca serve` installing a release it found by itself.
/// It renames a verified file into place too, so a click at the same moment
/// ends with one of two verified builds, and the click's own `lorca update` is
/// handed to that same `lorca serve`, which serializes them.
public enum LorcaActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case update(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .update(let pid): return "lorca update is running (pid \(pid))"
            case .download(let pid): return "a Lorca CLI release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/egoist/lorca/releases/"

    /// The port `lorca` talks to its `lorca serve` on when nothing names
    /// another (`DEFAULT_PORT` in `config.rs`).
    static let defaultPort = 4862

    /// A `lorca serve` from inside a `.app` — the Mac app's own copy, which it
    /// starts with `--port 4862` — that holds the default port: the pid, or nil.
    ///
    /// The CLI's `lorca update` hands the update to whatever `lorca serve`
    /// answers on its port, and the app's copy refuses it: measured 2026-10-09
    /// with Lorca.app 1.0.11 running, `~/.local/bin/lorca update` printed
    /// `Error: Lorca on This Device updates with the app that installed it.` and
    /// exited 1. Lorca's own docs have the app run `lorca serve` itself on such
    /// a Mac (`lorca service install` refuses to start a second), so that serve
    /// is never the CLI's.
    public static func appServe(processes: [ClaudeCodeActivity.Process]) -> pid_t? {
        for process in processes {
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "lorca",
                  first.split(separator: "/").contains(where: { $0.hasSuffix(".app") }),
                  subcommand(of: Array(process.arguments.dropFirst())) == "serve"
            else { continue }
            if port(of: process.arguments) == defaultPort { return process.pid }
        }
        return nil
    }

    /// The `--port` a `lorca` command line names, else the default.
    static func port(of arguments: [String]) -> Int? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--port" {
                return arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
            }
            if argument.hasPrefix("--port=") { return Int(argument.dropFirst("--port=".count)) }
        }
        return defaultPort
    }

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if isUpdate(process.arguments) { return .update(process.pid) }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains(assetPath) && $0.contains("lorca-cli") })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }

    /// `lorca update` that installs: `update` as lorca's first word that is not
    /// an option, without `--check` (which only reads) or `--auto` (which only
    /// writes the setting).
    static func isUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "lorca" else { return false }
        let rest = arguments.dropFirst()
        guard subcommand(of: Array(rest)) == "update" else { return false }
        return !rest.contains { $0 == "--check" || $0 == "--auto" || $0.hasPrefix("--auto=") }
    }

    /// lorca's subcommand: its first word that is neither an option nor the
    /// value of a global `--home` / `--port`.
    static func subcommand(of arguments: [String]) -> String? {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--home" || argument == "--port" {
                index += 2
                continue
            }
            if !argument.hasPrefix("-") { return argument }
            index += 1
        }
        return nil
    }
}
