import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// The gate issue #462 asked for: an upgraded machine and a fresh install can
/// end up with different `events` table shapes, and nothing checked. Three
/// leftovers on a real upgraded machine motivated the issue — an orphaned
/// `task_id` column, `events_host_at` unable to serve the window's `host:`
/// filter, and an `events_app_at` index that only ever existed in a comment —
/// but the defect underneath all three is structural, not any one column or
/// index. These tests pin the structural property.
///
/// Not `.serialized`: every test builds its own `UUID`-named temp database and
/// touches nothing shared, so there is no ordering or isolation hazard here to
/// document.
@Suite
struct EventStoreSchemaDriftTests {

    private static func store(fileURL: URL) -> EventStore {
        EventStore(fileURL: fileURL, flushEventCount: 1, flushDelay: .milliseconds(10))
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("events-schema-\(UUID().uuidString).sqlite")
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    // MARK: - Raw inspection

    /// `pragma_table_info` column names in declaration order — the same shape
    /// `createSchema`'s `CREATE TABLE` and any prior `ALTER TABLE ADD COLUMN`
    /// leave behind. A second, independent connection, never the store's own:
    /// the point is to see exactly what is on disk, not what the store's API
    /// says it wrote.
    private static func columnNames(table: String, at url: URL) throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else { throw URLError(.cannotOpenFile) }
        defer { sqlite3_close_v2(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT name FROM pragma_table_info(?) ORDER BY cid;", -1, &statement, nil
        ) == SQLITE_OK, let statement else { throw URLError(.cannotOpenFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) { names.append(String(cString: raw)) }
        }
        return names
    }

    /// Explicitly-created indexes on `table` — `sqlite_autoindex_*` (the
    /// implicit index behind `PRIMARY KEY`) excluded, since `createSchema`
    /// never issues a `CREATE INDEX` for those and this is checking what it
    /// declares.
    private static func indexNames(table: String, at url: URL) throws -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else { throw URLError(.cannotOpenFile) }
        defer { sqlite3_close_v2(db) }
        var statement: OpaquePointer?
        let sql = """
            SELECT name FROM sqlite_master
            WHERE type = 'index' AND tbl_name = ? AND name NOT LIKE 'sqlite_autoindex%';
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw URLError(.cannotOpenFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) { names.insert(String(cString: raw)) }
        }
        return names
    }

    // MARK: - Fixtures

    /// A table shaped like a real machine that upgraded through several schema
    /// versions: `app_id` already added, `task_id` still sitting there from
    /// before it fell out of `createSchema`'s declared column list (#462 item
    /// 1), `from_cache` not yet added. Column order and presence matches
    /// `pragma_table_info` measured against the live store on this machine
    /// 2026-09-12 (`id, at, client, kind, purpose, host, status, bytes_in,
    /// bytes_out, payload, app_id, task_id, from_cache`), minus `from_cache` so
    /// the migration path below has at least one column left to add — the same
    /// role `addColumnIfMissing` plays on every real launch.
    private static func makeUpgradedMachineSchema(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db else { throw URLError(.cannotCreateFile) }
        defer { sqlite3_close_v2(db) }
        let sql = """
            PRAGMA auto_vacuum=INCREMENTAL;
            PRAGMA journal_mode=WAL;
            CREATE TABLE events (
              id        TEXT PRIMARY KEY,
              at        INTEGER NOT NULL,
              client    TEXT    NOT NULL,
              kind      TEXT    NOT NULL,
              purpose   TEXT,
              host      TEXT,
              status    INTEGER,
              bytes_in  INTEGER,
              bytes_out INTEGER,
              payload   TEXT    NOT NULL,
              app_id    TEXT,
              task_id   TEXT
            );
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

    // MARK: - Tests

    /// A fresh install's `events` table must be exactly the twelve columns and
    /// three indexes `createSchema` declares — not "whatever `addColumnIfMissing`
    /// happened to add plus whatever the `CREATE TABLE` says", which is how a
    /// stray column like `task_id` could exist in the declaration without
    /// anyone noticing it never runs on a fresh install (or vice versa).
    ///
    /// Mutation-verified 2026-09-12: temporarily removing `bytes_out` from the
    /// `CREATE TABLE` in `createSchema` turns this red, printing both arrays —
    /// the declared list without `bytes_out` next to the expected list with it —
    /// which is what "naming the column" looks like for an array equality
    /// assertion. Reverted immediately after.
    @Test("A fresh install's events table is exactly what createSchema declares")
    func freshInstallSchemaMatchesDeclaration() async throws {
        let url = Self.tempURL()
        defer { Self.remove(url) }
        let store = Self.store(fileURL: url)
        _ = await store.schemaProblems() // forces open() -> createSchema()

        let columns = try Self.columnNames(table: "events", at: url)
        #expect(columns == [
            "id", "at", "client", "kind", "purpose", "host",
            "app_id", "from_cache", "status", "bytes_in", "bytes_out", "payload",
        ])

        let indexes = try Self.indexNames(table: "events", at: url)
        #expect(indexes == ["events_at", "events_kind_at", "events_host_at"])
    }

    /// #462 item 1, settled rather than argued from the SQL shape: run the
    /// store's real migration path (`open()` → `addColumnIfMissing` ×2 →
    /// `CREATE TABLE IF NOT EXISTS`) over a database shaped like a real
    /// upgraded machine, and compare the result to what a fresh install gets
    /// from the identical code path — columns *and* indexes.
    ///
    /// The index half is the one that matters for the historical failure this
    /// area is actually about (see the rewritten `events_app_at` comment in
    /// `createSchema`): a `CREATE INDEX` that fails on an upgraded database
    /// takes every statement after it in the same `sqlite3_exec` batch down
    /// with it. This fixture deliberately leaves `from_cache` un-added so the
    /// migration path has a real `addColumnIfMissing` call to run — if that
    /// call, or any statement before the index-creation batch, is ever moved
    /// to *after* the batch (or made to fail on an upgraded shape), the batch
    /// is abandoned and `events_kind_at`/`events_host_at` are silently never
    /// created on upgraded machines. This assertion is outside the
    /// `withKnownIssue` below because it passes today — both sides end up with
    /// the same three indexes — and its job is to keep it that way, not to
    /// record a known divergence.
    ///
    /// Mutation-verified 2026-09-12: moving the `app_id` `addColumnIfMissing`
    /// call to after the `exec` batch turns this half red, naming the missing
    /// indexes. Reverted immediately after.
    ///
    /// **The column half is expected to fail today.** `task_id` survives the
    /// migration — nothing in `createSchema` drops a column it does not
    /// declare — so the upgraded shape carries an extra column the fresh shape
    /// never has. That failure *is* the evidence for issue #462 item 1: an
    /// upgraded machine and a fresh install do not have the same `events`
    /// table shape. Turning this green means deciding what to do about
    /// `task_id` (see the issue and the PR description for the two options and
    /// their costs) — a decision this PR deliberately does not make.
    @Test("An upgraded machine's schema matches a fresh install's after migration")
    func upgradedMachineSchemaMatchesFreshInstallAfterMigration() async throws {
        let (oldURL, freshURL) = (Self.tempURL(), Self.tempURL())
        defer { Self.remove(oldURL); Self.remove(freshURL) }
        try Self.makeUpgradedMachineSchema(at: oldURL)

        let upgraded = Self.store(fileURL: oldURL)
        _ = await upgraded.schemaProblems()
        let fresh = Self.store(fileURL: freshURL)
        _ = await fresh.schemaProblems()

        let upgradedIndexes = try Self.indexNames(table: "events", at: oldURL)
        let freshIndexes = try Self.indexNames(table: "events", at: freshURL)
        #expect(upgradedIndexes == freshIndexes)
        #expect(upgradedIndexes == ["events_at", "events_kind_at", "events_host_at"])

        let upgradedColumns = try Self.columnNames(table: "events", at: oldURL)
        let freshColumns = try Self.columnNames(table: "events", at: freshURL)

        withKnownIssue("""
            #462 item 1: task_id is an orphan column — createSchema declares 12 \
            columns and does not include it, but a machine that already had it \
            (from an old schema version) keeps it forever because nothing drops \
            an undeclared column. A fresh install never gets it. The two shapes \
            diverge. Delete this wrapper once #462 is resolved one way or the \
            other for task_id.
            """) {
            #expect(upgradedColumns == freshColumns)
        }
    }
}
