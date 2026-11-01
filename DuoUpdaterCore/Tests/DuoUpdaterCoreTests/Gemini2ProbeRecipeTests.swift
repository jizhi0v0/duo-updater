import Testing
import Foundation
@testable import DuoUpdaterCore

/// Gemini 2 (MacPaw) — the DevMate appcast probe, and why it compares builds.
///
/// The feed reuses `sparkle:shortVersionString` for the marketing version on
/// older items ("2.10.1") but publishes the build there on the newest one
/// (`sparkle:version="407" sparkle:shortVersionString="407"`), while that
/// package's own `CFBundleShortVersionString` is 2.10.2. The expectations below
/// are checked against the response captured from the vendor on 2026-11-01:
/// `https://updates.devmate.com/com.macpaw.site.Gemini2.xml`.
struct Gemini2ProbeRecipeTests {

    private static let bundleID = "com.macpaw.site.Gemini2"

    /// The feed, verbatim except that all items after the second and the
    /// `xml:lang` duplicates of the notes links are cut. The 407 item keeps its
    /// deltas: they are what a looser install pattern would match.
    private static let body = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    	<channel>
    		<title>Gemini 2</title>
    		<item>
    			<title>407</title>
    			<sparkle:releaseNotesLink>https://updates.devmate.com/releasenotes/407/com.macpaw.site.Gemini2.html</sparkle:releaseNotesLink>
    			<pubDate>Fri, 04 Sep 2026 12:10:58 +0000</pubDate>
    			<enclosure url="https://dl.devmate.com/com.macpaw.site.Gemini2/407/1788524594/Gemini2-407.zip" length="51483368" type="application/octet-stream" sparkle:version="407" sparkle:shortVersionString="407"/>
    			<sparkle:deltas>
    				<enclosure url="https://dl.devmate.com/com.macpaw.site.Gemini2/407/1788524594/406.delta" sparkle:version="407" sparkle:shortVersionString="407" sparkle:deltaFrom="406" length="47135701" type="application/octet-stream"/>
    			</sparkle:deltas>
    		</item>
    		<item>
    			<title>406</title>
    			<sparkle:releaseNotesLink>https://updates.devmate.com/releasenotes/406/com.macpaw.site.Gemini2.html</sparkle:releaseNotesLink>
    			<pubDate>Thu, 18 Jun 2026 00:10:57 +0000</pubDate>
    			<enclosure url="https://dl.devmate.com/com.macpaw.site.Gemini2/406/1781745541/Gemini2-406.zip" length="51492695" type="application/octet-stream" sparkle:version="406" sparkle:shortVersionString="2.10.1"/>
    		</item>
    	</channel>
    </rss>
    """#

    private static func recipe() throws -> VendorProbeRecipe {
        let matches = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }
        try #require(matches.count == 1)
        return matches[0]
    }

    private static func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        guard case .bodyPattern(let pattern)? = recipe.install?.urlSource else {
            Issue.record("expected a .bodyPattern install")
            throw CancellationError()
        }
        return pattern
    }

    @Test func probeComparesTheBuildAndInstallsTheZIP() throws {
        let recipe = try Self.recipe()
        #expect(recipe.versionIsBuild)
        #expect(recipe.install?.kind == .zip)
        #expect(recipe.url.absoluteString
            == "https://updates.devmate.com/com.macpaw.site.Gemini2.xml")
    }

    /// `sparkle:version` is the build (407), and the newest item is the first one
    /// — the feed is descending, so the first match is the latest release.
    @Test func versionIsTheNewestBuild() throws {
        let pattern = try Self.recipe().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: Self.body, pattern: pattern) == "407")
    }

    /// The trap this recipe exists to sidestep: the newest item's
    /// `sparkle:shortVersionString` is the BUILD too. Reading the marketing
    /// string out of the feed would offer "407" to a 2.10.2 install forever.
    @Test func theNewestItemsShortVersionStringIsTheBuildNotTheMarketingVersion() {
        let naive = #"sparkle:shortVersionString="([0-9.]+)""#
        #expect(VendorProbeRecipe.extractVersion(from: Self.body, pattern: naive) == "407")
        // The item below it still carries a marketing string, so a "skip items
        // whose shortVersionString looks like a build" rule would silently report
        // 2.10.1 as the latest — a release behind the one the same feed installs.
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.body,
            pattern: #"<title>406</title>[\s\S]*?sparkle:shortVersionString="([0-9.]+)""#) == "2.10.1")
    }

    /// The one-click takes the newest item's zip, never its `.delta` siblings.
    @Test func installTakesTheNewestZipAndNotADelta() throws {
        let pattern = try Self.installPattern(try Self.recipe())
        #expect(VendorProbeRecipe.extractVersion(from: Self.body, pattern: pattern)
            == "https://dl.devmate.com/com.macpaw.site.Gemini2/407/1788524594/Gemini2-407.zip")
    }
}
