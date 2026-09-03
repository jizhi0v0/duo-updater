import Foundation
import Testing
@testable import DuoUpdaterCore

struct UTMChangelogRecipeTests {
    /// Representative GitHub Releases payload: UTM uses the same endpoint for
    /// both trains, with GitHub's `prerelease` bit as the channel boundary.
    private let fixture = #"""
    [
      {
        "tag_name": "v5.0.5",
        "name": "UTM v5.0.5",
        "body": "## Changes (v5.0.5)\n* Beta-only DirectX update",
        "published_at": "2026-09-02T05:14:37Z",
        "prerelease": true,
        "draft": false
      },
      {
        "tag_name": "v4.7.5",
        "name": "UTM v4.7.5",
        "body": "## Changes (v4.7.5)\n* Stable-only QEMU update",
        "published_at": "2026-05-09T12:00:00Z",
        "prerelease": false,
        "draft": false
      },
      {
        "tag_name": "v5.0.6",
        "name": "UTM v5.0.6 draft",
        "body": "* Unpublished draft",
        "published_at": "2026-09-03T00:00:00Z",
        "prerelease": true,
        "draft": true
      }
    ]
    """#

    @Test func recipesShareTheFeedButDecodeOnlyTheirOwnChannel() throws {
        let stableRecipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.utmapp.UTM", channel: .stable))
        let betaRecipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.utmapp.UTM", channel: .beta))

        #expect(stableRecipe.source == betaRecipe.source)
        #expect(stableRecipe.structuredFormat == .gitHubReleases)
        #expect(betaRecipe.structuredFormat == .gitHubReleases)

        let stableDecoded = StructuredChangelogDecoder.decode(
            fixture, format: .gitHubReleases,
            channel: stableRecipe.channel, maxEntries: stableRecipe.maxEntries)
        let betaDecoded = StructuredChangelogDecoder.decode(
            fixture, format: .gitHubReleases,
            channel: betaRecipe.channel, maxEntries: betaRecipe.maxEntries,
            includesPromotedStable: betaRecipe.includesPromotedStable)
        let stable = try #require(stableDecoded)
        let beta = try #require(betaDecoded)

        #expect(stable.entries.map(\.version) == ["4.7.5"])
        // Not the mirror image, deliberately: a preview install is offered the
        // release its own line graduated to, and that release is not a
        // prerelease — a prerelease-only history would render its notes as an
        // empty panel. See `ChangelogRecipe.includesPromotedStable`.
        #expect(beta.entries.map(\.version) == ["5.0.5", "4.7.5"])
        #expect(stable.entries.flatMap(\.items).contains {
            $0.contains("Stable-only QEMU update")
        })
        #expect(!stable.entries.flatMap(\.items).contains {
            $0.contains("Beta-only")
        })
        #expect(beta.entries.flatMap(\.items).contains {
            $0.contains("Beta-only DirectX update")
        })
        #expect(beta.entries.flatMap(\.items).contains {
            $0.contains("Stable-only QEMU update")
        })
        #expect(stableRecipe.includesPromotedStable == false,
                "the stable history must never show a preview")
        #expect(betaRecipe.includesPromotedStable)
        // The draft is not published on either side.
        #expect(!beta.entries.map(\.version).contains("5.0.6"))
    }
}
