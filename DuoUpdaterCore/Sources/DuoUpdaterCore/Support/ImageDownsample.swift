import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks an encoded image to the widest it will ever be drawn, before it is cached.
///
/// Written for the changelog image cache: vendors embed marketing renders at 3440 px
/// wide and the changelog column draws them at most 480 pt wide, so both the bytes on
/// disk and the decoded bitmap in memory were several times what the screen can show.
/// Measured 2026-09-27 on one machine's cache (32 images): 63 MB on disk; decoded, the
/// same images would cost 318 MB against a 64 MB memory cache.
///
/// Pure and synchronous: CPU work only, no waiting on anything, so it is fine on the
/// cooperative pool (it is not one of the calls `scripts/check_offpool.py` guards).
public enum ImageDownsample {
    /// `data` re-encoded as PNG at `maxPixelWidth` pixels wide, aspect kept — or `data`
    /// itself, unchanged, when it is not wider than that, is animated, or anything fails.
    ///
    /// - Width, not longest side: the column caps width and lets height follow, so a
    ///   tall image capped by its height would end up narrower than the column.
    /// - Animated images (more than one frame: GIF, APNG, animated WebP) are returned
    ///   untouched; a thumbnail is a single frame.
    /// - PNG because it is lossless and keeps alpha. HEIC at quality 0.8 was about a
    ///   twelfth the size on the sample above but lossy on screenshots with text,
    ///   which is a judgement this does not make; PNG already brings that cache from
    ///   63 MB to about 12 MB.
    /// - The result can be larger than `data` (a 45 KB lossy WebP became a 190 KB PNG)
    ///   and is kept anyway: the decoded bitmap, which is what the memory cache is
    ///   charged for, still drops from 11 MB to 1.4 MB.
    public static func downsampledIfWider(_ data: Data, maxPixelWidth: Int) -> Data {
        guard maxPixelWidth > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return data }
        // EXIF orientations 5–8 are quarter turns: the displayed width is the stored
        // height. The thumbnail below applies the turn, so measure what it will draw.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard width > maxPixelWidth else { return data }

        // kCGImageSourceThumbnailMaxPixelSize bounds the LONGER side, so ask for the
        // longer side that a `maxPixelWidth`-wide image of this aspect has.
        let scaledHeight = Int((Double(height) * Double(maxPixelWidth) / Double(width)).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelWidth, scaledHeight),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return data }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return data }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }
}
