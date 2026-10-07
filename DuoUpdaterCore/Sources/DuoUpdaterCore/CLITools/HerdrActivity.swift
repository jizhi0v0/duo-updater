import Foundation

/// Is herdr already being updated?
///
/// Three signs, from `src/update.rs`, `src/cli.rs` and the installer:
/// - a `herdr update` process — or `herdr channel set …`, which runs the same
///   update in-process after writing the channel;
/// - its download, `.herdr-update-<pid>.tmp` beside the binary, while that pid
///   is still running (the file is removed when the update ends; one a killed
///   update left behind names a pid that is gone);
/// - a `curl` fetching a herdr release asset (`github.com/herdrdev/herdr/releases/download/`)
///   — the installer's download, or the one `herdr update` runs.
///
/// Not seen: herdr's background version check, which only tells the user and
/// installs nothing (`auto_update`).
public enum HerdrActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case update(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .update(let pid): return "herdr update is running (pid \(pid))"
            case .download(let pid): return "a herdr build is being downloaded (pid \(pid))"
            }
        }
    }

    /// `directory`: where the binary is, which `herdr update` downloads into.
    public static func busy(directory: URL, processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes where isUpdate(process.arguments) {
            return .update(process.pid)
        }
        let running = Set(processes.map(\.pid))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted() {
            if let pid = downloadPID(name), running.contains(pid) { return .update(pid) }
        }
        for process in processes {
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains("github.com/herdrdev/herdr/releases/download/") })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }

    /// `herdr … update` or `herdr … channel set …`, however herdr was named; a
    /// session option before the subcommand (`herdr --session work update`) is
    /// looked past.
    static func isUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "herdr" else { return false }
        let rest = Array(arguments.dropFirst())
        if rest.contains("update") { return true }
        guard let channel = rest.firstIndex(of: "channel") else { return false }
        return rest[(channel + 1)...].first == "set"
    }

    /// The pid in `.herdr-update-<pid>.tmp`.
    static func downloadPID(_ name: String) -> pid_t? {
        guard name.hasPrefix(".herdr-update-"), name.hasSuffix(".tmp") else { return nil }
        return pid_t(name.dropFirst(".herdr-update-".count).dropLast(".tmp".count))
    }
}
