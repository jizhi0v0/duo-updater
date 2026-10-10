import Testing
import Foundation
@testable import DuoUpdaterCore

// VS Code Insiders — two-stage. The index fixture is the side nav of the real
// `code.visualstudio.com/updates` page (which redirected to `/updates/v1_141`),
// preceded by the site header's own `/updates` link. The page fixture is the
// real `/updates/v1_142` page from its `<h1>` to the content `</main>`, verbatim.
private let insidersIndex = #"""
<li class="active" ><a id="nav-updates" href="/updates" data-m='{"cN":"Release Notes"}'>Release Notes</a>
            <nav id="docs-navbar" aria-label="Updates" class="docs-nav updates-nav visible-md visible-lg">
            	<h4>Updates</h4>
            	<ul class="nav">

            			<li >
            				<a href="/updates/v1_142" >Insiders</a>
            			</li>

            			<li class="active">
            				<a href="/updates/v1_141" aria-label="Current Page: 1.141">1.141</a>
            			</li>

            			<li >
            				<a href="/updates/v1_140" >1.140</a>
            			</li>
"""#

private let insidersPage = #"""
<h1>Visual Studio Code 1.142 (Insiders)</h1>
<p>Follow us on <a href="https://www.linkedin.com/showcase/vs-code" class="external-link" target="_blank">LinkedIn</a>, <a href="https://go.microsoft.com/fwlink/?LinkID=533687" class="external-link" target="_blank">X</a>, <a href="https://bsky.app/profile/vscode.dev" class="external-link" target="_blank">Bluesky</a>, <a href="https://www.instagram.com/vscode.ig" class="external-link" target="_blank">Instagram</a> | Follow Insiders Changelog on <a href="https://x.com/VSCodeChangelog" class="external-link" target="_blank">X</a> or <a href="https://bsky.app/profile/vscodechangelog.bsky.social" class="external-link" target="_blank">Bluesky</a></p>
<hr>
<p><em>Last updated: October 7, 2026</em></p>
<p>Welcome to the 1.142 Insiders release of Visual Studio Code.</p>
<p>These release notes cover the Insiders build of VS Code and continue to evolve as new features are added.</p>
<p>You can still track our progress in the <a href="https://github.com/Microsoft/vscode/commits/main" class="external-link" target="_blank">Commit log</a> and our list of <a href="https://github.com/Microsoft/vscode/issues?q=is%3Aissue%20is%3Aclosed%20milestone%3A1.142.0" class="external-link" target="_blank">Closed issues</a>.</p>
<p>Happy Coding!</p>
<hr>
<!-- TOC
<div class="toc-nav-layout">
  <nav id="toc-nav">
    <div>In this update</div>
    <ul>
      <li><a href="#october-7-2026">October 7, 2026</a></li>
    </ul>
  </nav>
  <div class="notes-main">
Navigation End -->
<h2 id="_october-7-2026" data-needslink="_october-7-2026">October 7, 2026</h2>
<ul>
<li>Add support for merging document highlights from multiple providers with the <span class="setting"><span class="setting-dropdown" data-setting-id="editor.occurrencesHighlightFromAllProviders">
    <span class="setting-link-main">
      <span class="codicon codicon-settings-gear dynamic-setting-icon"></span>
      editor.occurrencesHighlightFromAllProviders

    </span>
    <button
      type="button"
      class="setting-dropdown-trigger"
      aria-haspopup="menu"
      aria-expanded="false"
      aria-label="Open setting in VS Code">
        <svg class="setting-dropdown-chevron" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M7.976 10.072l4.357-4.357.62.618L8.284 11h-.618L3 6.333l.619-.618 4.357 4.357z"/>
        </svg>
    </button>
    <span class="setting-dropdown-menu" role="menu" aria-label="Open setting">
      <span role="menuitem" class="setting-action-item" data-version="stable" tabindex="0">Open in VS Code</span>
      <span role="menuitem" class="setting-action-item" data-version="insiders" tabindex="-1">Open in VS Code Insiders</span>
    </span>
  </span></span> setting. <em><a href="https://github.com/microsoft/vscode/issues/48821" class="external-link" target="_blank">#48821</a></em></li>
</ul>
<hr>
<p>We really appreciate people trying our new features as soon as they are ready, so check back here often and learn what's new.</p>
<p><a id="scroll-to-top" role="button" title="Scroll to top" aria-label="scroll to top" href="#"><span class="icon"></span></a></p>

                <div class="feedback" data-edit-url="https://vscode.dev/github/microsoft/vscode-docs/blob/main/release-notes/v1_142.md"></div>
            </main>
"""#

private func insidersRecipe() throws -> ChangelogRecipe {
    try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.microsoft.VSCodeInsiders", channel: .preview))
}

@Test func vsCodeInsidersFollowsTheInsidersNavLink() throws {
    let recipe = try insidersRecipe()
    let pattern = try #require(recipe.indexLinkPattern)
    let url = ChangelogService.firstLink(in: insidersIndex, pattern: pattern, base: recipe.source)
    // Neither the header's `/updates` nor the stable `v1_141` page.
    #expect(url?.absoluteString == "https://code.visualstudio.com/updates/v1_142")
    // A nav with no Insiders item gives no link, never a stable page.
    let stableOnly = insidersIndex.replacingOccurrences(of: ">Insiders</a>", with: ">1.142</a>")
    #expect(ChangelogService.firstLink(in: stableOnly, pattern: pattern, base: recipe.source) == nil)
}

@Test func vsCodeInsidersPageParsesDaysAsOneEntry() throws {
    let log = try #require(ChangelogExtractor.extract(from: insidersPage, using: try insidersRecipe()))
    #expect(log.entries.count == 1)
    let entry = try #require(log.entries.first)
    #expect(entry.version == "1.142")
    #expect(entry.date == "October 7, 2026")
    #expect(entry.content.first == .heading("October 7, 2026"))
    // The setting's dropdown menu text stays inline: tag stripping can't drop it.
    #expect(entry.items == [
        "Add support for merging document highlights from multiple providers with the "
            + "editor.occurrencesHighlightFromAllProviders Open in VS Code Open in VS Code Insiders "
            + "setting. #48821",
    ])
}

// Right after a stable release the nav's Insiders item points at a page that
// has its header but no day yet: the same page with the TOC comment and the
// `<h2>`/`<ul>` removed, which is what the vscode-docs "Initialize Insiders
// release notes" commit renders to. It must parse to nothing, so the pane falls
// back to embedding the page instead of showing an empty entry.
@Test func vsCodeInsidersPageWithNoDayYetParsesToNothing() throws {
    let start = try #require(insidersPage.range(of: "<!-- TOC"))
    let end = try #require(insidersPage.range(of: "</ul>\n<hr>"))
    let blank = insidersPage.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "<hr>")
    #expect(!blank.contains("<h2"))
    #expect(ChangelogExtractor.extract(from: blank, using: try insidersRecipe()) == nil)
}
