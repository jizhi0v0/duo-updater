import Foundation

/// Is something already replacing Helm?
///
/// Helm's script takes no lock. While it runs, the process table shows the shell
/// running it — a file named `get-helm-3` or `get-helm-4` (or `get_helm.sh`, as
/// the docs save it), or `bash` reading it from a pipe — and its `curl`
/// downloading `get.helm.sh/helm-v<version>-…`. The pipe's `bash` carries no
/// name, so the `curl` is what tells it: either curl fetching a Helm archive or
/// a shell running a named script is busy.
public enum HelmActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case script(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .script(let pid): return "Helm's install script is running (pid \(pid))"
            case .download(let pid): return "a Helm release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPrefix = "get.helm.sh/helm-v"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            guard let first = process.arguments.first else { continue }
            let name = (first as NSString).lastPathComponent
            if ["bash", "sh"].contains(name), process.arguments.dropFirst().contains(where: isScript) {
                return .script(process.pid)
            }
            if name == "curl", process.arguments.contains(where: { $0.contains(assetPrefix) }) {
                return .download(process.pid)
            }
        }
        return nil
    }

    static func isScript(_ argument: String) -> Bool {
        let name = (argument as NSString).lastPathComponent
        return name == "get-helm-3" || name == "get-helm-4" || name == "get_helm.sh"
    }
}
