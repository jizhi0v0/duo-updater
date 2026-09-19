import Foundation

/// What a comparison needs to know about a backup, kept on this Mac beside the
/// backup rather than inside it.
///
/// Comparing an app with its backup is a pure function of two ``BundleFacts``
/// values, and only one of them changes: the installed copy is read fresh every
/// time, while the backup is bytes that cannot move. On a backup that has been
/// transferred to a disk, reading it again for every comparison means unpacking a
/// whole app bundle back across a cable before anything can be looked at, because
/// what is on the disk is one Apple Archive. Recording the facts once turns that
/// into reading one file: measured on a real backup on a USB stick — Cursor,
/// 930.2 MB and 17,246 files out of a 280 MB archive — the old side went from
/// **12.29s to 0.06s**, and the 1.30s afterwards spent deleting the unpacked copy
/// went to zero. Nothing left on that side is on the critical path.
///
/// Written by ``BackupStore/transferToDestination(forKey:compression:)`` and by
/// nothing else, which is why a backup still sitting on this Mac has no entry:
/// the transfer is the only route to a disk, it has just read the whole bundle to
/// compress it, and it runs on a queue rather than on the update the user is
/// waiting for. Reading the backup directly is the local case anyway, and both
/// sides of a comparison are read concurrently, so skipping one of two equal
/// walks moved the wall clock by 4–10% (measured) — not worth a second walk of
/// every bundle at backup time.
///
/// **This is a cache, never a gate.** Nothing here decides whether a backup is
/// intact, whether it may be restored, or what is in it: an entry that is
/// missing, stale, truncated or unreadable simply means the comparison reads the
/// backup itself, which is what it did before this existed. That is why an entry
/// is addressed by the fingerprint of the copy it describes and by the format
/// version that wrote it — both in the file's own name, so a mismatch is a
/// missing file rather than a decode that has to be trusted to fail.
///
/// Lives under ``DuoStateDirectory`` and not in the backup store, for two
/// reasons. A transfer rebuilds the key's directory on the disk from the sidecar
/// alone and deletes the outbox copy it came from, so anything kept in either
/// place would be destroyed by the very operation that writes this. And the disk
/// may be formatted for Windows or be a share — the reason the backup is an
/// archive at all — while the point of this is to be read without going near it.
public enum BackupFactsLibrary {

    /// Test seam, task-local for the same reason as ``BackupStore/rootOverride``:
    /// suites run in parallel, so a global would be visible to whichever other
    /// suite happened to read it. Production never binds it.
    @TaskLocal public static var rootOverride: URL?

    /// Bumped whenever the stored shape changes. It is part of the file name, so
    /// last version's entries are not decoded and mistaken for this version's —
    /// they are simply not found, and the next backup supersedes them.
    static let formatVersion = 1

    /// Per-process, so a test that saves a backup without binding
    /// ``rootOverride`` cannot reach the developer's own library — the same
    /// protection, and for the same reason, as ``TauriProofStore``'s. `save`
    /// records an entry now, and every existing backup test goes through it.
    static let testProcessRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("duo-backup-facts-tests-\(UUID().uuidString)", isDirectory: true)

    public static var root: URL {
        if let rootOverride { return rootOverride }
        if DuoStateDirectory.isTestProcess,
           ProcessInfo.processInfo.environment["DUO_STATE_DIR"] == nil {
            return testProcessRoot
        }
        return DuoStateDirectory.base
            .appendingPathComponent("DuoUpdater/BackupFacts", isDirectory: true)
    }

    /// Which stored copy an entry describes.
    ///
    /// The fingerprint is the backup's own manifest digest — a SHA-256 over every
    /// path, size and content digest in the copy as it was written. A backup that
    /// has none (one written before manifests, or an app with a file we could not
    /// read) has no reference and therefore no entry: refusing to cache what we
    /// cannot identify is the whole of the freshness rule.
    public struct Reference: Sendable, Equatable {
        public let key: String
        public let fingerprint: String

        public init?(_ backup: BackupStore.Backup) {
            guard let fingerprint = backup.fingerprint else { return nil }
            self.key = backup.key
            self.fingerprint = fingerprint
        }

        init(key: String, fingerprint: String) {
            self.key = key
            self.fingerprint = fingerprint
        }
    }

    static func directory(forKey key: String) -> URL {
        root.appendingPathComponent(key, isDirectory: true)
    }

    /// The file an entry for this copy would be at.
    ///
    /// Reading and writing take a URL from here rather than a ``Reference``, and
    /// the caller resolves it **before** hopping off the cooperative pool:
    /// ``rootOverride`` is a task-local and a Dispatch thread does not carry one,
    /// so a path resolved on the far side of a hop would silently be the wrong
    /// one — a lookup that always misses, and a write into somewhere else.
    static func entry(for reference: Reference) -> URL {
        directory(forKey: reference.key)
            .appendingPathComponent("\(reference.fingerprint).v\(formatVersion).facts")
    }

    /// The facts at `entry`, or nil for every other outcome — missing, truncated,
    /// written by a format this one cannot read, anything.
    ///
    /// Blocking disk work and a decompression of up to a few megabytes, so
    /// callers run it off the cooperative pool, as they do ``BundleFactsReader``.
    static func facts(at entry: URL) -> BundleFacts? {
        guard let stored = try? Data(contentsOf: entry),
              let json = try? (stored as NSData).decompressed(using: .zlib) as Data,
              let facts = try? JSONDecoder().decode(BundleFacts.self, from: json)
        else { return nil }
        return facts
    }

    /// Record `facts` at `entry` as what that copy holds, replacing whatever was
    /// held for its key.
    ///
    /// Best effort: the caller has a complete backup either way, and a comparison
    /// that has to read the backup is the behaviour this is an optimisation of.
    /// Returns whether the entry landed, for the log line and for tests.
    @discardableResult
    static func store(_ facts: BundleFacts, at entry: URL) -> Bool {
        let fm = FileManager.default
        let directory = entry.deletingLastPathComponent()
        guard let json = try? JSONEncoder().encode(facts),
              let compressed = try? (json as NSData).compressed(using: .zlib) as Data,
              (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              (try? compressed.write(to: entry, options: .atomic)) != nil
        else { return false }
        // Retention is one, like the backups themselves: an entry for a copy that
        // no longer exists can never be asked for again. Done after the write, so
        // a failed write leaves the previous entry rather than nothing.
        for stale in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? [] where stale.lastPathComponent != entry.lastPathComponent {
            try? fm.removeItem(at: stale)
        }
        return true
    }

    /// Forget everything recorded for `key`. Called wherever a backup is deleted:
    /// the entry describes bytes that are gone, and nothing will ever ask for it.
    static func drop(forKey key: String) {
        try? FileManager.default.removeItem(at: directory(forKey: key))
    }
}
