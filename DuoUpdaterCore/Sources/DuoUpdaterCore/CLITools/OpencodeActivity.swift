import Foundation
import Darwin

/// Is OpenCode's installer already running?
///
/// Every update of a curl install runs the vendor's installer: the user's `curl
/// … | bash`, OpenCode's own (`upgradeCurl`, `v1.18.34`, which pipes the script
/// into `bash` on standard input with `VERSION` set — argv is just `bash`), and
/// DuoUpdater's click. No lock is taken, but each run leaves two traces while it
/// works:
/// - its download, `curl … -o $TMPDIR/opencode_install_<pid>/opencode-darwin-<arch>.zip
///   https://github.com/anomalyco/opencode/releases/…` (or `/latest/download/…`);
/// - `${TMPDIR:-/tmp}/opencode_install_<pid>`, the directory it downloads and
///   unzips into and removes when done, named after the installer's shell — so
///   one a killed run left behind is told apart by asking whether that pid lives.
///
/// The `mv` that puts the new file in place is a rename, and a running OpenCode
/// keeps the file it started from, so a running session is not a reason to wait.
public enum OpencodeActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case download(pid_t)
        case installer(pid_t)

        public var description: String {
            switch self {
            case .download(let pid): return "the OpenCode installer is downloading (pid \(pid))"
            case .installer(let pid): return "the OpenCode installer is running (pid \(pid))"
            }
        }
    }

    public static func busy(
        processes: [NpmActivity.Process], temporaryDirectories: [URL],
        isAlive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) -> Busy? {
        for process in processes {
            if isDownload(process.arguments) { return .download(process.pid) }
            if process.arguments.prefix(2).contains(where: { ($0 as NSString).lastPathComponent == OpencodeUpdater.scriptName }) {
                return .installer(process.pid)
            }
        }
        for directory in temporaryDirectories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names.sorted() where name.hasPrefix("opencode_install_") {
                guard let pid = pid_t(name.dropFirst("opencode_install_".count)), pid > 0, isAlive(pid) else { continue }
                return .installer(pid)
            }
        }
        return nil
    }

    /// `curl … https://github.com/anomalyco/opencode/releases/…` (or the old
    /// `sst/opencode`).
    static func isDownload(_ arguments: [String]) -> Bool {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "curl" else { return false }
        return arguments.dropFirst().contains { argument in
            let lower = argument.lowercased()
            return lower.contains("github.com/anomalyco/opencode/releases/")
                || lower.contains("github.com/sst/opencode/releases/")
        }
    }

    /// The user's temporary directory, where an installer run from their shell
    /// or by OpenCode puts its work (`${TMPDIR:-/tmp}`), and `/tmp`.
    static var temporaryDirectories: [URL] {
        var directories = [FileManager.default.temporaryDirectory]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] {
            directories.append(URL(fileURLWithPath: tmp))
        }
        directories.append(URL(fileURLWithPath: "/tmp"))
        var seen = Set<String>()
        return directories.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }
}
