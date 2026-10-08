import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import DuoUpdaterCore

/// The pure rules `BrewFormulaIconService` decides with: where a formula's icon
/// is asked for, and which of a page's links is taken. Nothing here touches the
/// network or Homebrew.
struct BrewFormulaIconServiceTests {

    // MARK: GitHub owner avatar

    @Test func githubRepoHomepageNamesItsOwner() {
        #expect(BrewFormulaIconService.githubOwner(
            ofHomepage: URL(string: "https://github.com/BurntSushi/ripgrep")!) == "BurntSushi")
    }

    @Test func onlyAnOrganisationsAvatarIsTaken() {
        let org = #"{"login":"apple","type":"Organization","avatar_url":"https://avatars.githubusercontent.com/u/10639145?v=4"}"#
        #expect(BrewFormulaIconService.organizationAvatar(fromUser: Data(org.utf8))?.absoluteString
            == "https://avatars.githubusercontent.com/u/10639145?v=4&s=128")
        let person = #"{"login":"BurntSushi","type":"User","avatar_url":"https://avatars.githubusercontent.com/u/456674?v=4"}"#
        #expect(BrewFormulaIconService.organizationAvatar(fromUser: Data(person.utf8)) == nil)
    }

    @Test func githubPagesHomepageNamesItsOwner() {
        #expect(BrewFormulaIconService.githubOwner(
            ofHomepage: URL(string: "https://jqlang.github.io/jq/")!) == "jqlang")
    }

    @Test func otherHomepagesHaveNoOwner() {
        #expect(BrewFormulaIconService.githubOwner(ofHomepage: URL(string: "https://curl.se/")!) == nil)
        #expect(BrewFormulaIconService.githubOwner(ofHomepage: URL(string: "https://github.com/")!) == nil)
        // Not a login: refused rather than spliced into a URL.
        #expect(BrewFormulaIconService.githubOwner(
            ofHomepage: URL(string: "https://github.com/a.b/c")!) == nil)
    }

    @Test func codeHostsAreNotAskedForAProjectIcon() {
        #expect(BrewFormulaIconService.isSharedHost(URL(string: "https://sourceforge.net/projects/iperf2/")!))
        #expect(BrewFormulaIconService.isSharedHost(URL(string: "https://git.sr.ht/~foo/bar")!))
        #expect(!BrewFormulaIconService.isSharedHost(URL(string: "https://www.gnu.org/software/wget/")!))
    }

    // MARK: Page links

    private let base = URL(string: "https://example.org/docs/")!

    @Test func largestLinkComesFirstAndFaviconLast() {
        let html = """
            <head>
            <link rel="icon" href="/favicon-32.png" sizes="32x32">
            <link rel="apple-touch-icon" href="touch.png">
            <link rel="icon" type="image/png" href="https://cdn.example.org/i-192.png" sizes="16x16 192x192">
            </head>
            """
        #expect(BrewFormulaIconService.iconCandidates(inHTML: html, base: base).map(\.absoluteString) == [
            "https://cdn.example.org/i-192.png",
            "https://example.org/docs/touch.png",   // apple-touch-icon with no sizes: 180
            "https://example.org/favicon-32.png",
            "https://example.org/favicon.ico",
        ])
    }

    @Test func svgMaskAndCleartextLinksAreSkippedOrUpgraded() {
        let html = """
            <link rel="mask-icon" href="/safari.svg" color="#000">
            <link rel="icon" type="image/svg+xml" href="/icon">
            <link rel="icon" href="/logo.svg">
            <LINK REL='Shortcut Icon' HREF='http://example.org/old.ico'>
            """
        #expect(BrewFormulaIconService.iconCandidates(inHTML: html, base: base).map(\.absoluteString) == [
            "https://example.org/old.ico",
            "https://example.org/favicon.ico",
        ])
    }

    @Test func aPageWithNoLinksStillOffersTheFavicon() {
        #expect(BrewFormulaIconService.iconCandidates(inHTML: "<html></html>", base: base)
            .map(\.absoluteString) == ["https://example.org/favicon.ico"])
    }

    @Test func declaredSizes() {
        #expect(BrewFormulaIconService.largestDeclaredSize("16x16 32x32") == 32)
        #expect(BrewFormulaIconService.largestDeclaredSize("180X180") == 180)
        #expect(BrewFormulaIconService.largestDeclaredSize("any") == nil)
    }

    @Test func httpHomepageIsAskedOverHTTPS() {
        #expect(BrewFormulaIconService.secure(URL(string: "http://www.x.org/")!)?.absoluteString
            == "https://www.x.org/")
        #expect(BrewFormulaIconService.secure(URL(string: "ftp://ftp.gnu.org/")!) == nil)
    }

    // MARK: brew info

    @Test func homepagesKeyedByNameAndFullName() {
        let json = #"""
            {"formulae": [
              {"name": "bun", "full_name": "oven-sh/bun/bun", "homepage": "https://bun.sh"},
              {"name": "nohome", "full_name": "nohome"}
            ], "casks": []}
            """#
        let map = BrewFormulaIconService.parseHomepages(Data(json.utf8))
        #expect(map["bun"]?.absoluteString == "https://bun.sh")
        #expect(map["oven-sh/bun/bun"]?.absoluteString == "https://bun.sh")
        #expect(map["nohome"] == nil)
    }

    // MARK: Image normalisation

    private func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func pixelWidth(_ data: Data) -> Int? {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int
    }

    @Test func largeIconIsStoredAt128() throws {
        let stored = try #require(BrewFormulaIconService.normalizedIcon(png(width: 512, height: 512)))
        #expect(pixelWidth(stored) == 128)
    }

    @Test func smallIconKeepsItsSize() throws {
        let stored = try #require(BrewFormulaIconService.normalizedIcon(png(width: 48, height: 48)))
        #expect(pixelWidth(stored) == 48)
    }

    @Test func tinyFaviconAndNonImagesAreRefused() {
        #expect(BrewFormulaIconService.normalizedIcon(png(width: 16, height: 16)) == nil)
        #expect(BrewFormulaIconService.normalizedIcon(Data("<html>".utf8)) == nil)
    }
}
