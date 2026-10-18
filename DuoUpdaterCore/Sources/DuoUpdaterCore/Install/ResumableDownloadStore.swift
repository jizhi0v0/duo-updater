import CryptoKit
import Foundation

/// Half-finished downloads kept across `Downloader` calls, so a download that
/// was stopped — the user cancelled it, the network gave out for good, the
/// process was killed — picks up where it left off next time instead of
/// starting from zero.
///
/// `Downloader` already resumes *within* one call (`Range` + `If-Range`). What
/// this adds is only that the partial file outlives the call: it is written
/// here, outside the install's scratch directory (which is deleted after every
/// install), keyed by the exact request URL, query included.
///
/// **Why the URL is enough.** If the object behind a URL changes, the
/// `If-Range` a resume carries makes the server answer `200` with the whole new
/// object, which discards the partial; and every download is checked again
/// afterwards (EdDSA, SHA-256, codesign). Comparing versions or channels as
/// well would only be stricter than that, never safer.
///
/// **What is kept.** Only a partial whose response carried a *strong*
/// validator (a non-weak `ETag`, else `Last-Modified`): without one a resumed
/// tail cannot be shown to belong to the same file, so the partial is dropped
/// when the download stops. A finished file is never kept — that would be an
/// installer cache, a much bigger thing than this.
///
/// **On disk**, per URL: `<key>.partial` (the bytes) and `<key>.json` (URL,
/// validator, bytes written, app id, created time). The sidecar is written and
/// fsync'ed as soon as a response's headers arrive, so a `kill -9` mid-transfer
/// still leaves something the next process can resume from.
///
/// **When it goes**, whichever comes first:
/// 1. ``resumeRetention`` after the last byte was written (``sweepExpired()``:
///    the app on a timer and at launch, `duo` before it installs);
/// 2. as soon as an install is short of disk space — before any backup
///    (``discardAllForSpace()``, from `DiskSpaceGuard`): keeping a partial must
///    never cost an install its room;
/// 3. when the app it belongs to installs successfully (``discard(forApp:)``);
/// 4. when the same app starts a download from a different URL.
public enum ResumableDownloadStore {

    /// How long a partial may sit untouched before it is deleted. Five
    /// minutes: resuming is for "cancelled, then retried straight away" and
    /// "crashed, then reopened straight away"; a download picked up again the
    /// next day starts over, on purpose. The one place this number lives — a
    /// later setting reads it from here.
    public static let resumeRetention: TimeInterval = 5 * 60

    /// Test seam: where partials are kept. Bound like `BackupStore.rootOverride`
    /// — task-local, so parallel suites cannot see each other's.
    @TaskLocal static var rootOverride: URL?

    /// Test seam: the clock expiry is measured against. Production reads `Date()`.
    @TaskLocal static var nowOverride: (@Sendable () -> Date)?

    static var now: Date { nowOverride?() ?? Date() }

    /// Set by `DiskSpaceGuard.watching` when it stops a download because the
    /// disk is under the floor with nothing left to delete. Bound as a task
    /// local around that download's task.
    ///
    /// The reason a download stopped has to be said, not inferred: the
    /// guard's stop arrives as a plain task cancellation, the same as the
    /// user's. Without this, `Downloader` kept the partial — possibly
    /// gigabytes, on the disk that just ran out — because "cancelled" is when
    /// it keeps one; and `discardAllForSpace()` could not take it either,
    /// since the download still held it while the guard was reclaiming.
    @TaskLocal static var outOfSpace: OutOfSpace?

    /// A one-way flag, safe to set from the guard's watcher and read from the
    /// download's `defer`.
    final class OutOfSpace: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    /// The directory partials live in, or nil when keeping them is off.
    ///
    /// Off in a test process that did not bind ``rootOverride``. Every
    /// `Downloader` test serves `http://127.0.0.1:<port>/…`, and ports are
    /// reused: a partial one test left behind would be "resumed" by an
    /// unrelated later test that drew the same port and path. Those tests keep
    /// the per-call behaviour they were written against; the ones about this
    /// store bind a scratch root of their own.
    static var root: URL? {
        if let rootOverride { return rootOverride }
        if DuoStateDirectory.isTestProcess { return nil }
        return DuoStateDirectory.cachesBase
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
    }

    /// What the sidecar records about one partial.
    struct Meta: Codable, Equatable, Sendable {
        /// The exact request URL, query included — the key's preimage, kept so
        /// a hash collision can never splice two downloads.
        var url: String
        /// The strong validator the partial was started under, sent back as
        /// `If-Range`.
        var validator: String
        var bytesWritten: Int64
        var appID: String?
        var createdAt: Date
    }

    /// The two files of one URL's partial.
    struct Entry: Sendable, Equatable {
        let partial: URL
        let sidecar: URL

        init(url: URL, root: URL) {
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            let key = digest.map { String(format: "%02x", $0) }.joined()
            partial = root.appendingPathComponent("\(key).partial", isDirectory: false)
            sidecar = root.appendingPathComponent("\(key).json", isDirectory: false)
        }

        fileprivate init(key: String, root: URL) {
            partial = root.appendingPathComponent("\(key).partial", isDirectory: false)
            sidecar = root.appendingPathComponent("\(key).json", isDirectory: false)
        }
    }

    /// One `Downloader` call's hold on its URL's partial: where to write, and
    /// what it may resume from. Released by ``close(_:keep:)``.
    struct Lease: Sendable {
        let entry: Entry
        let url: URL
        let appID: String?
        let createdAt: Date
        /// The validator to send as `If-Range` when the partial on disk is
        /// resumed; nil when there is nothing to resume.
        let validator: String?
    }

    // MARK: - In-process claims

    /// Partials a `Downloader` in this process is writing right now, by path.
    /// Never deleted by a sweep or a reclaim, and never handed to a second
    /// download of the same URL — that one falls back to a scratch file of its
    /// own. Across processes the two hosts never install at once
    /// (`InstallLock`), and a running transfer keeps its file's modification
    /// time fresh, which keeps it out of the other's expiry sweep.
    private static let claimLock = NSLock()
    private nonisolated(unsafe) static var claimed: Set<String> = []

    private static func claim(_ entry: Entry) -> Bool {
        claimLock.withLock { claimed.insert(entry.partial.path).inserted }
    }

    private static func release(_ entry: Entry) {
        _ = claimLock.withLock { claimed.remove(entry.partial.path) }
    }

    private static func isClaimed(_ entry: Entry) -> Bool {
        claimLock.withLock { claimed.contains(entry.partial.path) }
    }

    // MARK: - Downloader's side

    /// Take `url`'s partial for one download. Nil when keeping partials is off,
    /// the directory cannot be made, or another download in this process holds
    /// the same URL — the caller then downloads into a scratch file as before.
    ///
    /// A partial is offered for resume only when its sidecar names this exact
    /// URL, carries a validator, the file has bytes, and it is not past
    /// ``resumeRetention``. Anything else is deleted here and the download
    /// starts from zero. Partials of the same app under another URL go too
    /// (rule 4): a new URL means the old download is not coming back.
    static func open(for url: URL, appID: String?) -> Lease? {
        guard let root else { return nil }
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: root, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let entry = Entry(url: url, root: root)
        guard claim(entry) else { return nil }

        if let appID {
            for key in keys(in: root) {
                let other = Entry(key: key, root: root)
                guard other != entry, !isClaimed(other),
                      readMeta(other)?.appID == appID else { continue }
                remove(other)
                Log.install.notice("resumable download: dropped an earlier partial of the same app under another URL")
            }
        }

        let size = fileSize(entry.partial)
        if let meta = readMeta(entry), meta.url == url.absoluteString, !meta.validator.isEmpty,
           size > 0, !isExpired(entry, at: now) {
            Log.install.notice("resumable download: resuming from \(size, privacy: .public) bytes kept by an earlier attempt")
            return Lease(entry: entry, url: url, appID: appID, createdAt: meta.createdAt,
                         validator: meta.validator)
        }
        remove(entry)
        return Lease(entry: entry, url: url, appID: appID, createdAt: now, validator: nil)
    }

    /// Record, durably, that `lease`'s partial was started under `validator`
    /// — called when a response's headers arrive. With no validator the sidecar
    /// is removed instead: those bytes cannot be resumed, so nothing may offer
    /// them.
    ///
    /// Written to a temporary file, fsync'ed, then renamed over the sidecar, so
    /// a process killed at any point leaves either the old sidecar or the new
    /// one, never half of one.
    static func record(_ lease: Lease, validator: String?, bytesWritten: Int64) {
        guard let validator else {
            try? FileManager.default.removeItem(at: lease.entry.sidecar)
            return
        }
        let meta = Meta(url: lease.url.absoluteString, validator: validator,
                        bytesWritten: bytesWritten, appID: lease.appID, createdAt: lease.createdAt)
        do {
            try writeMeta(meta, to: lease.entry)
        } catch {
            // Not fatal to the download: it only loses the ability to resume.
            try? FileManager.default.removeItem(at: lease.entry.sidecar)
            Log.install.error("resumable download: could not write the sidecar — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// End one download's hold. `keep` says whether what is on disk is worth
    /// resuming (a strong validator, and a stop a retry could get past); when it
    /// is not — or the file is gone because the download finished and moved it —
    /// both files are deleted.
    static func close(_ lease: Lease, keep: Bool) {
        defer { release(lease.entry) }
        let size = fileSize(lease.entry.partial)
        guard keep, size > 0, let meta = readMeta(lease.entry) else {
            remove(lease.entry)
            return
        }
        var updated = meta
        updated.bytesWritten = size
        try? writeMeta(updated, to: lease.entry)
        Log.install.notice("resumable download: kept \(size, privacy: .public) bytes for \(Int(resumeRetention), privacy: .public)s")
    }

    // MARK: - Retention

    /// Delete every partial untouched for longer than ``resumeRetention``,
    /// plus any file of ours left without its pair past the same age. Returns
    /// how many partials went.
    ///
    /// Age runs from the newest modification time among a partial's files —
    /// i.e. from the last byte written — so a download still running, in this
    /// process or the other host, is never swept from under itself.
    @discardableResult
    public static func sweepExpired() -> Int {
        guard let root else { return 0 }
        let at = now
        var removed = 0
        for key in keys(in: root) {
            let entry = Entry(key: key, root: root)
            guard !isClaimed(entry), isExpired(entry, at: at) else { continue }
            remove(entry)
            removed += 1
        }
        if removed > 0 {
            Log.install.notice("resumable download: swept \(removed, privacy: .public) expired partial(s)")
        }
        return removed
    }

    /// Delete every partial `appID` left — it has just installed, so none of
    /// them will be resumed.
    public static func discard(forApp appID: String) {
        guard let root else { return }
        for key in keys(in: root) {
            let entry = Entry(key: key, root: root)
            guard !isClaimed(entry), readMeta(entry)?.appID == appID else { continue }
            remove(entry)
        }
    }

    /// Delete every partial not being written right now, to give an install
    /// the space. Called by `DiskSpaceGuard` before it deletes any backup.
    /// Returns how many went.
    @discardableResult
    static func discardAllForSpace() -> Int {
        guard let root else { return 0 }
        var removed = 0
        for key in keys(in: root) {
            let entry = Entry(key: key, root: root)
            guard !isClaimed(entry) else { continue }
            remove(entry)
            removed += 1
        }
        if removed > 0 {
            Log.install.notice("disk space: deleted \(removed, privacy: .public) kept partial download(s) before any backup")
        }
        return removed
    }

    /// The app's sweeper: once now, then every minute for as long as the
    /// process runs. A minute's granularity on a five-minute retention — a
    /// partial lives at most six. `duo` does not call this: it exits, and
    /// sweeps once before it installs instead.
    @discardableResult
    public static func startSweeping(every interval: Duration = .seconds(60)) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            while !Task.isCancelled {
                sweepExpired()
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: - Files

    /// The key of every file in `root` that looks like ours: `<hex>.partial`,
    /// `<hex>.json`, or a sidecar's `<hex>.json.tmp-…` left by a kill mid-write.
    private static func keys(in root: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var keys = Set<String>()
        for name in names {
            guard let dot = name.firstIndex(of: ".") else { continue }
            let key = String(name[..<dot])
            guard key.count == 64, key.allSatisfy(\.isHexDigit) else { continue }
            keys.insert(key)
        }
        return keys
    }

    private static func files(of entry: Entry) -> [URL] {
        let root = entry.partial.deletingLastPathComponent()
        let key = entry.partial.deletingPathExtension().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix(key + ".") }
            .map { root.appendingPathComponent($0, isDirectory: false) }
    }

    private static func isExpired(_ entry: Entry, at date: Date) -> Bool {
        let newest = files(of: entry).compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
        guard let newest else { return true }
        return date.timeIntervalSince(newest) > resumeRetention
    }

    private static func remove(_ entry: Entry) {
        for file in files(of: entry) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?
            .int64Value ?? 0
    }

    static func readMeta(_ entry: Entry) -> Meta? {
        guard let data = try? Data(contentsOf: entry.sidecar) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    static func writeMeta(_ meta: Meta, to entry: Entry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meta)
        let tmp = entry.sidecar.appendingPathExtension("tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: tmp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            // rename(2), not `replaceItemAt`: one atomic step on the same
            // directory, with none of that API's copy-and-swap machinery.
            guard rename(tmp.path, entry.sidecar.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }
}
