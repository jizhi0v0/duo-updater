import Testing
import Foundation
@testable import DuoUpdaterCore

/// WeChat's feed lists 7 releases spanning four generations, and the recipe reads
/// two different things out of it with two different rules: the version is the
/// HIGHEST match anywhere (`selectHighest`), the download URL is the FIRST
/// `<enclosure>` anywhere. Un-sliced, those are independent selections over the
/// same body — they agree today only because Tencent lists newest first.
///
/// `entryStartPattern` ties them to one item. This suite pins that, against the
/// real response body (`dldir1.qq.com/weixin/mac/mac-release.xml`, captured
/// 2026-08-30, trimmed to the fields these rules read and with the volatile
/// `?t=<token>` query stripped so the fixture cannot rot).
@Suite struct WeChatEntryScopingTests {

    /// The real body. Note item 2 carries `sparkle:shortVersionString` as an
    /// ATTRIBUTE on the enclosure rather than an element — which is why the
    /// recipe's pattern accepts both forms, and why a fixture that normalised
    /// that away would stop testing the pattern that ships.
    static let feed = #"""
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>4.1.13.11</title>
      <sparkle:shortVersionString>4.1.13.11</sparkle:shortVersionString>
      <sparkle:version>269579</sparkle:version>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <enclosure url="https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_4.1.13.11_269579.dmg" length="521477708" type="application/octet-stream" sparkle:edSignature="haHkQfkun3E/sbD4kj0tqleyQXa3aojYKDQw8G+GRU/013bVl1oP0JPmQ9Dtt8jGkxpuS7qLUYDogu19nx/oAg=="/>
    </item>
    <item>
      <title>4.1.13.11</title>
      <sparkle:version>269579</sparkle:version>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <sparkle:maximumSystemVersion>14.3</sparkle:maximumSystemVersion>
      <enclosure url="https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_4.1.13.11_269579.dmg" sparkle:shortVersionString="4.1.13.11" type="application/octet-stream" sparkle:edSignature="haHkQfkun3E/sbD4kj0tqleyQXa3aojYKDQw8G+GRU/013bVl1oP0JPmQ9Dtt8jGkxpuS7qLUYDogu19nx/oAg=="/>
    </item>
    <item>
      <title>4.1.13.11</title>
      <sparkle:shortVersionString>4.1.13.11</sparkle:shortVersionString>
      <sparkle:version>269579</sparkle:version>
      <sparkle:minimumSystemVersion>14.3</sparkle:minimumSystemVersion>
      <sparkle:maximumSystemVersion>15.0</sparkle:maximumSystemVersion>
    </item>
    <item>
      <title>3.8.10.17</title>
      <sparkle:version>28632</sparkle:version>
      <sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
      <enclosure url="https://dldir1.qq.com/weixin/mac/WeChatMac_10_15.dmg" sparkle:version="28632" sparkle:shortVersionString="3.8.10.17" length="370570664" type="application/octet-stream" sparkle:dsaSignature="MC0CFQDQt42HUBrBXN8fP7AAZsITuIgrWwIUb3nhJLkVqnIn73ZrGNJO9ezN6bQ=" sparkle:edSignature="vnxq+yKHT7wtRZKz5clxP/6fKM5ng7of8dSZwuayHqbVTueREDTRRPtwltKAU1zW4mqVzApy1FmU0toaVtmpAg==" sparkle:md5="f2d068df06390024415b5a402ad34478"/>
    </item>
    <item>
      <title>3.8.2.21</title>
      <sparkle:version>27317</sparkle:version>
      <sparkle:minimumSystemVersion>10.12</sparkle:minimumSystemVersion>
      <enclosure url="https://dldir1.qq.com/weixin/mac/WeChatMac_382.dmg" sparkle:version="27317" sparkle:shortVersionString="3.8.2.21" length="352516168" type="application/octet-stream" sparkle:dsaSignature="MC0CFBrYEPv5JuSiPHM+57PV17xJSotlAhUA8Fd15e0jfeTJXcIqRC0C/jCgrIE=" sparkle:md5="0cfc2e9306f44de8d40c1d9bfd69ce0a"/>
    </item>
    <item>
      <title>3.4.1.17</title>
      <sparkle:minimumSystemVersion>10.11</sparkle:minimumSystemVersion>
      <enclosure url="https://dldir1.qq.com/weixin/mac/WeChatMac_10_11.dmg" sparkle:version="21938" sparkle:shortVersionString="3.4.1.17" length="169643054" type="application/octet-stream" sparkle:dsaSignature="MCwCFBCz91aF8uBSK7AA+yew2Oh5giOuAhQ6bnb0SRsIm+Q4DJYn/NuHVSzVGA==" sparkle:md5="86619de1d7571014a65c4e5f37462d72"/>
    </item>
    <item>
      <title>2.3.31.22</title>
      <sparkle:maximumSystemVersion>10.10.6</sparkle:maximumSystemVersion>
      <enclosure url="https://dldir1.qq.com/weixin/mac/WeChatMac_10_10.dmg" sparkle:version="13425" sparkle:shortVersionString="2.3.31.22" length="33457380" type="application/octet-stream" sparkle:dsaSignature="MCwCFEsn/7iLKqYAcVbAKVhMlm8fJnNAAhQK7Bm3Yy6YcZzfmivf/aNR8clpkQ==" sparkle:md5="f1dcdcef40bd9c05a5ac4bd5f8760d84"/>
    </item>
  </channel>
</rss>
"""#

    private func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.tencent.xinWeChat" })
    }

    /// Every item's own enclosure, in document order — derived from the fixture
    /// rather than hand-listed, so a re-capture cannot leave a stale copy behind.
    private static func enclosures(in body: String) -> [String] {
        body.components(separatedBy: "<item>").dropFirst().map { item in
            guard let r = item.range(of: #"<enclosure url="[^"]+""#, options: .regularExpression)
            else { return "NONE" }
            return String(item[r]).replacingOccurrences(of: #"<enclosure url=""#, with: "")
                .replacingOccurrences(of: "\"", with: "")
                .components(separatedBy: "/").last ?? "NONE"
        }
    }

    /// The premise the whole suite rests on: this really is a multi-generation
    /// feed whose items disagree about which artifact they name. If Tencent ever
    /// collapses it to one item, these tests stop testing anything and should be
    /// re-derived rather than left passing vacuously.
    @Test func theFixtureReallyIsAMultiGenerationFeed() {
        let encs = Self.enclosures(in: Self.feed)
        #expect(encs.count == 7)
        #expect(encs[0] == "xWeChatMac_universal_4.1.13.11_269579.dmg")
        #expect(encs[2] == "NONE", "the min14.3/max15.0 bucket ships no enclosure at all")
        #expect(encs[3] == "WeChatMac_10_15.dmg", "a 3.8-generation artifact lives in the same feed")
        #expect(Set(encs).count > 1, "items must not all name the same file")
    }

    @Test func theRecipeSlicesTheFeedIntoItems() throws {
        #expect(try recipe().entryStartPattern == "<item>")
        #expect(try recipe().selectHighest)
    }

    /// Against the real body as Tencent orders it today: version and download URL
    /// both come from item 1.
    @Test func versionAndDownloadBothComeFromTheWinningItem() async throws {
        let server = try RecipeVerificationTests.StubServer(
            body: Self.feed, contentType: "application/xml")
        defer { server.stop() }
        let outcome = await VendorProbeSource().probeDiagnostic(try recipe().with(url: server.url))
        #expect(outcome.remote?.shortVersion == "4.1.13")
        #expect(outcome.remote?.downloadURL?.lastPathComponent
            == "xWeChatMac_universal_4.1.13.11_269579.dmg")
    }

    /// THE REGRESSION. Same body, items reordered so the 3.8-generation item is
    /// listed first — the one thing standing between today's correct answer and a
    /// wrong one, since document order is the vendor's to change and not ours.
    ///
    /// Un-sliced, this pairs the highest version found anywhere ("4.1.13") with
    /// the first enclosure found anywhere (`WeChatMac_10_15.dmg`, a 3.8 build):
    /// the user is told 4.1.13 and handed a three-generation-old artifact, with
    /// nothing failing and nothing to notice. Sliced, both readers land in the
    /// same item and the pairing holds.
    @Test func aReorderedFeedCannotPairTheNewVersionWithALegacyArtifact() async throws {
        let items = Self.feed.components(separatedBy: "<item>")
        let head = items[0]
        var rest = Array(items.dropFirst())
        rest.insert(rest.remove(at: 3), at: 0)   // the WeChatMac_10_15.dmg item, first
        let reordered = head + rest.map { "<item>" + $0 }.joined()

        // Premise: the reorder really did put the legacy artifact first, so the
        // un-sliced first-match rule would now select it.
        #expect(Self.enclosures(in: reordered).first == "WeChatMac_10_15.dmg")

        let server = try RecipeVerificationTests.StubServer(
            body: reordered, contentType: "application/xml")
        defer { server.stop() }
        let outcome = await VendorProbeSource().probeDiagnostic(try recipe().with(url: server.url))

        #expect(outcome.remote?.shortVersion == "4.1.13")
        #expect(outcome.remote?.downloadURL?.lastPathComponent
            == "xWeChatMac_universal_4.1.13.11_269579.dmg",
            "the version and the artifact must come from the same item")
        #expect(outcome.remote?.downloadURL?.lastPathComponent != "WeChatMac_10_15.dmg")
    }

    /// Three items all read "4.1.13"; only the first of them carries the universal
    /// dmg (the second names the same file but is capped at macOS 14.3, the third
    /// ships no enclosure). `highestVersionEntry` replaces its running best only
    /// on a STRICTLY newer version, so the first of a tie wins — which is the
    /// bucket we want. Pinned because it is load-bearing and invisible: flip that
    /// comparison to `>=` and one-click would silently go away for every WeChat
    /// user, with detection still working.
    @Test func theFirstOfTheTiedItemsWinsWhichIsTheOneCarryingTheArtifact() async throws {
        let sliced = try #require(VendorProbeRecipe.highestVersionEntry(
            in: Self.feed, entryStartPattern: "<item>",
            versionPattern: try recipe().versionPattern, selectHighest: true))
        #expect(sliced.contains("xWeChatMac_universal_4.1.13.11_269579.dmg"))
        #expect(!sliced.contains("maximumSystemVersion"), "the winner is the uncapped bucket")
    }
}
