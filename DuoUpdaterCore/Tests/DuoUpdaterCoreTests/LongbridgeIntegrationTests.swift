import Foundation
import Testing
@testable import DuoUpdaterCore

private let longbridgeLatestFixture = #"""
{"version":"0.19.1","created_at":"2026-08-20T10:13:36Z","published_at":"2026-08-20T07:46:53Z","release_notes":{"en":"### Improvements\r\n\r\n- Fixed an issue where the editor could quit unexpectedly.\r\n- Fixed vertical lists occasionally showing an unnecessary horizontal scrollbar.","zh-CN":"### 优化\r\n\r\n- 修复编辑器问题。","zh-HK":"### 優化\r\n\r\n- 修復編輯器問題。"},"assets":[{"name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa"},{"name":"longbridge-v0.19.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-x86_64.dmg","sha256":"5d3325bd671735b4720e2ac7d232cedf9b4a8abf3953ff2247e17e54d9d134b5"}]}
"""#

private let longbridgeCurrentNotesFixture = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_v0_19_1" data-v-x><div>
<h1 id="v0-19-1">v0.19.1 <a class="header-anchor">#</a></h1>
<p><em>Release Date: 2026-08-20</em></p>
<h3>Improvements</h3><ul>
<li>Fixed an issue where the editor could quit unexpectedly.</li>
<li>Fixed vertical lists occasionally showing an unnecessary horizontal scrollbar.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

private let longbridgeRichNotesFixture = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_v0_19_0" data-v-x><div>
<h1 id="v0-19-0">v0.19.0 <a class="header-anchor">#</a></h1>
<p><em>Release Date: 2026-08-19</em></p>
<p><strong>Screening &amp; quant</strong></p><ul>
<li>Screener: Added multi-dimensional filters.<video src="https://assets.lbkrs.com/demo.mp4">Your browser does not support the video tag.</video></li>
<li>Financials: Added score details.<img src="https://assets.lbkrs.com/uploads/Score.png" alt="Score"></li>
<li>Watchlist: Added list-width controls.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

@Suite struct LongbridgeIntegrationTests {
    private func probe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.longbridge.app.desktop" && $0.channel == .stable
        })
    }

    @Test func vendorProbeReadsMarketingVersionAndPublishedDate() throws {
        let recipe = try probe()
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeLatestFixture, pattern: recipe.versionPattern) == "0.19.1")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeLatestFixture,
            pattern: try #require(recipe.publishedAtPattern)) == "2026-08-20T07:46:53Z")
        #expect(recipe.versionIsBuild == false)
    }

    @Test func installerSelectsTheAppleSiliconDMG() throws {
        let spec = try #require(try probe().install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("Longbridge installer must resolve from the manifest body")
            return
        }
        let url = VendorProbeRecipe.extractVersion(
            from: longbridgeLatestFixture, pattern: pattern)
        #expect(url?.hasSuffix("longbridge-v0.19.1-macos-aarch64.dmg") == true)
        #expect(url?.contains("x86_64") == false)
    }

    private func changelogRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop", channel: .stable))
    }

    @Test func changelogUsesTheExactEnglishVersionPage() throws {
        let recipe = try changelogRecipe()
        #expect(recipe.structuredFormat == nil)
        #expect(recipe.resolvedSource(forVersion: "0.19.0").absoluteString
            == "https://longbridge.com/desktop/release-notes/v0.19.0")

        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeCurrentNotesFixture, using: recipe)?.entries.first)
        #expect(entry.version == "0.19.1")
        #expect(entry.date == "2026-08-20")
        #expect(entry.items == [
            "Fixed an issue where the editor could quit unexpectedly.",
            "Fixed vertical lists occasionally showing an unnecessary horizontal scrollbar.",
        ])
        #expect(entry.items.allSatisfy { !$0.contains("installer") })
        #expect(entry.content.isEmpty)
    }

    @Test func richChangelogKeepsImagesInDocumentOrder() throws {
        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeRichNotesFixture, using: try changelogRecipe())?.entries.first)
        #expect(entry.version == "0.19.0")
        #expect(entry.items == [
            "Screening & quant",
            "Screener: Added multi-dimensional filters.",
            "Financials: Added score details.",
            "Watchlist: Added list-width controls.",
        ])
        #expect(entry.items.allSatisfy {
            !$0.contains("does not support") && !$0.contains("installer")
        })
        #expect(entry.content == [
            .note("Screening & quant"),
            .note("Screener: Added multi-dimensional filters."),
            .note("Financials: Added score details."),
            .image(try #require(URL(string: "https://assets.lbkrs.com/uploads/Score.png"))),
            .note("Watchlist: Added list-width controls."),
        ])
    }

    @Test func changelogCatalogProvidesAWebFallback() {
        #expect(ChangelogCatalog.url(forBundleID: "com.longbridge.app.desktop")?
            .absoluteString == "https://longbridge.com/desktop/release-notes/")
    }

    @Test func manifestStillCarriesEnglishNotesAsVendorFallback() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop", channel: .stable))
        #expect(recipe.mode == .html)
        #expect(longbridgeLatestFixture.contains("\"en\":\"### Improvements"))
    }
}
