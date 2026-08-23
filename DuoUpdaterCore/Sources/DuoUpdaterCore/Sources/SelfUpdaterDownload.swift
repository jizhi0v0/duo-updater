import Foundation

/// Bytes an app's OWN updater currently has in flight — landed in Sparkle's
/// download cache, not yet unpacked into anything installable.
///
/// This is the window `SelfUpdaterStaging.staged` structurally cannot see. That
/// one answers "is there a finished build waiting for a relaunch?", which is only
/// true once `Autoupdate` has unpacked the archive into `Installation/` and parked
/// itself on the app's next quit. Between "the app started downloading" and that
/// moment there is nothing in `Installation/`, no parked installer, and — for a
/// 605 MB archive on a slow link — a window measured in minutes during which we
/// would happily download the very same release a second time.
public struct InFlightSelfUpdateDownload: Sendable, Hashable {

    /// The per-download directory Sparkle created under `PersistentDownloads/`.
    /// Its name is a random token (`SPULocalCacheDirectory.createUniqueDirectory`),
    /// so it identifies the attempt, never the version.
    public let directory: URL
    /// Total bytes on disk under `directory` at the time of the check.
    public let bytes: Int64
    /// Most recent write anywhere under `directory`.
    public let lastWrite: Date

    public init(directory: URL, bytes: Int64, lastWrite: Date) {
        self.directory = directory
        self.bytes = bytes
        self.lastWrite = lastWrite
    }
}

extension SelfUpdaterStaging {

    /// How recently something must have been written for us to treat a download
    /// directory as live rather than debris.
    ///
    /// Sparkle's own housekeeping is no help here: `SPULocalCacheDirectory`
    /// sweeps `PersistentDownloads/` with `OLD_ITEM_DELETION_INTERVAL = 86400 * 10`,
    /// so a download killed mid-flight (app force-quit, machine slept, network
    /// dropped) sits there for **ten days**. Deferring to that would mean ten days
    /// of refusing to install, which is far worse than the duplicate download this
    /// is meant to prevent.
    ///
    /// Ten minutes is chosen against the failure that matters. A live
    /// `URLSession` download rewrites its file continuously, so any transfer still
    /// making progress is seconds old, not minutes; the margin is for a stalled-but-
    /// recovering link, not for normal operation. Erring long here is cheap (we wait
    /// one more check cycle) and erring short is what costs 605 MB.
    public static let inFlightDownloadFreshness: TimeInterval = 600

    /// The download an app's own Sparkle updater currently has in flight, or nil.
    ///
    /// Deliberately NOT gated on a parked installer the way `sparkleStagedBundle`
    /// is. That gate is correct there — without an `Autoupdate` waiting, a bundle
    /// in `Installation/` is unclaimed debris that will never be installed — but
    /// the installer is launched *after* the download completes, so requiring it
    /// here would exclude every case this function exists to catch.
    ///
    /// Returns nil rather than throwing on any malformed or unreadable piece: this
    /// feeds a "hold off" decision, and a detector that fails loudly on a cache
    /// directory it cannot read would block installs for the wrong reason.
    public static func inFlightDownload(
        for app: InstalledApp,
        cachesDirectory: URL? = nil,
        now: Date = Date(),
        freshness: TimeInterval? = nil,
        fileManager: FileManager = .default
    ) -> InFlightSelfUpdateDownload? {
        guard let bundleID = app.bundleID else { return nil }
        let caches = cachesDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return nil }
        let window = freshness ?? inFlightDownloadFreshness

        if app.hasSparkleUpdater,
           let sparkle = sparkleInFlight(
            bundleID: bundleID, caches: caches, now: now,
            window: window, fileManager: fileManager) {
            return sparkle
        }
        if app.hasSelfUpdater {
            return squirrelInFlight(
                bundleID: bundleID, caches: caches, now: now,
                window: window, fileManager: fileManager)
        }
        return nil
    }

    /// Squirrel's staging area, `Caches/<bundleID>.ShipIt/`.
    ///
    /// Worth covering even though Squirrel has no delta mechanism at all — its
    /// delta request has been open and labelled "distant-future" since 2013 — which
    /// makes *not downloading the same release twice* the only saving available for
    /// this family. It is also the larger share: Claude, Cursor and VS Code are
    /// 16.6 GB of the traffic ledger against ChatGPT's 31 GB.
    ///
    /// The layout is read from a real `ShipItState.plist` on this machine, whose
    /// `updateBundleURL` pointed at
    /// `…/com.anthropic.claudefordesktop.ShipIt/update.PvAvgLY/Claude.app/`. So the
    /// unpacked bundle lands in a `update.<random>` sibling of the state file, and
    /// everything is swept once the install completes.
    ///
    /// **Not established by observation:** where Squirrel puts the archive while it
    /// is still transferring, before that directory exists. Every `.ShipIt` folder
    /// on this machine was idle when inspected, so rather than guess at a filename
    /// this treats *any* fresh content that is not the state file or ShipIt's own
    /// logs as work in progress. That covers the unpack phase for certain and the
    /// download phase only if Squirrel stages it here too. `SelfUpdaterStaging.staged`
    /// already covers the finished case by reading the state file, so the gap left
    /// is narrower than it looks — and erring toward "busy" only costs one check
    /// cycle, while erring the other way costs the whole download.
    private static func squirrelInFlight(
        bundleID: String, caches: URL, now: Date,
        window: TimeInterval, fileManager: FileManager
    ) -> InFlightSelfUpdateDownload? {
        let root = caches.appendingPathComponent("\(bundleID).ShipIt", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }

        // ShipIt rewrites these on every run, including runs that install nothing,
        // so their mtime says nothing about a transfer.
        let bookkeeping: Set<String> = [
            "ShipItState.plist", "ShipIt_stdout.log", "ShipIt_stderr.log",
        ]
        var newest: InFlightSelfUpdateDownload?
        for entry in entries where !bookkeeping.contains(entry.lastPathComponent) {
            guard let (bytes, lastWrite) = measure(entry, fileManager: fileManager),
                  bytes > 0,
                  now.timeIntervalSince(lastWrite) < window
            else { continue }
            if let current = newest, current.lastWrite >= lastWrite { continue }
            newest = InFlightSelfUpdateDownload(
                directory: entry, bytes: bytes, lastWrite: lastWrite)
        }
        return newest
    }

    private static func sparkleInFlight(
        bundleID: String, caches: URL, now: Date,
        window: TimeInterval, fileManager: FileManager
    ) -> InFlightSelfUpdateDownload? {
        let root = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)
            .appendingPathComponent("PersistentDownloads", isDirectory: true)

        // The directory itself outlives every download — it is created once and
        // emptied after each install, so its existence says nothing and, like
        // `Installation/`, its own mtime does not follow its children.
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }

        var newest: InFlightSelfUpdateDownload?
        for entry in entries {
            guard let (bytes, lastWrite) = measure(entry, fileManager: fileManager),
                  bytes > 0,
                  now.timeIntervalSince(lastWrite) < window
            else { continue }
            if let current = newest, current.lastWrite >= lastWrite { continue }
            newest = InFlightSelfUpdateDownload(
                directory: entry, bytes: bytes, lastWrite: lastWrite)
        }
        return newest
    }

    /// Total size and most recent write under `directory`, walking its contents.
    /// Sparkle nests the archive one level deeper (`<token>/<filename>/<file>`),
    /// so the interesting mtime is never the top directory's own.
    private static func measure(
        _ directory: URL, fileManager: FileManager
    ) -> (bytes: Int64, lastWrite: Date)? {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = fileManager.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]) else { return nil }

        var bytes: Int64 = 0
        var lastWrite: Date?
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate,
               lastWrite == nil || modified > lastWrite! {
                lastWrite = modified
            }
        }
        guard let lastWrite else { return nil }
        return (bytes, lastWrite)
    }
}
