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
}
