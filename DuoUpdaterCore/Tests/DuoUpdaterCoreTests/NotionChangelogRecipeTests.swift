import Testing
import Foundation
@testable import DuoUpdaterCore

/// Two consecutive posts from `www.notion.com/releases`, captured verbatim
/// 2026-08-20 and trimmed to the first paragraphs of each.
///
/// This is the markup that BROKE the recipe: on 2026-08-20 the page switched
/// CSS-modules naming from `release_release__<hash>` to
/// `release-module-scss-module__<hash>__release`. Same elements, same nesting,
/// every class renamed — the sweep reported `noEntriesExtracted` while fetching
/// the page perfectly well, which is the shape a restyle always takes.
private let notionNewNamingFixture = #"""
<article class="release-module-scss-module__Ht_S5q__release"><div class="release-module-scss-module__Ht_S5q__releaseMeta"><div class="release-module-scss-module__Ht_S5q__dateRow"><time class="release-module-scss-module__Ht_S5q__date">August 19, 2026</time></div></div><div class="release-module-scss-module__Ht_S5q__content"><a class="release-module-scss-module__Ht_S5q__titleLink" href="/releases/2026-08-19"><div style="display:contents" class="base-module-scss-module__QPCBRq__theme theme-module-scss-module__thoEPa__theme"><h2 class="semanticTypography-module-scss-module__Db2fhq__semanticTypography semanticTypography-module-scss-module__Db2fhq__variantGlobalTitleSubtle release-module-scss-module__Ht_S5q__title">Your Developer Portal, now in the sidebar</h2><p class="contentfulRichText-module-scss-module__GleVCa__paragraph">Manage your Workers, connections, and personal access tokens from the new <strong class="contentfulRichText-module-scss-module__GleVCa__strong">Developer</strong> section of your Notion workspace. See an overview of deployed Workers and logs behind every run. </p><p class="contentfulRichText-module-scss-module__GleVCa__paragraph">Plus, the new <strong class="contentfulRichText-module-scss-module__GleVCa__strong">developer bar</strong> makes it easy for anyone building with the API to find IDs for the page, database, block, workspace, or user. Copy any one of them, or the full API object, in one click. </p></article></div></article>
<article class="release-module-scss-module__Ht_S5q__release"><div class="release-module-scss-module__Ht_S5q__releaseMeta"><div class="release-module-scss-module__Ht_S5q__dateRow"><time class="release-module-scss-module__Ht_S5q__date">August 14, 2026</time></div></div><div class="release-module-scss-module__Ht_S5q__content"><a class="release-module-scss-module__Ht_S5q__titleLink" href="/releases/2026-08-14"><div style="display:contents" class="base-module-scss-module__QPCBRq__theme theme-module-scss-module__thoEPa__theme"><h2 class="semanticTypography-module-scss-module__Db2fhq__semanticTypography semanticTypography-module-scss-module__Db2fhq__variantGlobalTitleSubtle release-module-scss-module__Ht_S5q__title">Model selection, simplified</h2><p class="contentfulRichText-module-scss-module__GleVCa__paragraph">No more guessing which model to use.</p><p class="contentfulRichText-module-scss-module__GleVCa__paragraph">The model picker now leads with a shortlist of models made for your hardest tasks, and every model has a scorecard to compare speed, intelligence, and cost. Pin your favorites for easy access and dial up the effort when you need a more thorough answer.</p></article></div></article>
</main>
"""#

/// The legacy `release_*__<hash>` spelling keeps its coverage from the real
/// capture already in `ChangelogExtractorTests.extractsNotionEntries` — genuine
/// pre-change markup, which is why no reconstruction is kept here. That test
/// passing alongside this one is what proves both alternatives in the pattern
/// still fire.
@Suite struct NotionChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == "notion.id" })
    }

    @Test func readsTheCurrentCSSModulesNaming() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: notionNewNamingFixture, using: try recipe()))
        #expect(log.entries.count == 2)
        // Notion publishes no build number on this page, so the post title is
        // the version string by design — see the recipe's comment.
        #expect(log.entries.first?.version == "Your Developer Portal, now in the sidebar")
        #expect(log.entries.first?.date == "August 19, 2026")
        #expect(log.entries.first?.items.isEmpty == false)
        #expect(log.entries.last?.version == "Model selection, simplified")
        // The body must stop at the next post rather than swallowing it — the
        // inner rich-text <article> also closes with </article>, which is the
        // trap this bound exists for.
        #expect(log.entries.first?.items.allSatisfy {
            !$0.contains("No more guessing which model")
        } == true)
    }
}
