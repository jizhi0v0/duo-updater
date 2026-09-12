import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChangelogCache` is a `[URL: Entry]` keyed by whatever `cacheKeyURL` returns,
/// and its doc comment promises "each recipe owns exactly one cache slot". That
/// held only for structured recipes: they got the channel folded into the key as a
/// fragment, and everyone else got the bare resolved URL. Two recipes that read
/// two different products out of ONE page (Antigravity's hub and its IDE, both
/// `antigravity.google/changelog`, both regex recipes, neither carrying a channel)
/// therefore shared a slot: whichever detail window opened first filled it, and
/// for the next 15 minutes the other app showed the first one's releases. Worse,
/// the loser was short-circuited before the fetch closure ran, so it wrote no disk
/// cache entry and recorded no `RecipeHealth` outcome either.
///
/// Derived from the registry, per CLAUDE.md, rather than listing the pair by hand:
/// the property is "every recipe owns its own slot", and the next one-page-many-
/// products recipe must fail here instead of being discovered by a user reading
/// the wrong app's notes.
/// Counts how many times a cache-miss fetch closure actually ran.
private actor FetchCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

@Suite struct ChangelogCacheKeyTests {

    @Test func noTwoRegisteredRecipesShareAnInMemoryCacheSlot() {
        var owners: [URL: [String]] = [:]
        for recipe in ChangelogRecipeRegistry.recipes {
            let key = ChangelogService.cacheKeyURL(for: recipe, resolved: recipe.source)
            owners[key, default: []].append(recipe.recipeID)
        }
        let shared = owners.filter { $0.value.count > 1 }
        #expect(shared.isEmpty, """
            These recipes share one ChangelogCache slot and will serve each other's \
            entries for a TTL window: \
            \(shared.map { "\($0.key.absoluteString) ← \($0.value.sorted())" }.sorted())
            """)
    }

    /// The pair that was actually colliding, named directly: the registry-derived
    /// check above goes green the moment someone deletes one of these two recipes,
    /// and this one says which case put the guard there.
    @Test func theTwoAntigravityRecipesGetDistinctKeys() throws {
        let hub = try #require(
            ChangelogRecipeRegistry.recipes.first { $0.bundleID == "com.google.antigravity" })
        let ide = try #require(
            ChangelogRecipeRegistry.recipes.first { $0.bundleID == "com.google.antigravity-ide" })
        #expect(hub.source == ide.source)
        #expect(ChangelogService.cacheKeyURL(for: hub, resolved: hub.source)
            != ChangelogService.cacheKeyURL(for: ide, resolved: ide.source))
    }

    /// The key is the page URL plus a fragment, and `load` fetches the
    /// un-fragmented `resolved` — so the identity we key on can never turn into a
    /// different request. A key that differed anywhere but the fragment would be a
    /// URL we might one day fetch.
    @Test func theKeyDiffersFromTheFetchedURLOnlyInItsFragment() throws {
        for recipe in ChangelogRecipeRegistry.recipes {
            let resolved = recipe.source
            let key = ChangelogService.cacheKeyURL(for: recipe, resolved: resolved)
            var stripped = try #require(URLComponents(url: key, resolvingAgainstBaseURL: false))
            stripped.fragment = nil
            #expect(stripped.url == resolved, "key \(key) is not \(resolved) plus a fragment")
        }
    }

    /// Two channels of one app reading one endpoint (the structured case this
    /// function was written for) must still land in separate slots — the fix
    /// generalised the key, it did not replace what was already working.
    @Test func twoChannelsOfOneEndpointStillGetDistinctKeys() {
        let page = URL(string: "https://zzfixture.example/changelog.json")!
        let stable = ChangelogRecipe(
            bundleID: "zz.fixture.app", source: page,
            channel: .stable, structuredFormat: .warpChannelVersions)
        let beta = ChangelogRecipe(
            bundleID: "zz.fixture.app", source: page,
            channel: .beta, structuredFormat: .warpChannelVersions)
        #expect(ChangelogService.cacheKeyURL(for: stable, resolved: page)
            != ChangelogService.cacheKeyURL(for: beta, resolved: page))
    }

    /// `invalidateMemoryCache` has to drop the slots `load` actually filled, and
    /// `load` keys on `resolvedSource(forVersion:)` — so for a templated recipe
    /// (one page per version) the slots are under URLs the un-templated
    /// `recipe.source` never names, and one recipe can hold several at once. This
    /// walks every templated recipe in the registry, warms two versions' slots, and
    /// requires the next load of each to fetch again.
    @Test func invalidationDropsEveryVersionResolvedSlotATemplatedRecipeOwns() async {
        let templated = ChangelogRecipeRegistry.recipes.filter { $0.sourceTemplate != nil }
        #expect(!templated.isEmpty, "no templated recipes left — this test would be vacuous")

        for recipe in templated {
            let cache = ChangelogCache()
            let counter = FetchCounter()
            let versions = ["1.2.3", "4.5.6"]

            func warm(_ version: String) async {
                let key = ChangelogService.cacheKeyURL(
                    for: recipe, resolved: recipe.resolvedSource(forVersion: version))
                _ = await cache.load(for: key) {
                    await counter.bump()
                    return Changelog(entries: [
                        .init(title: "t", version: version, date: nil, items: ["i"])
                    ])
                }
            }

            for version in versions { await warm(version) }
            #expect(await counter.count == versions.count)
            // Warm slots: a repeat load must not fetch.
            for version in versions { await warm(version) }
            #expect(await counter.count == versions.count)

            await ChangelogService.invalidateMemoryCache(for: recipe, in: cache)

            for version in versions { await warm(version) }
            #expect(
                await counter.count == versions.count * 2,
                "\(recipe.recipeID) kept a slot through invalidateMemoryCache")
        }
    }

    /// Two recipes for one bundle id and channel that differ only in their version
    /// window (Windscribe's, for one) read DIFFERENT pages for different installed
    /// versions — and `recipeID` is what keeps their verify history apart, so it is
    /// the right identity to key the cache on too.
    @Test func twoVersionWindowsOfOnePageGetDistinctKeys() {
        let page = URL(string: "https://zzfixture.example/notes")!
        let old = ChangelogRecipe(
            bundleID: "zz.fixture.app", source: page, belowAppVersion: "2.0")
        let new = ChangelogRecipe(
            bundleID: "zz.fixture.app", source: page, minimumAppVersion: "2.0")
        #expect(ChangelogService.cacheKeyURL(for: old, resolved: page)
            != ChangelogService.cacheKeyURL(for: new, resolved: page))
    }
}
