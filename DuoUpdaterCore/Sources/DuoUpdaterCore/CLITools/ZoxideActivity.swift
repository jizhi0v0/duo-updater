import Foundation

/// Is something already replacing zoxide?
///
/// zoxide has no update command, and its installer piped into `sh` reads its
/// script from stdin, which the process table does not show. What can be seen is
/// the installer `ZoxideUpdater` runs, whose file name starts with
/// `ZoxideUpdater.scriptPrefix`, and a `curl` fetching a zoxide release asset —
/// the installer's download, whoever started it.
public enum ZoxideActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installer(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .installer(let pid): return "zoxide's installer is running (pid \(pid))"
            case .download(let pid): return "a zoxide release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/ajeetdsouza/zoxide/releases/download/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if process.arguments.contains(where: {
                ($0 as NSString).lastPathComponent.hasPrefix(ZoxideUpdater.scriptPrefix)
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
