import SwiftUI
import AppKit

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
    /// bytes don't decode). `NSCache` cost follows the bitmap footprint rather than
    /// the compressed PNG/JPEG byte count: a 2 MB screenshot can occupy tens of MB
    /// once decoded, which is the memory the 64 MB limit is intended to bound.
    @discardableResult
    func store(_ data: Data, for url: URL) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(
            image, forKey: url as NSURL,
            cost: Self.decodedCost(of: image, encodedByteCount: data.count))
        return image
    }

    private static func decodedCost(of image: NSImage, encodedByteCount: Int) -> Int {
        let representationCosts = image.representations.compactMap { representation -> Int? in
            let width = representation.pixelsWide
            let height = representation.pixelsHigh
            guard width > 0, height > 0 else { return nil }

            // AppKit commonly expands even 24-bit source images into 32-bit buffers.
            // Preserve a larger native pixel width for high-depth bitmap reps.
            let nativeBytesPerPixel: Int
            if let bitmap = representation as? NSBitmapImageRep, bitmap.bitsPerPixel > 0 {
                nativeBytesPerPixel = (bitmap.bitsPerPixel + 7) / 8
            } else {
                nativeBytesPerPixel = 4
            }
            let bytesPerPixel = max(4, nativeBytesPerPixel)
            let minimumRowBytes = clampedProduct(width, bytesPerPixel)
            let rowBytes = max(
                minimumRowBytes,
                (representation as? NSBitmapImageRep)?.bytesPerRow ?? 0)
            return clampedProduct(rowBytes, height)
        }

        // NSImage may retain encoded backing data as well as a decoded rep. Taking
        // the larger estimate stays conservative without double-counting both.
        return max(encodedByteCount, representationCosts.max() ?? encodedByteCount)
    }

    private static func clampedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? Int.max : result
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
