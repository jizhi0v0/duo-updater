import SwiftUI
import AppKit
import CryptoKit
import DuoUpdaterCore

/// Cross-launch byte cache for changelog illustration images (WeChat embeds feature
/// screenshots between its change lines). The changelog disk cache stores image
/// *URLs*; this stores the *bytes*, so a prewarmed changelog's pictures paint
/// instantly instead of streaming in on appear.
///
/// Disk layer only (bytes, `Data` is Sendable so it crosses the actor boundary
/// cleanly — `NSImage` is not). Decoding to `NSImage` happens on the main actor in
/// ``ImageMemoryCache``. Best-effort throughout: any failure yields nil and the view
/// just shows nothing, exactly as the old `AsyncImage` error branch did.
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
    /// least-recently-modified files are pruned back under it after a write. Changelog
    /// illustrations are small; this bounds an otherwise unbounded directory that
    /// would accumulate every version's images forever.
    private static let diskByteCap = 64 * 1024 * 1024   // 64 MB

    /// Running estimate of the directory's byte total, so the cap can be enforced
    /// without a full `contentsOfDirectory` + per-file `resourceValues` sweep after
    /// *every* image. A changelog with a dozen illustrations used to trigger a dozen
    /// directory walks in a row. `nil` = not measured yet this session, so the next
    /// write does one real sweep (which also seeds this).
    private var estimatedDiskBytes: Int?

    /// Image bytes for `url`: disk hit, else download (via the shared update session,
    /// whose private cache also absorbs a repeat), persist, and return. nil on any
    /// network/decoding failure.
    func data(for url: URL) async -> Data? {
        if let onDisk = try? Data(contentsOf: fileURL(for: url)) { return onDisk }
        if let task = inflight[url] { return await task.value }
        let task = Task<Data?, Never> { [directory] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.updates.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  NSImage(data: data) != nil   // only cache things that actually decode
            else { return nil }
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try? data.write(
                to: directory.appendingPathComponent(Self.filename(for: url)), options: .atomic)
            return data
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

/// In-memory decoded-image cache. The synchronous read is what lets ``CachedImage``
/// paint a prewarmed image on the very first frame with no spinner — so it must be
/// callable from a `View.init` (any actor). `NSCache` is itself thread-safe, so this
/// needs no isolation and is safely `Sendable`.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 64 * 1024 * 1024   // ~64 MB of decoded pixels
    }

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    /// Decode `data` and cache it under `url`. Returns the decoded image (nil if the
    /// bytes don't decode). Cost is the byte count — a coarse but adequate proxy.
    @discardableResult
    func store(_ data: Data, for url: URL) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }
}

/// A changelog illustration that paints from cache instantly when prewarmed, and
/// otherwise loads disk→network once and caches. Drop-in replacement for the
/// `AsyncImage` we used before, minus the per-appear network round-trip.
struct CachedImage: View {
    let url: URL
    @State private var phase: Phase

    /// Three explicit states so a load can actually *fail*: `loading` shows a quiet
    /// placeholder, `loaded` paints, and `failed` collapses to nothing — matching the
    /// old `AsyncImage` error branch, so a dead/404/undecodable URL never strands a
    /// perpetual spinner. `loaded` carries the image so a reused view (the content
    /// `ForEach` is keyed by offset) can reconcile against a changed `url` below.
    private enum Phase { case loading, loaded(NSImage), failed }

    init(url: URL) {
        self.url = url
        // Seed synchronously from the main-actor memory cache so a prewarmed image
        // is on screen on the first frame — no loading flash.
        _phase = State(initialValue: ImageMemoryCache.shared.image(for: url)
            .map(Phase.loaded) ?? .loading)
    }

    var body: some View {
        Group {
            switch phase {
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .failed:
                // Confirmed failure: show nothing rather than a perpetual spinner or
                // a broken-image box.
                EmptyView()
            case .loading:
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 120)
                    .overlay(ProgressView())
            }
        }
        // Re-resolves whenever `url` changes. SwiftUI reuses this view's identity
        // across changelog entries (the content `ForEach` is keyed by offset), and
        // `init` does NOT re-run on reuse — so the reconciliation must happen here, or
        // a recycled instance would keep the previous entry's image.
        .task(id: url) {
            if let cached = ImageMemoryCache.shared.image(for: url) {
                phase = .loaded(cached)
                return
            }
            phase = .loading
            guard let data = await ImageStore.shared.data(for: url),
                  let image = ImageMemoryCache.shared.store(data, for: url) else {
                phase = .failed
                return
            }
            phase = .loaded(image)
        }
    }
}
