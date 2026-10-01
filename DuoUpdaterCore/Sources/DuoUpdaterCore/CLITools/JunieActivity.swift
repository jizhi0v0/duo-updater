import Foundation
import Darwin

/// Is something already updating Junie right now?
///
/// Two things change a Junie install, and each leaves its own traces:
///
/// - **Junie itself.** A running session checks for an update at start and
///   downloads it into `updates/<file>.download` (`AutoUpdateService`), then writes
///   `updates/pending-update.json` for the shim to apply at the next launch. Junie
///   treats a `.download` file younger than ten minutes as another instance's live
///   download and an older one as left behind (`OLD_DOWNLOAD_THRESHOLD_MS`, the
///   constant 600000 in 1543.24's `AutoUpdateService`, read from the class file
///   2026-10-02, and the same in 3419.26), so that is the rule here too.
///   `pending-update.json.processing` is read the same way: the managed shim's
///   `sanitize_pending_updates` calls it part of "a legitimate in-flight update",
///   though no class in 3419.26's jar names it.
/// - **An installer.** `install.sh` downloads with `curl … <…>/junie/releases/download/…`,
///   extracts into `versions/.<build>.tmp.<pid>` and swaps it in; the shim's own
///   apply also moves a build aside as `versions/.<build>.old.<pid>`. Those carry
///   the pid of the bash doing it, so a directory a killed install left behind
///   (`install.sh` cleans up on EXIT, INT and TERM, but not on SIGKILL) is told
///   apart by asking whether the pid is alive. A `curl … | bash` piped from
///   `junie.jetbrains.com/install*.sh` shows its fetching curl, and the installer
///   DuoUpdater runs is a file named `junie-install-<channel>.sh`.
///
/// A running Junie session is **not** a reason to wait. `install.sh` replaces only
/// `versions/<new build>` (`rm -rf "$TARGET_DIR"; mv "$STAGING" "$TARGET_DIR"`) and
/// re-points `current`; the session runs from its own `versions/<old build>`, which
/// the installer never touches, so it keeps running the build it started with and
/// the next launch gets the new one.
public enum JunieActivity {

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// A Junie session is downloading an update (`updates/<name>`).
        case downloading(String)
        /// The shim is applying a staged update (`pending-update.json.processing`).
        case applying
        /// An installer or the shim is extracting a build (`versions/.<build>.tmp.<pid>`).
        case extracting(version: String, pid: pid_t)
        /// An installer is running (pid).
        case installer(pid_t)

        public var description: String {
            switch self {
            case .downloading(let name): return "Junie is downloading an update (\(name))"
            case .applying: return "Junie is applying a downloaded update"
            case .extracting(let version, let pid): return "installing \(version) (pid \(pid))"
            case .installer(let pid): return "the Junie installer is running (pid \(pid))"
            }
        }
    }

    /// How long a `.download` stays live: Junie's own threshold (above).
    static let liveDownloadWindow: TimeInterval = 600

    public static func busy(
        _ install: JunieInstall,
        processes: [ClaudeCodeActivity.Process],
        now: Date = Date(),
        isAlive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) -> Busy? {
        for process in processes where isInstaller(process.arguments) {
            return .installer(process.pid)
        }
        let data = URL(fileURLWithPath: install.dataDirectory)
        let fm = FileManager.default
        let updates = data.appendingPathComponent("updates")
        for name in ((try? fm.contentsOfDirectory(atPath: updates.path)) ?? []).sorted() {
            guard name.hasSuffix(".download") || name == "pending-update.json.processing",
                  let modified = (try? fm.attributesOfItem(atPath: updates.appendingPathComponent(name).path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < liveDownloadWindow
            else { continue }
            return name.hasSuffix(".download") ? .downloading(name) : .applying
        }
        let versions = data.appendingPathComponent("versions")
        for name in ((try? fm.contentsOfDirectory(atPath: versions.path)) ?? []).sorted() {
            guard let (version, pid) = stagingOwner(name), isAlive(pid) else { continue }
            return .extracting(version: version, pid: pid)
        }
        return nil
    }

    /// `.<build>.tmp.<pid>` / `.<build>.old.<pid>` → (build, pid).
    static func stagingOwner(_ name: String) -> (version: String, pid: pid_t)? {
        guard name.hasPrefix(".") else { return nil }
        let parts = name.dropFirst().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, ["tmp", "old"].contains(parts[parts.count - 2]),
              let pid = pid_t(parts[parts.count - 1]), pid > 0
        else { return nil }
        let version = parts.dropLast(2).joined(separator: ".")
        return JunieScanner.isBuild(version) ? (version, pid) : nil
    }

    /// The installer's download, a piped installer's fetch, or DuoUpdater's own
    /// installer file.
    static func isInstaller(_ arguments: [String]) -> Bool {
        if arguments.prefix(2).contains(where: { ($0 as NSString).lastPathComponent.hasPrefix(JunieUpdater.scriptPrefix) }) {
            return true
        }
        guard let first = arguments.first, (first as NSString).lastPathComponent == "curl" else { return false }
        return arguments.dropFirst().contains { argument in
            let lower = argument.lowercased()
            return lower.contains("/junie/releases/download/") || lower.contains("junie.jetbrains.com/install")
        }
    }
}
