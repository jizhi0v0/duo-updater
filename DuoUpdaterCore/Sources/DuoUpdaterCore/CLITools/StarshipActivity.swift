import Foundation

/// Is something already replacing Starship?
///
/// The script takes no lock. While it runs, its `curl` downloads
/// `github.com/starship/starship/releases/…/starship-<target>.tar.gz` into a
/// temporary file before `tar` unpacks it into the bin directory. A `curl`
/// fetching a Starship release asset is busy, whoever runs it; so is a shell
/// running this app's own copy of the script (`StarshipUpdater.scriptName`).
/// A script piped into `sh` from a terminal shows no name of its own until its
/// `curl` starts.
public enum StarshipActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case download(pid_t)
        case script(pid_t)

        public var description: String {
            switch self {
            case .download(let pid): return "a Starship release is being downloaded (pid \(pid))"
            case .script(let pid): return "Starship's install script is running (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/starship/starship/releases/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            guard let first = process.arguments.first else { continue }
            let name = (first as NSString).lastPathComponent
            if name == "curl", process.arguments.contains(where: { $0.contains(assetPath) }) {
                return .download(process.pid)
            }
            if ["sh", "bash"].contains(name),
               process.arguments.dropFirst().contains(where: { ($0 as NSString).lastPathComponent == StarshipUpdater.scriptName }) {
                return .script(process.pid)
            }
        }
        return nil
    }
}
