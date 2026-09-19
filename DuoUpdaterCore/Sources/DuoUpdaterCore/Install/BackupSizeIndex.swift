import Foundation

/// What each stored backup measured, remembered across calls and across
/// processes so that listing them need not walk every file of every one.
///
/// Sizing is the one part of ``BackupStore/listing()`` whose cost grows with
/// the store. Everything else is a handful of small reads per backup; the size
/// is a recursive walk of a whole app bundle, and the sheet that offers to
/// delete backups shows a size on every row — so pressing "Clean Up…" walked
/// every file of every backup before the first row appeared, and did it again
/// on the next press.
///
/// Measured 2026-09-19 against a store of 101 backups, 240,308 files and 48 GB
/// on a USB HFS+ disk, with the filesystem cache already warm. Three
/// consecutive calls in one process, debug build: `listing()` 1.90/1.92/1.90 s
/// and `storeSizes()` 1.80/1.84/1.83 s — the cost of the walk, paid in full
/// every time. Through this index the same three calls were 1.32 s (every
/// backup a miss, fanned out) and then 0.015 s. End to end in a release build,
/// `duo backups disks`, which is `sizesByStore()` and little else: 4.46 s with
/// no index file, 0.022 s with one.
///
/// A stored backup does not change while it sits there. Retention per key is
/// one; `save` builds the new copy in a hidden staging directory and swaps the
/// whole key directory into place with `replaceItemAt`/`moveItem`; a transfer
/// rebuilds the key directory on the disk and deletes the outbox copy. Nothing
/// writes *inside* a backup that is already stored. So a measurement stays true
/// until the key directory is replaced, and that is exactly what its inode and
/// modification date report — two fields of one `stat`, against a walk of
/// tens of thousands of files.
///
/// **A cache, never a gate.** Nothing here decides whether a backup exists, may
/// be restored, or should be deleted; it answers "how many bytes" for a figure
/// on screen. A missing, stale or unreadable entry means the directory is
/// walked, which is what every caller did before this existed.
///
/// Lives under ``DuoStateDirectory`` rather than in the store, for the reasons
/// ``BackupFactsLibrary`` gives at greater length: the destination may be a
/// disk this Mac must not write to more than it already does, a transfer
/// rebuilds the key directory from the sidecar alone, and the point of the
/// entry is to be read without going near the disk it describes.
final class BackupSizeIndex: @unchecked Sendable {

    /// Bumped if the stored shape or the meaning of `bytes` changes. A file
    /// stamped with anything else reads as empty — one re-walk per entry, and
    /// nothing else.
    static let generation = 1

    /// `identity` is the key directory's inode and modification date. Inode
    /// alone would miss a sidecar rewritten in place
    /// (``BackupStore/holdOnThisMac(keys:)``); date alone would miss a
    /// replacement inside the same second, because the date is a whole-second
    /// field on HFS+ — measured 2026-09-19 on an HFS+ volume, where three
    /// directories created in one second all reported the identical
    /// `1789817168.000000000`, against nanosecond values on APFS. An external
    /// backup disk is routinely HFS+. See ``identity(of:)``.
    struct Entry: Codable, Equatable {
        var identity: String
        var bytes: Int64
    }

    private struct FileContents: Codable {
        var generation: Int
        var entries: [String: Entry]
    }

    /// The instance ``BackupStore`` reads through. `init(fileURL:)` exists for
    /// tests, which must not share one file across suites running in parallel.
    static let shared = BackupSizeIndex()

    private let lock = NSLock()

    /// Resolved once, at construction, for the reason
    /// ``TauriProofStore/resolvedFileURL`` sets out at length: this is a
    /// process-wide singleton, and re-reading `DUO_STATE_DIR` on every call
    /// would let another suite's `setenv` window move where it writes.
    let resolvedFileURL: URL

    init(fileURL: URL? = nil) {
        self.resolvedFileURL = fileURL
            ?? (DuoStateDirectory.isTestProcess
                ? Self.testProcessScratchFileURL : Self.defaultFileURL())
    }

    /// How many bytes each of `directories` holds — one answer per directory, in
    /// the order given — walking only the ones whose recorded measurement no
    /// longer describes what is on disk.
    ///
    /// `walk` is passed in rather than written here so that what counts as a
    /// byte stays in ``BackupStore/directorySize(_:)``, next to the comment
    /// explaining why it is the logical size and not the allocated one. It is
    /// called from several threads at once and must not assume otherwise.
    ///
    /// Every directory asked about is answered, including ones that cannot be
    /// stat'd at all — a disk pulled mid-call — which are walked and not
    /// recorded, since there is no identity to record them against. The answer
    /// is positional rather than a dictionary because two `URL`s spelling the
    /// same directory differently are two different keys, and a caller that
    /// spelled one of them the other way would silently get nothing back.
    ///
    /// Callers pass **every** directory of a store in one call. That is what
    /// lets this prune: an entry under a parent that was scanned and was not
    /// asked about is a backup that has been deleted, and dropping it here is
    /// what keeps the file from growing with every backup ever taken.
    ///
    /// With one gap, left deliberately: a call with nothing in it returns before
    /// the prune, having been told about no parent to prune under, so emptying a
    /// store entirely strands that store's last entries until something is stored
    /// there again. They are a few dozen bytes each and they cannot be read back
    /// as a size — the paths are gone, and a directory later created at one of
    /// them arrives with a new inode. Closing it would mean passing the root
    /// separately and deciding, for a store that reads as empty, whether it is
    /// empty or unreadable; getting that wrong retires a whole disk's entries
    /// every time it is unplugged at the wrong moment.
    func sizes(of directories: [URL], measuring walk: @Sendable (URL) -> Int64) -> [Int64] {
        guard !directories.isEmpty else { return [] }
        let asked = directories.map { (url: $0, identity: Self.identity(of: $0)) }

        lock.lock()
        let known = Self.load(from: resolvedFileURL)
        lock.unlock()

        var out = [Int64](repeating: 0, count: asked.count)
        var pending: [Int] = []
        for (index, (url, identity)) in asked.enumerated() {
            if let identity, let entry = known[url.path], entry.identity == identity {
                out[index] = entry.bytes
            } else {
                pending.append(index)
            }
        }

        if !pending.isEmpty {
            let urls = pending.map { asked[$0].url }
            let measured = UnsafeMutableBufferPointer<Int64>.allocate(capacity: urls.count)
            defer { measured.deallocate() }
            // Fanned out because a miss is a walk of an entire app bundle, and the
            // first call against a store that has never been measured is all
            // misses. The walks are independent reads of separate directories, and
            // `FileManager`'s shared instance is documented thread-safe for
            // everything but delegate-based operations, which these are not.
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                (measured.baseAddress! + index).initialize(to: walk(urls[index]))
            }
            for (slot, index) in pending.enumerated() { out[index] = measured[slot] }
        }

        lock.lock()
        defer { lock.unlock() }
        // Merged into whatever is on disk now rather than written blind, so the app
        // and `duo` measuring two different stores at once do not clobber each
        // other's entries. A lost write costs one re-walk and nothing else.
        var merged = Self.load(from: resolvedFileURL)
        // Everything under a root this call has just scanned in full is now known
        // exactly: dropping it first is what retires the entries of backups that
        // have been deleted, which is the only thing keeping this file bounded.
        let scanned = Set(directories.map { $0.deletingLastPathComponent().path })
        merged = merged.filter {
            !scanned.contains(URL(fileURLWithPath: $0.key).deletingLastPathComponent().path)
        }
        for (index, (url, identity)) in asked.enumerated() {
            // A directory that could not be stat'd has no identity to record it
            // against, so its measurement is used and then forgotten.
            guard let identity else { continue }
            merged[url.path] = Entry(identity: identity, bytes: out[index])
        }
        guard let data = try? JSONEncoder().encode(
            FileContents(generation: Self.generation, entries: merged)) else { return out }
        try? FileManager.default.createDirectory(
            at: resolvedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: resolvedFileURL, options: .atomic)
        return out
    }

    /// What the directory at `url` is right now, or nil when it cannot be
    /// asked — which is not an identity and must never be recorded as one.
    ///
    /// Read through `FileManager`, which stats, rather than through
    /// `URL.resourceValues`, which caches on the `URL` value itself. Measured
    /// 2026-09-19: a `URL` that had been asked for `.contentModificationDateKey`
    /// once kept answering with that date after the directory was written to,
    /// while a freshly constructed `URL` for the same path saw the new one. An
    /// index built on that would go stale exactly when a caller reused a `URL`
    /// it had already measured with — which is the normal way to use one.
    static func identity(of url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let node = attributes[.systemFileNumber] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        // The inode is what changes when a key directory is *replaced* — which is
        // how `BackupStore.save` supersedes one and how a transfer rebuilds one —
        // and the date is what changes when something inside it is rewritten
        // without the directory itself moving. Neither alone covers both.
        return "\(node)@\(modified.timeIntervalSince1970)"
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FileContents.self, from: data),
              decoded.generation == generation
        else { return [:] }
        return decoded.entries
    }

    /// Where a test process's default instance writes — always, whatever
    /// `DUO_STATE_DIR` says. Same shape, and the same reasoning, as
    /// ``TauriProofStore/testProcessScratchFileURL``.
    static let testProcessScratchFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("duo-backup-sizes-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("com.duoupdater.app", isDirectory: true)
        .appendingPathComponent("backup-sizes.json")

    static func defaultFileURL() -> URL {
        if DuoStateDirectory.isTestProcess
            && ProcessInfo.processInfo.environment["DUO_STATE_DIR"] == nil {
            return testProcessScratchFileURL
        }
        return DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("backup-sizes.json")
    }
}
