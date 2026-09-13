import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// A changelog recipe that resolves no entries can have failed in four different
/// places, and each one sends its reader somewhere else: fix a regex, chase a
/// moved page, or do nothing at all because the network stalled. Getting this
/// wrong is how HBuilderX Alpha spent a sweep reported as a broken entry pattern
/// while that pattern still matched the vendor's page perfectly.
@Suite struct ChangelogFailureClassificationTests {

    /// A real two-stage recipe from the registry — the index/detail split is the
    /// whole point, so this must not be a hand-built fixture that could drift
    /// from what the app actually runs.
    private func twoStageRecipe() throws -> ChangelogRecipe {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipes.first { $0.indexLinkPattern != nil },
            "the registry no longer has a two-stage recipe to test against")
        return recipe
    }

    /// Not a `feedPagePattern` recipe either: with no detail URL that one is
    /// reported as `noFeedPage`, not as its entry pattern failing.
    private func oneStageRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.indexLinkPattern == nil && $0.feedPagePattern == nil
        })
    }

    private func diagnostic(
        recipe: ChangelogRecipe,
        fetchFailed: Bool = false,
        httpStatus: Int? = 200,
        detailURL: URL? = nil,
        detailFetchFailed: Bool = false,
        detailHTTPStatus: Int? = nil
    ) -> ChangelogService.ChangelogDiagnostic {
        ChangelogService.ChangelogDiagnostic(
            changelog: nil, resolvedURL: recipe.source, httpStatus: httpStatus,
            fetchFailed: fetchFailed, bodySample: nil, detailURL: detailURL,
            detailFetchFailed: detailFetchFailed, detailHTTPStatus: detailHTTPStatus)
    }

    /// The regression: index fine, release page unreachable. Must read as
    /// infrastructure — and must NOT quote a pattern, because none was run.
    @Test func aStalledReleasePageIsNotAPatternFailure() throws {
        let recipe = try twoStageRecipe()
        let result = Verify.classifyChangelogFailure(
            diagnostic(
                recipe: recipe,
                detailURL: URL(string: "https://example.com/changelog/5.23.html")!,
                detailFetchFailed: true),
            recipe: recipe, host: "example.com")

        #expect(result.status == .infra, "a stalled fetch must be streak-exempt, not 'broken'")
        #expect(result.kind == "detailTransport")
        #expect(result.pattern == nil, "quoting a regex that never ran is what misled the reader")
        #expect(result.detail.contains("release page"))
    }

    /// A release page that answers 404 is a real, actionable break — the vendor
    /// moved it — so this one IS broken, and still quotes no pattern.
    @Test func aMovedReleasePageIsBrokenButStillQuotesNoPattern() throws {
        let recipe = try twoStageRecipe()
        let result = Verify.classifyChangelogFailure(
            diagnostic(
                recipe: recipe,
                detailURL: URL(string: "https://example.com/changelog/5.23.html")!,
                detailFetchFailed: true, detailHTTPStatus: 404),
            recipe: recipe, host: "example.com")

        #expect(result.status == .broken)
        #expect(result.kind == "detailHttpStatus404")
        #expect(result.pattern == nil)
    }

    /// …but a 5xx on that page is the vendor having a bad minute, not a recipe
    /// to repair.
    @Test func aServerErrorOnTheReleasePageStaysInfrastructure() throws {
        let recipe = try twoStageRecipe()
        let result = Verify.classifyChangelogFailure(
            diagnostic(
                recipe: recipe,
                detailURL: URL(string: "https://example.com/changelog/5.23.html")!,
                detailFetchFailed: true, detailHTTPStatus: 503),
            recipe: recipe, host: "example.com")

        #expect(result.status == .infra)
        #expect(result.kind == "detailHttpStatus503")
    }

    /// Index fetched, but no link in it — that is the INDEX pattern failing, and
    /// the report must quote that one rather than the entry pattern.
    @Test func aLinklessIndexBlamesTheIndexPattern() throws {
        let recipe = try twoStageRecipe()
        let result = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe, detailURL: nil),
            recipe: recipe, host: "example.com")

        #expect(result.status == .broken)
        #expect(result.kind == "noDetailLink")
        #expect(result.pattern == recipe.indexLinkPattern)
        #expect(result.pattern != recipe.entryPattern)
    }

    /// A feed-page recipe whose appcast answered but linked no page it accepts
    /// never ran its entry pattern, so the page pattern is the one quoted — a
    /// vendor that moved its notes shows up here. Mutation: remove the
    /// `noFeedPage` branch and this reads as `noEntriesExtracted`.
    @Test func aFeedWithNoAcceptedPageBlamesThePagePattern() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipes.first { $0.feedPagePattern != nil },
            "the registry no longer has a feedPagePattern recipe to test against")
        let result = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe, detailURL: nil),
            recipe: recipe, host: "raw.githubusercontent.com")

        #expect(result.status == .broken)
        #expect(result.kind == "noFeedPage")
        #expect(result.pattern == recipe.feedPagePattern)
    }

    /// The page was fetched and parsed to nothing, so the message must name the
    /// host the entry pattern ran on, not the appcast's. Mutation: name `host`
    /// again and this reads "fetched raw.githubusercontent.com fine".
    @Test func aFeedPageThatParsesToNothingNamesThePageHost() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipes.first { $0.feedPagePattern != nil })
        let result = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe, detailURL: URL(string: "https://raw.githack.com/zz/de.html")!),
            recipe: recipe, host: "raw.githubusercontent.com")

        #expect(result.kind == "noEntriesExtracted")
        #expect(result.detail.contains("raw.githack.com"))
        #expect(!result.detail.contains("raw.githubusercontent.com"))
    }

    /// A dead notes host must be filed under its own name: the infra-streak issue
    /// tells the reader to `dig` this host. Mutation: `failingHost` returns `host`
    /// unconditionally and the first expectation names the appcast host.
    @Test func aFailedReleasePageIsFiledUnderItsOwnHost() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipes.first { $0.feedPagePattern != nil })
        let page = URL(string: "https://raw.githack.com/zz/de.html")!
        #expect(Verify.failingHost(
            diagnostic(recipe: recipe, detailURL: page, detailFetchFailed: true),
            host: "raw.githubusercontent.com") == "raw.githack.com")
        // The page was fetched; only the pattern failed. Stage one is still the
        // request to name when stage one is what failed.
        #expect(Verify.failingHost(
            diagnostic(recipe: recipe, detailURL: page),
            host: "raw.githubusercontent.com") == "raw.githubusercontent.com")
        #expect(Verify.failingHost(
            diagnostic(recipe: recipe, fetchFailed: true, httpStatus: nil),
            host: "raw.githubusercontent.com") == "raw.githubusercontent.com")
    }

    /// The genuine pattern failure still reports as one, quoting the entry
    /// pattern — the fix must not make every failure look like a network blip.
    @Test func aRestyledPageStillBlamesTheEntryPattern() throws {
        let recipe = try oneStageRecipe()
        let result = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe), recipe: recipe, host: "example.com")

        #expect(result.status == .broken)
        #expect(result.kind == "noEntriesExtracted")
        #expect(result.pattern == recipe.entryPattern)
    }

    /// Stage-1 failures are unchanged: unreachable is infrastructure, a 404 is a
    /// moved page.
    @Test func stageOneFailuresKeepTheirOldMeaning() throws {
        let recipe = try oneStageRecipe()
        let unreachable = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe, fetchFailed: true, httpStatus: nil),
            recipe: recipe, host: "example.com")
        #expect(unreachable.kind == "transport")
        #expect(unreachable.status == .infra)

        let gone = Verify.classifyChangelogFailure(
            diagnostic(recipe: recipe, fetchFailed: true, httpStatus: 404),
            recipe: recipe, host: "example.com")
        #expect(gone.kind == "httpStatus404")
        #expect(gone.status == .broken)
    }
}
