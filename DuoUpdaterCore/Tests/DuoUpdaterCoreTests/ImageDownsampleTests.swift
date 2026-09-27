import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DuoUpdaterCore

/// A fabricated RGBA image: a diagonal gradient, so it is not trivially compressible
/// and a resampler has something to do.
private func makeImage(width: Int, height: Int, shade: UInt8 = 0) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [CGColor(red: 1, green: CGFloat(shade) / 255, blue: 0, alpha: 1),
                 CGColor(red: 0, green: 0.3, blue: 1, alpha: 1)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    return context.makeImage()!
}

/// `frames` encoded as one file of `type`; more than one frame makes it animated.
private func encode(_ frames: [CGImage], as type: UTType,
                    properties: [CFString: Any] = [:]) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        data, type.identifier as CFString, frames.count, nil)!
    for frame in frames { CGImageDestinationAddImage(destination, frame, properties as CFDictionary) }
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

/// (width, height, frame count) of an encoded image, as ImageIO reads it.
private func measure(_ data: Data) throws -> (width: Int, height: Int, frames: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int),
            CGImageSourceGetCount(source))
}

@Test func wideImageIsStoredAtTheTargetWidthWithItsAspectKept() throws {
    // The shape of the illustrations that filled the cache: 3440 × 1260.
    let original = encode([makeImage(width: 3440, height: 1260)], as: .png)
    let stored = ImageDownsample.downsampledIfWider(original, maxPixelWidth: 960)
    let size = try measure(stored)
    #expect(size.width == 960)
    #expect(abs(size.height - 352) <= 1)   // 1260 × 960 / 3440 = 351.6
    #expect(size.frames == 1)
}

@Test func tallImageIsCappedByWidthNotByItsLongerSide() throws {
    // A thumbnail's max pixel size bounds the longer side; passing 960 straight
    // through would make this 960 tall and only 480 wide, half the column.
    let original = encode([makeImage(width: 2000, height: 4000)], as: .png)
    let size = try measure(ImageDownsample.downsampledIfWider(original, maxPixelWidth: 960))
    #expect(size.width == 960)
    #expect(size.height == 1920)
}

@Test func quarterTurnedImageIsMeasuredByTheWidthItDisplaysAt() throws {
    // Stored 800 × 2000 with EXIF orientation 6 (rotate 90° CW): it displays
    // 2000 wide and 800 tall, so it IS wider than 960 and must shrink to 960 × 384.
    let original = encode(
        [makeImage(width: 800, height: 2000)], as: .jpeg,
        properties: [kCGImagePropertyOrientation: 6])
    let size = try measure(ImageDownsample.downsampledIfWider(original, maxPixelWidth: 960))
    #expect(size.width == 960)
    #expect(abs(size.height - 384) <= 1)
}

@Test func imageNoWiderThanTheTargetIsReturnedByteForByte() {
    for width in [960, 400] {
        let original = encode([makeImage(width: width, height: 300)], as: .png)
        #expect(ImageDownsample.downsampledIfWider(original, maxPixelWidth: 960) == original)
    }
}

@Test func animatedImagesAreNeverFlattened() throws {
    // Wide enough to be downsampled if they were stills. Both formats ImageIO can
    // write with several frames; animated WebP it can read but not write.
    for type in [UTType.gif, UTType.png] {
        let frames = [makeImage(width: 2000, height: 600, shade: 0),
                      makeImage(width: 2000, height: 600, shade: 200)]
        let original = encode(frames, as: type)
        #expect(try measure(original).frames == 2, "fixture must actually be animated: \(type)")
        #expect(ImageDownsample.downsampledIfWider(original, maxPixelWidth: 960) == original,
                "\(type)")
    }
}

@Test func bytesThatAreNotAnImageComeBackUnchanged() {
    let junk = Data("not an image".utf8)
    #expect(ImageDownsample.downsampledIfWider(junk, maxPixelWidth: 960) == junk)
}
