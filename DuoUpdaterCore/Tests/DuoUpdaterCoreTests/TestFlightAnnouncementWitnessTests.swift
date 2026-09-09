import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// The second witness: TestFlight's own notifications, used only ever to **refuse**
/// an up-to-date verdict the local store is not entitled to give.
///
/// ⚠️ **The first rule written here was wrong, and live data is what said so.**
/// "An announced build the store does not hold proves the store is behind" sounds
/// self-evident and is false: the store keeps one row per platform for the *current*
/// build and no history, so every announcement older than the current build fails a
/// membership test. Measured 2026-09-10 across the two live stores — of 5
/// announcements, **3 named a build the store did not hold, and in all three the
/// store was ahead**. Those three numbers are the fixtures below, because a rule
/// this plausible needs the counter-example written down next to it.
struct TestFlightAnnouncementWitnessTests {

    private static func frontier(adam: Int64, max: Int64) -> TestFlightInventory.Frontier {
        TestFlightInventory.Frontier(adamID: adam, maxBuildID: max)
    }
    private static func announced(_ pairs: [(Int64, Int64)]) -> TestFlightAnnouncements {
        TestFlightAnnouncements(
            announcements: pairs.map {
                TestFlightAnnouncements.Announcement(appAdamID: $0.0, buildID: $0.1)
            })
    }

    // MARK: - The comparison

    /// The three live rows that killed the membership rule. Each announced a build
    /// the store does not hold, and in each the store is **ahead** — so the honest
    /// answer is "not behind", and a membership test would have said the opposite
    /// on every one.
    ///
    /// Mutation: change `announced > frontier.maxBuildID` to
    /// `!buildIDs(forAppAdamID:).contains(frontier.maxBuildID)` — all three fail.
    @Test(arguments: [
        (announced: Int64(234414114), held: Int64(234615396)),  // co.nowledge.mem.mobile
        (announced: Int64(234696688), held: Int64(234839053)),  // com.jizhi0v0.claude-usage
        (announced: Int64(234026569), held: Int64(234783351)),  // com.ampcode.amp.ios
    ])
    func aStoreAheadOfAStaleAnnouncementIsNotBehind(c: (announced: Int64, held: Int64)) {
        let witness = Self.announced([(42, c.announced)])
        #expect(!witness.isBehind(Self.frontier(adam: 42, max: c.held)))
    }

    /// The case the witness exists for.
    ///
    /// Mutation: use `>=`, or drop the comparison and return true whenever an
    /// announcement exists — the equality case below fails instead.
    @Test func anAnnouncementBeyondTheStoreMeansTheStoreIsBehind() {
        let witness = Self.announced([(42, 234_900_000)])
        #expect(witness.isBehind(Self.frontier(adam: 42, max: 234_839_053)))
    }

    /// Measured live: the store held exactly the newest announced build. That is a
    /// store which is current, not one that is behind by zero.
    ///
    /// Mutation: `>=` instead of `>` — this fails, and every machine whose store is
    /// perfectly current starts refusing its own up-to-date verdicts.
    @Test func aStoreHoldingExactlyTheAnnouncedBuildIsNotBehind() {
        let witness = Self.announced([(42, 234_839_053)])
        #expect(!witness.isBehind(Self.frontier(adam: 42, max: 234_839_053)))
    }

    /// Announcements are scoped to their app. A neighbour's newer build says
    /// nothing, and TestFlight build ids look like one global sequence, so without
    /// the scoping every app on the machine would be refused whenever any app got a
    /// build.
    ///
    /// Mutation: drop the `$0.appAdamID == id` filter in `buildIDs(forAppAdamID:)`
    /// — this fails.
    @Test func aNeighboursAnnouncementDoesNotAccuseThisApp() {
        let witness = Self.announced([(999, 234_900_000)])
        #expect(!witness.isBehind(Self.frontier(adam: 42, max: 234_839_053)))
    }

    /// The absence of an announcement proves nothing, so it can never produce a
    /// refusal. Measured on one of the two Macs: every TestFlight notification there
    /// was a *post-install* "is Now Up to Date", and the two builds actually waiting
    /// were never announced at all.
    ///
    /// Mutation: return `true` when `latestAnnouncedBuild` is nil — this fails, and
    /// every app with no notification loses its up-to-date verdict.
    @Test func silenceIsNotEvidence() {
        #expect(!Self.announced([]).isBehind(Self.frontier(adam: 42, max: 1)))
    }

    /// No frontier means the store had no app row, or the frontier query did not
    /// prepare. Either way there is nothing to compare against.
    ///
    /// Mutation: treat a nil frontier as behind — this fails, and a schema change
    /// would take every TestFlight verdict on the machine with it.
    @Test func noFrontierIsNoAccusation() {
        #expect(!Self.announced([(42, 234_900_000)]).isBehind(nil))
    }

    /// A withdrawn build keeps refusing until its notification ages out, and this
    /// pins that rather than hiding it. The store's maximum *drops* back when a
    /// build is expired or rolled back, while the announcement for the withdrawn one
    /// stays in the window — measured at 5 records spanning three days.
    ///
    /// This is an accepted cost, not a bug being asserted: the alternative needs a
    /// timestamp comparison the announcement does not carry, and the failure is a
    /// refusal rather than a wrong update. It is a case so that changing it is a
    /// decision someone makes on purpose — and because the refusal sticks:
    /// `.testFlightManaged` is not in `UpdatePolicy.settledRowIDs`, so the row does
    /// not settle for as long as this holds.
    ///
    /// Mutation: none — this asserts current behaviour. If a future change starts
    /// ignoring aged-out announcements, this case is the one that must be updated,
    /// and its failure is the reminder to update the doc comment with it.
    @Test func aWithdrawnBuildKeepsRefusingUntilItsNotificationAgesOut() {
        // Announced 234900000, then pulled; the store falls back to 234839053.
        let witness = Self.announced([(42, 234_900_000)])
        #expect(witness.isBehind(Self.frontier(adam: 42, max: 234_839_053)))
    }

    // MARK: - What the checker does with it

    private static func app(build: String) -> InstalledApp {
        InstalledApp(
            name: "ZZFixture", bundleID: "zz.fixture.beta",
            shortVersion: "1.0", buildVersion: build,
            path: URL(fileURLWithPath: "/ZZFixture-does-not-exist/ZZFixture.app"),
            isMASApp: false, isiOSAppOnMac: false, isTestFlightApp: true,
            sparkleFeedURL: nil)
    }

    private static func inventory(storeBuild: String, frontierMax: Int64) -> TestFlightInventory {
        TestFlightInventory(
            macRows: [(bundleID: "zz.fixture.beta", shortVersion: "1.0", build: storeBuild)],
            frontiers: ["zz.fixture.beta": frontier(adam: 42, max: frontierMax)])
    }

    /// Fixture guard: the invented path must not exist, or this suite starts
    /// measuring the host's filesystem instead of the rule.
    @Test func theFixturePathIsNotReal() {
        #expect(!FileManager.default.fileExists(
            atPath: "/ZZFixture-does-not-exist/ZZFixture.app"))
    }

    /// The store says "you are current"; the notification says a newer build exists.
    /// The store's "latest" is therefore not an upper bound for this app, which is
    /// exactly the verdict `.upToDate` claims it is — so the verdict goes, and no
    /// version is shown in its place.
    ///
    /// Mutation: delete the `announcements?.isBehind(...)` branch — the status
    /// becomes `.upToDate` and this fails.
    @Test func anAnnouncedBuildBeyondTheStoreTakesAwayTheUpToDateVerdict() async {
        let result = await UpdateChecker(
            sources: [],
            testflight: Self.inventory(storeBuild: "100", frontierMax: 234_839_053),
            announcements: Self.announced([(42, 234_900_000)])
        ).check(Self.app(build: "100"))

        #expect(result.status == .testFlightManaged)
        #expect(result.remote == nil, "a version we just called unusable must not be shown")
    }

    /// ...and it only ever takes that verdict away. When the store already knows
    /// about a newer build, the concrete version survives: replacing it with
    /// "TestFlight manages this" would throw information away in order to say
    /// something weaker.
    ///
    /// Mutation: drop the `!hasUpdate` condition — the status collapses to
    /// `.testFlightManaged` and this fails.
    @Test func anAnnouncementNeverReplacesAnUpdateTheStoreAlreadyFound() async {
        let result = await UpdateChecker(
            sources: [],
            testflight: Self.inventory(storeBuild: "200", frontierMax: 234_839_053),
            announcements: Self.announced([(42, 234_900_000)])
        ).check(Self.app(build: "100"))

        guard case .updateAvailable(let latest) = result.status else {
            Issue.record("expected the store's update to survive, got \(result.status)")
            return
        }
        #expect(latest == "1.0 (200)")
        #expect(result.remote?.version == "200")
    }

    /// A stale announcement leaves a current store alone — the live shape from the
    /// top of this file, now end to end through the checker.
    ///
    /// Mutation: any of the comparison mutations above — this becomes
    /// `.testFlightManaged` and fails.
    @Test func aStaleAnnouncementLeavesTheVerdictAlone() async {
        let result = await UpdateChecker(
            sources: [],
            testflight: Self.inventory(storeBuild: "100", frontierMax: 234_839_053),
            announcements: Self.announced([(42, 234_696_688)])
        ).check(Self.app(build: "100"))

        #expect(result.status == .upToDate)
    }

    /// No witness at all must leave every verdict exactly as it was — this is what
    /// makes the whole thing safe to fail open when the notification store cannot be
    /// read.
    ///
    /// Mutation: make `announcements == nil` behave like "behind" — this fails.
    @Test func noWitnessChangesNothing() async {
        let result = await UpdateChecker(
            sources: [],
            testflight: Self.inventory(storeBuild: "100", frontierMax: 1)
        ).check(Self.app(build: "100"))

        #expect(result.status == .upToDate)
    }

    // MARK: - Reading the frontier out of a real schema

    /// The frontier survives a schema that breaks the row queries. Its two columns
    /// live in different tables from theirs, so "the row queries did not prepare"
    /// does not imply "this one cannot" — and the whole reason it got its own query
    /// is that each signal fails on its own.
    ///
    /// The fixture drops `ZSHORTVERSION`, which both row queries name and neither
    /// can do without, while leaving everything the frontier needs.
    ///
    /// Mutation: return `([], [], [], [:], true)` from the both-queries-failed path
    /// instead of calling `readFrontiers` — the frontier comes back nil and this
    /// fails.
    @Test func theFrontierIsStillReadWhenTheRowQueriesCannotPrepare() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-noshort-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("TestFlight.sqlite")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let schema = """
            CREATE TABLE ZTFAPPMODEL (Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR);
            CREATE TABLE ZTFAPPBUNDLEMODEL (
                Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER,
                ZBUNDLEID VARCHAR, ZBUNDLEVERSION VARCHAR, ZPLATFORMRAW INTEGER);
            INSERT INTO ZTFAPPMODEL VALUES (1, 6761822408, 'zz.fixture.beta');
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 234839053, 'zz.fixture.beta', '200', 3);
            """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let inventory = TestFlightInventory(databaseURL: dbURL)
        #expect(inventory.accessible, "fixture database was not opened")
        #expect(inventory.latest(forBundleID: "zz.fixture.beta") == nil,
                "fixture guard: the row queries must actually have failed here")
        let frontier = try #require(
            inventory.frontier(forBundleID: "zz.fixture.beta"),
            "the frontier query does not name ZSHORTVERSION, so it must still have run")
        #expect(frontier.maxBuildID == 234_839_053)
    }

    /// The notification store read is bounded and abandons its thread, like the
    /// TestFlight store read beside it. `Task.detached` is not a substitute — a
    /// detached task still runs on the cooperative pool — and a timeout on the
    /// caller's wait stops us waiting, not the thread being held.
    ///
    /// Mutation: drop the `bounded.run` wrapper and open inline — this fails.
    /// Pinned in the source text because a hang is not a thing a unit case can wait
    /// for.
    @Test func theNotificationStoreReadIsBounded() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/DuoUpdaterCore/Sources/TestFlightAnnouncements.swift"),
            encoding: .utf8)
        #expect(source.contains("bounded.run(key: url.path, timeout: openTimeout)"))
    }

    /// The install recheck must not pay for a read whose answer it cannot use: it
    /// deliberately carries a TestFlight inventory with no frontiers, so the witness
    /// can only ever say "not behind".
    ///
    /// Mutation: delete the `announcements:` argument at that call site and let the
    /// default fire — this fails.
    @Test func theInstallRecheckPassesTheEmptyWitness() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("CLI/Sources/DuoKit/Install.swift"),
            encoding: .utf8)
        #expect(source.contains("TestFlightAnnouncements(announcements: [], accessible: false)"))
        #expect(source.contains("announcements: recheckAnnouncements"))
    }

    /// The frontier query has to run against TestFlight's actual two-table shape,
    /// not just against the injected seam — the join, the `MAX`, and both column
    /// names are only exercised here.
    ///
    /// Mutation: rename any column in `frontierSQL`, or drop the `GROUP BY` — the
    /// frontier comes back empty or wrong and this fails.
    @Test func theFrontierIsReadFromTheStoresOwnTwoTables() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZZFixture-frontier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("TestFlight.sqlite")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let schema = """
            CREATE TABLE ZTFAPPMODEL (Z_PK INTEGER PRIMARY KEY, ZAPPID INTEGER, ZBUNDLEID VARCHAR);
            CREATE TABLE ZTFAPPBUNDLEMODEL (
                Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZBUILDID INTEGER,
                ZBUNDLEID VARCHAR, ZSHORTVERSION VARCHAR, ZBUNDLEVERSION VARCHAR,
                ZPLATFORMRAW INTEGER, ZINSTALLSTATUSRAW INTEGER);
            INSERT INTO ZTFAPPMODEL VALUES (1, 6761822408, 'zz.fixture.beta');
            -- Two platforms, deliberately out of order, so MAX has something to do.
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES (1, 1, 234839053, 'zz.fixture.beta', '1.0', '200', 3, 1);
            INSERT INTO ZTFAPPBUNDLEMODEL VALUES (2, 1, 234696688, 'zz.fixture.beta', '1.0', '100', 1, 0);
            """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        db = nil

        let inventory = TestFlightInventory(databaseURL: dbURL)
        #expect(inventory.accessible, "fixture database was not opened")
        let frontier = try #require(inventory.frontier(forBundleID: "zz.fixture.beta"))
        #expect(frontier.adamID == 6_761_822_408)
        #expect(frontier.maxBuildID == 234_839_053, "MAX across platforms, not the first row")
        #expect(inventory.frontier(forBundleID: "zz.fixture.absent") == nil)
    }
}
