import AppKit
import DuoUpdaterCore
import Observation

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
    /// bundle read while missing has no stamp, and gets one once the copy lands.
    /// `nil` for a path that has no Info.plist at all (a flat file, a bundle id),
    /// which then never changes and stays cached as before.
    ///
    /// Half-copied is covered only as far as copiers write Info.plist after the
    /// icon. Measured 2026-10-16 copying OBS.app (450 MB) while polling every 2 ms:
    /// `cp -R` and `ditto --noclone` both finished `AppIcon.icns` before
    /// Info.plist appeared (cp 0.63 s vs 0.99 s; ditto 1.01 s vs 1.73 s), with no
    /// poll seeing Info.plist beside a partial icon. Finder was not measured.
    struct BundleStamp: Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        let mtimeSeconds: Int
        let mtimeNanoseconds: Int

        nonisolated static func read(_ path: String) -> BundleStamp? {
            if case .present(let stamp) = probe(path) { return stamp }
            return nil
        }

        /// What a `stat` of the Info.plist says. `absent` only for the answers that
        /// mean "no such file" — anything else (EIO, a timed-out network mount)
        /// says nothing about whether the bundle changed.
        enum Probe: Equatable, Sendable { case present(BundleStamp), absent, unreadable }

        nonisolated static func probe(_ path: String) -> Probe {
            var info = stat()
            guard stat(path + "/Contents/Info.plist", &info) == 0 else {
                return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable
            }
            return .present(BundleStamp(
                device: Int64(info.st_dev), inode: UInt64(info.st_ino),
                mtimeSeconds: info.st_mtimespec.tv_sec, mtimeNanoseconds: info.st_mtimespec.tv_nsec))
        }
    }

    /// Bumped after each icon `revalidate` re-reads. `icon(for:)` reads it, so a
    /// view that drew an icon in `body` is redrawn once that icon is replaced —
    /// nothing else would tell SwiftUI the cache changed under an unchanged row.
    @Observable final class Revision { fileprivate(set) var value = 0 }
    static let revision = Revision()

    /// A hit is a dictionary lookup and nothing else: no `stat`, so no disk I/O
    /// on the main actor for a row that repaints on every progress tick, even when
    /// the bundle sits on a slow or hung network volume (a custom scan location
    /// can). Whether the bundle behind an entry was replaced is `revalidate`'s job.
    static func icon(for path: String) -> NSImage {
        _ = revision.value
        if let cached = cache.object(forKey: path as NSString) { return cached.image }
        let stamp = BundleStamp.read(path)
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
            for path in pending where cache.object(forKey: path as NSString) == nil {
                try? await Task.sleep(for: .milliseconds(1))
                if Task.isCancelled { return }
                _ = icon(for: path)
            }
        }
    }

    private static var prefetchTask: Task<Void, Never>?

    /// Re-read the icons whose bundle was replaced since they were cached. Called
    /// on every write to `AppListModel.results` — the one place every change on
    /// disk arrives (`refreshRow`, `replaceRow`, both scan paths) — so a swap by
    /// the CLI, a vendor updater or Finder shows within the cycle that notices it.
    ///
    /// The `stat`s run off the main actor; they are plain syscalls, and a custom
    /// scan location can sit on a volume where one blocks. Only the re-reads come
    /// back here, under the same rules as `prefetch`: one path per step with the
    /// run loop handed back in between.
    ///
    /// One pass at a time, and a call that lands while one runs only replaces the
    /// paths the NEXT pass will check. Cancelling the running pass instead (the
    /// first version) could not cancel the detached `stat`s it was awaiting, so on
    /// a mount where they hang every write to `results` would have parked another
    /// cooperative-pool thread behind them.
    ///
    /// A path whose `stat` fails for any reason but "no such file" is left as it
    /// is: re-reading it would put the same unreachable volume's I/O on the main
    /// actor, which is what keeping the `stat`s off it is for. Measured 2026-10-16 in one long-lived process, replacing bundles in
    /// place with `replaceItemAt` and re-reading at the same path: one re-read took
    /// 6–130 ms (mostly 10–60); ten in one pass, 183–284 ms over three runs — what
    /// reading them synchronously in `body` would have cost as a single stall.
    static func revalidate(_ paths: [String]) {
        pendingRevalidation = paths
        guard revalidateTask == nil else { return }
        revalidateTask = Task(priority: .utility) {
            while let next = pendingRevalidation {
                pendingRevalidation = nil
                await revalidatePass(next)
            }
            revalidateTask = nil
        }
    }

    private static var revalidateTask: Task<Void, Never>?
    private static var pendingRevalidation: [String]?

    /// How `revalidatePass` stats a path. A seam so tests can hold a `stat` the
    /// way a hung mount would, or fail one; nothing in the app sets it.
    static var probeBundle: @Sendable (String) -> BundleStamp.Probe = BundleStamp.probe

    /// Wait for the passes `revalidate` has queued. Tests only.
    static func revalidationSettled() async { await revalidateTask?.value }

    /// One `revalidate`, awaitable so tests can run it to completion.
    static func revalidatePass(_ paths: [String]) async {
        let cached = paths.compactMap { path in
            cache.object(forKey: path as NSString).map { (path, $0.stamp) }
        }
        guard !cached.isEmpty else { return }
        let toStat = cached.map(\.0)
        let probe = probeBundle
        let current = await Task.detached(priority: .utility) {
            toStat.map(probe)
        }.value
        for ((path, old), now) in zip(cached, current) {
            let stamp: BundleStamp?
            switch now {
            case .present(let s): stamp = s
            case .absent: stamp = nil
            case .unreadable: continue
            }
            if stamp == old { continue }
            try? await Task.sleep(for: .milliseconds(1))
            // Still the entry that was checked: a miss or `invalidate` since then
            // has already put the new copy's icon (or nothing) there.
            guard let entry = cache.object(forKey: path as NSString), entry.stamp == old else { continue }
            Log.app.info("icon stale: bundle replaced at \((path as NSString).lastPathComponent, privacy: .public), re-reading")
            cache.removeObject(forKey: path as NSString)
            _ = icon(for: path)
            revision.value &+= 1
        }
    }

    /// Drop the cached icon for a path so the next lookup re-reads from disk.
    /// Called after an in-place install: the bundle is replaced but its path is
    /// unchanged, so the stale icon would otherwise persist until app restart.
    static func invalidate(_ path: String) { cache.removeObject(forKey: path as NSString) }

    /// Draw `path`'s icon from the bundle at `source`: for an app an
    /// interrupted install left gone, whose row has nothing at its own path to
    /// read one from (`InstallJournal.InterruptedInstall.iconSource`). Stamped
    /// as a missing bundle, so the app's own icon replaces it once a copy is
    /// back at `path` (`revalidate`), or at once after a restore (`invalidate`).
    static func standIn(for path: String, from source: String) {
        guard BundleStamp.read(path) == nil else { return }
        cache.setObject(Entry(image: NSWorkspace.shared.icon(forFile: source), stamp: nil), forKey: path as NSString)
        revision.value &+= 1
    }

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
