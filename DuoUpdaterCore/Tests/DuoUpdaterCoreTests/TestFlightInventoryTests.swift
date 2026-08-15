import XCTest
@testable import DuoUpdaterCore

final class TestFlightInventoryTests: XCTestCase {

    private func inventory() -> TestFlightInventory {
        // Mirrors the real DB shape: multiple macOS builds per app, newest wins.
        TestFlightInventory(macRows: [
            (bundleID: "com.wiheads.paste", shortVersion: "6.5.3", build: "18655"),
            (bundleID: "com.wiheads.paste", shortVersion: "6.6.1", build: "18706"),
            (bundleID: "cam.thescreen", shortVersion: "1.0.0", build: "20260521180922"),
            (bundleID: "cam.thescreen", shortVersion: "1.0.1", build: "20260601160715"),
        ])
    }

    func testLatestPicksHighestBuild() {
        let tf = inventory()
        XCTAssertEqual(tf.latest(forBundleID: "com.wiheads.paste")?.latestBuild, "18706")
        XCTAssertEqual(tf.latest(forBundleID: "com.wiheads.paste")?.latestShortVersion, "6.6.1")
        XCTAssertEqual(tf.latest(forBundleID: "cam.thescreen")?.latestBuild, "20260601160715")
        XCTAssertNil(tf.latest(forBundleID: "com.unknown.app"))
    }

    func testIsManagedRequiresBundleAndBuildMatch() {
        let tf = inventory()
        // An on-disk build that's one of the DB's macOS builds → managed.
        XCTAssertTrue(tf.isManaged(bundleID: "com.wiheads.paste", installedBuild: "18706"))
        XCTAssertTrue(tf.isManaged(bundleID: "com.wiheads.paste", installedBuild: "18655"))
        // Bundle known, but this build isn't in the DB (e.g. an App Store copy).
        XCTAssertFalse(tf.isManaged(bundleID: "com.wiheads.paste", installedBuild: "99999"))
        // Unknown bundle / nil inputs.
        XCTAssertFalse(tf.isManaged(bundleID: "com.unknown.app", installedBuild: "1"))
        XCTAssertFalse(tf.isManaged(bundleID: nil, installedBuild: "18706"))
        XCTAssertFalse(tf.isManaged(bundleID: "com.wiheads.paste", installedBuild: nil))
    }

    func testCheckerOffersBetaUpdateWhenNewerBuildExists() async {
        let tf = inventory()
        let checker = UpdateChecker(sources: [], testflight: tf)
        let app = InstalledApp(
            name: "Paste", bundleID: "com.wiheads.paste",
            shortVersion: "6.5.3", buildVersion: "18655",
            path: URL(fileURLWithPath: "/Applications/Paste.app"),
            isMASApp: false, isTestFlightApp: true, sparkleFeedURL: nil)
        let result = await checker.check(app)
        XCTAssertEqual(result.remote?.sourceName, "TestFlight")
        guard case .updateAvailable(let latest) = result.status else {
            return XCTFail("expected an update, got \(result.status)")
        }
        XCTAssertEqual(latest, "6.6.1")  // short bumped, so build is not appended
    }

    func testCheckerUpToDateOnNewestBuild() async {
        let tf = inventory()
        let checker = UpdateChecker(sources: [], testflight: tf)
        let app = InstalledApp(
            name: "Paste", bundleID: "com.wiheads.paste",
            shortVersion: "6.6.1", buildVersion: "18706",
            path: URL(fileURLWithPath: "/Applications/Paste.app"),
            isMASApp: false, isTestFlightApp: true, sparkleFeedURL: nil)
        let result = await checker.check(app)
        XCTAssertEqual(result.status, .upToDate)
    }

    func testCheckerManagedWhenNoCache() async {
        // TestFlight app but the inventory has nothing for it → managed label.
        let checker = UpdateChecker(sources: [], testflight: TestFlightInventory(macRows: []))
        let app = InstalledApp(
            name: "Mirage", bundleID: "com.ethanlipnik.Mirage",
            shortVersion: "1.0.4", buildVersion: "388",
            path: URL(fileURLWithPath: "/Applications/Mirage.app"),
            isMASApp: false, isTestFlightApp: true, sparkleFeedURL: nil)
        let result = await checker.check(app)
        XCTAssertEqual(result.status, .testFlightManaged)
    }

    /// A FIFO stands in for macOS's app-data privacy gate, and reproduces the
    /// part that actually hurts: the file exists, so every "does it exist" check
    /// passes, and then `open(2)` blocks waiting for something that never comes.
    /// Behind the real gate that something is a consent prompt no background job
    /// can answer; here it is a writer that never opens.
    ///
    /// Without the bound this is not a slow read, it is a permanent one —
    /// `sqlite3_open_v2` on this FIFO was measured never returning, and a
    /// nightly sweep sat in `guarded_open_np` for ten minutes at 0.03s of CPU
    /// before it was killed (2026-08-15).
    func testABlockedDatabaseOpenGivesUpAndIsNotRetried() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tf-blocked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fifo = dir.appendingPathComponent("TestFlight.sqlite")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0, "could not create the blocking stand-in")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fifo.path))

        // First read: must give up on its own rather than pin the caller.
        let firstStarted = Date()
        let blocked = TestFlightInventory(databaseURL: fifo)
        let firstElapsed = Date().timeIntervalSince(firstStarted)

        XCTAssertFalse(
            blocked.accessible,
            "a gate we never got through must not read as 'opened it, nothing inside'")
        XCTAssertNil(blocked.latest(forBundleID: "com.wiheads.paste"))
        XCTAssertFalse(blocked.isManaged(bundleID: "com.wiheads.paste", installedBuild: "18706"))
        XCTAssertGreaterThanOrEqual(
            firstElapsed, TestFlightInventory.openTimeout - 1,
            "returned too early to have actually waited on the open")
        XCTAssertLessThan(
            firstElapsed, TestFlightInventory.openTimeout + 15,
            "did not give up — this is the hang the bound exists to prevent")

        // Second read of the same path: the first open is still stranded, so
        // this must not start another one. One stuck thread per path, not one
        // per scan — the menu-bar app scans on a timer.
        let secondStarted = Date()
        let stillBlocked = TestFlightInventory(databaseURL: fifo)
        let secondElapsed = Date().timeIntervalSince(secondStarted)

        XCTAssertFalse(stillBlocked.accessible)
        XCTAssertLessThan(
            secondElapsed, 1,
            "a path already known to be stuck should short-circuit, not wait again")

        // Release the stranded reader so it doesn't outlive the test: opening
        // the write end lets its open(2) complete and the thread unwind.
        let writeEnd = open(fifo.path, O_WRONLY | O_NONBLOCK)
        if writeEnd >= 0 { close(writeEnd) }
    }

    /// The other half of the `accessible` contract: a database that isn't there
    /// at all is also "never got in", and must not cost a timeout to discover.
    func testAMissingDatabaseIsInaccessibleImmediately() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tf-missing-\(UUID().uuidString)/TestFlight.sqlite")

        let started = Date()
        let tf = TestFlightInventory(databaseURL: missing)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(tf.accessible)
        XCTAssertLessThan(elapsed, 1, "a missing file is answered by stat, not by waiting")
    }
}
