import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// `duo backups list` and the new `duo backups disks`, once more than one
/// backup disk can be read from.
///
/// `BackupStoreDiscovery.scanMountedVolumes()` walks whatever is actually
/// mounted on the machine running the test — which, on a real dev Mac, can
/// include a real backup disk holding real data. `Backups.diskRows(discovered:)`
/// exists so these tests can hand it canned `Found` values instead, the same
/// reason `BackupStoreDiscovery` itself keeps `stores(among:)` separate from
/// `scanMountedVolumes()`.
@Suite struct BackupsDisksTests {

    // MARK: - Fixtures

    /// The outbox, the disk currently being written to, and a disk that was
    /// adopted at some point but is not plugged in right now — the shape
    /// switching disks (or just unplugging one) leaves behind. Each case gets
    /// its own directory tree: Swift Testing runs suites in parallel, and a
    /// fixture name shared across cases has already cost this repo a day of
    /// debugging (see `BackupStoreMultipleDisksTests` in Core).
    private func withDisks(
        _ body: (_ outbox: URL, _ active: URL, _ activeDisk: BackupDestination,
                 _ retiredDisk: BackupDestination) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoKitBackupsDisks-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }

        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        let active = base.appendingPathComponent("active", isDirectory: true)
        for dir in [outbox, active] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try BackupVolumeMarker(identity: "active-id", volumeName: "ActiveDisk").write(to: active)

        let activeDisk = BackupDestination(
            kind: .external, path: active.path, identity: "active-id", volumeName: "ActiveDisk")
        // Never actually created on disk: a disk that used to be adopted but
        // is unplugged right now has no directory a test process can see —
        // that absence is exactly what `.volumeNotMounted` is about.
        let retiredDisk = BackupDestination(
            kind: .external,
            path: base.appendingPathComponent("retired-not-mounted", isDirectory: true).path,
            identity: "retired-id", volumeName: "RetiredDisk")

        try await BackupStore.$rootOverride.withValue(outbox) {
            try await BackupStore.$destinationOverride.withValue(activeDisk) {
                try await BackupStore.$knownDisksOverride.withValue([activeDisk, retiredDisk]) {
                    try await body(outbox, active, activeDisk, retiredDisk)
                }
            }
        }
    }

    @discardableResult
    private func makeApp(named name: String, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let bundle = dir.appendingPathComponent(name)
        try? fm.removeItem(at: bundle)
        try fm.createDirectory(
            at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: bundle.appendingPathComponent("Contents/marker.txt"))
        return bundle
    }

    private func appsDirectory(beside outbox: URL) throws -> URL {
        let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        return apps
    }

    // MARK: - `list` names the disk

    /// A backup that lives on the disk being written to, not this Mac, must
    /// say so by name. "backup disk" as a bare label stopped meaning anything
    /// specific once a second disk could be readable too.
    @Test func listNamesTheDiskABackupIsOn() async throws {
        try await withDisks { outbox, _, _, _ in
            let apps = try appsDirectory(beside: outbox)
            let bundle = try makeApp(named: "Foo.app", in: apps)
            try await BackupStore.save(
                appPath: bundle, key: "foo", version: "1.0", bundleID: "com.example.foo")
            // Only `transferToDestination` ever writes to the active disk —
            // this is what actually puts a copy there rather than in the outbox.
            try await BackupStore.transferToDestination(forKey: "foo")

            let backup = try #require(BackupStore.backup(forKey: "foo"))
            #expect(backup.store.volumeName == "ActiveDisk")

            let rows = Backups.rows(installed: [], backups: BackupStore.allBackups())
            #expect(rows.first?.disk == "ActiveDisk")

            var lines: [String] = []
            Backups.emitText(rows, print: { lines.append($0) })
            #expect(lines.first?.contains("(ActiveDisk)") == true)
        }
    }

    /// A backup still sitting only in the outbox is shown with no disk name —
    /// `nil` reads as "this Mac", not as "unknown".
    @Test func listShowsThisMacForABackupNeverTransferred() async throws {
        try await withDisks { outbox, _, _, _ in
            let apps = try appsDirectory(beside: outbox)
            let bundle = try makeApp(named: "Foo.app", in: apps)
            try await BackupStore.save(
                appPath: bundle, key: "foo", version: "1.0", bundleID: "com.example.foo")

            let rows = Backups.rows(installed: [], backups: BackupStore.allBackups())
            #expect(rows.first?.disk == nil)

            var lines: [String] = []
            Backups.emitText(rows, print: { lines.append($0) })
            #expect(lines.first?.contains("(this Mac)") == true)
        }
    }

    // MARK: - `disks`

    /// The whole point of the subcommand: a disk that was adopted before but
    /// is not plugged in right now must still appear, marked as not connected
    /// — not silently dropped, which is what `list`/`verify` already do for a
    /// disk that isn't part of the picture right now.
    @Test func aKnownButUnpluggedDiskIsListedAsNotConnected() async throws {
        try await withDisks { _, _, _, _ in
            let rows = await Backups.diskRows(discovered: [])
            let retired = try #require(rows.first { $0.name == "RetiredDisk" })
            #expect(retired.status == "notMounted")
            #expect(retired.isActive == false)
            #expect(retired.bytes == nil)
        }
    }

    /// This Mac is always the first row, with the bytes it holds — never
    /// dropped just because an external disk is also configured.
    @Test func thisMacIsAlwaysFirstAndCarriesItsSize() async throws {
        try await withDisks { outbox, _, _, _ in
            let apps = try appsDirectory(beside: outbox)
            let bundle = try makeApp(named: "Foo.app", in: apps)
            try await BackupStore.save(
                appPath: bundle, key: "foo", version: "1.0", bundleID: "com.example.foo")

            let rows = await Backups.diskRows(discovered: [])
            let thisMac = try #require(rows.first)
            #expect(thisMac.name == "This Mac")
            #expect(thisMac.isThisMac)
            #expect((thisMac.bytes ?? 0) > 0)
        }
    }

    /// The disk currently being written to is marked active; the retired one
    /// is not, even though both are known.
    @Test func theActiveDiskIsMarkedAsSuch() async throws {
        try await withDisks { _, _, _, _ in
            let rows = await Backups.diskRows(discovered: [])
            #expect(rows.first { $0.name == "ActiveDisk" }?.isActive == true)
            #expect(rows.first { $0.name == "RetiredDisk" }?.isActive == false)
        }
    }

    /// A disk found holding our marker that Settings never adopted is listed
    /// too, distinctly from a known-but-unplugged one — it is a candidate to
    /// offer, not a disk already in the rotation.
    @Test func aDiscoveredButUnadoptedDiskIsListedSeparately() async throws {
        try await withDisks { _, _, _, _ in
            let found = BackupStoreDiscovery.Found(
                root: URL(fileURLWithPath: "/Volumes/Stranger/DuoUpdater Backups"),
                marker: BackupVolumeMarker(identity: "stranger-id", volumeName: "StrangerDisk"),
                volumeName: "StrangerDisk", isOnBootVolume: false)

            let rows = await Backups.diskRows(discovered: [found])
            let stranger = try #require(rows.first { $0.name == "StrangerDisk" })
            #expect(stranger.status == "notConfigured")
            #expect(stranger.bytes == nil)
            #expect(stranger.isActive == false)
        }
    }

    /// A disk `scanMountedVolumes()` finds that is already known (adopted, and
    /// currently readable) must not be listed a second time under
    /// "notConfigured" just because it also shows up in the mounted-volume scan.
    @Test func aKnownDiskFoundAgainByTheScanIsNotDuplicated() async throws {
        try await withDisks { _, active, _, _ in
            let found = BackupStoreDiscovery.Found(
                root: active, marker: BackupVolumeMarker(identity: "active-id", volumeName: "ActiveDisk"),
                volumeName: "ActiveDisk", isOnBootVolume: false)

            let rows = await Backups.diskRows(discovered: [found])
            #expect(rows.filter { $0.name == "ActiveDisk" }.count == 1)
        }
    }
}
