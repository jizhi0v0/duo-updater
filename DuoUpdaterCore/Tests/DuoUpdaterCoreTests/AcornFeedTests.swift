import Foundation
import Testing
@testable import DuoUpdaterCore

struct AcornFeedTests {
    private let app = com_flyingmeat_Acorn8.self

    @Test func onlyTheVendorPreviewPreferenceOptsIn() {
        for preference in [nil, "", app.stableFeed.absoluteString,
                           "http://flyingmeat.com/download/latest/acorn8update.xml",
                           "https://example.com/download/latest/acorn8update.xml"] {
            let resolution = app.resolve(feedPreference: preference)
            #expect(resolution.channel == .stable)
            #expect(resolution.feedOverride == app.stableFeed)
        }
        let preview = app.resolve(feedPreference: app.betaFeed.absoluteString)
        #expect(preview.channel == .beta)
        #expect(preview.feedOverride == app.betaFeed)
    }

    @Test func stableAndPreviewKeepVersionAndSectionsSeparate() throws {
        let stable = Self.block("8.7.3", heading: "Fixes And Other Things", item: "Stability improvements.")
        let preview = Self.block("8.8", heading: "New Stuff", item: "A new <span class=\"ui\">Gradient Map</span> filter.")
        let release = try #require(app.changelog(for: Self.item("8.7.3", html: stable), feedURL: app.stableFeed))
        #expect(release.entries.map(\.version) == ["8.7.3"])
        #expect(release.entries.first?.content == [.heading("Fixes And Other Things"), .note("Stability improvements.")])
        #expect(release.entries.first?.date == "Mon, 09 Nov 2026 12:29:08 CDT")

        let beta = try #require(app.changelog(for: Self.item("8.8b1", html: preview + stable), feedURL: app.betaFeed))
        #expect(beta.entries.map(\.version) == ["8.8b1", "8.7.3"])
        #expect(beta.entries.first?.content == [.heading("New Stuff"), .note("A new Gradient Map filter.")])
        #expect(beta.entries.last?.items == ["Stability improvements."])
    }

    @Test func missingOrUnrelatedNotesDoNotGetAssignedToTheOffer() {
        let stable = Self.block("8.7.3", heading: "Fixes And Other Things", item: "Stability improvements.")
        let preview = Self.block("8.8", heading: "New Stuff", item: "A new Gradient Map filter.")
        #expect(app.changelog(for: Self.item("8.8b1", html: stable), feedURL: app.betaFeed) == nil)
        #expect(app.changelog(for: Self.item("8.8b1", html: preview + stable), feedURL: app.stableFeed) == nil)
        #expect(app.changelog(for: Self.item("8.8b1", html: stable + preview), feedURL: app.betaFeed) == nil)
        let malformed = preview.replacingOccurrences(of: "Acorn 8.8", with: "Other App 8.8")
        #expect(app.changelog(for: Self.item("8.8b1", html: malformed + stable), feedURL: app.betaFeed) == nil)
    }

    @Test func historicalAutomationNotesKeepParagraphsAndStandaloneCodeInOrder() throws {
        let html = """
        <div class="releaseT"><div class="releaseInfo">
          <div class="releaseTitleT">Acorn 8.6</div>
        </div>
        <h3># Changes</h3><ul><li>Redrawing is much faster.</li></ul>
        <h3># New Automation and JavaScript Things</h3>
        <p>Lots of interesting JavaScript things this time around.</p>
        <!-- <li>An unpublished interface change.</li> -->
        <pre>print(JSON.stringify(documentPaths, null, 2));</pre>
        <p>This opens up a whole layer of possibilities for automation.</p>
        </div>
        """
        let log = try #require(app.changelog(for: Self.item("8.6", html: html), feedURL: app.stableFeed))
        #expect(log.entries.first?.content == [
            .heading("Changes"), .note("Redrawing is much faster."),
            .heading("New Automation and JavaScript Things"),
            .note("Lots of interesting JavaScript things this time around."),
            .note("print(JSON.stringify(documentPaths, null, 2));"),
            .note("This opens up a whole layer of possibilities for automation."),
        ])
    }

    private static func item(_ version: String, html: String) -> SparkleAppcastItem {
        SparkleAppcastItem(shortVersionString: version, descriptionHTML: html,
                           pubDate: "Mon, 09 Nov 2026 12:29:08 CDT")
    }

    private static func block(_ version: String, heading: String, item: String) -> String {
        // Trimmed version block shared by the vendor's stable and preview feeds.
        """
        <div class="releaseT">
            <div class="releaseInfo">
                <a name="\(version)" />
                <div class="releaseTitleT">Acorn \(version)</div>
                <div class="releaseDate">November 12, 2027.</div>
            </div>
            <h3># \(heading)</h3>
            <ul><li>\(item)</li></ul>
        </div>
        """
    }
}
