import Foundation
import Testing

@testable import DuoUpdaterCore

/// How a configured backup destination survives a trip through UserDefaults, and
/// how a destination proves which disk it is.
///
/// Worth testing at this level because both products resolve this independently:
/// the menu bar app and `duo backups` read the same keys out of the same suite,
/// and a disagreement between them would not surface as an error. Each would
/// simply use a different store, and the first sign of it would be a rollback
/// offered in one place and absent in the other.
@Suite struct BackupDestinationTests {

    /// A private, empty defaults suite — never `.standard`, which would read and
    /// write the developer's real preferences.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "BackupDestinationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func scratch() -> URL {
        // UUID-suffixed: several worktrees of this repo run `swift test`
        // concurrently against the same $TMPDIR.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoBackupDestTest-\(UUID().uuidString)")
    }

    // MARK: - Persistence

    @Test func nothingConfiguredMeansLocal() throws {
        try withDefaults { defaults in
            #expect(BackupDestination.load(from: defaults) == .local)
        }
    }

    @Test func anExternalDestinationRoundTrips() throws {
        try withDefaults { defaults in
            let destination = BackupDestination(
                kind: .external, path: "/Volumes/Archive/DuoBackups",
                identity: "F1E2D3C4", volumeName: "Archive")
            destination.save(into: defaults)
            #expect(BackupDestination.load(from: defaults) == destination)
        }
    }

    /// Going back to local is a switch, not an erasure: the disk stays
    /// remembered so turning it on again is one click rather than another trip
    /// through a file picker.
    @Test func goingBackToLocalStillRemembersTheDisk() throws {
        try withDefaults { defaults in
            let disk = BackupDestination(
                kind: .external, path: "/Volumes/Archive", identity: "OLD", volumeName: "Archive")
            disk.save(into: defaults)
            BackupDestination.local.save(into: defaults)

            #expect(BackupDestination.load(from: defaults) == .local, "backups go local")
            #expect(BackupDestination.remembered(from: defaults) == disk, "but the disk is kept")

            // And switching back needs nothing but the switch.
            disk.save(into: defaults)
            #expect(BackupDestination.load(from: defaults) == disk)
        }
    }

    /// Choosing a different folder replaces what was remembered — a stale
    /// identity matched against the new folder would read as a different disk.
    @Test func choosingAnotherFolderReplacesWhatIsRemembered() throws {
        try withDefaults { defaults in
            BackupDestination(kind: .external, path: "/Volumes/A", identity: "A").save(into: defaults)
            let second = BackupDestination(kind: .external, path: "/Volumes/B", identity: "B")
            second.save(into: defaults)
            #expect(BackupDestination.remembered(from: defaults) == second)
        }
    }

    /// Anyone who configured a disk before the switch existed must keep it. A
    /// missing flag read as `false` would have turned their store local
    /// silently, which looks exactly like never having moved it.
    @Test func aDiskConfiguredBeforeTheSwitchExistedStaysOn() throws {
        try withDefaults { defaults in
            // Exactly what an older build wrote: the location, and no flag.
            defaults.set("/Volumes/Archive", forKey: UpdateSettings.backupDestinationPathKey)
            defaults.set("OLD", forKey: UpdateSettings.backupDestinationIdentityKey)

            let loaded = BackupDestination.load(from: defaults)
            #expect(loaded.kind == .external)
            #expect(loaded.path == "/Volumes/Archive")
        }
    }

    /// An empty string is not a destination. Without this it would resolve to
    /// `URL(fileURLWithPath: "")`, which is the current directory — a place
    /// backups must never be written.
    @Test func anEmptyPathReadsAsLocal() throws {
        try withDefaults { defaults in
            defaults.set("", forKey: UpdateSettings.backupDestinationPathKey)
            #expect(BackupDestination.load(from: defaults) == .local)
        }
    }

    /// A path configured before the marker was written is legitimate — it reads
    /// as "not verified yet", which is a different state from "matches".
    @Test func anExternalPathWithoutAnIdentityStillLoads() throws {
        try withDefaults { defaults in
            defaults.set("/Volumes/Archive", forKey: UpdateSettings.backupDestinationPathKey)
            let loaded = BackupDestination.load(from: defaults)
            #expect(loaded.kind == .external)
            #expect(loaded.identity == nil)
        }
    }

    // MARK: - directory

    @Test func localHasNoDirectory() {
        #expect(BackupDestination.local.directory == nil)
    }

    @Test func externalResolvesItsDirectoryWithoutTouchingTheDisk() {
        let path = "/Volumes/Definitely Not Mounted \(UUID().uuidString)/Backups"
        let directory = BackupDestination(kind: .external, path: path).directory
        #expect(directory?.path == path)
        // Resolving must not have created it: conflating "configured" with
        // "reachable" is how a detached disk turns into a directory quietly
        // created on the boot volume, which then squats the mount point.
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Volume marker

    @Test func theMarkerRoundTrips() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let marker = BackupVolumeMarker(
            volumeName: "Archive", volumeUUID: "ABC", filesystem: "exfat")
        try marker.write(to: root)

        let read = try #require(BackupVolumeMarker.read(at: root))
        #expect(read.identity == marker.identity)
        #expect(read.volumeName == "Archive")
        #expect(read.filesystem == "exfat")
    }

    @Test func eachMarkerGetsItsOwnIdentity() {
        #expect(BackupVolumeMarker().identity != BackupVolumeMarker().identity)
    }

    /// No marker means "this is not the disk we were configured for" — including
    /// the case where nothing is mounted and the path is an empty directory
    /// someone else created.
    @Test func aDirectoryWithoutAMarkerReadsAsNil() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(BackupVolumeMarker.read(at: root) == nil)
    }

    @Test func anUnreadableMarkerReadsAsNilRatherThanThrowing() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: root.appendingPathComponent(BackupVolumeMarker.fileName))
        #expect(BackupVolumeMarker.read(at: root) == nil)
    }
}
