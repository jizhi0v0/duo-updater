import Foundation

/// Where DuoUpdater keeps its own on-disk state — the traffic log, the release
/// timeline, the changelog cache, formula release notes, and rollback backups.
///
/// This exists so a second DuoUpdater process can be pointed somewhere else.
/// The nightly `duo verify` sweep runs on the same machine and as the same user
/// as the menu-bar app, so without a redirect it writes the changelog cache and
/// traffic log the running app is reading — a scan of 152 recipes would poison
/// a cache that exists to answer "what did this app ship last time I looked".
///
/// Only *our* state moves. Directories we read that belong to other apps
/// (Squirrel staging, Alfred's preferences, the Toolbox inventory) resolve
/// Application Support directly and must keep doing so — they are facts about
/// the machine, not state we own.
public enum DuoStateDirectory {

    /// The container to place DuoUpdater's state directories inside. Callers
    /// append their own subpath (`com.duoupdater.app/traffic.json`,
    /// `DuoUpdater/Backups`, …) exactly as they did against Application Support,
    /// so an override relocates every store at once without renaming anything.
    ///
    /// `DUO_STATE_DIR` wins when set to a non-empty path. It is read fresh on
    /// every access rather than cached: tests set it per-case, and the cost is a
    /// dictionary lookup against operations that are already touching disk.
    public static var base: URL {
        if let override = ProcessInfo.processInfo.environment["DUO_STATE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}
