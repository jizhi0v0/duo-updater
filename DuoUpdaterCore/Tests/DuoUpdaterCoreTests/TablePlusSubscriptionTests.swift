import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// TablePlus will not activate a build released after the licence's updates
/// ended (`TablePlusSubscription`), and the end date reaches this Mac only in
/// TablePlus's own URL cache. Feed dates below are TablePlus's beta and stable
/// feeds on 2026-10-17.
struct TablePlusSubscriptionTests {

    static func body(_ until: Any?) -> Data {
        var payload: [String: Any] = ["DeviceID": "x", "policy": NSNull()]
        if let until { payload["UpdatesAvailableUntilString"] = until }
        return try! JSONSerialization.data(withJSONObject: ["Code": 200, "Message": "ok", "Data": payload])
    }

    static func utcDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - The response

    @Test func readsTheDayAsMidnightUTC() {
        #expect(TablePlusSubscription.window(fromResponse: Self.body("6 June 2027"))
            == .before(Self.utcDay(2027, 6, 6), dayOnly: true))
        // An expired licence still answers its end date (this Mac, March–May 2026).
        #expect(TablePlusSubscription.window(fromResponse: Self.body("4 May 2026"))
            == .before(Self.utcDay(2026, 5, 4), dayOnly: true))
    }

    @Test func anythingElseIsUnreadable() {
        #expect(TablePlusSubscription.window(fromResponse: nil) == .unreadable)
        #expect(TablePlusSubscription.window(fromResponse: Data("<html>".utf8)) == .unreadable)
        #expect(TablePlusSubscription.window(fromResponse: Self.body(nil)) == .unreadable)
        #expect(TablePlusSubscription.window(fromResponse: Self.body("2027-06-06")) == .unreadable)
        #expect(TablePlusSubscription.window(fromResponse: Self.body(1_812_240_000)) == .unreadable)
    }

    // MARK: - The cache

    /// A `Cache.db` shaped like CFNetwork's: the newest devices response wins,
    /// other requests are ignored, and a body kept on disk is followed.
    @Test func readsTheNewestDevicesResponse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("fsCachedData"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("Cache.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(cache.path, &db) == SQLITE_OK)
        func exec(_ sql: String) { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK) }
        func insertBody(_ id: Int, onFS: Bool, _ data: Data) {
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO cfurl_cache_receiver_data VALUES (?1, ?2, ?3)", -1, &st, nil)
            sqlite3_bind_int(st, 1, Int32(id)); sqlite3_bind_int(st, 2, onFS ? 1 : 0)
            _ = data.withUnsafeBytes {
                sqlite3_bind_blob(st, 3, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            #expect(sqlite3_step(st) == SQLITE_DONE); sqlite3_finalize(st)
        }
        exec("CREATE TABLE cfurl_cache_response (entry_ID INTEGER PRIMARY KEY, time_stamp TEXT, request_key TEXT)")
        exec("CREATE TABLE cfurl_cache_receiver_data (entry_ID INTEGER PRIMARY KEY, isDataOnFS INTEGER, receiver_data BLOB)")
        exec("INSERT INTO cfurl_cache_response VALUES (1, '2026-05-07 02:16:15', 'https://tableplus.com/v1/licenses/devices?deviceID=a')")
        exec("INSERT INTO cfurl_cache_response VALUES (2, '2026-10-14 09:16:58', 'https://tableplus.com/v1/licenses/devices?deviceID=a')")
        exec("INSERT INTO cfurl_cache_response VALUES (3, '2026-10-16 00:00:00', 'https://tableplus.com/v1/apps/osx/tableplus')")
        insertBody(1, onFS: false, Self.body("4 May 2026"))
        insertBody(2, onFS: true, Data("BODY-2".utf8))
        insertBody(3, onFS: false, Self.body("1 January 2000"))
        sqlite3_close(db)
        try Self.body("6 June 2027").write(to: dir.appendingPathComponent("fsCachedData/BODY-2"))

        let data = try #require(TablePlusSubscription.readLatestDevicesResponse(cache: cache))
        #expect(TablePlusSubscription.window(fromResponse: data) == .before(Self.utcDay(2027, 6, 6), dayOnly: true))
        #expect(TablePlusSubscription.readLatestDevicesResponse(cache: dir.appendingPathComponent("missing.db")) == nil)
    }

    // MARK: - The offer

    /// 27.1.0 (827) came out 16 Oct 2026, 27.0.2 (818) on 8 Oct.
    static let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
        <item>
          <pubDate>Fri, 16 Oct 2026 04:58:50 +0000</pubDate>
          <enclosure url="https://example.com/827.dmg" sparkle:version="827" sparkle:shortVersionString="27.1.0" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
        <item>
          <pubDate>Thu, 08 Oct 2026 16:13:01 +0000</pubDate>
          <enclosure url="https://example.com/818.dmg" sparkle:version="818" sparkle:shortVersionString="27.0.2" sparkle:edSignature="sig" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """

    static func latest(installedBuild: String, short: String, window: SubscriptionWindow) async throws -> RemoteVersion? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tp-feed-\(UUID().uuidString).xml")
        try Data(feed.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let app = InstalledApp(
            name: "TablePlus", bundleID: "com.tinyapp.TablePlus", shortVersion: short, buildVersion: installedBuild,
            path: URL(fileURLWithPath: "/Applications/TablePlus.app"),
            isMASApp: false, sparkleFeedURL: url, sparkleEdPublicKey: "key")
        let source = SparkleAppcastSource(
            session: URLSession(configuration: .ephemeral), loginWalls: [], subscriptionWindow: { _ in window })
        return try await source.latestVersion(for: app)
    }

    @Test func offersTheNewestReleaseBeforeTheEnd() async throws {
        let remote = try #require(try await Self.latest(
            installedBuild: "810", short: "27.0.0", window: .before(Self.utcDay(2026, 10, 10), dayOnly: true)))
        #expect(remote.version == "818")
        #expect(remote.subscriptionHold == SubscriptionHold(
            version: "27.1.0", coveredBefore: Self.utcDay(2026, 10, 10), dayOnly: true))
    }

    /// The end day itself is not covered: whether TablePlus counts it was not
    /// established, and withholding is the side that cannot break the app.
    @Test func aReleaseOnTheEndDayIsWithheld() async throws {
        let remote = try #require(try await Self.latest(
            installedBuild: "818", short: "27.0.2", window: .before(Self.utcDay(2026, 10, 16), dayOnly: true)))
        #expect(remote.version == "818")
        #expect(remote.subscriptionHold?.version == "27.1.0")
        let covered = try #require(try await Self.latest(
            installedBuild: "818", short: "27.0.2", window: .before(Self.utcDay(2026, 10, 17), dayOnly: true)))
        #expect(covered.version == "827")
        #expect(covered.subscriptionHold == nil)
    }

    @Test func tablePlusIsGatedAndItsSetappEditionIsNot() {
        #expect(SubscriptionWindow.current(forBundleID: "com.tinyapp.TablePlus") != nil)
        #expect(SubscriptionWindow.current(forBundleID: "com.tinyapp.TablePlus-setapp") == nil)
    }
}
