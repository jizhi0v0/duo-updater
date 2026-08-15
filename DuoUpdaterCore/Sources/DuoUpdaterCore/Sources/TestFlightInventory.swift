import Foundation
import SQLite3

/// Reads the local TestFlight database to learn which installed apps came from
/// TestFlight and what the newest available beta build is. Like `ToolboxInventory`,
/// this is a read of another app's local cache — no network, no auth. TestFlight
/// maintains the DB when it runs and via push when new builds drop; we never
/// refresh it ourselves, so a reading is "as TestFlight last saw it" (the same
/// freshness caveat the Toolbox cache carries).
///
/// The DB lives in TestFlight's sandbox container and stores one row per
/// (app, build, platform) in `ZTFAPPBUNDLEMODEL`:
///   - `ZPLATFORMRAW` 3 == macOS (1 == iOS); we only care about Mac builds.
///   - `ZINSTALLSTATUSRAW` 1 == the build currently installed on this machine
///     (its `ZBUNDLEVERSION` matches the app's on-disk `CFBundleVersion`).
///   - The newest available build is the highest `ZBUNDLEVERSION` among an app's
///     macOS rows.
public struct TestFlightInventory: Sendable {

    /// The macOS TestFlight builds known for one app, newest first by build.
    public struct App: Sendable, Hashable {
        public let bundleID: String
        /// Marketing version of the newest available build (`ZSHORTVERSION`).
        public let latestShortVersion: String
        /// Build number of the newest available build (`ZBUNDLEVERSION`).
        public let latestBuild: String

        public init(bundleID: String, latestShortVersion: String, latestBuild: String) {
            self.bundleID = bundleID
            self.latestShortVersion = latestShortVersion
            self.latestBuild = latestBuild
        }
    }

    /// macOS builds present in the DB, keyed by bundle id. The value carries the
    /// newest available build plus the full set of build numbers, so we can both
    /// offer an update and recognize that an on-disk build is a TestFlight install.
    private let appsByBundleID: [String: App]
    /// Every (bundleID, build) macOS pair seen — used to confirm a given on-disk
    /// app really is the TestFlight install (its build appears here).
    private let buildsByBundleID: [String: Set<String>]

    /// Whether we actually opened the TestFlight database. `false` means the file
    /// was missing or the read was blocked/denied — notably the "access data from
    /// other apps" TCC gate. The UI uses this to tell "we read it and there was
    /// nothing" apart from "we never got in", so it can re-apply once the user
    /// grants access (an empty inventory alone can't distinguish the two).
    public let accessible: Bool

    /// Default path to TestFlight's sandboxed Core Data store.
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.apple.TestFlight/Data/Library/Application Support/TestFlight/TestFlight.sqlite")
    }

    public init(databaseURL: URL? = nil) {
        let url = databaseURL ?? Self.defaultDatabaseURL
        let (rows, opened) = Self.readMacRows(at: url)
        self.accessible = opened

        var latest: [String: App] = [:]
        var builds: [String: Set<String>] = [:]
        for row in rows {
            builds[row.bundleID, default: []].insert(row.build)
            if let cur = latest[row.bundleID] {
                if VersionComparator.isNewer(row.build, than: cur.latestBuild) {
                    latest[row.bundleID] = App(
                        bundleID: row.bundleID,
                        latestShortVersion: row.shortVersion, latestBuild: row.build)
                }
            } else {
                latest[row.bundleID] = App(
                    bundleID: row.bundleID,
                    latestShortVersion: row.shortVersion, latestBuild: row.build)
            }
        }
        self.appsByBundleID = latest
        self.buildsByBundleID = builds
    }

    /// Test seam / explicit construction: inject the parsed rows directly, skipping
    /// the DB read. `accessible` defaults to `true` (the caller supplied data); pass
    /// `false` to build the "couldn't read TestFlight" sentinel used when the TCC
    /// gate blocks the real read.
    public init(macRows: [(bundleID: String, shortVersion: String, build: String)], accessible: Bool = true) {
        self.accessible = accessible
        var latest: [String: App] = [:]
        var builds: [String: Set<String>] = [:]
        for row in macRows {
            builds[row.bundleID, default: []].insert(row.build)
            if let cur = latest[row.bundleID] {
                if VersionComparator.isNewer(row.build, than: cur.latestBuild) {
                    latest[row.bundleID] = App(bundleID: row.bundleID, latestShortVersion: row.shortVersion, latestBuild: row.build)
                }
            } else {
                latest[row.bundleID] = App(bundleID: row.bundleID, latestShortVersion: row.shortVersion, latestBuild: row.build)
            }
        }
        self.appsByBundleID = latest
        self.buildsByBundleID = builds
    }

    /// Whether an on-disk app is a TestFlight install: its bundle id has macOS
    /// rows in the DB and the installed build is one of them. Matching the build
    /// (not just the bundle id) avoids mistaking an App Store copy of an app the
    /// user merely *has access to* on TestFlight for a TestFlight install.
    public func isManaged(bundleID: String?, installedBuild: String?) -> Bool {
        guard let bundleID, let installedBuild,
              let builds = buildsByBundleID[bundleID] else { return false }
        return builds.contains(installedBuild)
    }

    /// The newest available macOS build for an app, if any.
    public func latest(forBundleID bundleID: String?) -> App? {
        guard let bundleID else { return nil }
        return appsByBundleID[bundleID]
    }

    // MARK: - SQLite

    typealias Row = (bundleID: String, shortVersion: String, build: String)

    /// How long to wait for the database to open before treating it as
    /// unreachable. Generous: a cold sandboxed sqlite open is milliseconds, so
    /// anything near this is the gate, not slow disk.
    static let openTimeout: TimeInterval = 5

    /// A slot one thread fills and another reads. Needed because the reader can
    /// give up before the writer finishes — see `readMacRows(at:)`.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (rows: [Row], opened: Bool)?
        func set(_ v: (rows: [Row], opened: Bool)) {
            lock.lock(); defer { lock.unlock() }
            value = v
        }
        func take() -> (rows: [Row], opened: Bool)? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    /// Paths whose open is *still* stuck behind the gate. Once one is, we stop
    /// starting new opens for it: in a long-running process (the menu-bar app) a
    /// scan happens periodically, and without this each one would strand another
    /// thread. Bounded at one stranded thread per path, and cleared the moment
    /// that open finally returns — so granting access mid-session recovers on
    /// the next scan without a restart.
    ///
    /// Keyed by path rather than a single flag so one unreadable database can
    /// never suppress reads of a different one.
    private final class ProbeState: @unchecked Sendable {
        private let lock = NSLock()
        private var stuck: Set<String> = []
        func isStuck(_ path: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return stuck.contains(path)
        }
        func mark(_ path: String, stuck isStuck: Bool) {
            lock.lock(); defer { lock.unlock() }
            if isStuck { stuck.insert(path) } else { stuck.remove(path) }
        }
    }
    private static let probe = ProbeState()

    /// Returns the macOS rows plus whether the DB was actually opened. `opened`
    /// is `false` for a missing file or a failed/denied open (the TCC gate), so
    /// the caller can tell "read it, nothing there" from "never got in".
    ///
    /// **Bounded, because the open can block forever rather than fail.** The
    /// database sits in TestFlight's container behind macOS's app-data privacy
    /// gate. With someone at the keyboard that surfaces a consent prompt; with
    /// nobody to answer it — a launchd job, a CI runner, an ssh session —
    /// `open(2)` simply never returns, and it is not a cancellation point, so no
    /// amount of `Task` cancellation reaches it. The only thing that works is to
    /// run it somewhere we are willing to abandon and stop waiting.
    ///
    /// Observed 2026-08-15: a nightly sweep sat in `guarded_open_np` for ten
    /// minutes at 0.03s of CPU before it was killed.
    private static func readMacRows(at url: URL) -> (rows: [Row], opened: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], false) }
        guard !probe.isStuck(url.path) else { return ([], false) }

        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        // A Thread, not a Task: a blocked syscall on a cooperative-pool thread
        // starves the pool, and a structured child would pin its parent until it
        // returned — which is the bug this replaces.
        let worker = Thread {
            box.set(openAndRead(at: url))
            probe.mark(url.path, stuck: false)
            done.signal()
        }
        worker.stackSize = 512 * 1024
        worker.start()

        if done.wait(timeout: .now() + openTimeout) == .timedOut {
            probe.mark(url.path, stuck: true)
            Log.scan.error("""
                TestFlight DB open did not return within \(openTimeout, privacy: .public)s at \
                \(url.path, privacy: .public) — treating it as inaccessible (app-data privacy gate)
                """)
            return ([], false)
        }
        return box.take() ?? ([], false)
    }

    /// The actual read. Only ever called from `readMacRows(at:)`'s worker thread.
    private static func openAndRead(at url: URL) -> (rows: [Row], opened: Bool) {
        var db: OpaquePointer?
        // Read-only; SQLITE_OPEN_READONLY still applies the -wal on open so we see
        // TestFlight's most recent (uncheckpointed) writes.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("TestFlight DB open failed at \(url.path, privacy: .public)")
            return ([], false)
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT ZBUNDLEID, ZSHORTVERSION, ZBUNDLEVERSION
        FROM ZTFAPPBUNDLEMODEL
        WHERE ZPLATFORMRAW = 3 AND ZBUNDLEID IS NOT NULL AND ZBUNDLEVERSION IS NOT NULL;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.scan.error("TestFlight DB prepare failed")
            return ([], true)  // we opened it; the schema just didn't match
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bundleC = sqlite3_column_text(stmt, 0),
                  let buildC = sqlite3_column_text(stmt, 2) else { continue }
            let bundleID = String(cString: bundleC)
            let short = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let build = String(cString: buildC)
            rows.append((bundleID, short, build))
        }
        return (rows, true)
    }
}
