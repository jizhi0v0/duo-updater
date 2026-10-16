import Foundation
import Testing

@testable import DuoUpdaterCore

/// The download form of `www.charlesproxy.com/download/latest-release/`, fetched
/// 2026-10-16, verbatim up to the first download option.
private let charlesLatestReleaseForm = #"""
			<form method="post" action="/latest-release/download.do" class="download-form"><input type="hidden" name="__csrf" value="sxSrOCFTQPuIJvPP" />
				<input type="hidden" name="os" value="" />
				<input type="hidden" name="beta" value="false" />
				<input type="hidden" name="version" value="5.2.2" />
"""#

/// A slice of `www.charlesproxy.com/documentation/version-history/`, fetched
/// 2026-10-16: the two newest releases (5.2.1's lists cut to two items each),
/// the 5.2 header, one beta, and 5.0 with its nested list, verbatim.
private let charlesVersionHistoryFixture = #"""
				<h3>Version History</h3>
				<h4>Version 5.2.2</h4>
<p>11 October 2026</p>
<p>Bug fixes</p>
<ul>
<li>Session importing fixes; faults existed if keys were in an unexpected order across Charles-native and HAR import formats.</li>
</ul>
<h4>Version 5.2.1</h4>
<p>4 August 2026</p>
<p>Minor new features</p>
<ul>
<li>Map Remote: new <em>Preserve base path</em> option stops a destination base path being applied twice.</li>
</ul>
<p>Bug fixes</p>
<ul>
<li>Improve Repeat behaviour after failed connects</li>
<li>HAR export no longer produces invalid output when containing unsupported encoded bodies</li>
</ul>
<h4>Version 5.1.1b11</h4>
<p>10 June 2026</p>
<p>Minor new features</p>
<ul>
<li>Allow saving the Error Log and streaming it to a file (right-click on Error Log)</li>
</ul>
<h4>Version 5.0</h4>
<p>12 March 2025</p>
<ul>
<li>Modernised UI and look &amp; feel with a focus on moden platform conventions and usability</li>
<li>Various UI enhancements:
<ul>
<li>Filtering in lists in dialogs</li>
<li>Updated iconography</li>
</ul>
</li>
<li>Support for Apple Silicon and Windows on ARM</li>
</ul>
</div>
"""#

private func charlesProbe() throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.xk72.Charles" })
}

@Test func charlesReadsTheLatestReleaseFormVersion() throws {
    let recipe = try charlesProbe()
    #expect(VendorProbeRecipe.extractVersion(
        from: charlesLatestReleaseForm, pattern: recipe.versionPattern) == "5.2.2")
    // A two-part release reads as itself.
    #expect(VendorProbeRecipe.extractVersion(
        from: charlesLatestReleaseForm.replacingOccurrences(of: "5.2.2", with: "5.2"),
        pattern: recipe.versionPattern) == "5.2")
    // A paid next major on this page reads nothing rather than being offered to 5.x.
    #expect(VendorProbeRecipe.extractVersion(
        from: charlesLatestReleaseForm.replacingOccurrences(of: "5.2.2", with: "6.0"),
        pattern: recipe.versionPattern) == nil)
    // A beta version string, or a form flagged as beta, never reads as stable.
    #expect(VendorProbeRecipe.extractVersion(
        from: charlesLatestReleaseForm.replacingOccurrences(of: "5.2.2", with: "5.3b1"),
        pattern: recipe.versionPattern) == nil)
    #expect(VendorProbeRecipe.extractVersion(
        from: charlesLatestReleaseForm.replacingOccurrences(
            of: #"name="beta" value="false""#, with: #"name="beta" value="true""#),
        pattern: recipe.versionPattern) == nil)
}

@Test func charlesInstallsTheVersionedDmgForCharles5Only() throws {
    let recipe = try charlesProbe()
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case .versionTemplate(let template) = install.urlSource else {
        Issue.record("expected a versionTemplate install source")
        return
    }
    #expect(template
        == "https://www.charlesproxy.com/assets/release/{version}/charles-proxy-{version}.dmg")
    // 4.x is a separately licensed major the vendor still ships; it is not offered 5.x.
    #expect(recipe.matchesInstalled(version: "5.2.1"))
    #expect(recipe.matchesInstalled(version: "5.1.1b11"))
    #expect(!recipe.matchesInstalled(version: "4.6.8"))
}

@Test func charlesChangelogSkipsBetasAndSplitsNestedLists() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.xk72.Charles", channel: .stable))
    let log = try #require(ChangelogExtractor.extract(from: charlesVersionHistoryFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["5.2.2", "5.2.1", "5.0"])
    #expect(log.entries.map(\.date) == ["11 October 2026", "4 August 2026", "12 March 2025"])
    #expect(log.entries[1].items == [
        "Map Remote: new Preserve base path option stops a destination base path being applied twice.",
        "Improve Repeat behaviour after failed connects",
        "HAR export no longer produces invalid output when containing unsupported encoded bodies",
    ])
    #expect(log.entries[1].content.compactMap {
        if case .heading(let text) = $0 { return text } else { return nil }
    } == ["Minor new features", "Bug fixes"])
    #expect(log.entries[2].items == [
        "Modernised UI and look & feel with a focus on moden platform conventions and usability",
        "Various UI enhancements:",
        "Filtering in lists in dialogs",
        "Updated iconography",
        "Support for Apple Silicon and Windows on ARM",
    ])
}
