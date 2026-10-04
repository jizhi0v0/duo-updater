import Foundation

/// Is Amp's installer already running?
///
/// The installer takes no lock. While it works it leaves files of its own under
/// `~/.amp`, all removed when it ends or is interrupted (its `cleanup` trap):
/// `amp-install-checksum.txt` (and `-version.txt`, `-signature.minisign`), and
/// the staged binary `bin/tmp.XXXXXX` it renames into place; and it downloads with
/// `curl … https://static.ampcode.com/cli/…`. A file of those names younger than
/// the install deadline, or such a download, is an install in flight. Amp's own
/// in-place update is not seen: it is a moment inside a running Amp, and it ends
/// in a rename as the installer's does.
public enum AmpActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        case installing(String)
        case download(pid_t)

        public var description: String {
            switch self {
            case .installing(let name): return "the Amp installer is running (\(name))"
            case .download(let pid): return "the Amp installer is downloading (pid \(pid))"
            }
        }
    }

    /// The install deadline (`AmpUpdater.defaultDeadline`): older files were left
    /// behind by a run that was killed.
    static let lifetime: TimeInterval = 20 * 60

    public static func busy(root: URL, processes: [NpmActivity.Process], now: Date = Date()) -> Busy? {
        let fm = FileManager.default
        let candidates =
            ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("amp-install-") }.map { root.appendingPathComponent($0) }
            + ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("bin").path)) ?? []).filter { $0.hasPrefix("tmp.") }
                .map { root.appendingPathComponent("bin/\($0)") }
        for file in candidates.sorted(by: { $0.path < $1.path }) {
            guard let modified = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < lifetime
            else { continue }
            return .installing(file.lastPathComponent)
        }
        for process in processes {
            guard let first = process.arguments.first, (first as NSString).lastPathComponent == "curl",
                  process.arguments.contains(where: { $0.contains("static.ampcode.com/cli/") })
            else { continue }
            return .download(process.pid)
        }
        return nil
    }
}
