import Foundation

/// Is something already replacing flyctl?
///
/// `flyctl version upgrade` (also spelled `version update`) takes no lock; it runs
/// the installer, whose `curl` downloads the release asset into `~/.fly/tmp`
/// before the `mv` into place. flyctl's own background update, when a terminal
/// session triggers one, is the same `flyctl version upgrade` started as a child.
/// So either of those in the process table is busy: a running upgrade, or a
/// `curl` fetching a flyctl release asset — whoever runs it.
public enum FlyctlActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case upgrade(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .upgrade(let pid): return "flyctl version upgrade is running (pid \(pid))"
            case .download(let pid): return "a flyctl release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/superfly/flyctl/releases/download/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if isUpgrade(process.arguments) { return .upgrade(process.pid) }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains(assetPath) })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }

    /// `flyctl version upgrade` or `fly version update`: the first two words
    /// that are not options.
    static func isUpgrade(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, ["flyctl", "fly"].contains((first as NSString).lastPathComponent)
        else { return false }
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard words.count >= 2, words[words.startIndex] == "version" else { return false }
        return ["upgrade", "update"].contains(words[words.startIndex + 1])
    }
}
