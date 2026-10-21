import Foundation

/// Is something already replacing Biome?
///
/// Biome has no update command, and its installer piped into `bash` reads its
/// script from stdin, which the process table does not show. What can be seen is
/// the installer `BiomeUpdater` runs, whose file name starts with
/// `BiomeUpdater.scriptPrefix`, and a `curl` fetching a Biome release asset —
/// the installer's download, whoever started it.
public enum BiomeActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installer(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .installer(let pid): return "Biome's installer is running (pid \(pid))"
            case .download(let pid): return "a Biome release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/biomejs/biome/releases/download/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if process.arguments.contains(where: {
                ($0 as NSString).lastPathComponent.hasPrefix(BiomeUpdater.scriptPrefix)
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
