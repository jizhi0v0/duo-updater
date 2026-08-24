import Foundation
import Testing

@testable import DuoUpdaterCore

/// Moving a backup from the local outbox onto the external disk: that it lands
/// intact, that the local copy is only dropped once it has, and that a disk
/// which is not there costs a delay rather than a rollback point.
@Suite struct BackupTransferQueueTests {

    // MARK: - Fixtures

    private struct Stores {
        let base: URL
        let outbox: URL
        let destination: URL
        let apps: URL
    }

    private func makeStores(mountDisk: Bool = true) throws -> Stores {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoTransferTest-\(UUID().uuidString)", isDirectory: true)
        let stores = Stores(
            base: base,
            outbox: base.appendingPathComponent("outbox", isDirectory: true),
            destination: base.appendingPathComponent("disk", isDirectory: true),
            apps: base.appendingPathComponent("apps", isDirectory: true))
        try fm.createDirectory(at: stores.outbox, withIntermediateDirectories: true)
        try fm.createDirectory(at: stores.apps, withIntermediateDirectories: true)
        if mountDisk {
            try fm.createDirectory(at: stores.destination, withIntermediateDirectories: true)
            try BackupVolumeMarker(identity: "disk-1", volumeName: "TestDisk")
                .write(to: stores.destination)
        }
        return stores
    }

    private func destination(_ stores: Stores) -> BackupDestination {
        BackupDestination(
            kind: .external, path: stores.destination.path,
            identity: "disk-1", volumeName: "TestDisk")
    }

    private func withStores(
        mountDisk: Bool = true, _ body: (Stores) async throws -> Void
    ) async throws {
        let stores = try makeStores(mountDisk: mountDisk)
        defer { try? FileManager.default.removeItem(at: stores.base) }
        try await BackupStore.$rootOverride.withValue(stores.outbox) {
            try await BackupStore.$destinationOverride.withValue(destination(stores)) {
                try await body(stores)
            }
        }
    }

    @discardableResult
    private func makeApp(named name: String, in dir: URL, marker: String) throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? fm.removeItem(at: app)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>com.example.testapp</string>
          <key>CFBundleName</key><string>App</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    @discardableResult
    private func saveBackup(
        _ stores: Stores, key: String, appName: String = "App.app", marker: String = "v1"
    ) throws -> URL {
        let app = try makeApp(named: appName, in: stores.apps, marker: marker)
        try BackupStore.save(
            appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")
        return app
    }

    // MARK: - The transfer itself

    @Test func aTransferLandsTheArchiveAndDropsTheLocalCopy() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "k")
            #expect(BackupStore.pendingTransferKeys() == ["k"])

            let moved = try BackupStore.transferToDestination(forKey: "k")
            #expect(moved.location == .destination)
            #expect(moved.bundlePath.lastPathComponent == "App.aar")

            let fm = FileManager.default
            #expect(fm.fileExists(atPath: moved.bundlePath.path))
            #expect(fm.fileExists(
                atPath: stores.destination.appendingPathComponent("k/backup.json").path))
            #expect(!fm.fileExists(atPath: stores.outbox.appendingPathComponent("k").path),
                    "the local copy should be gone once the disk has it")
            #expect(BackupStore.pendingTransferKeys().isEmpty)
            #expect(BackupStore.backup(forKey: "k")?.location == .destination)
        }
    }

    /// The end-to-end claim the whole design rests on: a backup that has been
    /// through compression, a foreign filesystem and back still restores.
    @Test func aTransferredBackupStillRestores() async throws {
        try await withStores { stores in
            let app = try saveBackup(stores, key: "k", marker: "v1")
            try BackupStore.transferToDestination(forKey: "k")

            try makeApp(named: "App.app", in: stores.apps, marker: "v2")
            #expect(marker(of: app) == "v2")

            let version = try BackupStore.restore(forKey: "k", over: app)
            #expect(version == "1.0")
            #expect(marker(of: app) == "v1")
        }
    }

    /// Nothing is created and nothing is lost when the disk is not there — the
    /// backup simply stays owed.
    @Test func aTransferWithNoDiskTouchesNothing() async throws {
        try await withStores(mountDisk: false) { stores in
            try saveBackup(stores, key: "k")

            #expect(throws: BackupStore.BackupError.self) {
                try BackupStore.transferToDestination(forKey: "k")
            }
            let fm = FileManager.default
            #expect(!fm.fileExists(atPath: stores.destination.path),
                    "a refused transfer must not conjure the destination")
            #expect(fm.fileExists(atPath: stores.outbox.appendingPathComponent("k").path))
            #expect(BackupStore.backup(forKey: "k")?.location == .outbox)
            #expect(BackupStore.pendingTransferKeys() == ["k"],
                    "the copy is still owed")
        }
    }

    /// The digest recorded at transfer time is read back off the destination, so
    /// it certifies what actually landed — and a later corruption is caught
    /// before anything is swapped over a working app.
    @Test func aCorruptedArchiveIsCaughtOnRestore() async throws {
        try await withStores { stores in
            let app = try saveBackup(stores, key: "k", marker: "v1")
            let moved = try BackupStore.transferToDestination(forKey: "k")

            var bytes = try Data(contentsOf: moved.bundlePath)
            bytes[bytes.count - 1] ^= 0xFF
            try bytes.write(to: moved.bundlePath)

            try makeApp(named: "App.app", in: stores.apps, marker: "v2")
            #expect(throws: BackupStore.BackupError.self) {
                _ = try BackupStore.restore(forKey: "k", over: app)
            }
            #expect(marker(of: app) == "v2", "a refused rollback must leave the app alone")
        }
    }

    /// A directory `save` left behind when it refused a bundle is not a backup,
    /// and must never enter the queue. Real remnants on a real machine: ToDesk
    /// and VSCodium keep root-owned state inside their own bundles, so `save`
    /// declines them and leaves the directory.
    @Test func aRemnantWithNoSidecarIsNotOwed() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "good")
            let remnant = stores.outbox.appendingPathComponent("junk", isDirectory: true)
            try FileManager.default.createDirectory(
                at: remnant.appendingPathComponent("ToDesk.app"),
                withIntermediateDirectories: true)

            #expect(BackupStore.pendingTransferKeys() == ["good"])
        }
    }

    /// **One bad item must not hold up the rest.** A single key that can never
    /// transfer used to end the whole run, leaving every remaining backup on the
    /// boot volume — the exact opposite of what moving the store is for.
    @Test func oneFailingKeyDoesNotStrandTheOthers() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "a", appName: "A.app")
            try saveBackup(stores, key: "b", appName: "B.app")

            let queue = BackupTransferQueue(maxAttempts: 2, backoffUnitNanos: 1_000)
            // Poison first, so a run that stops on failure moves nothing at all.
            await queue.enqueue("nope")
            await queue.enqueue("a")
            await queue.enqueue("b")
            await queue.drain()

            #expect(BackupStore.backup(forKey: "a")?.location == .destination)
            #expect(BackupStore.backup(forKey: "b")?.location == .destination)
            // And the failure is still reported rather than swallowed.
            guard case .failed(_, _, let count) = await queue.state else {
                Issue.record("expected .failed, got \(await queue.state)")
                return
            }
            #expect(count == 1)
        }
    }

    /// A backup taken **before** the disk was ever configured is still owed to
    /// it. Filtering on a flag written at save time meant the backups someone
    /// already had — the ones taking up the space they were trying to reclaim —
    /// would never move.
    @Test func backupsTakenBeforeTheDiskWasChosenStillMove() async throws {
        let stores = try makeStores()
        defer { try? FileManager.default.removeItem(at: stores.base) }

        // Saved while backups were still local: no destination configured, so
        // nothing marks this one as owed.
        try await BackupStore.$rootOverride.withValue(stores.outbox) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try saveBackup(stores, key: "old")
                #expect(BackupStore.pendingTransferKeys().isEmpty)
            }
        }

        // The user then points the store at a disk.
        try await BackupStore.$rootOverride.withValue(stores.outbox) {
            try await BackupStore.$destinationOverride.withValue(destination(stores)) {
                #expect(BackupStore.pendingTransferKeys() == ["old"])

                let queue = BackupTransferQueue(backoffUnitNanos: 1_000)
                await queue.resumePending()
                await queue.drain()

                #expect(await queue.state == .idle)
                #expect(BackupStore.backup(forKey: "old")?.location == .destination)
                #expect(!FileManager.default.fileExists(
                    atPath: stores.outbox.appendingPathComponent("old").path))
            }
        }
    }

    // MARK: - The queue

    @Test func theQueueDrainsEverythingOwed() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "a", appName: "A.app")
            try saveBackup(stores, key: "b", appName: "B.app")

            let queue = BackupTransferQueue(backoffUnitNanos: 1_000)
            await queue.resumePending()
            await queue.drain()

            #expect(await queue.state == .idle)
            #expect(BackupStore.pendingTransferKeys().isEmpty)
            #expect(BackupStore.backup(forKey: "a")?.location == .destination)
            #expect(BackupStore.backup(forKey: "b")?.location == .destination)
        }
    }

    /// An absent disk suspends the queue instead of failing it, and — the part
    /// that matters — does not consume the retry budget. A disk in a bag stays
    /// in a bag for longer than five backoffs, and a transfer that had already
    /// "failed" by the time it was plugged back in would never be picked up.
    @Test func aMissingDiskSuspendsRatherThanFails() async throws {
        try await withStores(mountDisk: false) { stores in
            try saveBackup(stores, key: "k")

            let queue = BackupTransferQueue(backoffUnitNanos: 1_000)
            await queue.resumePending()
            await queue.drain()

            #expect(await queue.state == .waitingForDisk(pending: 1))
            #expect(BackupStore.pendingTransferKeys() == ["k"])
            #expect(BackupStore.backup(forKey: "k")?.location == .outbox)
        }
    }

    /// And once the disk shows up, the same queue finishes the job.
    @Test func aSuspendedQueueFinishesWhenTheDiskAppears() async throws {
        let stores = try makeStores(mountDisk: false)
        defer { try? FileManager.default.removeItem(at: stores.base) }

        try await BackupStore.$rootOverride.withValue(stores.outbox) {
            try await BackupStore.$destinationOverride.withValue(destination(stores)) {
                try saveBackup(stores, key: "k")
                let queue = BackupTransferQueue(backoffUnitNanos: 1_000)
                await queue.resumePending()
                await queue.drain()
                #expect(await queue.state == .waitingForDisk(pending: 1))

                // The disk is plugged in.
                try FileManager.default.createDirectory(
                    at: stores.destination, withIntermediateDirectories: true)
                try BackupVolumeMarker(identity: "disk-1", volumeName: "TestDisk")
                    .write(to: stores.destination)

                await queue.drain()
                #expect(await queue.state == .idle)
                #expect(BackupStore.backup(forKey: "k")?.location == .destination)
            }
        }
    }

    /// A transfer that keeps failing while the disk is right there does exhaust
    /// its attempts and reports — that is what the retry budget is for.
    @Test func aTransferThatKeepsFailingIsReported() async throws {
        try await withStores { _ in
            let queue = BackupTransferQueue(maxAttempts: 2, backoffUnitNanos: 1_000)
            await queue.enqueue("no-such-key")
            await queue.drain()

            guard case .failed(let key, _, _) = await queue.state else {
                Issue.record("expected .failed, got \(await queue.state)")
                return
            }
            #expect(key == "no-such-key")
        }
    }

    @Test func enqueuingTheSameKeyTwiceOnlyCopiesItOnce() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "k")
            let queue = BackupTransferQueue(backoffUnitNanos: 1_000)
            await queue.enqueue("k")
            await queue.enqueue("k")
            await queue.drain()
            #expect(await queue.state == .idle)
        }
    }

    // MARK: - Sweeping interrupted work

    @Test func staleScratchIsSweptFromBothStores() async throws {
        try await withStores { stores in
            let fm = FileManager.default
            let old = Date().addingTimeInterval(-48 * 60 * 60)

            // A save that never finished, in the outbox.
            let staging = stores.outbox.appendingPathComponent(".staging-k", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: staging.path)

            // A transfer that never finished, on the disk: the `.partial` lives
            // inside the key's own directory.
            let keyDir = stores.destination.appendingPathComponent("k", isDirectory: true)
            try fm.createDirectory(at: keyDir, withIntermediateDirectories: true)
            let partial = keyDir.appendingPathComponent(".App.aar.partial")
            try Data("half".utf8).write(to: partial)
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: partial.path)

            BackupStore.sweepStaleScratch()

            #expect(!fm.fileExists(atPath: staging.path))
            #expect(!fm.fileExists(atPath: partial.path))
        }
    }

    @Test func recentScratchIsLeftAlone() async throws {
        try await withStores { stores in
            let fm = FileManager.default
            let staging = stores.outbox.appendingPathComponent(".staging-k", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)

            BackupStore.sweepStaleScratch()
            #expect(fm.fileExists(atPath: staging.path),
                    "scratch from a transfer still running must survive")
        }
    }

    /// mtime is the backstop, not the guard. A slow disk makes an in-flight
    /// `.partial` legitimately old, and a network volume's timestamps come from
    /// the server's clock, so the key a queue says is running is excluded
    /// regardless of what its mtime claims.
    @Test func inFlightScratchSurvivesEvenWhenItLooksStale() async throws {
        try await withStores { stores in
            let fm = FileManager.default
            let staging = stores.outbox.appendingPathComponent(".staging-k", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-48 * 60 * 60)],
                ofItemAtPath: staging.path)

            BackupStore.sweepStaleScratch(excluding: ["k"])
            #expect(fm.fileExists(atPath: staging.path))
        }
    }

    /// The shape that actually accumulated on a real machine: a key directory in
    /// the outbox holding a whole app bundle and **no sidecar**. `save` leaves
    /// one behind when it refuses a bundle it cannot fully read, and nothing
    /// could see it afterwards — `backup(forKey:)` needs the sidecar,
    /// `pruneOrphans` needs it to know which app the backup was for, and the
    /// delete sheet is the only place it showed up at all. Hundreds of megabytes
    /// per remnant, on the very disk the user moved the store off.
    @Test func aSidecarLessDirectoryInTheOutboxIsSwept() async throws {
        try await withStores { stores in
            let fm = FileManager.default
            let remnant = stores.outbox.appendingPathComponent("com.example.dead", isDirectory: true)
            try fm.createDirectory(at: remnant, withIntermediateDirectories: true)
            try makeApp(named: "Dead.app", in: remnant, marker: "x")
            try fm.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-48 * 60 * 60)],
                ofItemAtPath: remnant.path)

            BackupStore.sweepStaleScratch()
            #expect(!fm.fileExists(atPath: remnant.path))
        }
    }

    /// The same directory while a transfer is working on it is not a remnant.
    /// Between `createDirectory` and the sidecar write, a key directory on the
    /// destination legitimately has no sidecar for as long as the archive takes —
    /// minutes on a slow disk — so the in-flight key must win over mtime here too.
    @Test func aSidecarLessDirectoryInFlightIsLeftAlone() async throws {
        try await withStores { stores in
            let fm = FileManager.default
            let dir = stores.destination.appendingPathComponent("k", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-48 * 60 * 60)],
                ofItemAtPath: dir.path)

            BackupStore.sweepStaleScratch(excluding: ["k"])
            #expect(fm.fileExists(atPath: dir.path))
        }
    }

    /// The sweeper must never touch a finished backup, only scratch.
    @Test func sweepingLeavesRealBackupsAlone() async throws {
        try await withStores { stores in
            try saveBackup(stores, key: "k")
            try BackupStore.transferToDestination(forKey: "k")

            BackupStore.sweepStaleScratch(olderThan: 0)

            #expect(BackupStore.backup(forKey: "k")?.location == .destination)
            #expect(FileManager.default.fileExists(
                atPath: stores.destination.appendingPathComponent("k/App.aar").path))
        }
    }
}
