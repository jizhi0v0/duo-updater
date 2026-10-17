import Foundation
import SQLite3

/// Which TablePlus releases the user's licence covers. A licence buys a year of
/// updates; a build released after that does not activate on it.
///
/// Read from TablePlus 27.1.0 (821), 2026-10-17:
///  - the binary's own words for the rule: "This version of TablePlus was
///    released after the license's updates ended." and "TablePlus %@ came out
///    after them, so the key can't activate it. Renew the license for this
///    build, or download the last build it covers." So the release date decides,
///    against `TBLicenseModel.updatesAvailableUntil`. (Its
///    `bestValidUpdateInAppcast:forUpdater:` caps by a BUILD number instead, but
///    that is a team owner's approval — "Updates are approved by the license
///    owner up to build %@." — not the licence's end.)
///  - the end date reaches this Mac only in TablePlus's own URL cache
///    (`~/Library/Caches/com.tinyapp.TablePlus/Cache.db`): its periodic
///    `GET tableplus.com/v1/licenses/devices` answers
///    `{"Data": {"UpdatesAvailableUntilString": "6 June 2027", …}}`, and still
///    does after the licence lapsed (this Mac's cache held "4 May 2026" from March
///    to May 2026). The licence file itself (`.licensemac`) is encrypted, and the
///    request is signed, so neither is ours to read or replay.
///  - the feed's `<pubDate>` is RFC 822 (`Fri, 16 Oct 2026 04:58:50 +0000`).
///
/// A day, not a moment, so a release ON that day is withheld: whether TablePlus
/// counts the last day as covered was not established.
///
/// An HTTP cache, not an interface: missing, evicted, or reshaped → `.unreadable`,
/// and nothing newer is offered; the user can still update from TablePlus.
public enum TablePlusSubscription {
    static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.tinyapp.TablePlus/Cache.db", isDirectory: false)
    }

    static let devicesRequestPrefix = "https://tableplus.com/v1/licenses/devices"

    public static func currentWindow() -> SubscriptionWindow {
        window(fromResponse: readLatestDevicesResponse(cache: cacheURL))
    }

    /// Parse the devices response body. Pure and tested. Never logs: the body
    /// also carries the device id.
    static func window(fromResponse data: Data?) -> SubscriptionWindow {
        guard let data,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = body["Data"] as? [String: Any],
              let until = payload["UpdatesAvailableUntilString"] as? String,
              let day = untilFormatter.date(from: until.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return .unreadable }
        return .before(day, dayOnly: true)
    }

    /// "6 June 2027", read as that day's midnight UTC.
    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMMM yyyy"
        f.isLenient = false
        return f
    }()

    /// The newest cached devices response body. The cache is copied first — the
    /// database, its WAL and shared memory together — because TablePlus may be
    /// writing it, and a read-only open of a live WAL database still needs to
    /// write its `-shm`.
    static func readLatestDevicesResponse(cache: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cache.path) else { return nil }
        let scratch = fm.temporaryDirectory.appendingPathComponent("tableplus-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: cache.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                try fm.copyItem(at: source, to: scratch.appendingPathComponent("Cache.db" + suffix))
            }
        } catch { return nil }

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(scratch.appendingPathComponent("Cache.db").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
            SELECT d.isDataOnFS, d.receiver_data FROM cfurl_cache_response r
            JOIN cfurl_cache_receiver_data d ON d.entry_ID = r.entry_ID
            WHERE r.request_key LIKE ?1 ORDER BY r.time_stamp DESC LIMIT 1
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 1, devicesRequestPrefix + "%", -1,
                                unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 1)
        else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        // A large body is kept beside the database, named by this column.
        guard sqlite3_column_int(statement, 0) != 0 else { return data }
        let name = String(decoding: data, as: UTF8.self)
        return try? Data(contentsOf: cache.deletingLastPathComponent()
            .appendingPathComponent("fsCachedData", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false))
    }
}
