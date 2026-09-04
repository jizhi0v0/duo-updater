import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// Moving the download ledger into the event store, and the two properties that
/// make it safe to do to data a user already has: nothing is lost, and nothing is
/// counted twice.
@Suite(.serialized)
struct InstallEventMigrationTests {

    private static func store(
        retentionDays: Int = 30, pruneInterval: Duration = .seconds(3600)
    ) -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, retentionDays: retentionDays,
                           flushEventCount: 1, flushDelay: .milliseconds(10),
                           pruneInterval: pruneInterval), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    /// A legacy file shaped like the real one: several apps, several events each,
    /// builds on some and not others, both download kinds, a rename mid-history.
    private static func legacyFile() throws -> (URL, [String: AppTrafficStat]) {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        var stats: [String: AppTrafficStat] = [:]

        stats["/Applications/Surge.app"] = AppTrafficStat(
            appID: "/Applications/Surge.app", appName: "Surge",
            bundleID: "com.nssurge.surge-mac", totalBytes: 3_000,
            events: [
                TrafficEvent(date: start, fromVersion: "6.9.0", toVersion: "6.9.0",
                             sourceName: "Sparkle", bytes: 1_000,
                             fromBuild: "3200", toBuild: "3201", downloadKind: .full),
                TrafficEvent(date: start + day, fromVersion: "6.9.0", toVersion: "6.9.1",
                             sourceName: "Sparkle", bytes: 2_000,
                             fromBuild: "3201", toBuild: "3300", downloadKind: .delta),
            ])
        stats["/Applications/VLC.app"] = AppTrafficStat(
            appID: "/Applications/VLC.app", appName: "VLC",
            bundleID: "org.videolan.vlc", totalBytes: 500,
            events: [
                // No builds, no download kind: what a pre-0.3.62 row looks like.
                TrafficEvent(date: start + 2 * day, fromVersion: "3.0.20",
                             toVersion: "3.0.21", sourceName: "Vendor", bytes: 500),
            ])
        stats["/Applications/Renamed.app"] = AppTrafficStat(
            appID: "/Applications/Renamed.app", appName: "New Name",
            bundleID: nil, totalBytes: 90,
            events: [
                TrafficEvent(date: start + 3 * day, fromVersion: nil, toVersion: "2",
                             sourceName: nil, bytes: 40),
                TrafficEvent(date: start + 4 * day, fromVersion: "2", toVersion: "3",
                             sourceName: "GitHub", bytes: 50, downloadKind: .full),
            ])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("traffic-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stats).write(to: url)
        return (url, stats)
    }

    // MARK: - Nothing lost

    @Test("Everything traffic.json holds survives the move, field for field")
    func migrationIsLossless() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let (legacyURL, legacy) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let imported = await store.importLegacyTraffic(from: legacyURL)
        #expect(imported == 5)

        let migrated = await store.appTrafficStats()
        #expect(migrated.count == 3)

        // Compared as whole values per app rather than field by field, so a field
        // dropped from `InstallEvent` fails here instead of going unnoticed.
        for original in legacy.values {
            let moved = try #require(migrated.first { $0.appID == original.appID })
            #expect(moved.appName == original.appName)
            #expect(moved.bundleID == original.bundleID)
            #expect(moved.totalBytes == original.totalBytes)
            #expect(moved.events == original.events)
        }

        // And the aggregate the Traffic window's header reads is identical, which
        // is the claim that actually matters to someone looking at the window.
        let before = TrafficSummary(stats: Array(legacy.values))
        let after = TrafficSummary(stats: migrated)
        #expect(after.totalBytes == before.totalBytes)
        #expect(after.downloadCount == before.downloadCount)
        #expect(after.appCount == before.appCount)
        #expect(after.months == before.months)
        #expect(after.sources == before.sources)
    }

    // MARK: - Nothing counted twice

    @Test("Importing twice does not double a lifetime total")
    func migrationIsIdempotent() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let (legacyURL, legacy) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        let expected = legacy.values.reduce(Int64(0)) { $0 + $1.totalBytes }

        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        // The marker alone stops the second call…
        #expect(await store.importLegacyTraffic(from: legacyURL) == nil)
        // …and forcing past it still cannot double anything, because every event
        // takes a stable id and the totals are summed from the rows rather than
        // incremented. The marker is the belt; this is the mechanism.
        #expect(await store.importLegacyTraffic(from: legacyURL, force: true) == 5)
        #expect(await store.importLegacyTraffic(from: legacyURL, force: true) == 5)

        let stats = await store.appTrafficStats()
        #expect(stats.reduce(Int64(0)) { $0 + $1.totalBytes } == expected)
        #expect(stats.reduce(0) { $0 + $1.updateCount } == 5)
    }

    @Test("A stable id depends on the row, and only on the row")
    func migrationIDsAreDerivedFromContent() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let base = InstallEvent.migrationID(appID: "/Applications/A.app", date: date, bytes: 10)
        #expect(base == InstallEvent.migrationID(appID: "/Applications/A.app", date: date, bytes: 10))
        #expect(base != InstallEvent.migrationID(appID: "/Applications/B.app", date: date, bytes: 10))
        #expect(base != InstallEvent.migrationID(appID: "/Applications/A.app",
                                                 date: date + 1, bytes: 10))
        #expect(base != InstallEvent.migrationID(appID: "/Applications/A.app", date: date, bytes: 11))
    }

    @Test("A machine that never had a traffic.json settles too")
    func absentLegacyFileStillCompletes() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString).json")

        #expect(await store.importLegacyTraffic(from: missing) == nil)
        // Recorded as done: otherwise every launch re-reads a file that is not
        // there, forever.
        #expect(await store.importLegacyTraffic(from: missing, force: false) == nil)
        #expect(await store.appTrafficStats().isEmpty)
    }

    /// A database created before install events existed is the case that actually
    /// ships, and the one a fresh-database test cannot see.
    ///
    /// Found by running the real migration on this machine: `CREATE TABLE IF NOT
    /// EXISTS` left the older table alone, every insert failed on the unknown
    /// `app_id` column, and the import marked itself done having written nothing.
    /// The marker was set; the 115 GB was not.
    @Test("A database that predates install events gains the column and migrates")
    func migratesIntoAnOlderDatabase() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        defer { Self.remove(url) }
        try Self.makeLegacySchema(at: url, extraColumns: "")
        let (legacyURL, legacy) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let store = EventStore(fileURL: url, flushEventCount: 1, flushDelay: .milliseconds(10))
        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        let expected = legacy.values.reduce(Int64(0)) { $0 + $1.totalBytes }
        #expect(await store.appTrafficStats().reduce(Int64(0)) { $0 + $1.totalBytes } == expected)
    }

    /// An import that cannot write must not record that it did.
    ///
    /// The marker is what makes the migration a one-shot, so a marker written
    /// after a failed write does not lose a launch — it loses the history, on
    /// every launch after it, permanently.
    @Test("An import that writes nothing is not marked done")
    func failedImportIsRetriedNextTime() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        defer { Self.remove(url) }
        // A table that refuses install rows, standing in for any reason an insert
        // can fail that the import loop cannot see.
        try Self.makeLegacySchema(at: url, extraColumns: ", app_id TEXT",
                                  check: "CHECK (kind <> 'install')")
        let (legacyURL, _) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let store = EventStore(fileURL: url, flushEventCount: 1, flushDelay: .milliseconds(10))
        #expect(await store.importLegacyTraffic(from: legacyURL) == nil)
        #expect(await store.appTrafficStats().isEmpty)
        // And crucially it is still pending, so a later launch can try again.
        #expect(await store.importLegacyTraffic(from: legacyURL) == nil)
        #expect(await store.metaMarker("traffic.json") == nil,
                "a failed import marked itself done; the history is now unreachable")
    }

    private static func makeLegacySchema(
        at url: URL, extraColumns: String, check: String = ""
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db else { throw URLError(.cannotCreateFile) }
        defer { sqlite3_close_v2(db) }
        let sql = """
            PRAGMA auto_vacuum=INCREMENTAL;
            PRAGMA journal_mode=WAL;
            CREATE TABLE events (
              id TEXT PRIMARY KEY, at INTEGER NOT NULL, client TEXT NOT NULL,
              kind TEXT NOT NULL, purpose TEXT, host TEXT, status INTEGER,
              bytes_in INTEGER, bytes_out INTEGER, payload TEXT NOT NULL\(extraColumns)
              \(check));
            CREATE INDEX events_at ON events(at);
            CREATE TABLE totals (
              client TEXT NOT NULL, purpose TEXT NOT NULL, host TEXT NOT NULL,
              requests INTEGER NOT NULL DEFAULT 0, cached INTEGER NOT NULL DEFAULT 0,
              not_modified INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0,
              bytes_sent INTEGER NOT NULL DEFAULT 0, bytes_received INTEGER NOT NULL DEFAULT 0,
              first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
              PRIMARY KEY (client, purpose, host));
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw URLError(.cannotCreateFile)
        }
    }

    /// A colliding pair must cost at most itself.
    ///
    /// The first integrity guard compared this run's iterations against the
    /// table's total install count, so a single `INSERT OR REPLACE` collision made
    /// the numbers disagree and rolled the **whole** import back — permanently,
    /// on every future launch. Reproduced against a three-event file: 0 of 3
    /// imported, and `nil` returned forever after.
    @Test("Two legacy rows that would collide are both kept, and nothing aborts")
    func collidingLegacyRowsDoNotAbortTheImport() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        // Same app, same second, same byte count — the whole tuple the id hashes.
        // Legacy dates carry no sub-second part, so this is reachable in principle.
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        let stat = AppTrafficStat(
            appID: "/Applications/A.app", appName: "A", bundleID: nil, totalBytes: 300,
            events: [
                TrafficEvent(date: instant, fromVersion: "1.0", toVersion: "1.1",
                             sourceName: "Sparkle", bytes: 100),
                TrafficEvent(date: instant, fromVersion: "1.1", toVersion: "1.2",
                             sourceName: "Sparkle", bytes: 100),
                TrafficEvent(date: instant + 86_400, fromVersion: "1.2", toVersion: "1.3",
                             sourceName: "Sparkle", bytes: 100),
            ])
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("traffic-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([stat.appID: stat]).write(to: legacyURL)

        #expect(await store.importLegacyTraffic(from: legacyURL) == 3)
        let migrated = await store.appTrafficStats().first
        #expect(migrated?.updateCount == 3)
        #expect(migrated?.totalBytes == 300)
    }

    /// Re-import when the source changes, which is what survives a downgrade.
    ///
    /// The old build knows nothing about this store: it reads *and writes*
    /// `traffic.json`. A one-shot marker therefore skipped every install made
    /// while the user was back on it — replayed against a real 187-event file,
    /// the install made on the old build was silently and permanently lost.
    @Test("A traffic.json that changed since the last import is imported again")
    func aChangedSourceIsReimported() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let (legacyURL, legacy) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        #expect(await store.importLegacyTraffic(from: legacyURL) == nil, "unchanged")

        // An install recorded on the new build, which the old one cannot see.
        await store.append(DuoEvent(payload: .install(
            InstallEvent(appID: "/Applications/OnNew.app", appName: "OnNew", bundleID: nil,
                         fromVersion: "1", toVersion: "2", sourceName: "GitHub",
                         bytes: 7_000))))
        await store.flush()

        // …and one the old build appended to the legacy file while it was in charge.
        var updated = legacy
        var extra = AppTrafficStat(appID: "/Applications/OnOld.app", appName: "OnOld",
                                   bundleID: nil)
        extra.totalBytes = 3_000
        extra.events = [TrafficEvent(date: Date(), fromVersion: "1", toVersion: "2",
                                     sourceName: "Vendor", bytes: 3_000)]
        updated[extra.appID] = extra
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(updated).write(to: legacyURL)

        #expect(await store.importLegacyTraffic(from: legacyURL) == 6)
        let stats = await store.appTrafficStats()
        #expect(stats.contains { $0.appID == "/Applications/OnNew.app" }, "new-build install lost")
        #expect(stats.contains { $0.appID == "/Applications/OnOld.app" }, "old-build install lost")
        // 5 legacy (replaced in place) + 1 old-build + 1 new-build.
        #expect(stats.reduce(0) { $0 + $1.updateCount } == 7, "something was counted twice")
    }

    /// Pre-existing install rows must not mask a failed insert.
    @Test("Importing into a store that already holds installs still checks the write")
    func importIntoANonEmptyStore() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        for index in 0..<20 {
            await store.append(DuoEvent(payload: .install(
                InstallEvent(appID: "/Applications/P\(index).app", appName: "P\(index)",
                             bundleID: nil, fromVersion: "1", toVersion: "2",
                             sourceName: "GitHub", bytes: 100))))
        }
        await store.flush()
        let (legacyURL, _) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        // 20 live + 5 imported, and the guard did not pass merely because 20 rows
        // were already sitting there.
        #expect(await store.appTrafficStats().reduce(0) { $0 + $1.updateCount } == 25)
    }

    @Test("Wiping the ledger lets it be imported again")
    func wipingClearsTheImportMarker() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let (legacyURL, _) = try Self.legacyFile()
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        await store.reset(includingInstalls: true)
        // The whole design rests on traffic.json being kept as the user's copy; a
        // wipe that left the marker behind would make that copy unreachable.
        #expect(await store.metaMarker("traffic.json") == nil)
        #expect(await store.importLegacyTraffic(from: legacyURL) == 5)
        #expect(await store.appTrafficStats().reduce(0) { $0 + $1.updateCount } == 5)
    }

    @Test("Coverage counts the kind it is asked about, not the whole table")
    func coverageIsFilteredByKind() async throws {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let old = Date().addingTimeInterval(-200 * 86_400)
        await store.append(DuoEvent(date: old, payload: .install(
            InstallEvent(appID: "/Applications/A.app", appName: "A", bundleID: nil,
                         fromVersion: "1", toVersion: "2", sourceName: "GitHub",
                         bytes: 10))))
        await store.append(DuoEvent(payload: .request(
            RequestEvent(purpose: .versionCheck, method: "GET", scheme: "https",
                         host: "example.com", port: nil, path: "/f", taskID: UUID(),
                         hopIndex: 0, redirectCount: 0, status: 200,
                         fetchType: .networkLoad, responseBodyBytes: 10,
                         fetchStart: Date(), responseEnd: Date()))))
        await store.flush()

        // The network panel asks about requests. Counting installs too made it
        // over-report by the whole install history and dragged `oldest` back to
        // before the store existed — which silently disabled the retention caveat,
        // because that fires only when the events start *later* than the totals.
        let requests = await store.coverage(kind: "request")
        #expect(requests.count == 1)
        #expect((requests.oldest ?? .distantPast) > old)
        #expect(await store.coverage(kind: "install").count == 1)
        #expect(await store.coverage().count == 2)
    }

    // MARK: - Kept forever

    @Test("Retention prunes request events and never touches installs")
    func installsOutliveRetention() async throws {
        let (store, url) = Self.store(retentionDays: 7, pruneInterval: .zero)
        defer { Self.remove(url) }

        let old = Date().addingTimeInterval(-400 * 86_400)
        await store.append(DuoEvent(date: old, client: .app, payload: .install(
            InstallEvent(appID: "/Applications/Old.app", appName: "Old", bundleID: nil,
                         fromVersion: "1", toVersion: "2", sourceName: "GitHub",
                         bytes: 4_242))))
        await store.append(DuoEvent(date: old, client: .app, payload: .request(
            RequestEvent(purpose: .versionCheck, method: "GET", scheme: "https",
                         host: "example.com", port: nil, path: "/f", taskID: UUID(),
                         hopIndex: 0, redirectCount: 0, status: 200,
                         fetchType: .networkLoad, responseBodyBytes: 10,
                         fetchStart: old, responseEnd: old))))
        await store.flush()

        // The diagnostic half aged out; the ledger did not. An install a year old
        // is exactly the row someone opens this window to see.
        let events = await store.events(EventQuery(limit: 100))
        #expect(events.count == 1)
        #expect(events.first?.install?.appID == "/Applications/Old.app")
        #expect(await store.appTrafficStats().first?.totalBytes == 4_242)
    }

    @Test("The size budget gives up request events, not the ledger")
    func sizeRetentionSpareInstalls() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        defer { Self.remove(url) }
        let tiny = EventStore(fileURL: url, retentionDays: 3650, retentionBytes: 64 * 1024,
                              flushEventCount: 500, flushDelay: .milliseconds(10),
                              pruneInterval: .zero)

        for index in 0..<40 {
            await tiny.append(DuoEvent(payload: .install(
                InstallEvent(appID: "/Applications/A\(index).app", appName: "A\(index)",
                             bundleID: nil, fromVersion: "1", toVersion: "2",
                             sourceName: "GitHub", bytes: 1_000))))
        }
        for index in 0..<3000 {
            await tiny.append(DuoEvent(payload: .request(
                RequestEvent(purpose: .versionCheck, method: "GET", scheme: "https",
                             host: "h\(index % 40).example.com", port: nil, path: "/\(index)",
                             taskID: UUID(), hopIndex: 0, redirectCount: 0, status: 200,
                             fetchType: .networkLoad, responseBodyBytes: 10,
                             fetchStart: Date(), responseEnd: Date()))))
        }
        await tiny.flush()

        let stats = await tiny.appTrafficStats()
        #expect(stats.count == 40, "the size pass took install events with it")
        #expect(stats.reduce(Int64(0)) { $0 + $1.totalBytes } == 40_000)
        // And it really did have to give something up, so this is not passing
        // merely because the budget was never binding.
        #expect(await tiny.coverage(kind: "request").count < 3000,
                "nothing was pruned; the case proves nothing about the exemption")
    }

    @Test("Clearing the network log leaves the download ledger alone")
    func resetSparesTheInstallLedger() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(DuoEvent(payload: .install(
            InstallEvent(appID: "/Applications/Keep.app", appName: "Keep", bundleID: nil,
                         fromVersion: "1", toVersion: "2", sourceName: "GitHub",
                         bytes: 999))))
        await store.append(DuoEvent(payload: .request(
            RequestEvent(purpose: .versionCheck, method: "GET", scheme: "https",
                         host: "example.com", port: nil, path: "/f", taskID: UUID(),
                         hopIndex: 0, redirectCount: 0, status: 200,
                         fetchType: .networkLoad, responseBodyBytes: 10,
                         fetchStart: Date(), responseEnd: Date()))))
        await store.flush()

        await store.reset()

        // "Clear the network log" is routine. Someone's whole download history is
        // not the sort of thing that should go with it.
        #expect(await store.totals().totals.isEmpty)
        #expect(await store.appTrafficStats().first?.totalBytes == 999)
        let kinds = await store.events(EventQuery(limit: 10)).map(\.kind)
        #expect(kinds == ["install"])

        // And a caller that really means it can still say so.
        await store.reset(includingInstalls: true)
        #expect(await store.appTrafficStats().isEmpty)
    }

    // MARK: - Recording new installs

    @Test("A new install lands in the ledger without double-counting on the network panel")
    func newInstallsAreRecorded() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(DuoEvent(client: .app, payload: .install(
            InstallEvent(appID: "/Applications/Fresh.app", appName: "Fresh",
                         bundleID: "com.example.fresh", fromVersion: "1.0",
                         toVersion: "1.1", fromBuild: "10", toBuild: "11",
                         sourceName: "Vendor", bytes: 12_345,
                         downloadKind: .delta, applied: true))))
        await store.flush()

        let stat = await store.appTrafficStats().first
        #expect(stat?.appName == "Fresh")
        #expect(stat?.totalBytes == 12_345)
        #expect(stat?.events.first?.downloadKind == .delta)

        // And it adds nothing to the network rollups, because those bytes are
        // already there: `Downloader` files request events with purpose `.install`
        // for the very same transfer. Counting the ledger entry as well would
        // report one download twice — at two different byte counts, since the
        // request events measure the wire and this measures the file.
        #expect(await store.totals().totals.isEmpty)
    }
}
