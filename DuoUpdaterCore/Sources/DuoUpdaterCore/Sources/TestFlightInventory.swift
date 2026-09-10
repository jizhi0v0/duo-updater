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
///   - `ZPLATFORMRAW` 3 == macOS, 1 == iOS. The two are read into strictly
///     separate tables and never merged: mac rows feed ``latest(forBundleID:)``
///     and ``isManaged(bundleID:installedBuild:)``, iOS rows feed
///     ``latestIOS(forBundleID:)`` and ``hasInstalledIOSBuild(bundleID:installedBuild:)``,
///     and it is the CALLER that picks a side, from `isiOSAppOnMac`. A native Mac
///     app can hold iOS rows of its own, so a merged table would offer it an
///     iPhone build as its next Mac update.
///   - `ZINSTALLSTATUSRAW` 1 == a build TestFlight installed on this machine.
///   - `ZTFAPPMODEL.ZISTESTER` 1, reached through a build row's `ZAPP` == the signed-in
///     account is testing that app. Read by its own query; see `readTesters`.
///     Measured 2026-09-08: 6 of 110 rows carry it, no nulls, values only 0/1, and
///     all 6 matched an app on disk at exactly that build. It is what separates
///     "TestFlight installed this here" from "the user merely has access to this
///     build", which is the question ``hasInstalledIOSBuild(bundleID:installedBuild:)``
///     asks.
///     ⚠️ **It is NOT unique per (bundle, platform)**, and an earlier version of
///     this note said it was, on that one sample. Falsified 2026-09-09, watching
///     TestFlight auto-install a build we had just pushed: both rows stayed marked
///     installed —
///     ```
///     com.jizhi0v0.claude-usage | 0.3.384 | 1300 | platform 1 | installed 1
///     com.jizhi0v0.claude-usage | 0.3.384 | 1301 | platform 1 | installed 1
///     ```
///     while only 1301 was on disk. Membership is the only safe question to ask of
///     this column: "is this on-disk build one TestFlight put here" survives the
///     stale row, "which build is installed" does not. Mac rows
///     deliberately do NOT filter on it: ``latest(forBundleID:)`` needs the builds
///     that are *available*, and keeping only the installed one would make every
///     app permanently up to date.
///   - The newest available build is the newest row **on the platform being asked
///     about** — the two platforms are ranked separately and never against each
///     other. Newest means `VersionSide`: `ZSHORTVERSION` first, `ZBUNDLEVERSION`
///     only to break a marketing tie. Both halves are load-bearing, and the
///     reasoning (with the rows that measured each) is on ``newestByBundleID``.
public struct TestFlightInventory: Sendable {

    /// The newest TestFlight build known for one app on ONE platform. Both buckets
    /// use this type — `latest(forBundleID:)` returns the mac answer,
    /// `latestIOS(forBundleID:)` the iOS one — so nothing here names a platform and
    /// the caller is the only thing that knows which it asked for.
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

    /// The newest iOS build TestFlight OFFERS for each bundle — every iOS row,
    /// installed or not, exactly as `appsByBundleID` is built from every mac row.
    ///
    /// Separate from `iosBuildsByBundleID` above because the two answer opposite
    /// questions and the SQL treats them differently: that one is filtered to
    /// `ZINSTALLSTATUSRAW = 1` and asks "did TestFlight put this copy here", this
    /// one must keep the rows the user has NOT installed or it could never offer
    /// an update. Merging them would either make membership answer yes for a build
    /// the user merely has access to, or make this one permanently say "current".
    ///
    /// Only ``latestIOS(forBundleID:)`` reads it, and only for a wrapped bundle —
    /// see there for why a native Mac app must never be routed through it.
    private let iosLatestByBundleID: [String: App]

    /// What the store knows about one app, in TestFlight's **own** id space —
    /// nothing here is a `CFBundleVersion`.
    ///
    /// `maxBuildID` is a frontier, not a version: the store keeps one row per
    /// platform for the *current* build and no history, so the only question it can
    /// answer is "has this store seen anything at least this new".
    public struct Frontier: Sendable, Equatable {
        /// The App Store id, from `ZTFAPPMODEL.ZAPPID` — the same id TestFlight's
        /// notifications carry in their default-action URL.
        public let adamID: Int64
        /// The largest `ZTFAPPBUNDLEMODEL.ZBUILDID` this store holds for the app,
        /// across platforms.
        public let maxBuildID: Int64

        public init(adamID: Int64, maxBuildID: Int64) {
            self.adamID = adamID
            self.maxBuildID = maxBuildID
        }
    }

    /// Per bundle id: which app the store thinks it is, and the newest build id it
    /// has ever recorded for it. Empty when the frontier query did not prepare,
    /// which costs this signal and nothing else.
    private let frontierByBundleID: [String: Frontier]

    /// Bundles the signed-in account is testing, or nil when the tester query did
    /// not run — see `readTesters`, and `isTesting(bundleID:)` for what nil means.
    private let testerBundleIDs: Set<String>?

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
        let (rows, iosRows, iosAvailableRows, frontiers, testers, opened) = Self.readRows(at: url)
        self.accessible = opened
        self.frontierByBundleID = frontiers
        self.testerBundleIDs = testers
        self.iosBuildsByBundleID = Self.buildIndex(iosRows)
        self.iosLatestByBundleID = Self.newestByBundleID(iosAvailableRows)

        var builds: [String: Set<String>] = [:]
        for row in rows { builds[row.bundleID, default: []].insert(row.build) }
        self.appsByBundleID = Self.newestByBundleID(rows)
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
    ///
    /// `availableIOSRows` is the other iOS bucket and carries the opposite
    /// precondition: it is NOT filtered by install status, because
    /// ``latestIOS(forBundleID:)`` is asking what TestFlight offers. Passing only
    /// `installedIOSRows` therefore describes a machine where the user is already
    /// on the newest beta — a legitimate fixture, and the default, but not the one
    /// to use for a case about an update being available.
    public init(
        macRows: [(bundleID: String, shortVersion: String, build: String)],
        installedIOSRows: [(bundleID: String, shortVersion: String, build: String)] = [],
        availableIOSRows: [(bundleID: String, shortVersion: String, build: String)]? = nil,
        frontiers: [String: Frontier] = [:],
        testers: Set<String>? = nil,
        accessible: Bool = true
    ) {
        self.accessible = accessible
        self.frontierByBundleID = frontiers
        self.testerBundleIDs = testers
        self.iosBuildsByBundleID = Self.buildIndex(installedIOSRows)
        // The database always yields the installed rows as a subset of the
        // available ones, so a fixture that names only the installed rows gets the
        // same shape rather than an inventory that says "installed but not offered".
        self.iosLatestByBundleID = Self.newestByBundleID(availableIOSRows ?? installedIOSRows)
        var builds: [String: Set<String>] = [:]
        for row in macRows { builds[row.bundleID, default: []].insert(row.build) }
        self.appsByBundleID = Self.newestByBundleID(macRows)
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

    /// The newest iOS build TestFlight offers for a wrapped iPhone/iPad bundle.
    ///
    /// ⚠️ **Only for `isiOSAppOnMac` bundles**, and the caller owns that gate — the
    /// same split `AppScanner` already applies to `hasInstalledIOSBuild`. A native
    /// Mac app can hold iOS rows of its own, and handing it this answer is the
    /// exact corruption `iosBuildsByBundleID` was kept separate to prevent:
    /// measured 2026-09-09, Paste is on the mac track at 29808607 while its iOS
    /// track sits at 29814462, so a Mac app routed here would be offered an iPhone
    /// build as its next Mac update.
    ///
    /// ⚠️ **Compatibility is not in this database.** Whether a given build runs on
    /// this Mac lives in TestFlight's API response (`compatible`), not in any
    /// column here, so a build offered from these rows can turn out to be
    /// iPhone-only. The cost is bounded — the row's action is "open TestFlight",
    /// which is where the real answer is, and nothing is downloaded on our side —
    /// but it is a real gap, not one this can close.
    public func latestIOS(forBundleID bundleID: String?) -> App? {
        guard let bundleID else { return nil }
        return iosLatestByBundleID[bundleID]
    }

    /// What the store knows about this app in TestFlight's own id space, or nil
    /// when the store has no app row for it (or the frontier query did not run).
    ///
    /// ⚠️ **This one is deliberately NOT split by platform, and that is not the
    /// merge the warning above forbids.** That warning is about *offering* a build:
    /// hand a native Mac app its iOS track and it gets an iPhone build as its next
    /// Mac update. This offers nothing. It answers "how recently has this store
    /// synced anything at all for this app", and the store syncs every platform in
    /// one pass, so the newest row of any platform is the better answer to that
    /// question — a mac-only frontier would call a store stale on the strength of a
    /// track that simply has no new builds.
    public func frontier(forBundleID bundleID: String?) -> Frontier? {
        guard let bundleID else { return nil }
        return frontierByBundleID[bundleID]
    }

    /// Whether the signed-in account is testing this bundle.
    ///
    /// `false` when the store says it is not — signed out, a different Apple
    /// Account, or testing stopped — and then whatever rows are left for the
    /// bundle are not offers: see `readTesters` for what survives. nil when the
    /// store cannot say (no bundle id, a read that never got in, or a tester query
    /// that did not prepare), which a caller must treat as "no signal", never as
    /// "not testing".
    public func isTesting(bundleID: String?) -> Bool? {
        guard let bundleID, let testerBundleIDs else { return nil }
        return testerBundleIDs.contains(bundleID)
    }

    /// bundleID → the newest row. **Every** bucket ranks through here — mac and
    /// iOS, real database and test seam — so they cannot drift apart in how
    /// "newest" is decided.
    ///
    /// Newest means `VersionSide`: marketing version first, build only to break a
    /// marketing tie. Both halves are load-bearing here, and each is the whole
    /// answer for some app in this database:
    ///
    ///   * **Build alone is not enough.** The same build number can appear under
    ///     two marketing versions — the database's unique index is `(bundleID,
    ///     shortVersion, bundleVersion, platformRaw)`, and ASC's build-number
    ///     uniqueness is per marketing version, so this is a shape it is designed
    ///     to hold. Measured 2026-09-09: `com.jizhi0v0.claude-usage` held
    ///     (0.3.370, 1300) and (0.3.384, 1300) at once. Comparing builds alone made
    ///     `isNewer` false in both directions, so whichever row SQLite happened to
    ///     return first won — and the query has no `ORDER BY`, so "newest" was
    ///     arbitrary and could name an expired version older than the installed one
    ///     (#485).
    ///   * **Marketing alone is not enough.** Beta tracks routinely freeze it:
    ///     APTV's rows are all `1.0` with builds 300/301/304, and Claudo shipped
    ///     0.3.384 twice (1300, then 1301). For those apps the build is the whole
    ///     comparison.
    ///
    /// A blank `ZSHORTVERSION` is folded to nil rather than passed through: the
    /// comparator's tokenizer reads a string with no digits the same as `"0"`, so
    /// an empty marketing string would lose every comparison it entered instead of
    /// standing aside and letting the build decide.
    ///
    /// ⚠️ Marketing-first means a row whose build is higher but whose marketing
    /// version is LOWER does not win — a hotfix cut from an older line, say. That
    /// is `VersionComparator`'s rule everywhere in this codebase rather than a
    /// choice made here, and the alternative (build-first) is what #485 was.
    private static func newestByBundleID(
        _ rows: [(bundleID: String, shortVersion: String, build: String)]
    ) -> [String: App] {
        func side(marketing: String, build: String) -> VersionSide {
            VersionSide(marketing: marketing.isEmpty ? nil : marketing, build: build)
        }
        var newest: [String: App] = [:]
        for row in rows {
            let candidate = App(
                bundleID: row.bundleID,
                latestShortVersion: row.shortVersion, latestBuild: row.build)
            guard let cur = newest[row.bundleID] else {
                newest[row.bundleID] = candidate
                continue
            }
            if VersionComparator.isNewer(
                side(marketing: row.shortVersion, build: row.build),
                than: side(marketing: cur.latestShortVersion, build: cur.latestBuild)
            ) {
                newest[row.bundleID] = candidate
            }
        }
        return newest
    }

    // MARK: - SQLite

    typealias Row = (bundleID: String, shortVersion: String, build: String)
    /// What one read of the database yields: the two platform buckets, plus
    /// whether we got in at all.
    typealias Reading = (
        rows: [Row], iosRows: [Row], iosAvailableRows: [Row],
        frontiers: [String: Frontier], testers: Set<String>?, opened: Bool)

    /// How long to wait for the database to open before treating it as
    /// unreachable. Generous: a cold sandboxed sqlite open is milliseconds, so
    /// anything near this is the gate, not slow disk.
    static let openTimeout: TimeInterval = 5

    /// The bound itself, plus the memo of paths whose open never came back. Both
    /// live in `BoundedBlockingWork`, which is this code generalised — see its
    /// doc comment for why the thread is abandoned rather than pooled, and why
    /// one stranded thread per path is the ceiling. Keyed by path rather than a
    /// single flag so one unreadable database can never suppress reads of a
    /// different one.
    private static let bounded = BoundedBlockingWork(label: "TestFlight DB open")

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
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], [], [], [:], nil, false) }
        // nil covers both give-up modes — this open timed out, or an earlier one
        // for this path is still stranded — and both mean the same thing to the
        // caller: we never got in, so `opened` is false rather than "read it,
        // nothing inside".
        // Labelled rather than `([], [], [], false)`: with four elements the bare
        // literal leaves `bounded.run`'s generic parameter ambiguous between the
        // tuple type and `Reading`, and the compiler rejects it.
        return bounded.run(key: url.path, timeout: openTimeout) {
            openAndRead(at: url)
        } ?? (rows: [], iosRows: [], iosAvailableRows: [], frontiers: [:], testers: nil, opened: false)
    }

    /// The actual read. Only ever called from `readRows(at:)`'s worker thread.
    private static func openAndRead(at url: URL) -> Reading {
        var db: OpaquePointer?
        // Read-only; SQLITE_OPEN_READONLY still applies the -wal on open so we see
        // TestFlight's most recent (uncheckpointed) writes.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("TestFlight DB open failed at \(url.path, privacy: .public)")
            return ([], [], [], [:], nil, false)
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
        if var reading = runRowQuery(db, sql: Self.rowsWithInstallStatusSQL, hasInstallStatus: true) {
            reading.frontiers = readFrontiers(db)
            reading.testers = readTesters(db)
            return reading
        }
        Log.scan.error("""
            TestFlight DB prepare failed with ZINSTALLSTATUSRAW — retrying without it; \
            wrapped iOS apps lose their install signal for this read
            """)
        if var reading = runRowQuery(db, sql: Self.macRowsOnlySQL, hasInstallStatus: false) {
            reading.frontiers = readFrontiers(db)
            reading.testers = readTesters(db)
            return reading
        }
        Log.scan.error("TestFlight DB prepare failed")
        // Still ask for the frontier. Its two columns live in different tables from
        // the ones above, so a schema that breaks the row queries does not imply this
        // one cannot prepare — and the whole reason the frontier got its own query is
        // that each signal fails on its own. Returning here without trying made the
        // implication run backwards.
        return ([], [], [], readFrontiers(db), readTesters(db), true)  // we opened it; the schema just didn't match
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

    /// The store's build-id frontier per bundle, joined to the app row that carries
    /// the App Store id.
    ///
    /// **Its own query, and its own failure.** This file's rule is that naming a
    /// column in a SELECT makes its absence fatal, so `ZBUILDID` and `ZAPPID` are
    /// not added to the row queries above: a schema without them must cost this
    /// signal alone, not the macOS rows the inventory has read since before either
    /// existed. An empty map here is a working inventory with one witness missing.
    private static func readFrontiers(_ db: OpaquePointer?) -> [String: Frontier] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.frontierSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            Log.scan.error("TestFlight DB frontier query did not prepare — announcement witness is off")
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        var out: [String: Frontier] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(stmt, 0) else { continue }
            let bundleID = String(cString: raw)
            let frontier = Frontier(
                adamID: sqlite3_column_int64(stmt, 1), maxBuildID: sqlite3_column_int64(stmt, 2))
            // One app row per bundle in practice; keep the larger frontier if the
            // store ever carries two, since this is an "at least this new" bound.
            if let existing = out[bundleID], existing.maxBuildID >= frontier.maxBuildID { continue }
            out[bundleID] = frontier
        }
        return out
    }

    /// Both platforms deliberately: the frontier answers "has this store seen
    /// anything at least this new for this app", and a Mac beta and its iOS twin
    /// are announced through the same notification stream.
    private static let frontierSQL = """
        SELECT a.ZBUNDLEID, a.ZAPPID, MAX(b.ZBUILDID)
        FROM ZTFAPPMODEL a JOIN ZTFAPPBUNDLEMODEL b ON b.ZAPP = a.Z_PK
        WHERE a.ZBUNDLEID IS NOT NULL AND a.ZAPPID IS NOT NULL AND b.ZBUILDID IS NOT NULL
        GROUP BY a.Z_PK;
        """

    /// Which bundles the signed-in account is actually testing: a build row whose
    /// app row carries `ZISTESTER = 1`.
    ///
    /// Measured 2026-09-10 by snapshotting the store while the account changed
    /// under a running TestFlight. Signed in, every installed beta's rows hang off
    /// an app row with its bundle id filled in and `ZISTESTER = 1`. Signed out —
    /// and again signed in to a different Apple Account — the installed rows
    /// survive, but hang off placeholder app rows with no bundle id, no name and
    /// `ZISTESTER = 0`, and every offer row is gone. Read without this, the
    /// installed row was the only row left, so it was taken as the newest build and
    /// the beta called up to date, for an account that cannot even see it.
    /// Stopping testing a beta that is not installed removed its app row outright;
    /// one that is installed was not measured.
    ///
    /// Joined through `ZAPP` rather than matched on bundle id: the placeholders
    /// carry no bundle id, so a bundle-id match would agree here, but only by
    /// accident of what a placeholder happens to omit.
    ///
    /// **Its own query, and its own failure**, like the frontier: nil means it did
    /// not prepare, which switches this signal off and changes no verdict.
    private static func readTesters(_ db: OpaquePointer?) -> Set<String>? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.testerSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            Log.scan.error("TestFlight DB tester query did not prepare — the signed-in account's betas are unknown for this read")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        var out: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let raw = sqlite3_column_text(stmt, 0) { out.insert(String(cString: raw)) }
        }
        return out
    }

    private static let testerSQL = """
        SELECT DISTINCT b.ZBUNDLEID
        FROM ZTFAPPBUNDLEMODEL b JOIN ZTFAPPMODEL a ON b.ZAPP = a.Z_PK
        WHERE a.ZISTESTER = 1 AND b.ZBUNDLEID IS NOT NULL;
        """

    /// Runs one of the two queries above. `nil` means it would not prepare, which
    /// is the caller's cue to try the next one.
    ///
    /// ⚠️ `hasInstallStatus` cannot change the outcome today — the fallback query
    /// selects `ZPLATFORMRAW = 3`, so no iOS row ever reaches the branch that reads
    /// it (measured: inverting the flag leaves the suite green). It stays because
    /// of what it guards, not what it currently decides: column 4 does not exist in
    /// the fallback's result set, and `&&` short-circuiting is what keeps
    /// `sqlite3_column_int64(stmt, 4)` from being an out-of-range read the day
    /// someone widens that query the way the primary one is widened.
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
        var iosAvailableRows: [Row] = []
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
            case Self.iOSPlatform:
                // Every iOS row is what TestFlight OFFERS for this bundle, which is
                // the only bucket an update can come out of.
                iosAvailableRows.append((bundleID, short, build))
                // …and, separately, the one TestFlight says is installed here.
                // These rows answer a membership question, never an "is there
                // something newer" one, and an available-but-not-installed iOS
                // build is exactly the thing that must not tag a bundle.
                if hasInstallStatus && sqlite3_column_int64(stmt, 4) == Self.installedHere {
                    iosRows.append((bundleID, short, build))
                }
            default:
                break
            }
        }
        // Frontiers are filled in by `openAndRead`, from its own query.
        return (rows, iosRows, iosAvailableRows, [:], nil, true)
    }

    /// `ZPLATFORMRAW` values, both named because both are now matched positively.
    private static let macOSPlatform: Int64 = 3
    private static let iOSPlatform: Int64 = 1
    /// `ZINSTALLSTATUSRAW` for "this build is the one installed on this machine".
    private static let installedHere: Int64 = 1
}

extension TestFlightInventory.Frontier {
    /// TestFlight's page for this app: `itms-beta://beta.itunes.apple.com/v1/app/<id>`.
    ///
    /// Measured 2026-09-10 against a running TestFlight (Darwin 27.0.0), with the
    /// detail pane's title read through Accessibility as the witness: two ids in
    /// turn each landed on their own app's page, and `open -g` did not bring the
    /// window forward. A comment in this repository used to say this form "just
    /// opens the app list" on macOS; here it did not. Not measured: a TestFlight
    /// that is not already running.
    ///
    /// ⚠️ Never a `/join/<code>` URL. That form *joins a beta*, an account-level
    /// side effect, and this is only reached from a button that says "open".
    public var appPageURL: URL? {
        guard adamID > 0 else { return nil }
        return URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\(adamID)")
    }
}
