import Testing
import Foundation
@testable import DuoUpdaterCore

/// Install rollback points: the copy taken automatically before a third-party
/// route (brew, the App Store) changes an app, for a user who has no
/// backup being taken. They live apart from the user's one-per-app backup slot,
/// are not backups as far as every existing read path is concerned, survive
/// every automatic sweep, and go when the install succeeds.
///
/// Plus the restore half they need: putting a bundle back where nothing is
/// (the app vanished mid-install) and over a bundle that was emptied.
///
/// Serialized like `BackupStoreTests`: each test binds its own scratch root,
/// but the space seams are read by code shared across the suite.
@Suite(.serialized)
struct InstallRollbackPointTests {

    private let gib: Int64 = 1 << 30

    /// A scratch outbox bound for `body`, plus a sibling `apps` directory for the
    /// fabricated bundles. Facts and destination bound too, so nothing reads the
    /// real store or the real settings.
    private func withScratch(_ body: (_ root: URL, _ apps: URL) async throws -> Void) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdaterRollbackPointTest-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("Backups")
        let apps = scratch.appendingPathComponent("Apps")
        let facts = scratch.appendingPathComponent("Facts")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await BackupStore.$rootOverride.withValue(root) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try await BackupFactsLibrary.$rootOverride.withValue(facts) {
                    try await body(root, apps)
                }
            }
        }
    }

    /// A minimal unsigned bundle with a marker, structurally valid enough for
    /// the restore's signature fallback (see `BackupStoreTests.makeApp`).
    @discardableResult
    private func makeApp(
        named name: String = "ZZFixture-Rollback.app", in dir: URL, marker: String,
        bundleID: String = "com.example.zzfixture.rollback"
    ) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleName</key><string>App</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>\(marker)</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func installed(_ app: URL, version: String) -> InstalledApp {
        InstalledApp(
            name: app.deletingPathExtension().lastPathComponent,
            bundleID: "com.example.zzfixture.rollback", shortVersion: version,
            buildVersion: nil, path: app, isMASApp: false, sparkleFeedURL: nil)
    }

    /// Every regular file under `dir`, relative path → bytes. Compared before
    /// and after to say "nothing in here changed", sidecar included.
    private func snapshot(_ dir: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let walker = try #require(FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            out[String(url.path.dropFirst(dir.path.count))] = try Data(contentsOf: url)
        }
        return out
    }

    // MARK: - Purpose

    /// A sidecar written before `purpose` existed decodes, and reads as the
    /// user's backup — no migration of what is already on disk.
    @Test func aSidecarWithoutPurposeReadsAsAUserBackup() async throws {
        try await withScratch { root, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.save(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            let sidecar = root.appendingPathComponent(key).appendingPathComponent("backup.json")
            var json = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
            json.removeValue(forKey: "purpose")
            try JSONSerialization.data(withJSONObject: json).write(to: sidecar)

            #expect(BackupStore.backup(forKey: key)?.purpose == .userBackup)
            #expect(BackupStore.listing().first { $0.key == key }?.purpose == .userBackup)
        }
    }

    // MARK: - Stored apart

    /// The whole point of storing them apart: the user's backup for the same
    /// app — from back when backups were on — is not touched, byte for byte.
    @Test func aRollbackPointNeverTouchesTheUserBackupSlot() async throws {
        try await withScratch { root, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.save(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            let slot = root.appendingPathComponent(key, isDirectory: true)
            let before = try snapshot(slot)

            try makeApp(in: apps, marker: "v2")
            let point = try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v2", bundleID: "com.example.zzfixture.rollback")

            #expect(try snapshot(slot) == before)
            #expect(BackupStore.backup(forKey: key)?.version == "v1")
            #expect(point.purpose == .installRollbackPoint)
            #expect(point.bundlePath.path.hasPrefix(BackupStore.rollbackPointsRoot.path + "/"))
            #expect(BackupStore.rollbackPoint(forKey: key).map { marker(of: $0.bundlePath) } == "v2")
        }
    }

    /// Invisible to every read path that means "the user's backups" — the
    /// Rollback row, retention, transfers — and visible through its own.
    @Test func rollbackPointsAreListedApartFromBackups() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")

            #expect(BackupStore.allBackups()[key] == nil)
            #expect(BackupStore.backup(forKey: key) == nil)
            #expect(!BackupStore.listing().contains { $0.key == key })
            #expect(BackupStore.pendingTransferKeys().isEmpty)

            #expect(BackupStore.allRollbackPoints()[key]?.purpose == .installRollbackPoint)
            let row = try #require(BackupStore.rollbackPointListing().first { $0.key == key })
            #expect(row.purpose == .installRollbackPoint)
            #expect(row.version == "v1")
            #expect(row.appStillInstalled)
        }
    }

    // MARK: - Lifetime

    /// Kept through everything automatic: an orphan prune (the app being gone
    /// is exactly when it is needed), a stale-scratch sweep, and a later user
    /// backup of the same app. Only settling it with the app readable again —
    /// or the user — removes it.
    @Test func aRollbackPointOutlivesEverySweepAndGoesOnSuccess() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "v1"), route: .homebrew))

            // The install was cut off and the app is gone.
            try FileManager.default.removeItem(at: app)
            BackupStore.pruneOrphans()
            BackupStore.sweepStaleScratch(olderThan: 0)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)

            // Put back by hand and backed up the ordinary way: still there.
            try makeApp(in: apps, marker: "v1")
            try await BackupStore.save(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)

            #expect(await InstallCoordinator.settleInstallRollbackPoint(
                for: installed(app, version: "v1")) == .discarded)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
            #expect(BackupStore.backup(forKey: key) != nil)
        }
    }

    /// Freeing space never deletes one: it is the only way back for an app an
    /// interrupted install may have left broken.
    @Test func reclaimingSpaceSkipsRollbackPoints() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")

            let recovered = await BackupStore.$freeBytesOverride.withValue({ 1 }) {
                await BackupStore.reclaimFreeSpace(sparing: "nobody")
            }
            #expect(!recovered)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
        }
    }

    /// And the other direction: a rollback point nobody asked for does not
    /// delete the user's backups of other apps to make room for itself. A
    /// mid-copy fall under the floor stops the copy instead.
    @Test func aRollbackPointDoesNotDeleteBackupsToMakeRoom() async throws {
        try await withScratch { root, apps in
            let other = try makeApp(
                named: "ZZFixture-Other.app", in: apps, marker: "o1",
                bundleID: "com.example.zzfixture.other")
            let otherKey = BackupStore.key(bundleID: "com.example.zzfixture.other", path: other)
            try await BackupStore.save(
                appPath: other, key: otherKey, version: "o1", bundleID: "com.example.zzfixture.other")

            let app = try makeApp(in: apps, marker: "v1")
            let resources = app.appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            for i in 0..<3000 {
                try Data(repeating: 7, count: 4096).write(to: resources.appendingPathComponent("r\(i).bin"))
            }
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            // Room for the preflight; every read after it is under the floor —
            // and deleting `other` would have bought it back.
            let reads = Counter()
            let floor = BackupStore.freeSpaceFloorBytes
            let gib = self.gib
            var caught: (any Error)?
            do {
                _ = try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                    try await BackupStore.$freeBytesOverride.withValue({
                        let gone = !FileManager.default.fileExists(
                            atPath: root.appendingPathComponent(otherKey).path)
                        return reads.next() == 0 || gone ? floor + 10 * gib : floor - gib
                    }) {
                        try await BackupStore.saveInstallRollbackPoint(
                            appPath: app, key: key, version: "v1",
                            bundleID: "com.example.zzfixture.rollback")
                    }
                }
            } catch {
                caught = error
            }
            guard case .insufficientSpace? = caught as? BackupStore.BackupError else {
                Issue.record("expected insufficientSpace, got \(String(describing: caught))")
                return
            }
            #expect(BackupStore.backup(forKey: otherKey) != nil)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
    }

    // MARK: - Settling at the end of an attempt

    /// The App Store landed the update itself while the row waited, and the
    /// preflight skipped the install: the app reads (at its new version), so
    /// the point taken a moment earlier is let go rather than left to grow
    /// into a full-size copy of a version nothing will ask for.
    @Test func anAttemptThatEndsWithTheAppReadableDiscardsThePoint() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "v1"), route: .appStore))
            try makeApp(in: apps, marker: "v2")  // updated out of band

            #expect(await InstallCoordinator.settleInstallRollbackPoint(
                for: installed(app, version: "v1")) == .discarded)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
        }
    }

    /// A brew download failure: the install threw and never touched the app.
    @Test func aFailureThatLeftTheAppIntactDiscardsThePoint() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "v1"), route: .homebrew))

            #expect(await InstallCoordinator.settleInstallRollbackPoint(
                for: installed(app, version: "v1")) == .discarded)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
        }
    }

    /// brew failed after deleting the app, or after emptying it: exactly what
    /// the point is for, so it stays.
    @Test func aFailureThatLeftTheAppGoneOrEmptiedKeepsThePoint() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "v1"), route: .homebrew))
            try FileManager.default.removeItem(at: app)
            #expect(await InstallCoordinator.settleInstallRollbackPoint(
                for: installed(app, version: "v1")) == .kept)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)

            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
            #expect(await InstallCoordinator.settleInstallRollbackPoint(
                for: installed(app, version: "v1")) == .kept)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
        }
    }

    // MARK: - The sweep

    /// A lock file of the test's own, so the real install lock is never taken.
    private func scratchLock(_ dir: URL) -> (url: URL, lock: ProcessInstallLock) {
        let url = dir.appendingPathComponent("install.lock")
        return (url, ProcessInstallLock(url: url))
    }

    /// Points whose app reads again go; one whose app is still gone stays.
    @Test func theSweepDiscardsPointsWhoseAppReadsAndKeepsTheRest() async throws {
        try await withScratch { root, apps in
            let back = try makeApp(in: apps, marker: "v1")
            let backKey = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: back)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: back, key: backKey, version: "v1", bundleID: "com.example.zzfixture.rollback")
            let gone = try makeApp(
                named: "ZZFixture-Gone.app", in: apps, marker: "g1",
                bundleID: "com.example.zzfixture.gone")
            let goneKey = BackupStore.key(bundleID: "com.example.zzfixture.gone", path: gone)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: gone, key: goneKey, version: "g1", bundleID: "com.example.zzfixture.gone")
            try FileManager.default.removeItem(at: gone)

            let swept = await InstallCoordinator.sweepSettledInstallRollbackPoints(
                lock: scratchLock(root.deletingLastPathComponent()).lock)
            #expect(swept == 1)
            #expect(BackupStore.rollbackPoint(forKey: backKey) == nil)
            #expect(BackupStore.rollbackPoint(forKey: goneKey) != nil)
        }
    }

    /// An install in this process holding its point — taken, not yet settled,
    /// the app still intact because the third party has not started — is not
    /// the sweep's to decide. The shared install lock cannot say so; the claim
    /// does.
    @Test func theSweepLeavesAPointAnInstallIsHolding() async throws {
        try await withScratch { root, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "v1"), route: .homebrew))

            let lock = scratchLock(root.deletingLastPathComponent()).lock
            #expect(await InstallCoordinator.sweepSettledInstallRollbackPoints(lock: lock) == 0)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)

            await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "v1"))
        }
    }

    /// Another process holding the install lock: nothing is swept, and the
    /// answer says so rather than "none to sweep".
    @Test func theSweepStandsDownWhileAnotherProcessHoldsTheLock() async throws {
        try await withScratch { root, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            let (url, lock) = scratchLock(root.deletingLastPathComponent())
            // A separate open file description, as another process's would be.
            let other = try InstallLock.acquire(at: url)
            defer { other.release() }

            #expect(await InstallCoordinator.sweepSettledInstallRollbackPoints(lock: lock) == nil)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
        }
    }

    /// Settings' "on this Mac" total counts them: they are this Mac's disk.
    @Test func thisMacsStoreSizeIncludesRollbackPoints() async throws {
        try await withScratch { root, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            #expect(BackupStore.storeSize(of: root) == 0)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            let point = BackupStore.rollbackPointsRoot.appendingPathComponent(key)
            #expect(BackupStore.storeSize(of: root) == BackupStore.logicalSize(of: point))
            #expect(BackupStore.storeSize(of: root) > 0)
        }
    }

    // MARK: - Which installs take one

    /// Only brew and the App Store — third parties our own death can cut off
    /// mid-swap — and only when no user backup is being taken for this
    /// install: that backup is the rollback point then. Not a `.pkg`:
    /// Installer.app finishes it whatever happens to us, and we never see it
    /// succeed, so a point taken there would never be discarded.
    @Test func onlyThirdPartyRoutesWithoutAUserBackupTakeOne() {
        for route in InstallCoordinator.Route.allCases {
            let thirdParty: Bool
            switch route {
            case .homebrew, .appStore: thirdParty = true
            case .installer, .vendor, .sparkle, .xcode: thirdParty = false
            }
            #expect(InstallCoordinator.wantsInstallRollbackPoint(
                route, takingUserBackup: false) == thirdParty, "\(route)")
            #expect(!InstallCoordinator.wantsInstallRollbackPoint(
                route, takingUserBackup: true), "\(route)")
        }
    }

    // MARK: - Restore

    /// The app vanished (brew deleted it and never moved the new one in):
    /// there is nothing to swap with, so the copy is put where it was.
    @Test func restoringOntoAMissingTargetPutsTheBundleBack() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.save(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            try FileManager.default.removeItem(at: app)

            let restored = try await BackupStore.restore(forKey: key, over: app)
            #expect(restored == "v1")
            #expect(marker(of: app) == "v1")
            // A user backup is left in place after a restore, as it always was.
            #expect(BackupStore.backup(forKey: key) != nil)
            // Nothing left beside it.
            let left = try FileManager.default.contentsOfDirectory(atPath: apps.path)
            #expect(left == [app.lastPathComponent])
        }
    }

    /// The same from a rollback point, which is then done with: the app is
    /// back at the version it holds.
    @Test func restoringARollbackPointPutsItBackAndDropsIt() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            try FileManager.default.removeItem(at: app)

            let outcome = try await BackupStore.restoreReportingUserData(
                forKey: key, over: app, from: .installRollbackPoint)
            #expect(outcome.version == "v1")
            #expect(marker(of: app) == "v1")
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
        }
    }

    /// brew only empties the bundle when the successor has the same name, so
    /// the directory is there with nothing in it — no Info.plist, so nothing
    /// to read an identity from. The ordinary swap still applies.
    @Test func restoringOntoAnEmptiedTargetStillWorks() async throws {
        try await withScratch { _, apps in
            let app = try makeApp(in: apps, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.zzfixture.rollback", path: app)
            try await BackupStore.save(
                appPath: app, key: key, version: "v1", bundleID: "com.example.zzfixture.rollback")
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents"))

            try await BackupStore.restore(forKey: key, over: app)
            #expect(marker(of: app) == "v1")
        }
    }

    // MARK: - Place back, elevated

    /// Which way a place-back goes is the enclosing directory's writability —
    /// there is no bundle to ask about.
    @Test func placingBackIntoAnUnwritableDirectoryNeedsAnAdministrator() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("DuoPlaceBack-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? fm.removeItem(at: dir)
        }
        let target = dir.appendingPathComponent("ZZFixture-Gone.app")
        #expect(!InPlaceSwap.placeBackNeedsElevation(at: target))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        #expect(InPlaceSwap.placeBackNeedsElevation(at: target))
    }

    /// The administrator shell, run here as an ordinary one: it puts the copy
    /// in place when nothing is there, and refuses — leaving no debris — when
    /// something is, rather than `mv` dropping the copy INSIDE an existing
    /// bundle.
    @Test func thePrivilegedPlaceBackShellNeverWritesOverOrIntoABundle() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("DuoPlaceBack-\(UUID().uuidString)/it's here")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        let source = try makeApp(named: "Staged.app", in: dir, marker: "restored")
        let target = dir.appendingPathComponent("ZZFixture-Gone.app")

        let shell = InPlaceSwap.privilegedPlacementShell(newApp: source, target: target)
        #expect(try await run(shell) == 0)
        #expect(marker(of: target) == "restored")
        #expect(marker(of: source) == "restored")

        // Now there is a bundle at the target: refused, and it is untouched.
        try makeApp(named: "ZZFixture-Gone.app", in: dir, marker: "present")
        #expect(try await run(shell) != 0)
        #expect(marker(of: target) == "present")
        #expect(try fm.contentsOfDirectory(atPath: target.path) == ["Contents"])
        #expect(!fm.fileExists(atPath: target.path + ".duoupdater-new"))
    }

    private func run(_ shell: String) async throws -> Int32 {
        try await ChildProcess.run("/bin/sh", ["-c", shell], onCancel: .runToCompletion)
            .terminationStatus
    }
}
