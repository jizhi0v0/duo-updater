import Foundation
import SQLite3

/// Whether this Mac's Apple Account is signed in to the App Store — the sign-in
/// TestFlight uses — read from the system's accounts database.
///
/// Why this exists: signing out of TestFlight does not rewrite TestFlight's own
/// store until TestFlight next runs, so `TestFlightInventory` cannot see a sign-out
/// until a refresh has already started TestFlight, which then bounces in the Dock
/// asking the user to sign in. This is read before anything is started.
///
/// Measured 2026-09-10 on one Mac, over two sign-out and sign-in cycles in
/// TestFlight: the active `com.apple.account.iTunesStore` account stayed active
/// throughout, but its `activeMediaTypes` property lost
/// `…accountmediatype.appstore` on every sign-out and regained it on every sign-in,
/// while `…itunes` stayed. Nothing else examined flipped cleanly: the account's
/// flags did not change, and the preference files rewritten on sign-in and sign-out
/// carry no field that does.
///
/// **What is read, and nothing more:** the `activeMediaTypes` property of active App
/// Store accounts, which is a list of media-type names. Never a username, an Apple
/// ID, an identifier, or any other property.
///
/// **Fail-open.** This is a private database with no contract. Only a decoded list
/// that lacks the App Store media type answers `false`. A missing file, an open that
/// does not return, a query that no longer prepares, no such property, or a value
/// that does not decode all answer nil, which callers treat as "no signal" — so a
/// macOS that moves this costs the saved bounce and nothing else.
public enum AppStoreSignIn {
    /// The media type an App Store sign-in adds to the account.
    static let appStoreMediaType = "com.apple.AppleMediaServices.accountmediatype.appstore"

    /// The system's accounts database.
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts/Accounts4.sqlite")
    }

    /// Bounded like the TestFlight store's open, for the same reason: a protected
    /// database's open can block rather than fail.
    private static let bounded = BoundedBlockingWork(label: "Accounts DB open")
    static let openTimeout: TimeInterval = 5

    /// true, false, or nil — see the type's documentation. Blocks the calling
    /// thread for as long as the read takes (bounded), so call it off the
    /// cooperative pool.
    public static func isSignedIn(databaseURL: URL? = nil) -> Bool? {
        let url = databaseURL ?? defaultDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return bounded.run(key: url.path, timeout: openTimeout) { read(at: url) } ?? nil
    }

    /// `isSignedIn()` off the cooperative pool, for async callers: the read is a
    /// bounded but blocking open (see `offCooperativePool`).
    public static func current() async -> Bool? {
        await offCooperativePool { isSignedIn() }
    }

    /// Active App Store accounts' `activeMediaTypes`, and no other column.
    static let sql = """
        SELECT p.ZVALUE FROM ZACCOUNTPROPERTY p
        JOIN ZACCOUNT a ON p.ZOWNER = a.Z_PK
        JOIN ZACCOUNTTYPE t ON a.ZACCOUNTTYPE = t.Z_PK
        WHERE t.ZIDENTIFIER = 'com.apple.account.iTunesStore' AND a.ZACTIVE = 1
          AND p.ZKEY = 'activeMediaTypes';
        """

    static func read(at url: URL) -> Bool? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("Accounts DB open failed — App Store sign-in unknown for this read")
            return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            Log.scan.error("Accounts DB query did not prepare — App Store sign-in unknown for this read")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        var values: [Data] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            values.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
        }
        return signedIn(fromActiveMediaTypes: values)
    }

    /// The decision, apart from the database: `true` when any decoded list names the
    /// App Store media type, `false` only when at least one list decoded and none
    /// does, and nil when nothing decoded — including when there was nothing at all.
    static func signedIn(fromActiveMediaTypes values: [Data]) -> Bool? {
        var decodedAny = false
        for value in values {
            guard let names = decode(value) else { continue }
            decodedAny = true
            if names.contains(appStoreMediaType) { return true }
        }
        return decodedAny ? false : nil
    }

    /// The property is an archived array of strings (measured: `__NSArrayM`); a set
    /// is accepted too, since nothing promises which collection it is.
    static func decode(_ value: Data) -> [String]? {
        guard let object = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, NSSet.self, NSString.self], from: value) else { return nil }
        if let array = object as? [String] { return array }
        if let set = object as? Set<String> { return Array(set) }
        return nil
    }
}
