import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `ChangelogCoverage` on registries built here, so each case is one app and the
/// answer does not move when the real registries do.
struct ChangelogCoverageTests {

    private func probe(_ bundleID: String, changelog: String?) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "https://api.example.invalid/\(bundleID)/latest")!,
            mode: .responseBody,
            versionPattern: #""version":"([0-9.]+)""#,
            changelogURL: changelog.flatMap(URL.init(string:)))
    }

    private func recipe(_ bundleID: String) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://notes.example.invalid/\(bundleID)")!,
            entryPattern: #"<h2>(?<version>[0-9.]+)</h2>"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
    }

    private func byID(
        probes: [VendorProbeRecipe] = [], catalog: [String: URL] = [:],
        recipes: [ChangelogRecipe] = [], acknowledged: [String: String] = [:]
    ) -> [String: Finding] {
        let findings = ChangelogCoverage.findings(
            probes: probes, catalog: catalog, recipes: recipes, acknowledged: acknowledged)
        return Dictionary(uniqueKeysWithValues: findings.map { ($0.recipeID, $0) })
    }

    /// The TRAE shape: a probe links its notes page and nothing structures it.
    @Test func aPageWithNoRecipeIsANewGap() throws {
        let found = byID(probes: [probe("com.example.app", changelog: "https://docs.example.invalid/changelog")])
        let finding = try #require(found["coverage:com.example.app"])
        #expect(finding.status == .warn)
        #expect(finding.registry == .changelogCoverage)
        #expect(finding.failureKind == "noChangelogRecipe")
        #expect(finding.failureDetail?.contains("https://docs.example.invalid/changelog") == true)
        #expect(finding.endpointHost == "docs.example.invalid")
    }

    @Test func aRecipeOrAnAcknowledgementIsOK() {
        let page = "https://docs.example.invalid/changelog"
        let found = byID(
            probes: [probe("com.example.structured", changelog: page),
                     probe("com.example.accepted", changelog: page)],
            recipes: [recipe("com.example.structured")],
            acknowledged: ["com.example.accepted": "the page has no version numbers"])
        #expect(found["coverage:com.example.structured"]?.status == .ok)
        #expect(found["coverage:com.example.accepted"]?.status == .ok)
        #expect(found.count == 2)
    }

    /// A probe with no page is not this check's business, and a recipe with no
    /// page anywhere is covered by being a recipe.
    @Test func noPageNoFinding() {
        let found = byID(probes: [probe("com.example.silent", changelog: nil)],
                         recipes: [recipe("com.example.recipeonly")])
        #expect(found.isEmpty)
    }

    /// The list must not outlive its reasons, in either direction.
    @Test func aStaleAcknowledgementWarns() {
        let found = byID(
            probes: [probe("com.example.fixed", changelog: "https://docs.example.invalid/a")],
            recipes: [recipe("com.example.fixed")],
            acknowledged: ["com.example.fixed": "x", "com.example.retired": "y"])
        #expect(found["coverage:com.example.fixed"]?.status == .warn)
        #expect(found["coverage:com.example.fixed"]?.failureKind == "staleAcknowledgement")
        #expect(found["coverage:com.example.retired"]?.status == .warn)
        #expect(found["coverage:com.example.retired"]?.failureKind == "staleAcknowledgement")
        #expect(found["coverage:com.example.retired"]?.endpointHost == "-")
    }

    /// Bundle ids are matched without regard to case, the way `ChangelogCatalog`
    /// and the recipe lookups match them: Discord's probe spells `com.hnc.Discord`.
    @Test func bundleIDsMatchWithoutCase() {
        let found = byID(
            probes: [probe("com.Example.Mixed", changelog: "https://docs.example.invalid/a")],
            recipes: [recipe("com.EXAMPLE.mixed")])
        #expect(found["coverage:com.Example.Mixed"]?.status == .ok)
        let accepted = byID(
            probes: [probe("com.Example.Mixed", changelog: "https://docs.example.invalid/a")],
            acknowledged: ["com.EXAMPLE.mixed": "x"])
        #expect(accepted["coverage:com.Example.Mixed"]?.status == .ok)
    }

    /// A `ChangelogCatalog` page is a page too, and one app with both is one finding.
    @Test func catalogPagesCountAndMergeWithProbes() throws {
        let found = byID(
            probes: [probe("com.example.both", changelog: "https://a.example.invalid/notes")],
            catalog: ["com.example.both": URL(string: "https://b.example.invalid/notes")!,
                      "com.example.catalogonly": URL(string: "https://c.example.invalid/notes")!])
        #expect(found.count == 2)
        let both = try #require(found["coverage:com.example.both"]?.failureDetail)
        #expect(both.contains("a.example.invalid") && both.contains("b.example.invalid"))
        #expect(found["coverage:com.example.catalogonly"]?.status == .warn)
    }

    /// An issue for a gap is titled by the app alone: the id carries no channel.
    @Test func theIssueTitleNamesTheApp() throws {
        let finding = try #require(
            byID(probes: [probe("com.example.app", changelog: "https://d.example.invalid/n")]).values.first)
        #expect(Reconcile.title(for: finding)
            == "Recipe degraded: com.example.app (changelog gap) — noChangelogRecipe")
    }

    /// Every id the check can produce is one `Baseline.prune` keeps, so an issue
    /// it opened is not orphaned the next sweep.
    @Test func everyIDIsLive() {
        let live = Verify.liveRecipeIDs()
        #expect(ChangelogCoverage.findings().allSatisfy { live.contains($0.recipeID) })
    }

    @Test func theSummaryCountsTheAcceptedGaps() throws {
        let findings = ChangelogCoverage.findings()
        let line = try #require(ChangelogCoverage.summary(findings))
        let listed = Set(ChangelogCoverage.acknowledged.keys.map { $0.lowercased() })
        let accepted = findings.filter {
            $0.status == .ok && listed.contains($0.bundleID.lowercased())
        }
        #expect(line.hasPrefix("\(accepted.count) of \(findings.count) apps"))
        #expect(ChangelogCoverage.summary([]) == nil)
    }
}
