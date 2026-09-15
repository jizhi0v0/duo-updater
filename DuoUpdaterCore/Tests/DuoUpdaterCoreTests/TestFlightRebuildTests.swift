import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// Whether a read caught TestFlight partway through rebuilding its store, and
/// what waiting for the rebuild does.
///
/// The fixtures are the shapes measured 2026-09-15 by backing the store up every
/// 0.3s through six syncs on two Macs, a cold launch by hand, a Stop Testing, a
/// sign-out and a sign-in. A launch empties the store, puts back placeholders for
/// the installed builds, then applies the app list — every app row named and
/// `ZISTESTER = 1` but with no bundle id, the installed build rows the only build
/// rows — and fills everything in only when the second request lands.
struct TestFlightRebuildTests {

    private static let schema = """
        CREATE TABLE ZTFAPPMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR,
            ZISTESTER INTEGER, ZNAME VARCHAR);
        CREATE TABLE ZTFAPPBUNDLEMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER, ZBUNDLEID VARCHAR,
            ZSHORTVERSION VARCHAR, ZBUNDLEVERSION VARCHAR, ZPLATFORMRAW INTEGER,
            ZINSTALLSTATUSRAW INTEGER);
        """

    /// Complete: two betas the account tests, one installed at 83 with 91 offered,
    /// one not installed.
    private static let complete = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta', 1, 'Beta');
        INSERT INTO ZTFAPPMODEL VALUES (2, 222, 'zz.fixture.other', 1, 'Other');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '1.0', '83', 1, 1);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 11, 'zz.fixture.beta', '1.0', '91', 1, 0);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (3, 2, 20, 'zz.fixture.other', '2.0', '5', 1, 0);
        """

    /// Between the two requests: every app row named and testing, none with a
    /// bundle id; the installed build is the only build row, without its build id.
    private static let midRebuild = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, NULL, 1, 'Beta');
        INSERT INTO ZTFAPPMODEL VALUES (2, 222, NULL, 1, 'Other');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, NULL, 'zz.fixture.beta', '1.0', '83', 1, 1);
        """

    /// Before the app list lands, and — identically — a signed-out store: the
    /// placeholder for the installed build only.
    private static let placeholders = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, NULL, 0, NULL);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, NULL, 'zz.fixture.beta', '1.0', '83', 1, 1);
        """

    /// Stop Testing the beta that is not installed: its rows deleted in place.
    private static let stoppedTesting = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta', 1, 'Beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '1.0', '83', 1, 1);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 11, 'zz.fixture.beta', '1.0', '91', 1, 0);
        """

    /// App rows with bundle ids plus one that never gained one, and no build ids
    /// anywhere, so the bundle-id half alone decides. Not a shape that was measured;
    /// the case that decides "none" over "any".
    private static let oneOddRowAmongBundleIDs = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta', 1, 'Beta');
        INSERT INTO ZTFAPPMODEL VALUES (2, 333, NULL, 1, 'Odd');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, NULL, 'zz.fixture.beta', '1.0', '83', 1, 1);
        """

    /// Every tester app row without a bundle id, but the build rows carry build ids.
    /// Not measured; the case that makes the build-id half load-bearing.
    private static let appRowsWithoutBundleIDs = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, NULL, 1, 'Beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 10, 'zz.fixture.beta', '1.0', '83', 1, 1);
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 11, 'zz.fixture.beta', '1.0', '91', 1, 0);
        """

    /// Every build row without a build id, but the app rows carry bundle ids. Not
    /// measured; the case that makes the bundle-id half load-bearing.
    private static let buildRowsWithoutBuildIDs = schema + """
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, 'zz.fixture.beta', 1, 'Beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, NULL, 'zz.fixture.beta', '1.0', '83', 1, 1);
        """

    /// A schema without the tester column: the query cannot prepare.
    private static let noTesterColumn = """
        CREATE TABLE ZTFAPPMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR, ZNAME VARCHAR);
        CREATE TABLE ZTFAPPBUNDLEMODEL (
            Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER, ZBUNDLEID VARCHAR,
            ZSHORTVERSION VARCHAR, ZBUNDLEVERSION VARCHAR, ZPLATFORMRAW INTEGER,
            ZINSTALLSTATUSRAW INTEGER);
        INSERT INTO ZTFAPPMODEL VALUES (1, 111, NULL, 'Beta');
        INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, NULL, 'zz.fixture.beta', '1.0', '83', 1, 1);
        """

    /// Plants a store in a fresh `ZZFixture-*` directory and reads it.
    private static func inventory(_ sql: String) throws -> TestFlightInventory {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-rebuild-\(UUID().uuidString)")
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
    private static func installedBeta() -> InstalledApp {
        InstalledApp(
            name: "Beta", bundleID: "zz.fixture.beta",
            shortVersion: "1.0", buildVersion: "83",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Beta.app"),
            isMASApp: false, isiOSAppOnMac: true, isTestFlightApp: true,
            sparkleFeedURL: nil)
    }

    // MARK: - The marker

    /// The measured shapes. Mutation: `SELECT 0` — the mid-rebuild line fails.
    @Test func onlyTheStoreBetweenTheTwoRequestsReadsAsRebuilding() throws {
        #expect(try Self.inventory(Self.midRebuild).isRebuilding)
        #expect(try !Self.inventory(Self.complete).isRebuilding)
        #expect(try !Self.inventory(Self.stoppedTesting).isRebuilding)
    }

    /// Each "none" half on its own keeps a complete store from matching. Mutations:
    /// drop the `ZBUNDLEID IS NOT NULL` half — `buildRowsWithoutBuildIDs` matches and
    /// fails; drop the `ZBUILDID IS NOT NULL` half — `appRowsWithoutBundleIDs` does.
    @Test func eitherKindOfIDRulesOutARebuild() throws {
        #expect(try !Self.inventory(Self.appRowsWithoutBundleIDs).isRebuilding)
        #expect(try !Self.inventory(Self.buildRowsWithoutBuildIDs).isRebuilding)
    }

    /// The placeholder stage cannot be told from a sign-out, so it must not match:
    /// a store left signed out would otherwise hold every reader in a wait.
    /// Mutation: drop `WHERE ZISTESTER = 1` from the first half — the placeholder
    /// row, with no bundle id and no build id, then matches and this fails.
    @Test func aSignedOutStoreIsNotARebuild() throws {
        #expect(try !Self.inventory(Self.placeholders).isRebuilding)
    }

    /// "None", not "any". Mutation: replace the bundle-id half's `NOT EXISTS (…
    /// ZBUNDLEID IS NOT NULL)` with `EXISTS (… ZBUNDLEID IS NULL)` — the one odd row
    /// makes the store read as rebuilding and this fails.
    @Test func oneAppRowWithoutABundleIDDoesNotMakeACompleteStoreARebuild() throws {
        #expect(try !Self.inventory(Self.oneOddRowAmongBundleIDs).isRebuilding)
    }

    /// A schema the query cannot prepare on switches the guard off, never on.
    /// Mutation: return `true` from the prepare-failure branch — this fails.
    @Test func aQueryThatDoesNotPrepareIsNoSignal() throws {
        let inventory = try Self.inventory(Self.noTesterColumn)
        #expect(inventory.rowsReadable, "fixture guard: only the rebuild query should fail")
        #expect(inventory.latestIOS(forBundleID: "zz.fixture.beta")?.latestBuild == "83",
                "fixture guard: the row query must still have run")
        #expect(!inventory.isRebuilding)
    }

    /// A store whose build rows will not query at all opens, but says so. Mutation:
    /// report `true` from the reader's last fallback — this fails.
    @Test func aStoreWhoseRowsWillNotQuerySaysSo() throws {
        let unreadable = """
            CREATE TABLE ZTFAPPMODEL (
                Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR,
                ZISTESTER INTEGER, ZNAME VARCHAR);
            CREATE TABLE ZTFAPPBUNDLEMODEL (Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER);
            """
        #expect(try !Self.inventory(unreadable).rowsReadable)
        #expect(try Self.inventory(Self.complete).rowsReadable)
    }

    /// Why callers must ask: read as it stands, the half-built store calls a beta
    /// with an update current, because the installed build is the only row left.
    /// Not a mutation guard — a record that the fixture reproduces the defect, so the
    /// cases above are guarding against something real.
    @Test func aStoreMidRebuildWouldCallABetaWithAnUpdateCurrent() async throws {
        let complete = await UpdateChecker(sources: [], testflight: try Self.inventory(Self.complete))
            .check(Self.installedBeta())
        #expect(complete.status == .updateAvailable(latest: "1.0"))
        let half = await UpdateChecker(sources: [], testflight: try Self.inventory(Self.midRebuild))
            .check(Self.installedBeta())
        #expect(half.status != complete.status)
    }
}

// MARK: - Waiting a rebuild out

extension TestFlightRebuildTests {
    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [TestFlightInventory?]
        private(set) var count = 0
        private(set) var sleeps = 0
        init(_ queue: [TestFlightInventory?]) { self.queue = queue }
        func next() -> TestFlightInventory? {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return queue.isEmpty ? Self.rebuilding : queue.removeFirst()
        }
        func slept() {
            lock.lock(); defer { lock.unlock() }
            sleeps += 1
        }
        static let rebuilding = TestFlightInventory(macRows: [], rebuilding: true)
    }

    private static let settled = TestFlightInventory(
        macRows: [(bundleID: "zz.fixture.beta", shortVersion: "1.0", build: "91")])

    /// A read that is not mid-rebuild is the answer at once. Mutation: loop while
    /// `accessible` alone — this sleeps and reads again, and fails.
    @Test func aSettledReadIsNotWaitedOn() async {
        let reads = Reads([])
        let result = await TestFlightInventory.awaitingRebuild(
            Self.settled, sleep: { _ in reads.slept() }, read: { reads.next() })
        #expect(reads.count == 0)
        #expect(reads.sleeps == 0)
        #expect(result.latest(forBundleID: "zz.fixture.beta")?.latestBuild == "91")
    }

    /// The case the wait exists for: the store fills in a few reads later, and that
    /// read is what comes back. Mutation: return after the first re-read whatever it
    /// says — the result is still rebuilding and this fails.
    @Test func theWaitEndsOnTheFirstReadThatIsNoLongerRebuilding() async {
        let reads = Reads([Reads.rebuilding, Reads.rebuilding, Self.settled])
        let result = await TestFlightInventory.awaitingRebuild(
            Reads.rebuilding, sleep: { _ in reads.slept() }, read: { reads.next() })
        #expect(reads.count == 3)
        #expect(!result.isRebuilding)
        #expect(result.latest(forBundleID: "zz.fixture.beta")?.latestBuild == "91")
    }

    /// A rebuild that outlasts the cap comes back still rebuilding, after exactly
    /// the reads the cap allows. Mutation: drop `waited < cap` — this never returns
    /// (the run is killed by the harness's timeout, not an assertion).
    @Test func aRebuildThatOutlastsTheCapIsReturnedAsIs() async {
        let reads = Reads([])
        let result = await TestFlightInventory.awaitingRebuild(
            Reads.rebuilding, interval: .seconds(1), cap: .seconds(5),
            sleep: { _ in reads.slept() }, read: { reads.next() })
        #expect(result.isRebuilding)
        #expect(reads.count == 5)
    }

    /// A read that opened but could not query its rows is no answer about the
    /// rebuild, so the wait goes on past it. Mutation: drop the `rowsReadable` skip —
    /// the unreadable read ends the wait, comes back not rebuilding, and this fails.
    @Test func aReadWhoseRowsWouldNotQueryDoesNotEndTheWait() async {
        let reads = Reads([TestFlightInventory(macRows: [], rowsReadable: false), Self.settled])
        let result = await TestFlightInventory.awaitingRebuild(
            Reads.rebuilding, sleep: { _ in reads.slept() }, read: { reads.next() })
        #expect(reads.count == 2)
        #expect(result.latest(forBundleID: "zz.fixture.beta")?.latestBuild == "91")
    }

    /// A later read that does not open ends the wait and is returned, so the caller's
    /// "did not open" branch applies; one that never came back ends it with the last
    /// half-built read. Mutation: `continue` on nil instead of returning — the nil
    /// case reads until the cap and its count fails.
    @Test func aReadThatFailsEndsTheWait() async {
        let unopened = Reads([TestFlightInventory(macRows: [], accessible: false)])
        let afterUnopened = await TestFlightInventory.awaitingRebuild(
            Reads.rebuilding, sleep: { _ in unopened.slept() }, read: { unopened.next() })
        #expect(!afterUnopened.accessible)
        #expect(unopened.count == 1)

        let missing = Reads([nil])
        let afterMissing = await TestFlightInventory.awaitingRebuild(
            Reads.rebuilding, sleep: { _ in missing.slept() }, read: { missing.next() })
        #expect(afterMissing.accessible && afterMissing.isRebuilding)
        #expect(missing.count == 1)
    }
}
