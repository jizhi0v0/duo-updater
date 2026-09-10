import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// The App Store sign-in signal a TestFlight refresh reads before starting anything.
///
/// The fixtures are the measured shape (2026-09-10): an active App Store account
/// whose `activeMediaTypes` gains and loses the App Store media type with the
/// TestFlight sign-in, beside inactive App Store accounts that keep old values.
struct AppStoreSignInTests {

    private static let appStore = "com.apple.AppleMediaServices.accountmediatype.appstore"
    private static let itunes = "com.apple.AppleMediaServices.accountmediatype.itunes"

    private static func archived(_ names: [String]) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: names as NSArray, requiringSecureCoding: true)
    }

    // MARK: - The decision

    /// Only a decoded list can say "signed out". Mutation: set `decodedAny` before
    /// the decode guard — an undecodable value then reads as signed out, and a
    /// future macOS that changes the encoding would stop every refresh.
    @Test func onlyADecodedListCanSaySignedOut() throws {
        #expect(AppStoreSignIn.signedIn(fromActiveMediaTypes: [try Self.archived([Self.appStore, Self.itunes])]) == true)
        #expect(AppStoreSignIn.signedIn(fromActiveMediaTypes: [try Self.archived([Self.itunes])]) == false)
        #expect(AppStoreSignIn.signedIn(fromActiveMediaTypes: []) == nil)
        #expect(AppStoreSignIn.signedIn(fromActiveMediaTypes: [Data("not an archive".utf8)]) == nil)
    }

    // MARK: - The database

    private static let schema = """
        CREATE TABLE ZACCOUNTTYPE (Z_PK INTEGER PRIMARY KEY, ZIDENTIFIER VARCHAR);
        CREATE TABLE ZACCOUNT (Z_PK INTEGER PRIMARY KEY, ZACCOUNTTYPE INTEGER, ZACTIVE INTEGER);
        CREATE TABLE ZACCOUNTPROPERTY (Z_PK INTEGER PRIMARY KEY, ZOWNER INTEGER, ZKEY VARCHAR, ZVALUE BLOB);
        INSERT INTO ZACCOUNTTYPE VALUES (1, 'com.apple.account.iTunesStore');
        """

    /// A schema whose property table has gone — the query can no longer prepare.
    private static let noPropertyTable = """
        CREATE TABLE ZACCOUNTTYPE (Z_PK INTEGER PRIMARY KEY, ZIDENTIFIER VARCHAR);
        CREATE TABLE ZACCOUNT (Z_PK INTEGER PRIMARY KEY, ZACCOUNTTYPE INTEGER, ZACTIVE INTEGER);
        INSERT INTO ZACCOUNTTYPE VALUES (1, 'com.apple.account.iTunesStore');
        """

    /// Plants an accounts store in a fresh `ZZFixture-*` directory and reads it.
    /// Each account is an App Store account; `media` nil means it has no
    /// `activeMediaTypes` property at all.
    private static func signedIn(
        _ accounts: [(active: Bool, media: [String]?)], schema: String = schema
    ) throws -> Bool? {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Accounts4.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK, "fixture schema did not apply")
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, account) in accounts.enumerated() {
            let pk = index + 1
            #expect(sqlite3_exec(
                db, "INSERT INTO ZACCOUNT VALUES (\(pk), 1, \(account.active ? 1 : 0));", nil, nil, nil) == SQLITE_OK)
            guard let media = account.media else { continue }
            let blob = try archived(media)
            var stmt: OpaquePointer?
            #expect(sqlite3_prepare_v2(
                db, "INSERT INTO ZACCOUNTPROPERTY (ZOWNER, ZKEY, ZVALUE) VALUES (?, 'activeMediaTypes', ?);",
                -1, &stmt, nil) == SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, Int64(pk))
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(blob.count), transient) }
            #expect(sqlite3_step(stmt) == SQLITE_DONE)
            sqlite3_finalize(stmt)
        }
        sqlite3_close(db)
        return AppStoreSignIn.isSignedIn(databaseURL: url)
    }

    /// Signed in, and signed out beside an old inactive account that still names
    /// the App Store. Mutation: drop `a.ZACTIVE = 1` from the query — the inactive
    /// account's list then answers for the signed-out Mac and this fails.
    @Test func theActiveAccountDecides() throws {
        #expect(try Self.signedIn([(true, [Self.appStore, Self.itunes]), (false, [Self.itunes])]) == true)
        #expect(try Self.signedIn([(true, [Self.itunes]), (false, [Self.appStore, Self.itunes])]) == false)
    }

    /// Everything that is not a decoded list is "no signal". Mutation: answer false
    /// when there are no rows (`values.isEmpty`) — the first two cases fail.
    @Test func whatCannotBeReadIsNoSignal() throws {
        #expect(try Self.signedIn([(true, nil)]) == nil, "an active account with no such property")
        #expect(try Self.signedIn([]) == nil, "no App Store account at all")
        #expect(try Self.signedIn([(true, nil)], schema: Self.noPropertyTable) == nil, "a schema that no longer prepares")
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-accounts-missing-\(UUID().uuidString)/Accounts4.sqlite")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(AppStoreSignIn.isSignedIn(databaseURL: missing) == nil, "no database file")
    }
}
