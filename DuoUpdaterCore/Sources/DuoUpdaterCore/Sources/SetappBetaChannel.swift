import Foundation
import SQLite3

/// Which Setapp copies sit on its beta channel, as far as the client's own
/// catalogue can say.
///
/// The public catalogue this app reads carries **stable releases only** — measured
/// 2026-11-03: with Setapp's beta switch off a fresh fetch has 0 version rows with
/// `ZISBETA = 1`, with it on 15 (Bartender 7.0.3/700010 and 7.1.0/700013,
/// Dropshare 6.16, Soulver 4.0, …). The one place that records "this exact build
/// is a beta" is the client's fetched catalogue in CoreData.
///
/// So this is a best-effort label, not a channel signal: the rows exist only while
/// the client last fetched with beta on (a stable-only refresh drops them), and a
/// copy installed from beta survives that refresh. When it cannot answer, callers
/// say something they can prove — "ahead of Setapp's stable releases" — and never
/// claim "beta".
public enum SetappBetaChannel {

    /// Setapp's client catalogue.
    public static var databasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Setapp/Default/Databases/Apps.sqlite")
    }

    /// Whether `shortVersion`/`build` of `bundleID` is one of the beta rows the
    /// client last fetched.
    ///
    /// The database is copied first — database, WAL and shared memory together —
    /// because the client may be writing it and a read-only open of a live WAL
    /// database still needs to write its `-shm` (the same reason
    /// `TablePlusSubscription` copies its cache).
    public static func installedCopyIsBeta(
        bundleID: String, shortVersion: String?, build: String?, database: URL? = nil
    ) -> Bool {
        guard let shortVersion, shortVersion.isEmpty == false else { return false }
        let source = database ?? databasePath
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return false }

        let scratch = fm.temporaryDirectory
            .appendingPathComponent("setapp-catalogue-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: source.path + suffix)
                guard fm.fileExists(atPath: file.path) else { continue }
                try fm.copyItem(at: file, to: scratch.appendingPathComponent("Apps.sqlite" + suffix))
            }
        } catch { return false }

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(
            scratch.appendingPathComponent("Apps.sqlite").path, &db,
            SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return false }

        // Build is optional in the caller: an exact build match is what makes the
        // answer "this build is a beta"; a version-only match would claim a beta
        // for a copy whose build the client never recorded.
        let sql = """
            SELECT COUNT(*) FROM ZAPPVERSION v
            JOIN ZAPP a ON a.Z_PK = v.ZAPP
            WHERE a.ZBUNDLEIDENTIFIER = ?1 AND v.ZISBETA = 1
              AND v.ZMARKETINGVERSION = ?2 AND v.ZBUILDNUMBER = ?3
            """
        guard let build, build.isEmpty == false else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 1, bundleID, -1, Self.transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, shortVersion, -1, Self.transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 3, build, -1, Self.transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else { return false }
        return sqlite3_column_int(statement, 0) > 0
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
