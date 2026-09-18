import Foundation
import Testing

@testable import DuoUpdaterCore

/// The pure half of the mounted-volume scan: given directories standing in for
/// volume roots, which of them carry one of our stores.
///
/// A test cannot mount a volume, which is exactly why `stores(among:)` exists
/// separately from `scanMountedVolumes()` — everything here drives that pure
/// function with temporary directories instead of real mounts.
@Suite struct BackupStoreDiscoveryTests {

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoDiscoveryTest-\(UUID().uuidString)", isDirectory: true)
    }

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body(dir)
    }

    /// `BackupVolumeMarker.write` writes the file but does not create its
    /// parent, unlike `BackupDestinationProbe.adopt` which always creates the
    /// store directory first.
    private func write(marker: BackupVolumeMarker, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try marker.write(to: directory)
    }

    @Test func aStoreUnderTheBackupsSubdirectoryIsFound() throws {
        try withScratch { volume in
            let sub = volume.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
            let marker = BackupVolumeMarker(volumeName: "Archive")
            try write(marker: marker, to: sub)

            let found = BackupStoreDiscovery.stores(among: [volume])
            #expect(found.count == 1)
            #expect(found.first?.root == sub)
            #expect(found.first?.marker.identity == marker.identity)
        }
    }

    @Test func aVolumeWithNoMarkerIsNotFound() throws {
        try withScratch { volume in
            #expect(BackupStoreDiscovery.stores(among: [volume]).isEmpty)
        }
    }

    @Test func aCorruptMarkerIsNotFoundAndDoesNotThrow() throws {
        try withScratch { volume in
            let sub = volume.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data("{ not json, this is deliberately broken".utf8)
                .write(to: sub.appendingPathComponent(BackupVolumeMarker.fileName))

            #expect(BackupStoreDiscovery.stores(among: [volume]).isEmpty)
        }
    }

    @Test func aMarkerAtTheVolumeRootIsFound() throws {
        try withScratch { volume in
            let marker = BackupVolumeMarker(volumeName: "Root Disk")
            try marker.write(to: volume)

            let found = BackupStoreDiscovery.stores(among: [volume])
            #expect(found.count == 1)
            #expect(found.first?.root == volume)
            #expect(found.first?.marker.identity == marker.identity)
        }
    }

    /// Someone who copied the path shown in Settings and picked that folder
    /// ends up with a marker at the root; someone who picked its parent ends up
    /// with a marker in the subdirectory too, once `adopt` runs there. Whichever
    /// path this Mac created is the one to prefer.
    @Test func theSubdirectoryWinsWhenBothCarryMarkers() throws {
        try withScratch { volume in
            let rootMarker = BackupVolumeMarker()
            try rootMarker.write(to: volume)
            let sub = volume.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
            let subMarker = BackupVolumeMarker()
            try write(marker: subMarker, to: sub)

            let found = BackupStoreDiscovery.stores(among: [volume])
            #expect(found.count == 1)
            #expect(found.first?.root == sub)
            #expect(found.first?.marker.identity == subMarker.identity)
        }
    }

    /// A byte-for-byte clone of a disk carries the same identity, and macOS
    /// mounts both — verified on this machine with a cloned exFAT volume. The
    /// picker must offer that disk once, not twice.
    @Test func twoVolumesWithTheSameIdentityCollapseToOne() throws {
        try withScratch { a in
            try withScratch { b in
                let shared = BackupVolumeMarker(volumeName: "Clone")
                let subA = a.appendingPathComponent(
                    BackupDestination.storeFolderName, isDirectory: true)
                let subB = b.appendingPathComponent(
                    BackupDestination.storeFolderName, isDirectory: true)
                try write(marker: shared, to: subA)
                try write(marker: shared, to: subB)

                let found = BackupStoreDiscovery.stores(among: [a, b])
                #expect(found.count == 1, "a cloned disk mounted twice must not appear twice")
            }
        }
    }

    /// **The invariant most worth testing.** This scan may run against a store
    /// that belongs to someone else's Mac, so it must never create, repair, or
    /// touch anything — not even a directory. Asserted as byte-identical
    /// contents before and after, not just "no error was thrown".
    @Test func theScanCreatesNothing() throws {
        try withScratch { volume in
            let sub = volume.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
            try write(marker: BackupVolumeMarker(volumeName: "Untouched"), to: sub)

            func snapshot() throws -> [String: Data] {
                let fm = FileManager.default
                guard let relativePaths = try? fm.subpathsOfDirectory(atPath: volume.path)
                else { return [:] }
                var contents: [String: Data] = [:]
                for relative in relativePaths {
                    let full = volume.appendingPathComponent(relative)
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: full.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue
                    else { continue }
                    contents[relative] = try Data(contentsOf: full)
                }
                return contents
            }

            let before = try snapshot()
            _ = BackupStoreDiscovery.stores(among: [volume])
            let after = try snapshot()
            #expect(before == after, "a read-only scan must not create or modify anything")
        }
    }
}
