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
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        // Cache miss = a synchronous disk hit on the main actor. Time it: if app
        // switches stutter, a slow icon read here is one suspect.
        let start = Date()
        let image = NSWorkspace.shared.icon(forFile: path)
        let ms = Date().timeIntervalSince(start) * 1000
        if ms > 2 {
            Log.app.info("perf icon miss: \(ms, format: .fixed(precision: 1), privacy: .public)ms for \((path as NSString).lastPathComponent, privacy: .public)")
        }
        cache.setObject(image, forKey: path as NSString)
        return image
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
