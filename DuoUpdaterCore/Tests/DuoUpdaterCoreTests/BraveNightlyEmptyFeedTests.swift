import Testing
import Foundation
@testable import DuoUpdaterCore

/// Brave Nightly's feed answering with no releases reads as the vendor's outage,
/// and no feed that lists a release can read as one.
struct BraveNightlyEmptyFeedTests {

    static func nightly() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.brave.Browser.nightly" && $0.channel == .nightly
        })
    }

    /// `nightly-arm64/appcast.xml` as served on 2026-10-16 (465 B; indentation
    /// re-flowed by the literal, which the pattern does not care about).
    static let emptyFeed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>Brave-Browser</title>
                <link>https://updates.bravesoftware.com/sparkle/Brave-Browser/nightly-arm64/appcast.xml</link>
                <description>Most recent changes with links to updates.</description>
                <language>en</language>

            </channel>
        </rss>
        """

    /// The same feed with one release, shaped as `beta-arm64/appcast.xml` served
    /// it the same day (signatures and deltas cut).
    static let feedWithARelease = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>Brave-Browser</title>
                <link>https://updates.bravesoftware.com/sparkle/Brave-Browser/nightly-arm64/appcast.xml</link>
                <description>Most recent changes with links to updates.</description>
                <language>en</language>
        <item>
                        <title>Brave-Browser 199.44</title>
                        <pubDate>Thu, 15 Oct 2026 10:43:37 +0000</pubDate>
                        <enclosure url="https://updates-cdn.bravesoftware.com/sparkle/Brave-Browser/nightly-arm64/199.44/Brave-Browser-Nightly-arm64.dmg"
                                   sparkle:version="199.44"
                                   sparkle:shortVersionString="1.99.44.0"
                                   length="231915605" type="application/octet-stream"/>
                    </item>
            </channel>
        </rss>
        """

    @Test func anEmptyFeedIsTheVendorsOutageNotAClosedTrack() throws {
        let recipe = try Self.nightly()
        #expect(recipe.matchesTransientBody(Self.emptyFeed))
        #expect(!recipe.matchesTrackClosed(Self.emptyFeed))
    }

    @Test func aFeedListingAReleaseIsNeverAnOutage() throws {
        let recipe = try Self.nightly()
        #expect(!recipe.matchesTransientBody(Self.feedWithARelease))
        // Cut off mid-download: not a whole document, so not an empty feed either.
        #expect(!recipe.matchesTransientBody(String(Self.emptyFeed.dropLast(10))))
    }
}
