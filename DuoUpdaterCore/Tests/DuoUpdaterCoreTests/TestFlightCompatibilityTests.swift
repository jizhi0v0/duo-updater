import Foundation
import SQLite3
import Testing
@testable import DuoUpdaterCore

@Suite(.serialized)
struct TestFlightCompatibilityTests {
    private static let bundle = "zz.fixture.beta"
    private static let account = "11111111-1111-4111-8111-111111111111"
    private static let requestID = "22222222-2222-4222-8222-222222222222"
    private static let target = TestFlightCompatibility.Build(
        appID: 42, buildID: 5040, bundleID: bundle, shortVersion: "1.0", version: "504", platform: "ios")

    // The real Ampcode 504 response shape, stripped to the fields the decision
    // needs. Picsew returned the same generic reason/text with compatible=true.
    private static func payload(compatible: Any = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["error": NSNull(), "data": [
            "bundleId": bundle, "builds": [[
                "id": 5040, "bundleId": bundle, "platform": "ios",
                "cfBundleShortVersion": "1.0", "cfBundleVersion": "504",
                "compatible": compatible, "compatibilityStatement": "iPAD ONLY",
                "incompatibilityReason": "INCOMPATIBLE_DEVICE_FAMILY"
            ]]
        ]])
    }

    @Test func usesTheDeviceFlagRatherThanGenericCompatibilityText() throws {
        #expect(TestFlightCompatibility.parse(try Self.payload(), for: Self.target) == false)
        #expect(TestFlightCompatibility.parse(try Self.payload(compatible: true), for: Self.target) == true)
        #expect(TestFlightCompatibility.parse(try Self.payload(compatible: 0), for: Self.target) == nil)
        #expect(TestFlightCompatibility.parse(try Self.payload(compatible: "false"), for: Self.target) == nil)
    }

    @Test(arguments: ["id", "bundleId", "platform", "cfBundleShortVersion", "cfBundleVersion", "compatible"])
    func aDifferentOrMissingBuildFieldCannotRefuseAnUpdate(field: String) throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.payload()) as? [String: Any])
        var app = try #require(root["data"] as? [String: Any])
        var builds = try #require(app["builds"] as? [[String: Any]])
        builds[0].removeValue(forKey: field)
        app["builds"] = builds
        root["data"] = app
        #expect(TestFlightCompatibility.parse(try JSONSerialization.data(withJSONObject: root), for: Self.target) == nil)
    }

    @Test func serverErrorsAndOtherAppsAreUnknown() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.payload()) as? [String: Any])
        root["error"] = ["code": "expired-session"]
        #expect(TestFlightCompatibility.parse(try JSONSerialization.data(withJSONObject: root), for: Self.target) == nil)
        root["error"] = NSNull()
        var app = try #require(root["data"] as? [String: Any])
        app["bundleId"] = "zz.another.beta"
        root["data"] = app
        #expect(TestFlightCompatibility.parse(try JSONSerialization.data(withJSONObject: root), for: Self.target) == nil)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-tf-compat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "fixture SQL failed")
    }

    private func inventory(at root: URL) throws -> TestFlightInventory {
        let url = root.appendingPathComponent("TestFlight.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(db, """
            CREATE TABLE ZTFAPPBUNDLEMODEL (ZBUNDLEID TEXT,ZSHORTVERSION TEXT,ZBUNDLEVERSION TEXT,
                ZPLATFORMRAW INTEGER,ZINSTALLSTATUSRAW INTEGER,ZBUILDID INTEGER,ZAPP INTEGER);
            CREATE TABLE ZTFAPPMODEL (Z_PK INTEGER,ZAPPID INTEGER,ZBUNDLEID TEXT,ZISTESTER INTEGER);
            INSERT INTO ZTFAPPMODEL VALUES (1,42,'zz.fixture.beta',1);
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES ('zz.fixture.beta','1.0','354',1,1,NULL,1);
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES ('zz.fixture.beta','1.0','504',1,0,5040,1);
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES ('zz.fixture.beta','1.0','504',3,0,9000,1);
            """)
        return TestFlightInventory(databaseURL: url)
    }

    @Test func buildIDsStayBoundToTheirPlatformAndVersion() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inventory = try inventory(at: root)
        #expect(inventory.latestIOS(forBundleID: Self.bundle)?.latestBuildID == 5040)
        #expect(inventory.latest(forBundleID: Self.bundle)?.latestBuildID == 9000)
        #expect(inventory.frontier(forBundleID: Self.bundle)?.maxBuildID == 9000)
    }

    @Test func checkerWithholdsTheIncompatibleBuildButDoesNotCallItCurrent() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inventory = try inventory(at: root)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        let client = TestFlightCompatibility(session: URLSession(configuration: config), credentials: {
            .init(accountID: Self.account, headers: [
                "X-Session-Id": "fixture-session", "X-Session-Digest": "fixture-digest",
                "X-Request-Id": Self.requestID
            ])
        })
        let app = InstalledApp(name: "Beta", bundleID: Self.bundle, shortVersion: "1.0", buildVersion: "354",
                               path: root.appendingPathComponent("Beta.app"), isMASApp: false,
                               isiOSAppOnMac: true, isTestFlightApp: true, sparkleFeedURL: nil)
        let result = await UpdateChecker(sources: [], testflight: inventory,
                                         testFlightCompatibility: client, appStoreSignedIn: true).check(app)
        #expect(result.status == .testFlightIncompatible)
        #expect(!result.hasUpdate)
        #expect(result.remote == nil)
        #expect(await client.compatible(with: Self.target) == false)

        let unauthenticated = TestFlightCompatibility(session: URLSession(configuration: config), credentials: { nil })
        let unknown = await UpdateChecker(sources: [], testflight: inventory,
                                          testFlightCompatibility: unauthenticated, appStoreSignedIn: true).check(app)
        #expect(unknown.status == .testFlightManaged)
        #expect(!unknown.hasUpdate)

        let native = InstalledApp(name: "Beta", bundleID: Self.bundle, shortVersion: "1.0", buildVersion: "354",
                                  path: root.appendingPathComponent("Native.app"), isMASApp: false,
                                  isTestFlightApp: true, sparkleFeedURL: nil)
        let nativeResult = await UpdateChecker(sources: [], testflight: inventory,
                                               testFlightCompatibility: unauthenticated, appStoreSignedIn: true).check(native)
        #expect(nativeResult.status == .updateAvailable(latest: "1.0"))
    }

    @Test func cachedCredentialsMustBelongToTheLastAuthenticatedSession() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Cache.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(cache.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(db, """
            CREATE TABLE cfurl_cache_response (entry_ID INTEGER,request_key TEXT);
            CREATE TABLE cfurl_cache_receiver_data (entry_ID INTEGER,isDataOnFS INTEGER,receiver_data BLOB);
            CREATE TABLE cfurl_cache_blob_data (entry_ID INTEGER,request_object BLOB);
            INSERT INTO cfurl_cache_response VALUES (1,'https://testflight.apple.com/v1/session/authenticate');
            INSERT INTO cfurl_cache_response VALUES (2,'https://testflight.apple.com/v2/accounts/\(Self.account)/apps/42/builds/5040');
            INSERT INTO cfurl_cache_response VALUES (3,'https://testflight.apple.com/v2/accounts/\(Self.account)/apps/42/builds/5000');
            """)
        let auth = try JSONSerialization.data(withJSONObject: ["data": ["accountId": Self.account, "sessionId": "current"]])
        try insertBlob(db, sql: "INSERT INTO cfurl_cache_receiver_data VALUES (1,0,?1)", data: auth)
        func request(session: String, requestID: String? = Self.requestID) throws -> Data {
            var headers = ["X-Session-Id": session, "X-Session-Digest": "fixture-digest", "Cookie": "must-not-copy"]
            headers["X-Request-Id"] = requestID
            return try PropertyListSerialization.data(fromPropertyList: ["Version": 1, "Array": [headers]], format: .binary, options: 0)
        }
        try insertBlob(db, sql: "INSERT INTO cfurl_cache_blob_data VALUES (2,?1)", data: request(session: "current"))
        try insertBlob(db, sql: "INSERT INTO cfurl_cache_blob_data VALUES (3,?1)", data: request(session: "previous"))
        let credentials = try #require(TestFlightCompatibility.readCredentials(cache: cache))
        #expect(credentials.headers["X-Session-Id"] == "current")
        #expect(credentials.headers["X-Request-Id"] == Self.requestID)
        #expect(credentials.headers["Cookie"] == nil)
        try exec(db, "UPDATE cfurl_cache_response SET request_key='https://testflight.apple.com/v2/accounts/33333333-3333-4333-8333-333333333333/apps/42/builds/5040' WHERE entry_ID=2")
        #expect(TestFlightCompatibility.readCredentials(cache: cache) == nil,
                "a matching session header from a different account must not be reused")
        try exec(db, "UPDATE cfurl_cache_response SET request_key='https://testflight.apple.com/v2/accounts/\(Self.account)/apps/42/builds/5040' WHERE entry_ID=2")
        try exec(db, "DELETE FROM cfurl_cache_blob_data WHERE entry_ID=2")
        #expect(TestFlightCompatibility.readCredentials(cache: cache) == nil)
        try insertBlob(db, sql: "INSERT INTO cfurl_cache_blob_data VALUES (2,?1)", data: request(session: "current", requestID: nil))
        #expect(TestFlightCompatibility.readCredentials(cache: cache) == nil)
    }

    @Test func anExpiredSessionIsUnknownEvenWithAnIncompatibleBody() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Server.self]
        let reader = TestFlightCompatibility(session: URLSession(configuration: config), credentials: {
            .init(accountID: Self.account, headers: ["X-Session-Id": "expired", "X-Request-Id": Self.requestID])
        })
        #expect(await reader.compatible(with: Self.target) == nil)
    }

    private func insertBlob(_ db: OpaquePointer?, sql: String, data: Data) throws {
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }

    private final class Server: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            #expect(request.url?.path == "/v2/accounts/\(TestFlightCompatibilityTests.account)/apps/42/builds/5040")
            #expect(request.value(forHTTPHeaderField: "X-Request-Id") == TestFlightCompatibilityTests.requestID)
            #expect(request.cachePolicy == URLRequest.versionFeedCachePolicy)
            let code = request.value(forHTTPHeaderField: "X-Session-Id") == "expired" ? 401 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! TestFlightCompatibilityTests.payload())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
