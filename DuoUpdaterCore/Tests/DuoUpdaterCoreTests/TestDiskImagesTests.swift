import Foundation
import Testing

/// `TestDiskImages` reading `hdiutil info` that, under load, sometimes leaves
/// out an image that is attached.
///
/// Each names the mutation that turns it red.
@Suite struct TestDiskImagesTests {

    let image = URL(fileURLWithPath: "/var/folders/xy/T/duo-1.sparseimage")

    /// An `hdiutil info -plist` listing of `paths`, each attached as `/dev/disk15`.
    private func listing(_ paths: [String]) throws -> Data {
        let images = paths.map { path -> [String: Any] in
            ["image-path": path,
             "system-entities": [["dev-entry": "/dev/disk15"], ["dev-entry": "/dev/disk15s1"]]]
        }
        return try PropertyListSerialization.data(fromPropertyList: ["images": images], format: .xml, options: 0)
    }

    /// The listing the image is missing from is the truncated one seen under
    /// load: the system's own images only. The next listing has it again.
    ///
    /// Mutation: `absentListings = 1` → empty.
    @Test func anImageMissingFromOneListingIsLookedForAgain() async throws {
        let truncated = try listing(["/System/Library/AssetsV2/Restore/043-70362-657.dmg"])
        let full = try listing(["/System/Library/AssetsV2/Restore/043-70362-657.dmg", image.path])
        var answers = [truncated, full]
        let found = await TestDiskImages.attachments(of: image) { answers.removeFirst() }
        #expect(found.map(\.device) == ["/dev/disk15"])
        #expect(answers.isEmpty)
    }

    /// An image left out of every listing is not attached, after
    /// `absentListings` of them and no more.
    ///
    /// Mutation: break out of the loop on an empty result → one read.
    @Test func anImageMissingFromEveryListingIsNotAttached() async throws {
        let truncated = try listing(["/System/Library/AssetsV2/Restore/043-70362-657.dmg"])
        var reads = 0
        let found = await TestDiskImages.attachments(of: image) {
            reads += 1
            return truncated
        }
        #expect(found.isEmpty)
        #expect(reads == TestDiskImages.absentListings)
        #expect(TestDiskImages.absentListings == 3)
    }
}
