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

    /// Default path to TestFlight's sandboxed Core Data store.
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.apple.TestFlight/Data/Library/Application Support/TestFlight/TestFlight.sqlite")
    }

    public init(databaseURL: URL? = nil) {
        let url = databaseURL ?? Self.defaultDatabaseURL
        let rows = Self.readMacRows(at: url)

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

    /// Test seam: inject the parsed rows directly, skipping the DB read.
    public init(macRows: [(bundleID: String, shortVersion: String, build: String)]) {
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

    private static func readMacRows(at url: URL)
        -> [(bundleID: String, shortVersion: String, build: String)] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        var db: OpaquePointer?
        // Read-only; SQLITE_OPEN_READONLY still applies the -wal on open so we see
        // TestFlight's most recent (uncheckpointed) writes.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("TestFlight DB open failed at \(url.path, privacy: .public)")
            return []
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
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [(bundleID: String, shortVersion: String, build: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bundleC = sqlite3_column_text(stmt, 0),
                  let buildC = sqlite3_column_text(stmt, 2) else { continue }
            let bundleID = String(cString: bundleC)
            let short = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let build = String(cString: buildC)
            rows.append((bundleID, short, build))
        }
        return rows
    }
}
