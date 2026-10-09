import Foundation

/// Is DuoUpdater's own run of nvm's installer already under way?
///
/// nvm has no update command, and its installer piped into `bash` reads its
/// script from stdin, which the process table does not show. What can be seen
/// is the installer `NvmUpdater` runs, whose file name starts with
/// `NvmUpdater.scriptPrefix`.
public enum NvmActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installer(pid_t)

        public var description: String {
            switch self {
            case .installer(let pid): return "nvm's installer is running (pid \(pid))"
            }
        }
    }

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes where process.arguments.contains(where: {
            ($0 as NSString).lastPathComponent.hasPrefix(NvmUpdater.scriptPrefix)
        }) {
            return .installer(process.pid)
        }
        return nil
    }
}
