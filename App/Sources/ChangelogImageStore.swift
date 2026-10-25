import Foundation
import AppKit
import CryptoKit
import DuoUpdaterCore

/// Cross-launch byte cache for changelog illustration images (WeChat embeds feature
/// screenshots between its change lines). The changelog disk cache stores image
/// *URLs*; this stores the *bytes*, so a prewarmed changelog's pictures paint
/// instantly instead of streaming in on appear.
///
/// Disk layer only (bytes, `Data` is Sendable so it crosses the actor boundary
/// cleanly — `NSImage` is not). Decoding happens in ``ImageMemoryCache`` on the
/// caller's executor: off-main during prewarming, or from the view task on demand.
/// Best-effort throughout: any failure yields nil and the view just shows nothing,
/// exactly as the old `AsyncImage` error branch did.
actor ImageStore {
    static let shared = ImageStore()

    private let directory: URL
    /// Coalesce concurrent fetches of the same URL onto one request.
    private var inflight: [URL: Task<Data?, Never>] = [:]

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("changelog-images", isDirectory: true)
        }
    }

    /// Soft cap on the on-disk byte cache: once the directory exceeds this, the
    /// least-recently-modified files are pruned back under it after a write. Bounds an
    /// otherwise unbounded directory that would accumulate every version's images
    /// forever. Illustrations are NOT small at the source — vendors ship 3440 px
    /// renders of several MB, and full-size copies filled this cap (63 MB, 32 files,
    /// 2026-09-27) — which is why new ones are stored at ``storedPixelWidth``.
    private static let diskByteCap = 64 * 1024 * 1024   // 64 MB

    /// The widest the changelog draws an illustration, in points (`noteImage` in
    /// `WorkbenchWindowView` frames ``CachedImage`` to this; it is the only place one
    /// is shown).
    static let maxDisplayPointWidth: CGFloat = 480

    /// Pixel width images are stored at: ``maxDisplayPointWidth`` at a Retina
    /// display's 2x backing scale. Anything wider is downsampled before it is written,
    /// so neither the file nor the decoded bitmap carries pixels no screen draws.
    /// Files cached before this existed are read back as they are.
    static let storedPixelWidth = Int(maxDisplayPointWidth) * 2

    /// Running estimate of the directory's byte total, so the cap can be enforced
    /// without a full `contentsOfDirectory` + per-file `resourceValues` sweep after
    /// *every* image. A changelog with a dozen illustrations used to trigger a dozen
    /// directory walks in a row. `nil` = not measured yet this session, so the next
    /// write does one real sweep (which also seeds this).
    private var estimatedDiskBytes: Int?

    /// Image bytes for `url`: disk hit, else download (via the shared update session,
    /// whose private cache also absorbs a repeat), persist, and return. nil on any
    /// network/decoding failure.
    /// - Parameter appID: whose release notes referenced this image. Passed in
    ///   rather than read from a task-local because the fetch runs in a detached
    ///   `Task` that a caller's attribution scope would not reach — these images
    ///   are the largest thing the changelog pulls (6.5 MB on one Raycast note),
    ///   and an unattributed row that size is the one people ask about.
    func data(for url: URL, appID: String? = nil) async -> Data? {
        // Before the disk and the network both: the URL comes out of a vendor's
        // page and is fetched with nobody having clicked anything, so it is held
        // to the policy the changelog web view applies (https, a real name, no
        // credentials, port 443). `request` below is confined too, so a redirect
        // cannot take the fetch somewhere this check would have refused.
        guard ChangelogURLPolicy.isDisplayable(url) else { return nil }
        if let onDisk = try? Data(contentsOf: fileURL(for: url)) { return onDisk }
        if let task = inflight[url] { return await task.value }
        let task = Task<Data?, Never> { [directory] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await RequestAttribution.withApp(appID, operation: {
                    try await URLSession.updates.countedData(
                        for: ChangelogURLPolicy.confine(request), purpose: .changelogImage)
                  }),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  NSImage(data: data) != nil   // only cache things that actually decode
            else { return nil }
            let stored = ImageDownsample.downsampledIfWider(
                data, maxPixelWidth: Self.storedPixelWidth)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try? stored.write(
                to: directory.appendingPathComponent(Self.filename(for: url)), options: .atomic)
            return stored
        }
        inflight[url] = task
        let result = await task.value
        // Retract only our own registration — see `ChangelogCache.load` for why an
        // unconditional clear can unregister a *newer* task and lose coalescing.
        if inflight[url] == task { inflight[url] = nil }
        if let result { noteWrite(bytes: result.count) }
        return result
    }

    /// Account for a freshly-written image and sweep only when the running estimate
    /// says we might be over the cap. The estimate can only drift *low* (files we
    /// didn't write this session), which the first sweep corrects exactly.
    private func noteWrite(bytes: Int) {
        guard let current = estimatedDiskBytes else {
            pruneIfOverCap()   // unmeasured: one real sweep seeds the estimate
            return
        }
        estimatedDiskBytes = current + bytes
        if current + bytes > Self.diskByteCap { pruneIfOverCap() }
    }

    /// Keep the on-disk cache under ``diskByteCap`` by deleting the oldest files
    /// (by modification date) until it fits, and record the resulting exact total in
    /// ``estimatedDiskBytes``. Best-effort; the only path that walks the directory.
    private func pruneIfOverCap() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        else { return }
        var sized = entries.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize else { return nil }
            return (url, size, v.contentModificationDate ?? .distantPast)
        }
        var total = sized.reduce(0) { $0 + $1.size }
        defer { estimatedDiskBytes = total }
        guard total > Self.diskByteCap else { return }
        sized.sort { $0.date < $1.date }   // oldest first
        for entry in sized where total > Self.diskByteCap {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Empty the disk cache (Settings → Storage). Through the actor rather than
    /// a bare file removal so the running estimate restarts from zero with it —
    /// left alone it would read as still near the cap and sweep on the next write.
    /// An in-flight download still lands afterwards; that is one image, re-fetched
    /// because something on screen asked for it.
    func removeAll() {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: entry)
        }
        estimatedDiskBytes = 0
    }

    private func fileURL(for url: URL) -> URL {
        directory.appendingPathComponent(Self.filename(for: url))
    }

    /// A deterministic, collision-free filename — a SHA-256 of the absolute URL (the
    /// URLs carry query strings and slashes, and Swift's `Hasher` is per-process
    /// randomized, so neither is usable as a stable on-disk key).
    private static func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }
}
