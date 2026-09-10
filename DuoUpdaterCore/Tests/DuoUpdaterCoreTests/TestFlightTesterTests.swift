import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// Whether the signed-in TestFlight account is testing a beta, and what the
/// checker does when it is not.
///
/// The fixtures are the shapes measured 2026-09-10 by snapshotting TestFlight's
/// store while the account changed under it. Signed in, an installed beta's rows
/// hang off an app row that carries its bundle id and `ZISTESTER = 1`. Signed
/// out — and again signed in to a different Apple Account — only the installed
/// row survives, hanging off a placeholder app row with no bundle id, no name,
/// and `ZISTESTER = 0`.
struct TestFlightTesterTests {

    private static let bundleID = "zz.fixture.beta"

    private static let schema = """
        CREATE TABLE ZTFAPPMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR,
            ZISTESTER INTEGER, ZNAME VARCHAR);
        CREATE TABLE ZTFAPPBUNDLEMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER, ZBUNDLEID VARCHAR,
            ZSHORTVERSION VARCHAR, ZBUNDLEVERSION VARCHAR, ZPLATFORMRAW INTEGER,
            ZINSTALLSTATUSRAW INTEGER);
        """

    /// Signed in and testing: the offer row sits beside the installed one.
    private static let signedIn = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta', 1, 'Beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '0.3.384', '1300', 1, 1);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 11, 'zz.fixture.beta', '0.3.384', '1301', 1, 0);
        """

    /// Signed out, or another Apple Account: the measured placeholder.
    private static let signedOut = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, NULL, 0, NULL);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '0.3.384', '1300', 1, 1);
        """

    /// A schema with no tester column: the signal must switch off, not read as
    /// "testing nothing".
    private static let noTesterColumn = """
        CREATE TABLE ZTFAPPMODEL (Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR);
        CREATE TABLE ZTFAPPBUNDLEMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER, ZBUNDLEID VARCHAR,
            ZSHORTVERSION VARCHAR, ZBUNDLEVERSION VARCHAR, ZPLATFORMRAW INTEGER,
            ZINSTALLSTATUSRAW INTEGER);
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '0.3.384', '1300', 1, 1);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 11, 'zz.fixture.beta', '0.3.384', '1301', 1, 0);
        """

    /// Plants a store in a fresh `ZZFixture-*` directory and reads it. The
    /// inventory reads eagerly, so it outlives the directory.
    private static func inventory(_ sql: String) throws -> TestFlightInventory {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-tester-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("TestFlight.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "fixture schema did not apply")
        sqlite3_close(db)
        let inventory = TestFlightInventory(databaseURL: url)
        #expect(inventory.accessible, "fixture database was not opened")
        return inventory
    }

    /// An invented path, so the host's disk cannot change the answer.
    private static func wrappedApp() -> InstalledApp {
        InstalledApp(
            name: "Beta", bundleID: bundleID,
            shortVersion: "0.3.384", buildVersion: "1300",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Beta.app"),
            isMASApp: false, isiOSAppOnMac: true, isTestFlightApp: true,
            sparkleFeedURL: nil)
    }

    /// Mutation: drop `a.ZISTESTER = 1` from the tester query — the placeholder
    /// row still joins, so the signed-out store says "testing" and this fails.
    @Test func theStoreSaysWhichBetasTheAccountIsTesting() throws {
        #expect(try Self.inventory(Self.signedIn).isTesting(bundleID: Self.bundleID) == true)
        #expect(try Self.inventory(Self.signedOut).isTesting(bundleID: Self.bundleID) == false)
    }

    /// Mutation: return an empty set instead of nil when the tester query does not
    /// prepare — a schema change then reads as "testing nothing" and fails here.
    @Test func noTesterColumnMeansNoSignal() throws {
        let inventory = try Self.inventory(Self.noTesterColumn)
        #expect(inventory.latestIOS(forBundleID: Self.bundleID)?.latestBuild == "1301",
                "fixture guard: the row query must still have run")
        #expect(inventory.isTesting(bundleID: Self.bundleID) == nil)
    }

    /// The defect, end to end: signed out, the installed build is the only row
    /// left and was read as the newest — `.upToDate` for a beta the account cannot
    /// even see. Mutation: delete the `isTesting` check in `UpdateChecker` — this
    /// becomes `.upToDate` and fails.
    @Test func aBetaTheAccountIsNotTestingIsNotCalledCurrent() async throws {
        let inventory = try Self.inventory(Self.signedOut)
        #expect(inventory.latestIOS(forBundleID: Self.bundleID)?.latestBuild == "1300",
                "fixture guard: the installed row must be all the lookup sees")
        let result = await UpdateChecker(sources: [], testflight: inventory).check(Self.wrappedApp())
        #expect(result.status == .testFlightManaged)
        #expect(result.remote == nil)
    }

    /// ...and it takes nothing away when the account is testing, or when the store
    /// cannot say. Mutation: write the check as `!= true` — the no-signal store
    /// then blocks too, and its update disappears.
    @Test func testingOrUnknownKeepsTheUpdate() async throws {
        for sql in [Self.signedIn, Self.noTesterColumn] {
            let result = await UpdateChecker(sources: [], testflight: try Self.inventory(sql))
                .check(Self.wrappedApp())
            guard case .updateAvailable(let latest) = result.status else {
                Issue.record("expected the update to survive, got \(result.status)")
                continue
            }
            #expect(latest == "0.3.384")
            #expect(result.remote?.version == "1301")
        }
    }

    /// What the refresh gate reads. Mutation: answer true for a store that cannot
    /// say (`testerBundleIDs?.isEmpty != false`) — then a schema change stops every
    /// refresh, and the no-signal case fails.
    @Test func onlyAStoreThatSaysSoTestsNothing() throws {
        #expect(try Self.inventory(Self.signedOut).isTestingNothing)
        #expect(try !Self.inventory(Self.signedIn).isTestingNothing)
        #expect(try !Self.inventory(Self.noTesterColumn).isTestingNothing)
    }
}

// MARK: - The App Store sign-in, as an input to the verdict

extension TestFlightTesterTests {
    /// Signed out of TestFlight, the store keeps its signed-in shape until
    /// TestFlight next runs — measured 2026-09-10: offer rows present,
    /// `ZISTESTER = 1` — so the App Store sign-in is what says otherwise. The fixture
    /// is that stale shape. Mutation: delete the `appStoreSignedIn == false` check in
    /// `UpdateChecker` — the stale store's update comes back and this fails.
    @Test func aMacSignedOutOfTheAppStoreIsNotOfferedTheStoresUpdate() async throws {
        let result = await UpdateChecker(
            sources: [], testflight: try Self.inventory(Self.signedIn), appStoreSignedIn: false
        ).check(Self.wrappedApp())
        #expect(result.status == .testFlightManaged)
        #expect(result.remote == nil)
    }

    /// Signed in, or unknown: the store decides. Mutation: write the check as
    /// `!= true` — the unknown case loses its update and this fails.
    @Test func aSignInThatIsTrueOrUnknownLeavesTheStoreToDecide() async throws {
        for signedIn in [true, nil] as [Bool?] {
            let result = await UpdateChecker(
                sources: [], testflight: try Self.inventory(Self.signedIn), appStoreSignedIn: signedIn
            ).check(Self.wrappedApp())
            guard case .updateAvailable(let latest) = result.status else {
                Issue.record("signed in = \(String(describing: signedIn)): expected the update, got \(result.status)")
                continue
            }
            #expect(latest == "0.3.384")
        }
    }
}
