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
        guard rest.first(where: { !$0.hasPrefix("-") }) == "update" else { return false }
        return !rest.contains { $0 == "--check" || $0 == "--auto" || $0.hasPrefix("--auto=") }
    }
}
