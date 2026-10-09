import Testing
import Foundation
@testable import DuoUpdaterCore

/// The free-space floor on this Mac: a backup that would cross it is skipped
/// before it starts, and one that finds the disk falling under it mid-copy
/// deletes this Mac's oldest backups to get back over — and gives up its own
/// copy when there is nothing left to delete.
///
/// Free space is never read from the real disk here: `freeBytesOverride`
/// stands in for the volume, and goes up by a fixed amount whenever a backup
/// directory disappears from the scratch outbox, which is what deleting one
/// does to a real one.
@Suite(.serialized)
struct BackupStoreSpaceTests {

    /// A pretend volume: `base` free, plus `perRemoved` for every backup
    /// directory that has gone missing from `root` since it was made.
    final class Volume: @unchecked Sendable {
        private let lock = NSLock()
        private let root: URL
        private let initial: Set<String>
        private var base: Int64
        private let perRemoved: Int64
        private(set) var reads = 0

        init(root: URL, base: Int64, perRemoved: Int64) {
            self.root = root
            self.base = base
            self.perRemoved = perRemoved
            self.initial = Self.keys(in: root)
        }

        static func keys(in root: URL) -> Set<String> {
            Set(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
                .filter { !$0.hasPrefix(".") })
        }

        func setBase(_ bytes: Int64) { lock.withLock { base = bytes } }

        func free() -> Int64 {
            let gone = Int64(initial.subtracting(Self.keys(in: root)).count)
            return lock.withLock {
                reads += 1
                return base + gone * perRemoved
            }
        }
    }

    private let gib: Int64 = 1 << 30

    private func withScratch(_ body: (URL, URL) async throws -> Void) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdaterSpaceTest-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("Backups")
        let facts = scratch.appendingPathComponent("Facts")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await BackupStore.$rootOverride.withValue(root) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try await BackupFactsLibrary.$rootOverride.withValue(facts) {
                    try await body(scratch, root)
                }
            }
        }
    }

    @discardableResult
    private func makeApp(
        named name: String, in dir: URL, bundleID: String, files: Int = 0
    ) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try plist.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))
        if files > 0 {
            let resources = contents.appendingPathComponent("Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let payload = Data(repeating: 7, count: 4096)
            for i in 0..<files {
                try payload.write(to: resources.appendingPathComponent("r\(i).bin"))
            }
        }
        return app
    }

    /// Store a backup for `name`, dated `savedAt` seconds ago so the order
    /// of the oldest-first sweep is fixed by the test, not by the clock.
    @discardableResult
    private func storeBackup(
        _ name: String, in scratch: URL, root: URL, ageSeconds: TimeInterval
    ) async throws -> String {
        let app = try makeApp(
            named: "\(name).app", in: scratch, bundleID: "com.example.\(name.lowercased())")
        let key = BackupStore.key(bundleID: "com.example.\(name.lowercased())", path: app)
        _ = try await BackupStore.save(
            appPath: app, key: key, version: "1.0", bundleID: "com.example.\(name.lowercased())")
        let sidecar = root.appendingPathComponent(key).appendingPathComponent("backup.json")
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
        let saved = Date().addingTimeInterval(-ageSeconds)
        json["savedAt"] = saved.timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: json).write(to: sidecar)
        return key
    }

    // MARK: - Before the copy

    @Test func skipsBeforeCopyingWhenTheCopyWouldCrossTheFloor() async throws {
        try await withScratch { scratch, root in
            let app = try makeApp(named: "Big.app", in: scratch, bundleID: "com.example.big")
            let key = BackupStore.key(bundleID: "com.example.big", path: app)
            // A few bytes short of floor + bundle.
            let free = BackupStore.freeSpaceFloorBytes + 10
            await #expect(throws: BackupStore.BackupError.self) {
                try await BackupStore.$freeBytesOverride.withValue({ free }) {
                    _ = try await BackupStore.save(
                        appPath: app, key: key, version: "1.0", bundleID: "com.example.big")
                }
            }
            #expect(BackupStore.backup(forKey: key) == nil)
            // No staging left behind, and nothing else was touched.
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).isEmpty)
        }
    }

    @Test func coordinatorReportsLowSpaceAsItsOwnOutcome() async throws {
        try await withScratch { scratch, _ in
            let app = try makeApp(named: "Big.app", in: scratch, bundleID: "com.example.big")
            let installed = InstalledApp(
                name: "Big", bundleID: "com.example.big", shortVersion: "1.0",
                buildVersion: "1", path: app, isMASApp: false, sparkleFeedURL: nil)
            let outcome = await BackupStore.$freeBytesOverride.withValue({ 0 }) {
                await InstallCoordinator.backUp(installed, route: .sparkle)
            }
            #expect(outcome == .insufficientSpace)
        }
    }

    @Test func savesWhenThereIsRoomAboveTheFloor() async throws {
        try await withScratch { scratch, _ in
            let app = try makeApp(named: "Small.app", in: scratch, bundleID: "com.example.small")
            let key = BackupStore.key(bundleID: "com.example.small", path: app)
            let free = BackupStore.freeSpaceFloorBytes + gib
            _ = try await BackupStore.$freeBytesOverride.withValue({ free }) {
                try await BackupStore.save(
                    appPath: app, key: key, version: "1.0", bundleID: "com.example.small")
            }
            #expect(BackupStore.backup(forKey: key) != nil)
        }
    }

    // MARK: - Mid-copy reclaim

    @Test func reclaimDeletesOldestFirstAndStopsOnceBackOverTheFloor() async throws {
        try await withScratch { scratch, root in
            let oldest = try await storeBackup("Oldest", in: scratch, root: root, ageSeconds: 3000)
            let middle = try await storeBackup("Middle", in: scratch, root: root, ageSeconds: 2000)
            let newest = try await storeBackup("Newest", in: scratch, root: root, ageSeconds: 1000)
            // Two deletions' worth short of the floor.
            let volume = Volume(
                root: root, base: BackupStore.freeSpaceFloorBytes - 2 * gib + 1, perRemoved: gib)
            let recovered = await BackupStore.$freeBytesOverride.withValue({ volume.free() }) {
                await BackupStore.reclaimFreeSpace(sparing: "nobody")
            }
            #expect(recovered)
            let left = Volume.keys(in: root)
            #expect(!left.contains(oldest))
            #expect(!left.contains(middle))
            #expect(left.contains(newest))
        }
    }

    @Test func reclaimNeverDeletesTheAppBeingBackedUp() async throws {
        try await withScratch { scratch, root in
            let spared = try await storeBackup("Spared", in: scratch, root: root, ageSeconds: 9000)
            let other = try await storeBackup("Other", in: scratch, root: root, ageSeconds: 1000)
            let volume = Volume(root: root, base: 0, perRemoved: gib)
            let recovered = await BackupStore.$freeBytesOverride.withValue({ volume.free() }) {
                await BackupStore.reclaimFreeSpace(sparing: spared)
            }
            // Nothing left that it may delete, and still under the floor.
            #expect(!recovered)
            let left = Volume.keys(in: root)
            #expect(left.contains(spared))
            #expect(!left.contains(other))
        }
    }

    @Test func reclaimDeletesNothingWhileAboveTheFloor() async throws {
        try await withScratch { scratch, root in
            let key = try await storeBackup("Keep", in: scratch, root: root, ageSeconds: 1000)
            let free = BackupStore.freeSpaceFloorBytes
            let recovered = await BackupStore.$freeBytesOverride.withValue({ free }) {
                await BackupStore.reclaimFreeSpace(sparing: "nobody")
            }
            #expect(recovered)
            #expect(Volume.keys(in: root).contains(key))
        }
    }

    /// The oldest backup finishes its copy to the backup disk while the
    /// reclaim waits for it: by then it is off this Mac, which gave the space
    /// back, and its facts describe the copy on the disk. It is skipped, not
    /// counted as deleted, and its facts stay.
    @Test func aBackupMovedToTheDiskDuringTheWaitKeepsItsFacts() async throws {
        try await withScratch { scratch, root in
            let moved = try await storeBackup("Moved", in: scratch, root: root, ageSeconds: 9000)
            let newer = try await storeBackup("Newer", in: scratch, root: root, ageSeconds: 1000)
            let facts = BackupFactsLibrary.directory(forKey: moved)
            try FileManager.default.createDirectory(at: facts, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: facts.appendingPathComponent("entry.json"))
            let volume = Volume(
                root: root, base: BackupStore.freeSpaceFloorBytes - gib, perRemoved: 2 * gib)
            let recovered = await BackupStore.$reclaimAfterWithholdOverride.withValue({ key in
                // The transfer's last step: the outbox copy goes.
                if key == moved {
                    try? FileManager.default.removeItem(at: root.appendingPathComponent(key))
                }
            }) {
                await BackupStore.$freeBytesOverride.withValue({ volume.free() }) {
                    await BackupStore.reclaimFreeSpace(sparing: "nobody")
                }
            }
            #expect(recovered)
            #expect(FileManager.default.fileExists(atPath: facts.path))
            #expect(Volume.keys(in: root).contains(newer))
        }
    }

    /// End to end through `save`: the disk is fine when the copy starts and
    /// falls under the floor while `ditto` runs. The older backup is deleted
    /// to make room and the new copy still lands.
    @Test func midCopyFallIsAnsweredByDeletingAnOlderBackup() async throws {
        try await withScratch { scratch, root in
            let older = try await storeBackup("Older", in: scratch, root: root, ageSeconds: 5000)
            let app = try makeApp(
                named: "Busy.app", in: scratch, bundleID: "com.example.busy", files: 3000)
            let key = BackupStore.key(bundleID: "com.example.busy", path: app)
            let volume = Volume(
                root: root, base: BackupStore.freeSpaceFloorBytes + 10 * gib, perRemoved: 20 * gib)
            // Room for the preflight; the very first watch tick finds it gone.
            let saved = try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                try await BackupStore.$freeBytesOverride.withValue({
                    let now = volume.free()
                    volume.setBase(BackupStore.freeSpaceFloorBytes - gib)
                    return now
                }) {
                    try await BackupStore.save(
                        appPath: app, key: key, version: "1.0", bundleID: "com.example.busy")
                }
            }
            #expect(saved.key == key)
            let left = Volume.keys(in: root)
            #expect(!left.contains(older))
            #expect(left.contains(key))
        }
    }

    /// The same fall with nothing older to delete: the copy is stopped, no
    /// staging is left, and the error says it was space.
    @Test func midCopyFallWithNothingToDeleteStopsTheCopy() async throws {
        try await withScratch { scratch, root in
            let app = try makeApp(
                named: "Busy.app", in: scratch, bundleID: "com.example.busy", files: 3000)
            let key = BackupStore.key(bundleID: "com.example.busy", path: app)
            let volume = Volume(root: root, base: BackupStore.freeSpaceFloorBytes + 10 * gib, perRemoved: 0)
            var caught: (any Error)?
            do {
                _ = try await BackupStore.$spaceWatchIntervalOverride.withValue(.milliseconds(1)) {
                    try await BackupStore.$freeBytesOverride.withValue({
                        let now = volume.free()
                        volume.setBase(BackupStore.freeSpaceFloorBytes - gib)
                        return now
                    }) {
                        try await BackupStore.save(
                            appPath: app, key: key, version: "1.0", bundleID: "com.example.busy")
                    }
                }
            } catch {
                caught = error
            }
            guard case .insufficientSpace? = caught as? BackupStore.BackupError else {
                Issue.record("expected insufficientSpace, got \(String(describing: caught))")
                return
            }
            #expect(BackupStore.backup(forKey: key) == nil)
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).isEmpty)
        }
    }

    // MARK: - The walk that sizes it

    @Test func unreadableFilesWalkAlsoTotalsTheBundle() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdaterSpaceTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let app = try makeApp(named: "Sized.app", in: scratch, bundleID: "com.example.sized", files: 10)
        let plist = try FileManager.default.attributesOfItem(
            atPath: app.appendingPathComponent("Contents/Info.plist").path)[.size] as? Int64 ?? 0
        #expect(BackupManifest.unreadableFiles(in: app).bytes == 10 * 4096 + plist)
    }
}

/// Backups are off unless chosen; a Mac that finished onboarding before the
/// choice existed keeps them on.
@Suite(.serialized) struct KeepBackupsDefaultTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "com.duoupdater.tests.keepbackups"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func offForANewUser() {
        withDefaults { #expect(UpdateSettings.keepBackups(in: $0) == false) }
    }

    @Test func onForAUserWhoOnboardedBeforeTheChoiceExisted() {
        withDefaults {
            $0.set(true, forKey: UpdateSettings.hasCompletedOnboardingKey)
            #expect(UpdateSettings.keepBackups(in: $0) == true)
        }
    }

    @Test func anExplicitChoiceWins() {
        withDefaults {
            $0.set(true, forKey: UpdateSettings.hasCompletedOnboardingKey)
            $0.set(false, forKey: UpdateSettings.keepBackupsKey)
            #expect(UpdateSettings.keepBackups(in: $0) == false)
        }
        withDefaults {
            $0.set(true, forKey: UpdateSettings.keepBackupsKey)
            #expect(UpdateSettings.keepBackups(in: $0) == true)
        }
    }
}
