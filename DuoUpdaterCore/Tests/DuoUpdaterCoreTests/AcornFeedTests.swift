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

    @Test func historicalAutomationNotesKeepProseAndReferToOriginalCodeInOrder() throws {
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
            .note("[Code example in the official release notes]"),
            .note("This opens up a whole layer of possibilities for automation."),
        ])
    }

    @Test func historicalAutosavingNotesKeepBareTextAroundTheList() throws {
        let html = """
        <div class="releaseT"><div class="releaseInfo">
          <div class="releaseTitleT">Acorn 8.1</div>
        </div>
        <h3># Autosaving Changes</h3>
        There is a new preference in the Settings window for autosave with three options:<br/><br/>
        <ul>
        <li><span class="ui">Off</span>: This will disable all autosaving of images.</li>
        <li><span class="ui">Native Acorn Images</span>: This will enable autosaving and versions support for native Acorn files only (.acorn).</li>
        <li><span class="ui">All Images</span>: This will autosave all file types, including lossy encoded images such as JPEG or HEIC.</li>
        </ul>
        The default is set to <span class="ui">Native Acorn Images</span>.<br/><br/>
        In Acorn 8.0, when autosave was enabled, non-native files would open without a reference to the original file on disk. This is no longer the case in Acorn 8.1, where non-native files open with a reference to the original file, and pressing ⌘S will save back to the original, regardless of the autosave setting.
        <h3># Other Improvements</h3>
        <ul><li>The Smart Layer Export palette now has options to save as WebP and JPEG-XL.</li></ul>
        </div>
        """
        let log = try #require(app.changelog(for: Self.item("8.1", html: html), feedURL: app.stableFeed))
        #expect(log.entries.first?.content == [
            .heading("Autosaving Changes"),
            .note("There is a new preference in the Settings window for autosave with three options:"),
            .note("Off: This will disable all autosaving of images."),
            .note("Native Acorn Images: This will enable autosaving and versions support for native Acorn files only (.acorn)."),
            .note("All Images: This will autosave all file types, including lossy encoded images such as JPEG or HEIC."),
            .note("The default is set to Native Acorn Images."),
            .note("In Acorn 8.0, when autosave was enabled, non-native files would open without a reference to the original file on disk. This is no longer the case in Acorn 8.1, where non-native files open with a reference to the original file, and pressing ⌘S will save back to the original, regardless of the autosave setting."),
            .heading("Other Improvements"),
            .note("The Smart Layer Export palette now has options to save as WebP and JPEG-XL."),
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
