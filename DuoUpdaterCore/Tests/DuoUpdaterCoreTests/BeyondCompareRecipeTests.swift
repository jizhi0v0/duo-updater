import Foundation
import Testing

@testable import DuoUpdaterCore

/// The macOS download link of `www.scootersoftware.com/download` and
/// `/download/v4`, fetched 2026-10-16, verbatim lines; the rest of each page cut.
private let bc5DownloadFixture = #"""
		<h2 class="hasicon"><img src="icon_mac.png" alt=""> macOS</h2>
		<div style="min-height:150px">
			<p>English, German, French, Japanese, and Simplified Chinese</p>
			<a href="/files/BCompareOSX-5.2.6.32774.zip" class="button">Download</a>&nbsp; <span class="fineprint">54895kb</span><br>
"""#
private let bc4DownloadFixture = #"""
				<a href="/files/BCompareOSX-4.4.7.28397.zip" class="button">Download</a>&nbsp; <span class="fineprint">26773kb</span>
"""#

/// The first two releases of `www.scootersoftware.com/download/v5changelog` and
/// the list's closing `</div>`, fetched 2026-10-16; the first release's sections
/// after "Cloud Services" are cut.
private let bc5ChangelogFixture = #"""
<h1>Beyond Compare 5 Change Log</h1>
<div class="changelog">

<h2 id="september-24-2026">5.2.6.32774 - September 24, 2026</h2>
<h4 id="notable-changes">Notable Changes</h4>
<ul>
<li>General polish, stability improvements, and vulnerability fixes.</li>
</ul>
<h4 id="cloud-services">Cloud Services</h4>
<ul>
<li><strong>Windows</strong>: MIME types for uploaded files are determined from the system database instead of a custom <code>mime.types</code> file.</li>
</ul>
<h2 id="august-3-2026">5.2.5.32528 - August 3, 2026</h2>
<h4 id="notable-changes-1">Notable Changes</h4>
<ul>
<li><strong>Windows</strong>: Fixed Beyond Compare hanging on startup on Windows 7.</li>
<li>Fixed Table Compare incorrectly decoding cells with date/time data.</li>
</ul>
</div>
"""#

private func bcProbe(_ variant: String) throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first {
        $0.bundleID == "com.ScooterSoftware.BeyondCompare" && $0.variant == variant
    })
}

@Test func beyondCompareProbesReadTheirOwnGeneration() throws {
    let bc5 = try bcProbe("bc5")
    let bc4 = try bcProbe("bc4")
    #expect(VendorProbeRecipe.extractVersion(
        from: bc5DownloadFixture, pattern: bc5.versionPattern) == "5.2.6.32774")
    #expect(VendorProbeRecipe.extractVersion(
        from: bc4DownloadFixture, pattern: bc4.versionPattern) == "4.4.7.28397")
    // A paid major on the other probe's page never reads as this generation's.
    #expect(VendorProbeRecipe.extractVersion(
        from: bc4DownloadFixture, pattern: bc5.versionPattern) == nil)
    #expect(VendorProbeRecipe.extractVersion(
        from: #"<a href="/files/BCompareOSX-6.0.0.40000.zip">"#,
        pattern: bc5.versionPattern) == nil)
    #expect(bc5.installedVersionPattern == #"^5\."#)
    #expect(bc4.installedVersionPattern == #"^4\."#)
    #expect(bc5.install?.kind == .zip)
    #expect(bc4.install?.kind == .zip)
}

@Test func beyondCompareChangelogKeepsSectionsPerRelease() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.ScooterSoftware.BeyondCompare", channel: .stable,
        version: "5.2.5.32528"))
    #expect(recipe.source.absoluteString.hasSuffix("/download/v5changelog"))
    let v4 = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.ScooterSoftware.BeyondCompare", channel: .stable,
        version: "4.4.6.27483"))
    #expect(v4.source.absoluteString.hasSuffix("/download/v4changelog"))

    let log = try #require(ChangelogExtractor.extract(from: bc5ChangelogFixture, using: recipe))
    #expect(log.entries.map(\.version) == ["5.2.6.32774", "5.2.5.32528"])
    #expect(log.entries.map(\.date) == ["September 24, 2026", "August 3, 2026"])
    #expect(log.entries[0].content == [
        .heading("Notable Changes"),
        .note("General polish, stability improvements, and vulnerability fixes."),
        .heading("Cloud Services"),
        .note("Windows: MIME types for uploaded files are determined from the system database instead of a custom mime.types file."),
    ])
    #expect(log.entries[1].items == [
        "Windows: Fixed Beyond Compare hanging on startup on Windows 7.",
        "Fixed Table Compare incorrectly decoding cells with date/time data.",
    ])
}
