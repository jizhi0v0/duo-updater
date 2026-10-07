import Foundation

/// Is something already replacing Luvus?
///
/// `luvus update` takes no lock (`src/update.rs` at v0.14.3): it downloads the
/// archive with `curl`, unpacks it in a private temporary directory, copies the
/// binary beside the installed one as `.luvus-update-<pid>-<nonce>` and renames
/// it into place. Two at once each rename a verified file, but a click does not
/// start a second one beside a running `luvus update`, to keep its outcome its
/// own. The installer downloads the same release asset with `curl` before it
/// moves the file into place, so a `curl` fetching a Luvus release asset is busy
/// too — whichever of the two runs it.
///
/// Not seen: the installer's `tar` and `mv` around that download, and luvus's
/// own background check, which only reads `latest.json` and never installs
/// ("Automatic checks remain notify-only").
public enum LuvusActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case update(pid_t)
        case download(pid_t)

        public var description: String {
            switch self {
            case .update(let pid): return "luvus update is running (pid \(pid))"
            case .download(let pid): return "a Luvus release is being downloaded (pid \(pid))"
            }
        }
    }

    static let assetPath = "github.com/RizRiyz/luvus/releases/download/"

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

    /// `luvus update`, however luvus was named on the command line: `update` as
    /// its first word that is not an option — the word luvus dispatches on. A
    /// subcommand's own `update` (`luvus task update`, `luvus server
    /// update-manifest`) is not one.
    static func isUpdate(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "luvus" else { return false }
        return arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) == "update"
    }
}
