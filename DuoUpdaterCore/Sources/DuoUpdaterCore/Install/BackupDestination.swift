import Foundation

/// Where rollback backups are kept.
///
/// The default — and, until someone points it somewhere else, the only case —
/// is `local`: `~/Library/Application Support/DuoUpdater/Backups`, on the boot
/// volume, holding a plain copy of each replaced bundle. That copy is a real
/// second copy, so a 1.5 GB app costs 1.5 GB, and on a machine that is short of
/// space the usual response is to turn backups off entirely — trading the
/// rollback safety net for disk. Pointing the store at an external disk is the
/// way to keep both.
///
/// An external destination is identified by **two** things, and the second is
/// what makes it trustworthy. A path alone is not an identity: `/Volumes/Archive`
/// is whatever happens to be mounted there, which may be a different disk, or —
/// when nothing is mounted — a plain directory on the boot volume that something
/// created. So a configured destination also carries an `identity`, matched
/// against a marker file we wrote inside it (see ``BackupVolumeMarker``).
public struct BackupDestination: Sendable, Equatable {

    public enum Kind: String, Sendable {
        case local, external
    }

    public var kind: Kind
    /// Absolute, standardized path of the chosen directory. Nil for `.local`.
    public var path: String?
    /// The `identity` we expect ``BackupVolumeMarker`` at `path` to carry.
    /// Nil for `.local`, and nil for an external destination configured before
    /// the marker was written (which reads as "not yet verified", not "matches").
    public var identity: String?
    /// The volume's name when it was chosen, for UI copy only ("“Archive” isn't
    /// connected"). Never a matching criterion — volumes get renamed.
    public var volumeName: String?

    public static let local = BackupDestination(kind: .local)

    /// The directory we create inside the folder the user picks, and the only
    /// one we ever read, write, measure or delete within.
    ///
    /// Never treat the picked folder itself as the store. A folder picker hands
    /// back somewhere that belongs to the user and is usually full of their
    /// things — `~/Documents` here had seventy-five subdirectories — and a store
    /// rooted there would count every one of them as a backup: their size
    /// reported as ours, their names listed in the clean-up sheet, and one
    /// confirmation away from `removeItem`. Owning a subdirectory makes that
    /// impossible by construction rather than by remembering to filter.
    public static let storeFolderName = "DuoUpdater Backups"

    public init(
        kind: Kind, path: String? = nil, identity: String? = nil, volumeName: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.identity = identity
        self.volumeName = volumeName
    }

    /// The configured directory, or nil when backups stay local. Does **not**
    /// check whether it exists — that is ``BackupStore``'s job, and conflating
    /// "configured" with "reachable" is how a detached disk turns into a
    /// directory created on the boot volume.
    public var directory: URL? {
        guard kind == .external, let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Persistence

    /// Read the destination the app persisted.
    ///
    /// Lives here rather than in each product because the app and `duo` resolve
    /// it independently. A key name — or a default — that drifted between them
    /// would not fail loudly: the CLI would quietly write backups to the boot
    /// volume while the menu bar wrote them to the external disk, and both
    /// answers look individually correct.
    public static func load(from defaults: UserDefaults) -> BackupDestination {
        guard let remembered = remembered(from: defaults) else { return .local }
        // Absent means "on, if a folder was ever chosen". Reading a missing key
        // as `false` would have switched off the disk of everyone who configured
        // one before this flag existed — silently, since a store that has quietly
        // gone local looks exactly like one that was never moved.
        let enabled = defaults.object(forKey: UpdateSettings.backupDestinationEnabledKey)
            as? Bool ?? true
        return enabled ? remembered : .local
    }

    /// The folder last chosen, whether or not backups are going there now.
    ///
    /// Kept so that turning the disk back on is a switch rather than a second
    /// trip through a file picker — and so the settings page can name the disk
    /// it would return to.
    public static func remembered(from defaults: UserDefaults) -> BackupDestination? {
        guard let path = defaults.string(forKey: UpdateSettings.backupDestinationPathKey),
              !path.isEmpty
        else { return nil }
        return BackupDestination(
            kind: .external,
            path: path,
            identity: defaults.string(forKey: UpdateSettings.backupDestinationIdentityKey),
            volumeName: defaults.string(forKey: UpdateSettings.backupDestinationVolumeNameKey))
    }

    /// Persist this destination.
    ///
    /// Going local flips the switch and **keeps** the folder: erasing it would
    /// mean that changing your mind twice costs you the disk, and a stale
    /// location is harmless — nothing reads it while the switch is off, and
    /// picking a different folder overwrites it.
    public func save(into defaults: UserDefaults) {
        guard kind == .external, let path, !path.isEmpty else {
            defaults.set(false, forKey: UpdateSettings.backupDestinationEnabledKey)
            return
        }
        defaults.set(true, forKey: UpdateSettings.backupDestinationEnabledKey)
        defaults.set(path, forKey: UpdateSettings.backupDestinationPathKey)
        defaults.set(identity, forKey: UpdateSettings.backupDestinationIdentityKey)
        defaults.set(volumeName, forKey: UpdateSettings.backupDestinationVolumeNameKey)
    }
}

/// The file that proves a directory is the backup destination we were configured
/// for, written at the destination root as `.duo-backup-volume.json`.
///
/// `identity` is a UUID **we** generate, not anything the system reports, and
/// that is the point:
///
///   • every filesystem can store it — `volumeUUIDStringKey` is not guaranteed
///     on exFAT or an SMB share, so a check built on it would be unavailable
///     exactly where it is most needed;
///   • it distinguishes "my disk is mounted here" from "some other disk is
///     mounted at the same path", which a path check cannot;
///   • reformatting the volume destroys the marker along with the backups, so
///     the mismatch is detected instead of being silently written over.
///
/// The observed values below are diagnostics — better wording for "this looks
/// like a different disk", and something to put in a log. They are deliberately
/// **not** matching criteria: volumes get renamed, and a volume UUID that is
/// absent on one filesystem would otherwise read as a mismatch.
public struct BackupVolumeMarker: Codable, Sendable, Equatable {
    public static let fileName = ".duo-backup-volume.json"

    public let identity: String
    public let createdAt: Date
    public var volumeName: String?
    public var volumeUUID: String?
    /// `statfs` `f_fstypename`, purely descriptive. Never a gate: which
    /// filesystems can hold a backup is settled by the archive format, not by
    /// this string.
    public var filesystem: String?

    public init(
        identity: String = UUID().uuidString,
        createdAt: Date = Date(),
        volumeName: String? = nil,
        volumeUUID: String? = nil,
        filesystem: String? = nil
    ) {
        self.identity = identity
        self.createdAt = createdAt
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.filesystem = filesystem
    }

    /// Read the marker at a destination root, or nil when there is none to read.
    public static func read(at directory: URL) -> BackupVolumeMarker? {
        guard let data = try? Data(
            contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(BackupVolumeMarker.self, from: data)
    }

    public func write(to directory: URL) throws {
        try JSONEncoder().encode(self).write(
            to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
