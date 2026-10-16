import Foundation
import Testing

@testable import DuoUpdaterCore

/// `release.gitkraken.com/darwin-arm64/RELEASES`, fetched 2026-10-16, verbatim —
/// the Squirrel.Mac JSON the app's own updater reads.
private let gitKrakenReleasesBody = #"""
{"name":"12.6.0","url":"https://api.gitkraken.dev/releases/production/darwin/arm64/12.6.0/GitKraken-v12.6.0.zip"}
"""#

/// Two releases and the page footer from `help.gitkraken.com/gitkraken-desktop/current/`,
/// fetched 2026-10-16. The anchor `<svg>`s are elided and the lists cut short;
/// the rest is verbatim: 12.6.0 has a video and no date, 12.5.0 has a date and a
/// nested list under a bold lead-in, and the `<hr />` before the footer form.
private let gitKrakenNotesFixture = #"""
<hr />
<p><a id="v12-6-0"></a></p>
<h2><a href="#version-12-6-0" aria-hidden="true" class="aal_anchor" id="version-12-6-0"></a>Version 12.6.0</h2>
<div class="embed-container embed-container--16-9">
    <iframe width="560" height="315" src="https://www.youtube.com/embed/rXTnPufhdRM" frameborder="0" allowfullscreen></iframe>
</div>
<h3><a href="#new-%e2%9c%a8" aria-hidden="true" class="aal_anchor" id="new-%e2%9c%a8"></a>New ✨</h3>
<ul>
<li><strong>Multiple terminal tabs:</strong> Open, switch between, and close terminal tabs in the terminal panel. Each repository or worktree keeps its own terminals. </li>
</ul>
<h3><a href="#bug-fixes-%f0%9f%90%9b" aria-hidden="true" class="aal_anchor" id="bug-fixes-%f0%9f%90%9b"></a>Bug Fixes 🐛</h3>
<ul>
<li>Fixed an issue where GitKraken AI still offered Claude 4.1 Opus after Anthropic retired it.</li>
</ul>
<hr />
<p><a id="v12-5-0"></a></p>
<h2><a href="#version-12-5-0" aria-hidden="true" class="aal_anchor" id="version-12-5-0"></a>Version 12.5.0</h2>
<p><kbd>Tuesday, September 15th, 2026</kbd></p>
<h3><a href="#new-%e2%9c%a8" aria-hidden="true" class="aal_anchor" id="new-%e2%9c%a8"></a>New ✨</h3>
<ul>
<li><strong>Live agent status support for GitHub Copilot CLI:</strong>
<ul>
<li>GitKraken Desktop can now track Copilot CLI agent sessions and display their status across worktrees in the Agent Sessions panel.</li>
<li>You can install or uninstall the Copilot CLI Plugin that enables live status reporting from <em>Preferences &gt; External Tools</em>.</li>
</ul>
</li>
</ul>
<hr />
				</div>
				<div class="elementor-widget-container">
									Have feedback about this article? Did we miss something? Let us know!								</div>
"""#

@Test func gitKrakenProbeReadsSquirrelNameAndInstallsTheSameVersion() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.axosoft.gitkraken" })
    #expect(recipe.channel == .stable)
    #expect(VendorProbeRecipe.extractVersion(
        from: gitKrakenReleasesBody, pattern: recipe.versionPattern) == "12.6.0")
    // A prerelease string in `name` reads as nothing, never as its stable prefix.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"name":"12.7.0-beta.1","url":"x"}"#, pattern: recipe.versionPattern) == nil)
    // The next major, and a two-part version, still read.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"name":"13.0","url":"x"}"#, pattern: recipe.versionPattern) == "13.0")

    let install = try #require(recipe.install)
    #expect(install.kind == .zip)
    guard case .versionTemplate(let template) = install.urlSource else {
        Issue.record("expected a version template, got \(install.urlSource)")
        return
    }
    // The template resolves to exactly the URL the endpoint names for that version.
    let resolved = template.replacingOccurrences(of: "{version}", with: "12.6.0")
    #expect(gitKrakenReleasesBody.contains(#""url":"\#(resolved)""#))
}

@Test func gitKrakenChangelogKeepsHeadingsAndSplitsNestedLists() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.axosoft.gitkraken"))
    let log = try #require(ChangelogExtractor.extract(from: gitKrakenNotesFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["12.6.0", "12.5.0"])
    #expect(log.entries.map(\.date) == [nil, "Tuesday, September 15th, 2026"])
    #expect(log.entries[0].items == [
        "Multiple terminal tabs: Open, switch between, and close terminal tabs in the terminal panel. Each repository or worktree keeps its own terminals.",
        "Fixed an issue where GitKraken AI still offered Claude 4.1 Opus after Anthropic retired it.",
    ])
    #expect(log.entries[1].items == [
        "Live agent status support for GitHub Copilot CLI:",
        "GitKraken Desktop can now track Copilot CLI agent sessions and display their status across worktrees in the Agent Sessions panel.",
        "You can install or uninstall the Copilot CLI Plugin that enables live status reporting from Preferences > External Tools.",
    ])
    let headings = log.entries[0].content.compactMap { block -> String? in
        if case .heading(let text) = block { return text } else { return nil }
    }
    #expect(headings == ["New ✨", "Bug Fixes 🐛"])
    // The footer after the last `<hr />` is not an item.
    #expect(!log.entries.flatMap(\.items).contains { $0.contains("Have feedback") })
}
