import Testing
import Foundation
@testable import DuoUpdaterCore

/// Detection of a download an app's **own** Sparkle updater has in flight, before
/// anything is unpacked. The layout mirrors `SPUDownloader.m`, which creates
/// `PersistentDownloads/<random token>/<suggested filename>/<file>` via
/// `SPULocalCacheDirectory.createUniqueDirectoryInDirectory`.
///
/// The window this covers is the one `SparkleStagingTests` cannot reach: there is
/// no bundle in `Installation/` yet and no parked `Autoupdate`, because Sparkle
/// launches the installer only once the transfer finishes.
struct SelfUpdaterDownloadTests {

    private let bundleID = "com.example.sparkle"

    private func app(sparkle: Bool = true) -> InstalledApp {
        InstalledApp(
            name: "Sparkly", bundleID: bundleID, shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Sparkly.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: sparkle)
    }

    /// One download attempt, written `age` seconds ago.
    @discardableResult
    private func download(
        in caches: URL, token: String, filename: String = "Sparkly-2.0.zip",
        bytes: Int, age: TimeInterval, now: Date
    ) throws -> URL {
        let dir = caches
            .appendingPathComponent(bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("PersistentDownloads")
            .appendingPathComponent(token)
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(filename)
        try Data(repeating: 0, count: bytes).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        return file
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-inflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func detectsATransferStillInProgress() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        try download(in: caches, token: "NUZfp7vj8", bytes: 4096, age: 5, now: now)

        let found = SelfUpdaterStaging.inFlightDownload(
            for: app(), cachesDirectory: caches, now: now)
        let inFlight = try #require(found)
        #expect(inFlight.bytes == 4096)
        #expect(inFlight.directory.lastPathComponent == "NUZfp7vj8")
    }

    /// The reason this can't reuse Sparkle's own notion of staleness. Its sweep
    /// keeps debris for ten days (`OLD_ITEM_DELETION_INTERVAL`), so a download
    /// abandoned an hour ago is still sitting there — and treating that as "the
    /// app is busy" would block installs for the rest of the week.
    @Test func ignoresDebrisFromAnAbandonedTransfer() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        try download(in: caches, token: "dead1", bytes: 900_000, age: 3600, now: now)

        #expect(SelfUpdaterStaging.inFlightDownload(
            for: app(), cachesDirectory: caches, now: now) == nil)
    }

    /// Sparkle keeps `PersistentDownloads/` itself around across installs, so its
    /// mere existence proves nothing.
    @Test func anEmptyCacheIsNotADownload() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let root = caches
            .appendingPathComponent(bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("PersistentDownloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(SelfUpdaterStaging.inFlightDownload(
            for: app(), cachesDirectory: caches, now: Date()) == nil)
    }

    @Test func onlyAsksAboutSparkleApps() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        try download(in: caches, token: "live1", bytes: 4096, age: 5, now: now)

        #expect(SelfUpdaterStaging.inFlightDownload(
            for: app(sparkle: false), cachesDirectory: caches, now: now) == nil)
    }

    /// A retried download leaves the previous token behind — the live one is the
    /// most recently written, not whichever the filesystem enumerates first.
    @Test func picksTheMostRecentAttempt() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        try download(in: caches, token: "older", bytes: 1024, age: 400, now: now)
        try download(in: caches, token: "newer", bytes: 2048, age: 3, now: now)

        let inFlight = try #require(SelfUpdaterStaging.inFlightDownload(
            for: app(), cachesDirectory: caches, now: now))
        #expect(inFlight.directory.lastPathComponent == "newer")
        #expect(inFlight.bytes == 2048)
    }

    /// The distinguishing property against `sparkleStagedBundle`: that one requires
    /// a parked `Autoupdate` (correctly — without it, a staged bundle is never
    /// installed). Sparkle launches the installer only after the transfer finishes,
    /// so requiring one here would miss every in-flight download.
    @Test func doesNotRequireAParkedInstaller() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        try download(in: caches, token: "solo", bytes: 8192, age: 1, now: now)

        // No Launcher/ directory anywhere, and no running Updater.app.
        #expect(SelfUpdaterStaging.inFlightDownload(
            for: app(), cachesDirectory: caches, now: now) != nil)
    }

    // MARK: - Squirrel

    private func squirrelApp() -> InstalledApp {
        InstalledApp(
            name: "Claudey", bundleID: bundleID, shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Claudey.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: true, hasSparkleUpdater: false)
    }

    /// Squirrel's own bookkeeping, written on every ShipIt run including ones that
    /// install nothing. Reproduced from the real directory on this machine.
    private func shipItBookkeeping(in caches: URL, age: TimeInterval, now: Date) throws -> URL {
        let dir = caches.appendingPathComponent("\(bundleID).ShipIt")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["ShipItState.plist", "ShipIt_stdout.log", "ShipIt_stderr.log"] {
            let f = dir.appendingPathComponent(name)
            try Data(repeating: 0x20, count: 512).write(to: f)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: f.path)
        }
        return dir
    }

    /// The layout `ShipItState.plist` pointed at for real: `update.<random>/<App>.app`.
    @Test func detectsSquirrelStagingInProgress() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        let dir = try shipItBookkeeping(in: caches, age: 2, now: now)
        let staged = dir.appendingPathComponent("update.PvAvgLY/Claudey.app/Contents")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let f = staged.appendingPathComponent("MacOS-blob")
        try Data(repeating: 0, count: 65536).write(to: f)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-2)], ofItemAtPath: f.path)

        let found = try #require(SelfUpdaterStaging.inFlightDownload(
            for: squirrelApp(), cachesDirectory: caches, now: now))
        #expect(found.directory.lastPathComponent == "update.PvAvgLY")
        #expect(found.bytes == 65536)
    }

    /// The false positive that would matter most: ShipIt rewrites its state file and
    /// logs on runs that install nothing, so a freshly-touched `.ShipIt` directory
    /// with only those in it must not read as "busy" — that would block installs on
    /// every Squirrel app indefinitely.
    @Test func bookkeepingAloneIsNotATransfer() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        _ = try shipItBookkeeping(in: caches, age: 1, now: now)

        #expect(SelfUpdaterStaging.inFlightDownload(
            for: squirrelApp(), cachesDirectory: caches, now: now) == nil)
    }

    @Test func squirrelDebrisFromAnOldRunIsIgnored() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        let dir = try shipItBookkeeping(in: caches, age: 7200, now: now)
        let old = dir.appendingPathComponent("update.stale")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let f = old.appendingPathComponent("leftover")
        try Data(repeating: 0, count: 4096).write(to: f)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: f.path)

        #expect(SelfUpdaterStaging.inFlightDownload(
            for: squirrelApp(), cachesDirectory: caches, now: now) == nil)
    }

    /// An app with neither updater is never asked about, whatever is on disk.
    @Test func anAppWithNoSelfUpdaterIsNeverBusy() throws {
        let caches = try scratch()
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        let dir = try shipItBookkeeping(in: caches, age: 1, now: now)
        let staged = dir.appendingPathComponent("update.x")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: staged.appendingPathComponent("blob"))

        let plain = InstalledApp(
            name: "Plain", bundleID: bundleID, shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Plain.app"), isMASApp: false,
            sparkleFeedURL: nil, hasSelfUpdater: false, hasSparkleUpdater: false)
        #expect(SelfUpdaterStaging.inFlightDownload(
            for: plain, cachesDirectory: caches, now: now) == nil)
    }
}
