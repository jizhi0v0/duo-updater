import Foundation

/// Is an install of Cursor's CLI already running?
///
/// Two things install a version, and each leaves its own trace:
/// - **The CLI itself** (its update, background or `agent update`) creates
///   `~/.local/share/cursor-agent/.install.lock` with `O_EXCL` and removes it when
///   done; it treats a lock older than 60 seconds as left behind
///   (`install-core-posix.ts`, the 2026.10.01 bundle), and so does this.
/// - **The installer** takes no lock. It extracts into
///   `versions/.tmp-<version>-<epoch seconds>` and renames that into place, and
///   its download is `curl -fSL --progress-bar https://downloads.cursor.com/lab/…`.
///   A `.tmp-` directory younger than the install deadline counts.
public enum CursorAgentActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case updating
        case installing(String)
        case download(pid_t)

        public var description: String {
            switch self {
            case .updating: return "Cursor's CLI is updating itself (.install.lock)"
            case .installing(let name): return "the Cursor CLI installer is extracting (\(name))"
            case .download(let pid): return "the Cursor CLI installer is downloading (pid \(pid))"
            }
        }
    }

    static let lockLifetime: TimeInterval = 60
    /// The install deadline (`CursorAgentUpdater.defaultDeadline`): an
    /// extraction directory older than that was left behind.
    static let extractionLifetime: TimeInterval = 30 * 60

    public static func busy(
        root: URL, processes: [NpmActivity.Process], now: Date = Date()
    ) -> Busy? {
        let fm = FileManager.default
        if let modified = (try? fm.attributesOfItem(atPath: root.appendingPathComponent(".install.lock").path))?[.modificationDate] as? Date,
           now.timeIntervalSince(modified) < lockLifetime {
            return .updating
        }
        let versions = root.appendingPathComponent("versions")
        for name in ((try? fm.contentsOfDirectory(atPath: versions.path)) ?? []).sorted() where name.hasPrefix(".tmp-") {
            guard let epoch = name.split(separator: "-").last.flatMap({ TimeInterval(String($0)) }),
                  now.timeIntervalSince1970 - epoch < extractionLifetime
            else { continue }
            return .installing(name)
        }
        for process in processes {
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains("downloads.cursor.com/lab/") })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }
}

