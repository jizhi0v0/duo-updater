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

    // MARK: - Volumes that could hold a store, but do not yet

    /// A mounted volume worth offering as a place to keep backups.
    ///
    /// Offered at the moment of choosing rather than listed alongside the disks
    /// that hold backups: an empty disk is not a place backups are kept, and a
    /// row of its own would say that it was.
    public struct Candidate: Sendable, Equatable, Identifiable {
        /// The volume root. The store itself goes in a `DuoUpdater Backups`
        /// folder inside it — see ``BackupDestination/storeFolderName`` for why
        /// the picked folder is never the store.
        public let volume: URL
        public let name: String?
        /// A share rather than a disk. Worth carrying because it changes the
        /// failures to expect, the same distinction ``BackupDestinationProbe``
        /// reports as `isLocal`.
        public let isNetwork: Bool
        public let freeBytes: Int64?
        /// A Time Machine volume, which macOS reserves whole. Listed rather than
        /// dropped: someone who has just plugged this disk in is owed the reason
        /// it cannot be chosen, and a disk that silently fails to appear reads as
        /// a bug in the list. Nothing may be written to it — see
        /// ``BackupDestinationProbe/timeMachineVolumeName(holding:)``.
        public let isReservedForTimeMachine: Bool

        public var id: String { volume.path }

        public init(
            volume: URL, name: String?, isNetwork: Bool, freeBytes: Int64?,
            isReservedForTimeMachine: Bool = false
        ) {
            self.volume = volume
            self.name = name
            self.isNetwork = isNetwork
            self.freeBytes = freeBytes
            self.isReservedForTimeMachine = isReservedForTimeMachine
        }
    }

    /// What a volume says about itself, as far as choosing a backup disk cares.
    ///
    /// A plain value because the rule below has to be testable and no test can
    /// mount a disk. Every field is optional because macOS leaves them so: a
    /// network mount on this Mac reports `isInternal` as nil, and answering nil
    /// as `false` is what would put the boot volume in the list.
    public struct VolumeFacts: Sendable, Equatable {
        public var isRootFileSystem: Bool?
        public var isBrowsable: Bool?
        public var isReadOnly: Bool?
        public var isInternal: Bool?
        public var isLocal: Bool?

        public init(
            isRootFileSystem: Bool? = nil, isBrowsable: Bool? = nil, isReadOnly: Bool? = nil,
            isInternal: Bool? = nil, isLocal: Bool? = nil
        ) {
            self.isRootFileSystem = isRootFileSystem
            self.isBrowsable = isBrowsable
            self.isReadOnly = isReadOnly
            self.isInternal = isInternal
            self.isLocal = isLocal
        }
    }

    /// Whether a mounted volume is worth offering as a backup destination.
    ///
    /// Each clause is one thing this Mac actually mounts. Measured here, with
    /// two external disks and two disk images attached:
    ///
    ///     int  local rm ej br ro   path
    ///     Y    Y     n  n  Y  n    /
    ///     ?    n     n  n  Y  n    /Users/bobby/OrbStack       (NFS share)
    ///     ?    Y     Y  Y  Y  Y    /Volumes/SuperCmd           (mounted .dmg)
    ///     n    Y     Y  Y  Y  n    /Volumes/Install macOS…     (USB stick)
    ///     n    Y     n  n  Y  n    /Volumes/Samsung T7         (USB SSD)
    ///
    /// `removable` is the trap: it is **false** for the T7, so "is this an
    /// external disk" has to be asked as `isInternal == false`. Note also what
    /// keeps the two disk images out — they answer `isInternal` with nil, not
    /// with false, so the external clause never matches them. The read-only
    /// clause is not what excludes them; it is there for the disk or share that
    /// answers yes to one of those questions *and* cannot be written to.
    ///
    /// Deliberately not offered: a second *internal* volume. It would be a
    /// legitimate choice on a Mac that has one, but on the far more common
    /// Mac it is another APFS volume in the boot container, which shares its
    /// free space — moving backups there frees nothing while looking like it
    /// freed everything. The folder panel still reaches it.
    static func isWorthOffering(_ facts: VolumeFacts) -> Bool {
        if facts.isRootFileSystem == true { return false }
        if facts.isBrowsable == false { return false }
        if facts.isReadOnly == true { return false }
        return facts.isInternal == false || facts.isLocal == false
    }

    /// Every mounted volume worth offering, minus those already carrying a
    /// store and those under `configuredPaths` (a destination nested deeper
    /// than the marker check below can see).
    ///
    /// Run through `offCooperativePool` for the same reason as
    /// ``scanMountedVolumes()``: one unresponsive share would otherwise stop the
    /// app scheduling anything at all.
    public static func scanCandidateVolumes(
        excludingStoresAt configuredPaths: [String] = []
    ) async -> [Candidate] {
        await offCooperativePool {
            let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: candidateKeys,
                options: [.skipHiddenVolumes]) ?? []
            return candidates(among: volumes, excludingStoresAt: configuredPaths)
        }
    }

    private static let candidateKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        .volumeIsReadOnlyKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ]

    /// The pure half, for the same reason ``stores(among:)`` has one.
    static func candidates(
        among volumes: [URL], excludingStoresAt configuredPaths: [String] = []
    ) -> [Candidate] {
        let configured = Set(configuredPaths.map { URL(fileURLWithPath: $0).standardized.path })
        var out: [Candidate] = []
        for volume in volumes {
            guard let values = try? volume.resourceValues(forKeys: Set(candidateKeys)) else {
                continue
            }
            guard isWorthOffering(VolumeFacts(
                isRootFileSystem: values.volumeIsRootFileSystem,
                isBrowsable: values.volumeIsBrowsable,
                isReadOnly: values.volumeIsReadOnly,
                isInternal: values.volumeIsInternal,
                isLocal: values.volumeIsLocal))
            else { continue }
            guard !isSpokenFor(volume, configuredPaths: configured) else { continue }
            out.append(Candidate(
                volume: volume,
                name: values.volumeName,
                isNetwork: values.volumeIsLocal == false,
                freeBytes: BackupDestinationProbe.preferredFree(
                    important: values.volumeAvailableCapacityForImportantUsage,
                    plain: values.volumeAvailableCapacity.map(Int64.init)),
                isReservedForTimeMachine: BackupDestinationProbe
                    .carriesTimeMachineMarkers(at: volume)))
        }
        // Same reason as `stores(among:)`: a picker whose order shuffles between
        // openings is a picker you have to re-read every time. Disks that cannot
        // be chosen sort last, where a list is read least.
        return out.sorted { a, b in
            if a.isReservedForTimeMachine != b.isReservedForTimeMachine {
                return !a.isReservedForTimeMachine
            }
            return (a.name ?? a.volume.path) < (b.name ?? b.volume.path)
        }
    }

    /// Whether this volume is already accounted for by a row of its own.
    ///
    /// Two ways it can be. It carries a store, in which case adopting its root
    /// would start a second store beside the first; or a configured destination
    /// lives somewhere on it, which the marker check above cannot see because
    /// that destination may be nested deeper than the two places it looks.
    static func isSpokenFor(_ volume: URL, configuredPaths: Set<String>) -> Bool {
        if store(at: volume) != nil { return true }
        let root = volume.standardized.path
        return configuredPaths.contains { $0 == root || $0.hasPrefix(root + "/") }
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
