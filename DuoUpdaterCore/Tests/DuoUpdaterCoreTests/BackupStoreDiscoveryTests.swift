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

    // MARK: - Volumes worth offering as a destination

    /// The USB SSD on the machine this was written on reports `removable` as
    /// **false**, so the external test has to be `isInternal == false`. Asking
    /// `isRemovable` instead is a mistake that hides the disk most likely to be
    /// chosen — see ``BackupStoreDiscovery/isWorthOffering(_:)`` for the
    /// measured table.
    ///
    /// Mutation: drop the `isInternal == false` clause.
    @Test func anExternalSSDIsOfferedEvenThoughItSaysItIsNotRemovable() {
        #expect(BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: false,
            isInternal: false, isLocal: true)))
    }

    /// A mounted installer image — two were attached while this was written.
    /// What keeps it out is that it answers nil to `isInternal`, not that it is
    /// read-only: deleting the read-only clause does not let it through. Stated
    /// here so the next person does not read that clause as this one's guard.
    @Test func aMountedDiskImageIsNotOffered() {
        let image = BackupStoreDiscovery.VolumeFacts(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: true,
            isInternal: nil, isLocal: true)
        #expect(!BackupStoreDiscovery.isWorthOffering(image))
        #expect(image.isInternal != false, "it is the nil, not the read-only flag, that excludes this")
    }

    /// The read-only clause's own case: a share mounted read-only, or a disk
    /// with its write-protect switch on. Both answer the external or network
    /// question with a yes, so nothing else here keeps them out — and offering
    /// one means a probe that fails the moment it tries to write a marker.
    ///
    /// Mutation: drop the `isReadOnly` clause.
    @Test func aReadOnlyDiskOrShareIsNotOffered() {
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: true,
            isInternal: nil, isLocal: false)))
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: true,
            isInternal: false, isLocal: true)))
    }

    /// A share reports `isInternal` as nil rather than false, so the external
    /// clause alone never matches it.
    ///
    /// Mutation: drop the `isLocal == false` clause.
    @Test func aNetworkShareIsOffered() {
        let share = BackupStoreDiscovery.VolumeFacts(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: false,
            isInternal: nil, isLocal: false)
        #expect(BackupStoreDiscovery.isWorthOffering(share))
        #expect(share.isInternal != false, "the external clause must not be what passes this")
    }

    /// The volume this Mac booted from is already a row of its own, and moving
    /// backups there frees nothing.
    ///
    /// Stated for a Mac booted from an *external* disk, because that is the only
    /// shape in which the clause is load-bearing: an internally booted Mac is
    /// excluded by being internal, so a version of this test written that way
    /// would pass with the clause deleted.
    ///
    /// Mutation: drop the `isRootFileSystem` clause.
    @Test func theVolumeThisMacBootedFromIsNotOffered() {
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: true, isBrowsable: true, isReadOnly: false,
            isInternal: false, isLocal: true)))
        // And the ordinary internal case, which the clause below also covers.
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: true, isBrowsable: true, isReadOnly: false,
            isInternal: true, isLocal: true)))
    }

    /// Preboot, VM, Recovery and the cryptex mounts. They are volumes, they are
    /// writable, and the user has never seen any of them. Stated as an external
    /// one so that the browsable clause is what excludes it.
    ///
    /// Mutation: drop the `isBrowsable` clause.
    @Test func aVolumeTheUserCannotSeeIsNotOffered() {
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: false, isBrowsable: false, isReadOnly: false,
            isInternal: false, isLocal: true)))
    }

    /// A second internal volume is left out on purpose: on most Macs it is
    /// another APFS volume in the boot container, sharing the same free space.
    ///
    /// Mutation: `isInternal == false` → `isInternal != true`.
    @Test func aSecondInternalVolumeIsNotOffered() {
        #expect(!BackupStoreDiscovery.isWorthOffering(.init(
            isRootFileSystem: false, isBrowsable: true, isReadOnly: false,
            isInternal: true, isLocal: true)))
    }

    /// Nothing is known about a volume that will not answer. Offering it would
    /// mean offering every hidden system mount the moment `skipHiddenVolumes`
    /// stopped filtering them.
    ///
    /// Mutation: either `== false` → `!= true`.
    @Test func aVolumeThatSaysNothingIsNotOffered() {
        #expect(!BackupStoreDiscovery.isWorthOffering(.init()))
    }

    /// A directory on the boot volume answers with the boot volume's own facts,
    /// which is why a temporary directory is never a candidate — and why the
    /// clause above is worth having against something other than a fixture.
    @Test func aFolderOnTheBootVolumeIsNotACandidate() throws {
        try withScratch { dir in
            #expect(BackupStoreDiscovery.candidates(among: [dir]).isEmpty)
        }
    }

    /// A volume already carrying a store has a row of its own; offering its root
    /// as somewhere new would start a second store beside the first.
    ///
    /// Mutation: drop the `store(at:)` check in `isSpokenFor`.
    @Test func aVolumeThatAlreadyCarriesAStoreIsSpokenFor() throws {
        try withScratch { volume in
            #expect(!BackupStoreDiscovery.isSpokenFor(volume, configuredPaths: []))
            let sub = volume.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
            try write(marker: BackupVolumeMarker(volumeName: "Archive"), to: sub)
            #expect(BackupStoreDiscovery.isSpokenFor(volume, configuredPaths: []))
        }
    }

    /// The destination in use may sit deeper than the two places the marker
    /// check looks — `/Volumes/T7/Archive/Backups` carries the marker, the
    /// volume root carries nothing — and the disk would then be offered as new
    /// while it is the one already in use.
    ///
    /// Mutation: drop the `configuredPaths` check in `isSpokenFor`.
    @Test func aDiskConfiguredDeeperThanTheMarkerCheckLooksIsSpokenFor() throws {
        try withScratch { volume in
            let nested = volume
                .appendingPathComponent("Archive", isDirectory: true)
                .appendingPathComponent(BackupDestination.storeFolderName, isDirectory: true)
            try write(marker: BackupVolumeMarker(volumeName: "Archive"), to: nested)
            #expect(BackupStoreDiscovery.isSpokenFor(volume, configuredPaths: []) == false,
                    "fixture must be invisible to the marker check for this to prove anything")
            #expect(BackupStoreDiscovery.isSpokenFor(volume, configuredPaths: [nested.path]))
        }
    }

    /// A path that merely starts with the same characters is a different disk:
    /// `/Volumes/Archive 2` is not inside `/Volumes/Archive`.
    @Test func aDiskWhoseNameIsAPrefixOfAnotherIsNotSpokenFor() throws {
        try withScratch { volume in
            let sibling = volume.deletingLastPathComponent()
                .appendingPathComponent(volume.lastPathComponent + " 2", isDirectory: true)
            #expect(!BackupStoreDiscovery.isSpokenFor(
                volume, configuredPaths: [sibling.appendingPathComponent("x").path]))
        }
    }
}
