import AppKit
import DuoUpdaterCore

/// Caches app icons by path. `NSWorkspace.icon(forFile:)` hits the disk, and rows
/// re-render on every install-progress tick — without a cache that's one icon
/// lookup per row per tick, a real source of stutter while downloads run.
///
/// Its own file rather than a corner of `MenuContentView` so `RowStateGallery` can
/// link it without dragging in `AppListModel`.
@MainActor
enum AppIconCache {
    // NSCache (vs a plain dict): it evicts under memory pressure on its own, so a
    // large library's worth of cached icons can't grow unbounded.
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 512
        return cache
    }()

    /// An icon and the stamp of the bundle it was read from.
    private final class Entry {
        let image: NSImage
        let stamp: BundleStamp?
        init(image: NSImage, stamp: BundleStamp?) { self.image = image; self.stamp = stamp }
    }

    /// Which copy of a bundle sits at a path: its `Contents/Info.plist`'s file
    /// identity and mtime. `invalidate` only covers the GUI's own installs; the
    /// `duo` CLI, a vendor's self-updater or a drag in Finder replace the bundle at
    /// the same path without telling us, and the cached icon outlived the copy it
    /// came from until DuoUpdater restarted (MuseScore's row kept a ⊘ after `duo
    /// install` swapped 4.7.4 for 4.7.5, 2026-10-16, while a fresh process read the
    /// right icon). A replaced bundle brings a new Info.plist, so a new inode; a
    /// bundle read while missing or half-copied has no stamp, and gets one once the
    /// copy lands. `nil` for a path that has no Info.plist at all (a flat file, a
    /// bundle id), which then never changes and stays cached as before.
    ///
    /// Checked on every lookup rather than at scan time: rows repaint from many
    /// places (`refreshRow`, `replaceRow`, both scan paths) and a check at only some
    /// of them would leave the rest stale. The cost is one `stat`: measured
    /// 2026-10-16 at 1.2–1.6 µs per lookup over the 185 bundles in this Mac's
    /// /Applications (warm, -O, five runs of 1000 passes), against the 1–25 ms of a
    /// miss; at, say, 20 rows repainting 10× a second that is ~0.3 ms a second.
    struct BundleStamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let mtime: timespec

        static func == (a: Self, b: Self) -> Bool {
            a.device == b.device && a.inode == b.inode
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
        }

        static func read(_ path: String) -> BundleStamp? {
            var info = stat()
            guard stat(path + "/Contents/Info.plist", &info) == 0 else { return nil }
            return BundleStamp(device: info.st_dev, inode: info.st_ino, mtime: info.st_mtimespec)
        }
    }

    static func icon(for path: String) -> NSImage {
        let stamp = BundleStamp.read(path)
        if let cached = cache.object(forKey: path as NSString) {
            if cached.stamp == stamp { return cached.image }
            Log.app.info("icon stale: bundle replaced at \((path as NSString).lastPathComponent, privacy: .public), re-reading")
        }
        // Cache miss = a synchronous disk hit on the main actor. Time it: if app
        // switches stutter, a slow icon read here is one suspect.
        let start = Date()
        let image = NSWorkspace.shared.icon(forFile: path)
        let ms = Date().timeIntervalSince(start) * 1000
        if ms > 2 {
            Log.app.info("perf icon miss: \(ms, format: .fixed(precision: 1), privacy: .public)ms for \((path as NSString).lastPathComponent, privacy: .public)")
        }
        cache.setObject(Entry(image: image, stamp: stamp), forKey: path as NSString)
        return image
    }

    /// Read ahead of the first render. Popover and workbench rows call `icon(for:)`
    /// from `body`, so on a cold cache the first open paid a LaunchServices read
    /// per visible row — ~22 ms of the 269 ms main-thread cost of a cold first
    /// popover open in a Time Profiler trace (n=1).
    ///
    /// On the main actor, one path per step, because nothing in Apple's
    /// documentation says `icon(forFile:)` may be called anywhere else: the
    /// Thread Safety Summary lists `NSImage` as thread-unsafe and does not mention
    /// `NSWorkspace` (developer.apple.com/library/archive/documentation/Cocoa/
    /// Conceptual/Multithreading/ThreadSafetySummary). Staying here is also what
    /// keeps `invalidate` exact — a step is one read-and-insert with no suspension
    /// inside it, so an invalidation lands either before it (the read sees the new
    /// bundle) or after it (and removes what it inserted). An off-main read that
    /// began before an in-place install could insert the old icon after the
    /// invalidation and pin it.
    ///
    /// The sleep between steps is what hands the run loop back, so no step holds
    /// the main thread longer than that one path's on-demand miss already did.
    /// Measured 2026-09-25 over the 126 bundles in one /Applications, fresh
    /// process: a cold pass cost 81–98 ms; 122 reads were under 3 ms, the first
    /// ~6 ms, and two bundles (VLC, Amp) ~20–25 ms each on every run — a single
    /// call, which no batching on this actor can split. Prefetching those 126 with
    /// 1 ms between reads took ~300 ms and 92–102 ms of reads; with 5 ms, ~880 ms
    /// and 100–190 ms, the same reads running slower after the longer pauses (why
    /// is not established). So the pause is the shortest that still returns to
    /// the run loop. A new call replaces the one in flight, so the latest ordering
    /// wins. Callers pass paths in the order rows appear; at most `countLimit` are
    /// read, since past that each insert evicts an earlier one.
    static func prefetch(_ paths: [String]) {
        prefetchTask?.cancel()
        let pending = paths.prefix(cache.countLimit)
        prefetchTask = Task(priority: .utility) {
            for path in pending where !isFresh(path) {
                try? await Task.sleep(for: .milliseconds(1))
                if Task.isCancelled { return }
                _ = icon(for: path)
            }
        }
    }

    private static var prefetchTask: Task<Void, Never>?

    /// Cached, and read from the copy of the bundle that is at the path now.
    private static func isFresh(_ path: String) -> Bool {
        guard let cached = cache.object(forKey: path as NSString) else { return false }
        return cached.stamp == BundleStamp.read(path)
    }

    /// Drop the cached icon for a path so the next lookup re-reads from disk.
    /// Called after an in-place install: the bundle is replaced but its path is
    /// unchanged, so the stale icon would otherwise persist until app restart.
    static func invalidate(_ path: String) { cache.removeObject(forKey: path as NSString) }

    /// The real App Store.app icon, used as the source tag for store-managed apps.
    /// Resolved once (the path is fixed) and shared through the same icon cache.
    static let appStore = icon(for: "/System/Applications/App Store.app")

    /// The real TestFlight.app icon, the source tag for TestFlight-managed betas.
    /// Resolved by bundle id rather than by a fixed path like `appStore` above:
    /// TestFlight is not part of macOS, so it has no guaranteed location — and it
    /// is `nil` on a Mac without it, which is what keeps the tag from drawing
    /// `NSWorkspace.icon(forFile:)`'s generic placeholder for a missing file.
    ///
    /// A `var` for one caller only: `RowStateGallery` replaces it with a committed
    /// fixture before rendering. Because this one resolves through LaunchServices
    /// rather than a path every Mac has, the reference sheet would otherwise depend
    /// on whether the machine running `make gallery` happens to have TestFlight —
    /// on one that doesn't, four tiles regenerate as the word, with every gallery
    /// gate still green and nothing to say why. (`appStore` has a weaker version of
    /// the same exposure: its icon is whatever the host's macOS ships.) Nothing in
    /// the app writes this.
    private(set) static var testFlight: NSImage? = NSWorkspace.shared
        .urlForApplication(withBundleIdentifier: "com.apple.TestFlight")
        .map { icon(for: $0.path) }

    /// Point `testFlight` at a fixture. `RowStateGallery` only — see above.
    static func overrideTestFlightIconForGallery(_ image: NSImage) { testFlight = image }
}
