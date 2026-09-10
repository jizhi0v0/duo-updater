import Testing
import Foundation
@testable import DuoUpdaterCore

/// Replay of a real breakage: 2026-09-10, Microsoft's enterprise feed briefly
/// carried **no macOS release under Beta**, and Edge Beta resolved a *stable*
/// package.
///
/// The recipes select a product by name and then reach for the first macOS release
/// after it. With `(?s)` and a lazy `.*?` there was nothing stopping that reach from
/// leaving the product it started in, so an empty Beta walked straight into Stable
/// and produced `MicrosoftEdge-152.0.4191.66.pkg` for a bundle on the beta channel —
/// version and download URL both. `RecipeSanity.crossChannelArtifact` caught it in
/// CI ("carries no beta marker (expected /MicrosoftEdgeBeta-/)"), which is the whole
/// reason that gate exists, but the recipe was wrong for as long as the vendor's
/// feed was in that state.
///
/// The products are ordered Dev, Beta, Stable, so the same hole is in all five of
/// these patterns, not just Beta's: whichever track empties falls through to the
/// next one that has a macOS build. Stable was safe only by being last.
///
/// Everything here reads the patterns **out of the registry**, so the fix cannot
/// drift away from its test.
struct EdgeChannelBoundaryTests {

    /// The feed as it actually came back that morning. Trimmed **structurally** — the
    /// first macOS release of each product plus one non-macOS, in the original order
    /// — rather than by count: a "first two releases" trim dropped Dev's macOS entry
    /// and made three of these cases fail against a correct implementation.
    /// Beta's macOS list is empty here because that is what the vendor was serving.
    private static func fixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/edge-enterprise-beta-dormant.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The same feed two hours later, after Microsoft put a macOS build back under
    /// Beta (154.0.4258.9). Also a real capture, not a synthesised one — the pair is
    /// what makes the dormancy check two-sided.
    private static func fixtureWithBetaPublishing() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/edge-enterprise-beta-publishing.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func recipe(_ bundleID: String) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    private static func firstMatch(_ pattern: String, in body: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..., in: body)
        guard let m = re.firstMatch(in: body, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: body) else { return nil }
        return String(body[r])
    }

    private static func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        guard case .bodyPattern(let p) = try #require(recipe.install).urlSource else {
            throw CocoaError(.featureUnsupported)
        }
        return p
    }

    /// The bug itself: with Beta's macOS list empty, Beta must resolve **nothing**.
    /// Before the fix both of these returned Stable's 152 package.
    ///
    /// Mutation: drop the `(?:(?!"Product"\s*:)[\s\S])*?` tempering from either of
    /// Beta's two patterns — the match becomes Stable's artifact and this fails,
    /// naming the exact string that came back.
    @Test func anEmptyBetaTrackResolvesNothingRatherThanStablesPackage() throws {
        let body = try Self.fixture()
        let beta = try Self.recipe("com.microsoft.edgemac.Beta")

        let version = Self.firstMatch(beta.versionPattern, in: body)
        #expect(version == nil, "resolved \(version ?? "") from another product's block")

        let url = Self.firstMatch(try Self.installPattern(beta), in: body)
        #expect(url == nil, "resolved \(url ?? "") from another product's block")
    }

    /// ...and the tracks that *are* publishing still resolve their own artifacts, so
    /// the boundary did not simply break everything.
    ///
    /// Mutation: temper too aggressively (forbid crossing `"Platform"` as well) —
    /// Dev stops resolving and this fails.
    @Test func thePublishingTracksStillResolveTheirOwnArtifacts() throws {
        let body = try Self.fixture()

        let dev = try Self.recipe("com.microsoft.edgemac.Dev")
        #expect(Self.firstMatch(dev.versionPattern, in: body) == "155.0.4268.0")
        let devURL = try #require(Self.firstMatch(try Self.installPattern(dev), in: body))
        #expect(devURL.contains("MicrosoftEdgeDev-"), "Dev resolved \(devURL)")

        let stable = try Self.recipe("com.microsoft.edgemac")
        #expect(Self.firstMatch(stable.versionPattern, in: body) == "152.0.4191.66")
    }

    /// When Beta publishes again, it resolves its own package — the fix must not
    /// have turned a cross-channel bug into a permanently dead track.
    ///
    /// Mutation: replace the tempered reach with `(?!.)` or anything that can never
    /// cross a release boundary — Beta stops resolving even when publishing, and
    /// this fails.
    @Test func aBetaTrackThatPublishesAgainResolvesItsOwnPackage() throws {
        let body = try Self.fixtureWithBetaPublishing()
        let beta = try Self.recipe("com.microsoft.edgemac.Beta")

        #expect(Self.firstMatch(beta.versionPattern, in: body) == "154.0.4258.9")
        let url = try #require(Self.firstMatch(try Self.installPattern(beta), in: body))
        #expect(url.contains("MicrosoftEdgeBeta-"), "Beta resolved \(url)")
    }

    /// An empty track is dormancy, not breakage, and the recipe says how this vendor
    /// signals it — so the row stays calm instead of going red on a vendor that is
    /// simply between builds.
    ///
    /// The pattern is consulted only after the version pattern already missed, so
    /// the second half matters as much as the first: a track that IS publishing must
    /// not be talked into looking closed.
    ///
    /// Mutation: drop `trackClosedPattern` from the Beta recipe — the first
    /// expectation fails. Remove the `(?!"Platform"\s*:\s*"MacOS")` guard from it —
    /// it matches a publishing Beta too, and the second fails.
    @Test func anEmptyTrackIsReportedAsDormantAndAPublishingOneIsNot() throws {
        let beta = try Self.recipe("com.microsoft.edgemac.Beta")
        let closed = try #require(beta.trackClosedPattern)
        let re = try NSRegularExpression(pattern: closed)

        func matches(_ body: String) -> Bool {
            re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
        }
        #expect(matches(try Self.fixture()), "an empty Beta track must read as dormant")
        #expect(!matches(try Self.fixtureWithBetaPublishing()),
                "a publishing Beta track must never read as dormant")
    }

    /// Fixture guard. If the vendor body ever gets re-captured with Beta publishing,
    /// three of the cases above silently start asserting nothing.
    @Test func theFixtureReallyHasAnEmptyBetaTrack() throws {
        let body = try Self.fixture()
        let products = try #require(
            try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]])
        #expect(products.compactMap { $0["Product"] as? String } == ["Dev", "Beta", "Stable"],
                "the order is what makes an empty track fall into the next one")
        let betaMac = products
            .filter { $0["Product"] as? String == "Beta" }
            .flatMap { ($0["Releases"] as? [[String: Any]]) ?? [] }
            .filter { $0["Platform"] as? String == "MacOS" }
        #expect(betaMac.isEmpty, "the fixture is only a replay while Beta's macOS list is empty")
    }
}
