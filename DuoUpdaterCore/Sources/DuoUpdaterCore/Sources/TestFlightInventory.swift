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
///   - `ZPLATFORMRAW` 3 == macOS, 1 == iOS. Mac builds are what an update can be
///     *offered* for, so they alone feed ``latest(forBundleID:)`` and
///     ``isManaged(bundleID:installedBuild:)``. iOS rows are read too but kept
///     strictly apart, for one question only — see ``hasIOSBuild(bundleID:installedBuild:)``.
///   - `ZINSTALLSTATUSRAW` 1 == the build currently installed on this machine.
///     Measured 2026-09-08: 6 of 110 rows carry it, no nulls, values only 0/1,
///     never twice for one (bundle, platform) — and all 6 matched an app on disk
///     at exactly that build. It is what separates "TestFlight installed this
///     here" from "the user merely has access to this build", which is the
///     question ``hasInstalledIOSBuild(bundleID:installedBuild:)`` asks. Mac rows
///     deliberately do NOT filter on it: ``latest(forBundleID:)`` needs the builds
///     that are *available*, and keeping only the installed one would make every
///     app permanently up to date.
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
    /// The same, for the iOS rows TestFlight marks as installed here, and
    /// deliberately a separate map rather than more entries in the one above.
    ///
    /// Merging them would corrupt the answer `latest(forBundleID:)` gives for a
    /// native Mac app that ALSO has iOS betas — both TestFlight Mac apps on the
    /// machine this was written on are exactly that: Mithka carries mac 1138 and
    /// iOS 1149, Notability mac 7127 and iOS 7117. A merged table would offer
    /// Mithka the iOS build as its next Mac update.
    private let iosBuildsByBundleID: [String: Set<String>]

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
        let (rows, iosRows, opened) = Self.readRows(at: url)
        self.accessible = opened
        self.iosBuildsByBundleID = Self.buildIndex(iosRows)

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
    ///
    /// ⚠️ `installedIOSRows` is **already filtered**, and the label says so because
    /// the filter lives in the SQL rather than here: the reader keeps only iOS rows
    /// carrying `ZINSTALLSTATUSRAW = 1`. Passing a build the user merely has access
    /// to builds an inventory the database can never produce, and a case resting on
    /// it would assert behaviour that only exists in the fixture. `macRows` has no
    /// such precondition — every mac row is kept, installed or not, because
    /// ``latest(forBundleID:)`` is asking what is available.
    public init(
        macRows: [(bundleID: String, shortVersion: String, build: String)],
        installedIOSRows: [(bundleID: String, shortVersion: String, build: String)] = [],
        accessible: Bool = true
    ) {
        self.accessible = accessible
        self.iosBuildsByBundleID = Self.buildIndex(installedIOSRows)
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

    /// Whether TestFlight says this exact iOS build is installed **on this
    /// machine** — the rows behind this are already filtered to
    /// `ZINSTALLSTATUSRAW = 1`.
    ///
    /// For wrapped iPhone/iPad bundles, and still named for what it reads rather
    /// than for a verdict: `AppScanner` gates the call on `isiOSAppOnMac`, because
    /// a native Mac app can hold iOS rows of its own and a Mac bundle must never
    /// be tagged off a build installed on a phone.
    ///
    /// It exists because a wrapped app's rows carry `ZPLATFORMRAW` 1, never 3 —
    /// `com.ampcode.amp.ios` sat in the DB at build 64, matching the installed
    /// build exactly, and was invisible to `isManaged` (#456).
    ///
    /// **The build match stays, on top of the install flag**, and is not
    /// redundant with it: this database lags real installs (recorded in
    /// `AppScanner` — Paste on disk at 18771 while the DB still said 18655), so a
    /// stale `ZINSTALLSTATUSRAW = 1` can point at a build that is no longer the
    /// one on disk. Requiring both means a lagging DB answers false and the
    /// caller falls through to its other signal, rather than confirming an
    /// install on the strength of a number that has moved on.
    public func hasInstalledIOSBuild(bundleID: String?, installedBuild: String?) -> Bool {
        guard let bundleID, let installedBuild,
              let builds = iosBuildsByBundleID[bundleID] else { return false }
        return builds.contains(installedBuild)
    }

    /// bundleID → the set of build numbers seen for it.
    private static func buildIndex(
        _ rows: [(bundleID: String, shortVersion: String, build: String)]
    ) -> [String: Set<String>] {
        var index: [String: Set<String>] = [:]
        for row in rows { index[row.bundleID, default: []].insert(row.build) }
        return index
    }

    /// The newest available macOS build for an app, if any.
    public func latest(forBundleID bundleID: String?) -> App? {
        guard let bundleID else { return nil }
        return appsByBundleID[bundleID]
    }

    // MARK: - SQLite

    typealias Row = (bundleID: String, shortVersion: String, build: String)
    /// What one read of the database yields: the two platform buckets, plus
    /// whether we got in at all.
    typealias Reading = (rows: [Row], iosRows: [Row], opened: Bool)

    /// How long to wait for the database to open before treating it as
    /// unreachable. Generous: a cold sandboxed sqlite open is milliseconds, so
    /// anything near this is the gate, not slow disk.
    static let openTimeout: TimeInterval = 5

    /// A slot one thread fills and another reads. Needed because the reader can
    /// give up before the writer finishes — see `readRows(at:)`.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Reading?
        func set(_ v: Reading) {
            lock.lock(); defer { lock.unlock() }
            value = v
        }
        func take() -> Reading? {
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

    /// Returns the macOS rows, the iOS rows, and whether the DB was actually
    /// opened. `opened` is `false` for a missing file or a failed/denied open (the
    /// TCC gate), so the caller can tell "read it, nothing there" from "never got
    /// in".
    ///
    /// Both platforms come back from ONE open. Splitting them into two reads would
    /// double the exposure to the gate described below, which is the expensive and
    /// hazardous part of this — the extra rows are not.
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
    private static func readRows(at url: URL) -> Reading {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], [], false) }
        guard !probe.isStuck(url.path) else { return ([], [], false) }

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
            return ([], [], false)
        }
        return box.take() ?? ([], [], false)
    }

    /// The actual read. Only ever called from `readRows(at:)`'s worker thread.
    private static func openAndRead(at url: URL) -> Reading {
        var db: OpaquePointer?
        // Read-only; SQLITE_OPEN_READONLY still applies the -wal on open so we see
        // TestFlight's most recent (uncheckpointed) writes.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("TestFlight DB open failed at \(url.path, privacy: .public)")
            return ([], [], false)
        }
        defer { sqlite3_close(db) }

        // Two queries, tried in order, because a prepare failure is total: it
        // returns an empty inventory that still reports `opened`, so every
        // TestFlight app silently loses its build and no native-Mac beta is
        // offered an update again. `ZINSTALLSTATUSRAW` only feeds the wrapped-bundle
        // signal, so a schema that no longer has that column must cost that signal
        // and nothing else — not the macOS rows this file has read since before it
        // existed. Naming a column in a SELECT is what makes its absence fatal, so
        // the fallback names one fewer.
        if let reading = runRowQuery(db, sql: Self.rowsWithInstallStatusSQL, hasInstallStatus: true) {
            return reading
        }
        Log.scan.error("""
            TestFlight DB prepare failed with ZINSTALLSTATUSRAW — retrying without it; \
            wrapped iOS apps lose their install signal for this read
            """)
        if let reading = runRowQuery(db, sql: Self.macRowsOnlySQL, hasInstallStatus: false) {
            return reading
        }
        Log.scan.error("TestFlight DB prepare failed")
        return ([], [], true)  // we opened it; the schema just didn't match
    }

    /// Both platforms, sorted into two buckets by the reader rather than merged.
    /// The `IN` list is explicit rather than "anything non-null": platforms 2 and 4
    /// also occur (measured on one machine — 86 iOS rows, 5 of platform 2, 18
    /// macOS, 1 of platform 4), nothing here knows what they are, and a bucket
    /// nobody can name is not one to start filing installs under.
    private static let rowsWithInstallStatusSQL = """
        SELECT ZBUNDLEID, ZSHORTVERSION, ZBUNDLEVERSION, ZPLATFORMRAW, ZINSTALLSTATUSRAW
        FROM ZTFAPPBUNDLEMODEL
        WHERE ZPLATFORMRAW IN (1, 3) AND ZBUNDLEID IS NOT NULL AND ZBUNDLEVERSION IS NOT NULL;
        """

    /// The fallback: exactly the columns this file named before the install status
    /// was read, so it prepares on any schema the old query prepared on. iOS rows
    /// are not selected at all — without the status column there is no way to tell
    /// an installed build from one the user merely has access to, and guessing is
    /// the mistake the status column exists to prevent.
    private static let macRowsOnlySQL = """
        SELECT ZBUNDLEID, ZSHORTVERSION, ZBUNDLEVERSION, ZPLATFORMRAW
        FROM ZTFAPPBUNDLEMODEL
        WHERE ZPLATFORMRAW = 3 AND ZBUNDLEID IS NOT NULL AND ZBUNDLEVERSION IS NOT NULL;
        """

    /// Runs one of the two queries above. `nil` means it would not prepare, which
    /// is the caller's cue to try the next one.
    private static func runRowQuery(
        _ db: OpaquePointer?, sql: String, hasInstallStatus: Bool
    ) -> Reading? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [Row] = []
        var iosRows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bundleC = sqlite3_column_text(stmt, 0),
                  let buildC = sqlite3_column_text(stmt, 2) else { continue }
            let bundleID = String(cString: bundleC)
            let short = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let build = String(cString: buildC)
            // Each platform is matched POSITIVELY, with anything else dropped.
            // Written as "macOS or else iOS" this was correct only because the
            // WHERE clause thirty lines up says `IN (1, 3)` — so widening that
            // list later (visionOS, tvOS) would have filed rows from a platform
            // nobody identified straight into the iOS bucket, with no compile
            // error and nothing red. Platforms 2 and 4 do occur in the real
            // database; what they are is unknown, and an unknown bucket is not one
            // to start filing installs under.
            switch sqlite3_column_int64(stmt, 3) {
            case Self.macOSPlatform:
                // Every mac row, installed or not: `latest(forBundleID:)` is
                // asking which builds are AVAILABLE.
                rows.append((bundleID, short, build))
            case Self.iOSPlatform
                where hasInstallStatus && sqlite3_column_int64(stmt, 4) == Self.installedHere:
                // Only the one TestFlight says is installed here. These rows
                // answer a membership question, never an "is there something
                // newer" one, and an available-but-not-installed iOS build is
                // exactly the thing that must not tag a bundle.
                iosRows.append((bundleID, short, build))
            default:
                break
            }
        }
        return (rows, iosRows, true)
    }

    /// `ZPLATFORMRAW` values, both named because both are now matched positively.
    private static let macOSPlatform: Int64 = 3
    private static let iOSPlatform: Int64 = 1
    /// `ZINSTALLSTATUSRAW` for "this build is the one installed on this machine".
    private static let installedHere: Int64 = 1
}
