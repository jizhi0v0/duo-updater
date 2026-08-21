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
    // 2026-08-22: this regex recipe is no longer the ACTIVE `notion.id` entry in
    // `ChangelogRecipeRegistry` — it was replaced by the structured
    // `.notionPageChunk` recipe (see `NotionPageChunkTests` below and the
    // registry comment), because this page's "version" was really a post title
    // with no build number, which never matched the app's real installed
    // version. The pattern is reconstructed here (via the shared helper in
    // `ChangelogExtractorTests.swift`) rather than fetched from the registry,
    // so this regression coverage survives even though the pattern itself is no
    // longer in the registry at all (it is in git history, at 3603c3c^ and
    // earlier — deliberately NOT left behind as commented-out code).
    private func recipe() -> ChangelogRecipe {
        notionProductAnnouncementsRecipe()
    }

    @Test func readsTheCurrentCSSModulesNaming() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: notionNewNamingFixture, using: recipe()))
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

// MARK: - notionPageChunk (the ACTIVE `notion.id` recipe)

/// A real (trimmed) slice of `notion.notion.site/api/v3/loadPageChunk`'s response
/// for the desktop app's actual "What's New" page, captured live 2026-08-22 —
/// the first 3 of 24 releases (12 of its 101 blocks): a `page` block whose
/// `content` array names the reading order, plus that order's `header`/`text`/
/// `bulleted_list` blocks, each trimmed to only the `type`/`properties.title`
/// fields the decoder reads (the real response also carries `id`, `version`,
/// `format`, `created_time`, … which `Decodable` already ignores for free, so
/// dropping them here is a size cut, not a behavior change).
///
/// This is the fixture that pins the whole reason this recipe replaced the old
/// one: `v7.31.0` is a REAL desktop build number (it matches what the vendor
/// probe reads from the installer filename), not a post title standing in for
/// one.
private let notionPageChunkFixture = #"""
{"recordMap": {"block": {"3bfefdee-ad05-8039-a5e6-d8cb747ee142": {"value": {"value": {"type": "header","properties": {"title": [["v7.31.0"]]}}}},"3bfefdee-ad05-8057-9623-dff8b34b7bf0": {"value": {"value": {"type": "text","properties": {"title": [[" 📅 Released "],["‣",[["d",{"type": "datetime","start_date": "2026-08-17","start_time": "16:26","time_zone": "America/Los_Angeles","date_format": "relative"}]]],["  (macOS & Windows)"]]}}}},"3bfefdee-ad05-8067-8fa6-d6b559cfff1f": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["Allow additional SSO provider (Entra) login popups from in the app"]]}}}},"3b8efdee-ad05-807b-ba1a-fea9e1c1fac3": {"value": {"value": {"type": "header","properties": {"title": [["v7.29.0"]]}}}},"3b8efdee-ad05-8014-be1f-c9be494eeacd": {"value": {"value": {"type": "text","properties": {"title": [[" 📅 Released "],["‣",[["d",{"type": "date","start_date": "2026-08-03","date_format": "relative"}]]],["  (macOS & Windows)"]]}}}},"3b8efdee-ad05-80bd-99bf-d926b25f2d54": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["Resolved an issue where the quick search hotkey wouldn't work properly for certain users"]]}}}},"3b8efdee-ad05-807a-98ec-fd8db89d1895": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["Windows 10 users (20H2 and above) can now use the MSIX Installer"]]}}}},"3acefdee-ad05-80a8-8fa8-fde99932d47d": {"value": {"value": {"type": "header","properties": {"title": [["v7.28.0"]]}}}},"3acefdee-ad05-8056-811e-f20f1e5ea0e3": {"value": {"value": {"type": "text","properties": {"title": [[" 📅 Released "],["‣",[["d",{"date_format": "relative","type": "date","start_date": "2026-07-27"}]]],[" (macOS & Windows)"]]}}}},"3acefdee-ad05-80f7-9bfc-dcb3d570930b": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["Tabs recover automatically if your system unloads them under memory pressure"]]}}}},"3acefdee-ad05-80a9-919b-f6f7591f741f": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["Opening a Notion link in Desktop no longer closes the originating browser tab on macOS"]]}}}},"3acefdee-ad05-8075-80ef-d191c6bfc432": {"value": {"value": {"type": "bulleted_list","properties": {"title": [["As always, security and performance improvements, and small bug fixes"]]}}}},"5936dabc-8dd6-4978-9578-6c91b9d6f12a": {"value": {"value": {"type": "page","content": ["3bfefdee-ad05-8039-a5e6-d8cb747ee142","3bfefdee-ad05-8057-9623-dff8b34b7bf0","3bfefdee-ad05-8067-8fa6-d6b559cfff1f","3b8efdee-ad05-807b-ba1a-fea9e1c1fac3","3b8efdee-ad05-8014-be1f-c9be494eeacd","3b8efdee-ad05-80bd-99bf-d926b25f2d54","3b8efdee-ad05-807a-98ec-fd8db89d1895","3acefdee-ad05-80a8-8fa8-fde99932d47d","3acefdee-ad05-8056-811e-f20f1e5ea0e3","3acefdee-ad05-80f7-9bfc-dcb3d570930b","3acefdee-ad05-80a9-919b-f6f7591f741f","3acefdee-ad05-8075-80ef-d191c6bfc432"]}}}}}}
"""#

@Suite struct NotionPageChunkTests {
    @Test func registryPointsAtTheStructuredPostRecipe() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "notion.id"))
        #expect(recipe.structuredFormat == .notionPageChunk)
        #expect(recipe.httpMethod == .post)
        #expect(recipe.requestBody != nil)
        #expect(recipe.source.absoluteString == "https://notion.notion.site/api/v3/loadPageChunk")
    }

    @Test func decodesReleasesInPageOrderWithVStripped() throws {
        let log = try #require(StructuredChangelogDecoder.decode(
            notionPageChunkFixture, format: .notionPageChunk, channel: nil, maxEntries: 20))

        #expect(log.entries.count == 3)
        // Order must come from the page block's `content` array, not the JSON
        // object's own key order (which Swift's Decodable/[String: X] does not
        // preserve at all) — this is the one property this fixture actually
        // proves rather than assumes.
        #expect(log.entries.map(\.version) == ["7.31.0", "7.29.0", "7.28.0"])
        // The leading "v" is stripped so the rail label matches the installed
        // build's marketing version exactly (no "v" prefix anywhere else in the
        // app's version display).
        #expect(log.entries.allSatisfy { !$0.version.hasPrefix("v") })
    }

    @Test func decodesRealDatesFromTheDateMention() throws {
        let log = try #require(StructuredChangelogDecoder.decode(
            notionPageChunkFixture, format: .notionPageChunk, channel: nil, maxEntries: 20))
        // The "📅 Released ‣ (macOS & Windows)" line's `‣` is a real Notion date
        // mention carrying `start_date`; the visible "‣" text itself is NOT the
        // date and must never leak into the field.
        #expect(log.entries[0].date == "2026-08-17")
        #expect(log.entries[1].date == "2026-08-03")
        #expect(log.entries[2].date == "2026-07-27")
    }

    @Test func decodesItemsPinningCountsAndTheLastItem() throws {
        let log = try #require(StructuredChangelogDecoder.decode(
            notionPageChunkFixture, format: .notionPageChunk, channel: nil, maxEntries: 20))
        #expect(log.entries[0].items.count == 1)
        #expect(log.entries[0].items == ["Allow additional SSO provider (Entra) login popups from in the app"])
        #expect(log.entries[1].items.count == 2)
        #expect(log.entries[2].items.count == 3)
        // Explicitly pin the LAST item of the LAST entry: the grouping must not
        // silently drop a trailing bullet when a release has several.
        #expect(log.entries[2].items.last
            == "As always, security and performance improvements, and small bug fixes")
    }

    @Test func maxEntriesCapsWithoutTruncatingTheLastKeptEntrysItems() throws {
        let log = try #require(StructuredChangelogDecoder.decode(
            notionPageChunkFixture, format: .notionPageChunk, channel: nil, maxEntries: 2))
        #expect(log.entries.count == 2)
        #expect(log.entries.map(\.version) == ["7.31.0", "7.29.0"])
        // The cap must apply BETWEEN releases, not mid-release: the second (kept)
        // entry still has both its bullets, not a partial set.
        #expect(log.entries[1].items.count == 2)
    }
}

// MARK: - Fetch-layer POST/GET regression

/// `ChangelogRecipe.httpMethod` must default to `.get` for every recipe that
/// doesn't set it explicitly — this is the regression guard for that default,
/// since `notion.id` is the ONLY `.post` recipe in the entire registry and a
/// mistake in the default would silently flip every other vendor's changelog
/// fetch to a POST that endpoint never expects.
@Suite struct ChangelogRecipeHTTPMethodTests {
    @Test func everyRecipeDefaultsToGETExceptNotion() {
        for recipe in ChangelogRecipeRegistry.recipes {
            if recipe.bundleID == "notion.id" {
                #expect(recipe.httpMethod == .post, "notion.id should be the POST recipe")
                #expect(recipe.requestBody != nil)
            } else {
                #expect(recipe.httpMethod == .get, "\(recipe.bundleID) must default to GET")
                #expect(recipe.requestBody == nil, "\(recipe.bundleID) must carry no request body")
            }
        }
    }

    @Test func decodingATerseRecipeOmittingHTTPFieldsYieldsGET() throws {
        // The forgiving decode path (`ChangelogRecipe.init(from:)`): a
        // remotely-authored recipe that predates `httpMethod`/`requestBody`
        // entirely must still decode as a plain GET, not fail or default to
        // something else.
        let json = """
        {"bundleID": "example.app", "source": "https://example.com/changelog"}
        """
        let recipe = try JSONDecoder().decode(ChangelogRecipe.self, from: Data(json.utf8))
        #expect(recipe.httpMethod == .get)
        #expect(recipe.requestBody == nil)
    }
}
