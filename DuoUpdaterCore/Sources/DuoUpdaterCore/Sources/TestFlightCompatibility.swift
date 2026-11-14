import Foundation
import SQLite3

/// Reads compatibility for an exact beta build, using TestFlight's existing
/// session. No sign-in, session renewal, UI automation, or credential storage.
/// A missing/expired session or a changed response is an unknown answer.
public actor TestFlightCompatibility {
    struct Build: Sendable, Hashable {
        let appID: Int64
        let buildID: Int64
        let bundleID: String
        let shortVersion: String
        let version: String
        let platform: String
    }

    struct Credentials: Sendable {
        let accountID: String
        let headers: [String: String]
    }

    private let session: URLSession
    private let loadCredentials: @Sendable () async -> Credentials?
    private var credentials: Task<Credentials?, Never>?
    private var requests: [Build: Task<Bool?, Never>] = [:]

    public init() {
        self.session = Self.makeSession()
        self.loadCredentials = {
            await offCooperativePool { Self.readCredentials(cache: Self.cacheURL) }
        }
    }

    init(session: URLSession, credentials: @escaping @Sendable () async -> Credentials?) {
        self.session = session
        self.loadCredentials = credentials
    }

    deinit { session.invalidateAndCancel() }

    func compatible(with build: Build) async -> Bool? {
        guard !Task.isCancelled, build.appID > 0, build.buildID > 0 else { return nil }
        if let request = requests[build] { return await request.value }
        if credentials == nil { credentials = Task { await loadCredentials() } }
        let credentials = await credentials?.value
        guard !Task.isCancelled, let credentials,
              UUID(uuidString: credentials.accountID) != nil,
              let url = URL(string: "https://testflight.apple.com/v2/accounts/\(credentials.accountID)/apps/\(build.appID)/builds/\(build.buildID)")
        else {
            Log.check.info("TestFlight compatibility: no reusable cached session")
            return nil
        }
        // The credentials await above is reentrant; another copy of the same app
        // may have registered this build's request while it was loading.
        if let request = requests[build] { return await request.value }
        // Keep the three session headers together, including X-Request-Id:
        // replaying the digest without its request id returned 401 on 2026-11-14;
        // the complete set returned 200 for both build 499 and build 504.
        var request = URLRequest(url: url, cachePolicy: URLRequest.versionFeedCachePolicy, timeoutInterval: 10)
        request.allHTTPHeaderFields = credentials.headers
        let session = self.session
        let task = Task<Bool?, Never> {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    Log.check.info("TestFlight compatibility: HTTP \(http.statusCode, privacy: .public)")
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.scheme == "https", http.url?.host == "testflight.apple.com",
                      data.count <= 2 * 1024 * 1024 else { return nil }
                let answer = Self.parse(data, for: build)
                if answer == nil { Log.check.info("TestFlight compatibility: response does not match the requested build") }
                return answer
            } catch {
                // Do not log errors/requests: they can contain session headers.
                Log.check.info("TestFlight compatibility: request did not complete")
                return nil
            }
        }
        requests[build] = task
        return await task.value
    }

    /// Device-specific flags, not the generic compatibility text or the presence
    /// of "Mac" in device families. Measured 2026-11-14: Picsew said "iPAD ONLY"
    /// and INCOMPATIBLE_DEVICE_FAMILY while compatible was true; Ampcode 499 and
    /// 504 had compatible=false. Bind to the exact app, platform AND build.
    static func parse(_ data: Data, for build: Build) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil || root["error"] is NSNull,
              let app = root["data"] as? [String: Any],
              app["bundleId"] as? String == build.bundleID,
              let builds = app["builds"] as? [[String: Any]],
              let row = builds.first(where: {
                  ($0["id"] as? NSNumber)?.int64Value == build.buildID
                      && $0["bundleId"] as? String == build.bundleID
                      && $0["platform"] as? String == build.platform
                      && $0["cfBundleShortVersion"] as? String == build.shortVersion
                      && $0["cfBundleVersion"] as? String == build.version
              }),
              let value = row["compatible"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return value.boolValue
    }

    static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.apple.TestFlight/Data/Library/Caches/com.apple.TestFlight/Cache.db")
    }

    private static let bounded = BoundedBlockingWork(label: "TestFlight session cache")

    static func readCredentials(cache: URL) -> Credentials? {
        bounded.run(key: cache.path, timeout: 5) { readCache(cache) } ?? nil
    }

    private static func readCache(_ cache: URL) -> Credentials? {
        guard FileManager.default.fileExists(atPath: cache.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cache.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 200)
        var auth: OpaquePointer?
        defer { sqlite3_finalize(auth) }
        let authSQL = """
            SELECT d.isDataOnFS, d.receiver_data FROM cfurl_cache_response r
            JOIN cfurl_cache_receiver_data d USING (entry_ID)
            WHERE r.request_key = 'https://testflight.apple.com/v1/session/authenticate'
            """
        guard sqlite3_prepare_v2(db, authSQL, -1, &auth, nil) == SQLITE_OK,
              sqlite3_step(auth) == SQLITE_ROW,
              let body = cachedBody(auth, cache: cache),
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              root["error"] == nil || root["error"] is NSNull,
              let payload = root["data"] as? [String: Any],
              let accountID = payload["accountId"] as? String, UUID(uuidString: accountID) != nil,
              let sessionID = payload["sessionId"] as? String, !sessionID.isEmpty
        else { return nil }

        // The latest cached authentication identifies the account/session. Never
        // borrow a surviving request from a different Apple Account or session.
        var rows: OpaquePointer?
        defer { sqlite3_finalize(rows) }
        let sql = """
            SELECT r.request_key, b.request_object FROM cfurl_cache_response r
            JOIN cfurl_cache_blob_data b USING (entry_ID)
            WHERE r.request_key LIKE 'https://testflight.apple.com/%'
            ORDER BY r.entry_ID DESC
            """
        guard sqlite3_prepare_v2(db, sql, -1, &rows, nil) == SQLITE_OK else { return nil }
        while sqlite3_step(rows) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(rows, 0),
                  let url = URL(string: String(cString: raw)),
                  url.scheme == "https", url.host == "testflight.apple.com",
                  url.port == nil || url.port == 443,
                  url.pathComponents.count >= 4,
                  url.pathComponents[2] == "accounts", url.pathComponents[3] == accountID,
                  let data = blob(rows, column: 1), data.count <= 128 * 1024,
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let headers = headers(in: object), headers["X-Session-Id"] == sessionID,
                  headers["X-Session-Digest"]?.isEmpty == false,
                  headers["X-Request-Id"].flatMap(UUID.init(uuidString:)) != nil
            else { continue }
            return Credentials(accountID: accountID, headers: headers)
        }
        return nil
    }

    private static func headers(in object: Any) -> [String: String]? {
        if let dict = object as? [String: Any] {
            if dict["X-Session-Id"] is String {
                let allowed: Set<String> = [
                    "Accept", "Accept-Language", "User-Agent", "Content-Type",
                    "X-Session-Id", "X-Session-Digest", "X-Request-Id", "X-Apple-AMD-M",
                    "X-Apple-Device-Model", "X-Apple-Product-Type", "X-Apple-Rosetta-Available",
                    "X-Apple-Store-Front", "X-Apple-TA-Device", "X-Apple-TestFlight-iOS"
                ]
                return dict.reduce(into: [:]) { result, entry in
                    if allowed.contains(entry.key), let value = entry.value as? String,
                       !value.contains("\r"), !value.contains("\n") { result[entry.key] = value }
                }
            }
            for value in dict.values { if let result = headers(in: value) { return result } }
        } else if let array = object as? [Any] {
            for value in array { if let result = headers(in: value) { return result } }
        }
        return nil
    }

    private static func blob(_ statement: OpaquePointer?, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 128 * 1024, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private static func cachedBody(_ statement: OpaquePointer?, cache: URL) -> Data? {
        guard let data = blob(statement, column: 1) else { return nil }
        if sqlite3_column_int(statement, 0) == 0 { return data }
        let name = String(decoding: data, as: UTF8.self)
        guard UUID(uuidString: name) != nil else { return nil }
        let url = cache.deletingLastPathComponent().appendingPathComponent("fsCachedData").appendingPathComponent(name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128 * 1024 else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
