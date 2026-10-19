import Foundation

/// Is something already replacing Obelus?
///
/// Obelus has no update command, and its installer piped into `sh` reads its
/// script from stdin, which the process table does not show. What can be seen is
/// the installer `ObelusUpdater` runs, whose file name starts with
/// `ObelusUpdater.scriptPrefix`, and a `curl` fetching an Obelus release asset —
/// the installer's download, whoever started it.
public enum ObelusActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installer(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .installer(let pid): return "Obelus's installer is running (pid \(pid))"
            case .download(let pid): return "an Obelus release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/obelus-editor/obelus/releases/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if process.arguments.contains(where: {
                ($0 as NSString).lastPathComponent.hasPrefix(ObelusUpdater.scriptPrefix)
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
