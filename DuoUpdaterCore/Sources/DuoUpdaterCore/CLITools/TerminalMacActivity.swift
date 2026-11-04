import Foundation

/// Is something already replacing terminal-mac?
///
/// The update is the vendor's `install.sh`, which takes a lock while it works —
/// `<prefix>/lib/terminal-mac/.install-lock`, removed on exit, and the script
/// itself tells the reader to remove it after an interrupted run. The lock is
/// the first sign; the process table catches the same install before the lock
/// is made (the script verifies its package first) and the `curl` a person's
/// `get.sh` runs to fetch the archive.
///
/// terminal-mac itself running is not "busy": `install.sh` adds a new
/// directory and moves the launcher, and the running copy keeps its own
/// executable, so an update does not disturb a virtual Mac that is up.
public enum TerminalMacActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installer(pid_t)
        case download(pid_t)
        /// The installer's lock is there, and nothing of ours is visibly running:
        /// another installer, or one that was interrupted.
        case lock

        public var description: String {
            switch self {
            case .installer(let pid): return "terminal-mac's installer is running (pid \(pid))"
            case .download(let pid): return "a terminal-mac release is being downloaded (pid \(pid))"
            case .lock: return "terminal-mac's installer left its lock in place"
            }
        }
    }

    static let assetPath = "github.com/govijr/terminal-mac/releases/download/"

    /// The directory `install.sh` takes its lock in, from the install's prefix.
    static func lockPath(prefix: String) -> String {
        prefix + "/lib/terminal-mac/.install-lock"
    }

    public static func busy(prefix: String?, processes: [ClaudeCodeActivity.Process]) -> Busy? {
        if let prefix, FileManager.default.fileExists(atPath: lockPath(prefix: prefix)) { return .lock }
        for process in processes {
            if process.arguments.contains(where: {
                ($0 as NSString).lastPathComponent == "install.sh" && $0.contains("terminal-mac")
            }) {
                return .installer(process.pid)
            }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains(assetPath) })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }
}
