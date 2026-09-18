import Foundation

/// Finds backup stores sitting on disks that are plugged in right now, whether
/// or not this Mac was ever configured to use them.
///
/// The picker that chooses among backup disks needs to offer more than "the one
/// folder saved in defaults" — it needs to see a disk someone backed up to from
/// a different Mac, or reconnected after `BackupDestination`'s persisted path
/// went stale. Neither of those is discoverable by reading `UserDefaults`; both
/// are discoverable by asking every mounted volume whether it already carries
/// our marker.
///
/// Strictly read-only: this type opens files to read them and nothing else. A
/// store found here may belong to someone else's Mac, so there is nothing here
/// that writes, repairs, or even creates a directory — see ``BackupDestinationProbe``
/// for the code that is allowed to do that, once the user has actually chosen.
public enum BackupStoreDiscovery {

    /// A backup store found sitting on a mounted volume.
    public struct Found: Sendable, Equatable {
        /// The store directory itself (the one holding the marker), not the
        /// volume it sits on.
        public let root: URL
        public let marker: BackupVolumeMarker
        public let volumeName: String?
        /// True when this store is on the same volume as the boot volume, which
        /// means choosing it frees no space on this Mac.
        public let isOnBootVolume: Bool
    }

    /// Every mounted volume that carries one of our stores.
    ///
    /// Run through `offCooperativePool`: this is called from the Settings page
    /// on Swift concurrency's cooperative pool, and a `stat` against a share
    /// whose server has vanished blocks the calling thread indefinitely — see
    /// `Support/OffPool.swift`. That pool does not grow when a thread blocks, so
    /// one unresponsive network mount would stop the app scheduling anything at
    /// all, not just this scan.
    public static func scanMountedVolumes() async -> [Found] {
        await offCooperativePool {
            let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey],
                options: [.skipHiddenVolumes]) ?? []
            return stores(among: volumes)
        }
    }

    /// The pure half: the stores found among `volumes`, which are treated as
    /// volume roots. Exposed for tests, which cannot mount anything — everything
    /// a real scan does past "here is a list of volume URLs" lives here.
    static func stores(among volumes: [URL]) -> [Found] {
        // Compared against the home directory rather than `BackupStore.outboxRoot`
        // (which is how `BackupsSettingsPage.isOnThisMacsDisk` does it today):
        // this file is additive and must not import anything from `BackupStore`,
        // which another change is mid-refactor on. The home directory sits on
        // the boot volume exactly as `outboxRoot` does, so it answers the same
        // "is this the boot volume" question `isOnSameVolume` is asked here.
        let bootVolumeReference = URL(fileURLWithPath: NSHomeDirectory())

        var seenIdentities = Set<String>()
        var found: [Found] = []
        for volume in volumes {
            guard let (root, marker) = store(at: volume) else { continue }
            // The same disk can mount twice — a byte-for-byte clone carries the
            // same identity and macOS mounts both — and the picker must offer it
            // once, not twice. Keeping the first occurrence is enough: which of
            // two clones happens to be first is not a distinction the picker
            // can act on anyway.
            guard seenIdentities.insert(marker.identity).inserted else { continue }
            let volumeName = (try? volume.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            found.append(Found(
                root: root,
                marker: marker,
                volumeName: volumeName,
                isOnBootVolume: BackupDestinationProbe.isOnSameVolume(
                    volume, as: bootVolumeReference)))
        }

        // A picker's order should not shuffle between openings: disks that
        // actually free up space are worth surfacing first, and everything
        // after that is ordered by the one stable, user-visible label a volume
        // has. `sorted(by:)` is a stable sort, so entries tied on both keys keep
        // the order `volumes` handed them in.
        return found.sorted { a, b in
            if a.isOnBootVolume != b.isOnBootVolume { return !a.isOnBootVolume }
            return (a.volumeName ?? "") < (b.volumeName ?? "")
        }
    }

    /// The store at this volume root, preferring the `DuoUpdater Backups`
    /// subdirectory over the volume root itself carrying the marker directly.
    ///
    /// The root case matters: someone who pointed the picker at the root of a
    /// disk dedicated to backups (rather than at a folder within it) ends up
    /// with the marker at the volume root, not inside a subdirectory — see
    /// `BackupDestinationProbe.adopt`'s `alreadyOurs` check, which this mirrors
    /// from the read side.
    private static func store(at volume: URL) -> (root: URL, marker: BackupVolumeMarker)? {
        let subdirectory = volume.appendingPathComponent(
            BackupDestination.storeFolderName, isDirectory: true)
        if let marker = BackupVolumeMarker.read(at: subdirectory) {
            return (subdirectory, marker)
        }
        if let marker = BackupVolumeMarker.read(at: volume) {
            return (volume, marker)
        }
        // No marker, or one that failed to decode — `BackupVolumeMarker.read`
        // already collapses both into nil. Either way this volume is silently
        // not a store: a disk with an unrelated ".duo-backup-volume.json"-less
        // history is the overwhelmingly common case, not an error.
        return nil
    }
}
