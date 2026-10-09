import Foundation

/// Is something already replacing Atuin?
///
/// `atuin update` takes no lock (axoupdater 0.10.0, `AxoUpdater::run`): it
/// downloads the newer release's `atuin-installer.sh` into a temporary
/// directory as `installer.sh` and runs it; the installer downloads the archive
/// with `curl`, unpacks it, moves `atuin` into place and rewrites the receipt.
/// Two at once would interleave those moves and receipt writes, so a click does
/// not start one beside a running `atuin update`. A `curl` fetching an Atuin
/// release asset is busy too — whichever installer runs it, by hand or under
/// `atuin update`.
///
/// Not seen: the installer itself, saved as plain `installer.sh` — too common a
/// name to read as Atuin's (uv's rule, `UvActivity`), and its parent covers it.
/// `atuin update --check` only asks and is not busy.
public enum AtuinActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case update(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .update(let pid): return "atuin update is running (pid \(pid))"
            case .download(let pid): return "an Atuin release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/atuinsh/atuin/releases/download/"

    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Busy? {
        for process in processes {
            if isUpdate(process.arguments) { return .update(process.pid) }
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains(assetPath) })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }

    /// `atuin update`, however atuin was named, without `--check`: `update` as
    /// its first word that is not an option — the word atuin dispatches on — so
    /// `atuin search update` is not one.
    static func isUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "atuin" else { return false }
        let rest = arguments.dropFirst()
        guard rest.first(where: { !$0.hasPrefix("-") }) == "update" else { return false }
        return !rest.contains("--check")
    }
}
