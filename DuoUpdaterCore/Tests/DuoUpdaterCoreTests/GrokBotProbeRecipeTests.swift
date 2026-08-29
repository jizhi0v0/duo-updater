import Testing
import Foundation
@testable import DuoUpdaterCore

/// Grok Bot's update JSON, captured verbatim on 2026-08-29 (the whole body is
/// 297 bytes) against the installed 0.30.0.
private let grokBotFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/grokbot/stable/darwin-arm64/0.30.0/Grok_Bot_0.30.0.dmg","rehUrl":"https://cursor.blob.core.windows.net/remote-releases/2385d097738b3719cc5ecd9281a107aa106215f0/vscode-reh-darwin-arm64.tar.gz","version":"0.30.0","commitSha":"2385d097738b3719cc5ecd9281a107aa106215f1"}
"""#

/// The same endpoint asked for the other two architectures, captured in the same
/// minute. Kept because `downloads.cursor.com` is one host for all of them: what
/// keeps this recipe on arm64 is the pinned path, nothing else.
private let grokBotIntelFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/grokbot/stable/darwin-x64/0.30.0/Grok_Bot_0.30.0_x64.dmg","rehUrl":"https://cursor.blob.core.windows.net/remote-releases/2385d097738b3719cc5ecd9281a107aa106215f0/vscode-reh-darwin-x64.tar.gz","version":"0.30.0","commitSha":"2385d097738b3719cc5ecd9281a107aa106215f1"}
"""#

private let grokBotUniversalFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/grokbot/stable/darwin-universal/0.30.0/Grok_Bot_0.30.0.dmg","rehUrl":"https://cursor.blob.core.windows.net/remote-releases/2385d097738b3719cc5ecd9281a107aa106215f0/vscode-reh-darwin-universal.tar.gz","version":"0.30.0","commitSha":"2385d097738b3719cc5ecd9281a107aa106215f1"}
"""#

/// The vendor publishes the same artifact under a second path prefix: the API
/// says `/grokbot/…`, the Homebrew cask's url template builds `/sand/…`, and both
/// answered 200 with `application/x-apple-diskimage` on 2026-08-29. Synthetic
/// bodies — the API has not been observed returning these — but the URLs in them
/// are real, so the install pattern has to accept the arm64 one.
private let grokBotSandPrefixFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/sand/stable/darwin-arm64/0.30.0/Grok_Bot_0.30.0.dmg","version":"0.30.0"}
"""#

private let grokBotSandPrefixIntelFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/sand/stable/darwin-x64/0.30.0/Grok_Bot_0.30.0_x64.dmg","version":"0.30.0"}
"""#

/// Cursor's own answer from the same API, same shape, same download host —
/// captured 2026-08-29. The two recipes are neighbours reading the same service,
/// so each one's install pattern has to refuse the other's artifact.
private let cursorFixture = #"""
{"downloadUrl":"https://downloads.cursor.com/production/2ba48ff3f7514cc4643c52ca9f7b3173d9b66137/darwin/arm64/Cursor-darwin-arm64.dmg","rehUrl":"https://cursor.blob.core.windows.net/remote-releases/2ba48ff3f7514cc4643c52ca9f7b3173d9b66130/vscode-reh-darwin-arm64.tar.gz","version":"3.18.9","commitSha":"2ba48ff3f7514cc4643c52ca9f7b3173d9b66137"}
"""#

struct GrokBotProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.anysphere.sand" }
    }

    private func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return ""
        }
        return pattern
    }

    @Test func readsTheVersionFieldOffTheSandEndpoint() throws {
        let recipe = try #require(recipe)
        // `sand` is the app's name on this API, not `grok-bot`: every other name
        // 404s with "can only download stable for cursor or sand".
        #expect(recipe.url.absoluteString
            == "https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand")
        #expect(VendorProbeRecipe.extractVersion(
            from: grokBotFixture, pattern: recipe.versionPattern) == "0.30.0")
    }

    @Test func installsTheArm64BuildTheSameBodyNames() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        #expect(VendorProbeRecipe.extractVersion(
            from: grokBotFixture, pattern: try installPattern(recipe))
            == "https://downloads.cursor.com/grokbot/stable/darwin-arm64/0.30.0/Grok_Bot_0.30.0.dmg")
        // Electron + Squirrel, both inside the bundle; nothing lands in /Library,
        // so a bundle swap is the whole update.
        #expect(spec.kind == .dmg)
    }

    /// The reason the install pattern names a path prefix instead of just the
    /// host: one CDN serves this app, Cursor, and this app's other architectures.
    @Test func theInstallPatternRefusesEveryNeighbourOnTheSameHost() throws {
        let recipe = try #require(recipe)
        let pattern = try installPattern(recipe)
        for (label, body) in [("Intel", grokBotIntelFixture),
                              ("universal", grokBotUniversalFixture),
                              ("Cursor", cursorFixture)] {
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == nil,
                    "the \(label) artifact must not be offered to an arm64 Grok Bot")
            #expect(body.contains("downloads.cursor.com"),
                    "the fixture must still exercise the shared host")
        }
    }

    @Test func acceptsTheOtherPathPrefixTheVendorPublishesUnder() throws {
        let recipe = try #require(recipe)
        let pattern = try installPattern(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: grokBotSandPrefixFixture, pattern: pattern)
            == "https://downloads.cursor.com/sand/stable/darwin-arm64/0.30.0/Grok_Bot_0.30.0.dmg")
        // Widening to a second prefix must not have widened the architecture with it.
        #expect(VendorProbeRecipe.extractVersion(
            from: grokBotSandPrefixIntelFixture, pattern: pattern) == nil)
    }

    /// Cursor's build is 3.18.9 against this app's 0.30.0 on the same JSON shape.
    /// Reading the wrong endpoint would not fail loudly — it would report a
    /// permanent update — so pin that the two recipes are separate entries.
    @Test func doesNotShareCursorsEndpoint() throws {
        let recipe = try #require(recipe)
        let cursor = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.todesktop.230313mzl4w4u92" })
        #expect(recipe.url != cursor.url)
        #expect(VendorProbeRecipe.extractVersion(
            from: cursorFixture, pattern: recipe.versionPattern) == "3.18.9",
            "the version pattern is shape-based, which is exactly why the URL has to be right")
    }

    /// The bundle offers three tracks (`stable` → `sand`, `nightly` →
    /// `sand-nightly`, `dogfood` → `sand-dogfood`) but coerces nightly back to
    /// stable and gates dogfood behind an internal unlock — and the server 404s
    /// both of those app names. One reachable channel, so one recipe.
    @Test func hasExactlyOneStableChannelRecipe() throws {
        let matches = VendorProbeRegistry.recipes.filter { $0.bundleID == "com.anysphere.sand" }
        #expect(matches.count == 1)
        #expect(matches.first?.channel == .stable)
    }

    /// The capture is bounded by quotes on both sides, so the segment count is
    /// not the boundary — a 0.31 or a 0.30.0.1 must both still parse (the Zotero
    /// rule), while the commit SHA beside them must not.
    @Test func acceptsOtherSegmentCountsWithoutDriftingOntoTheSha() throws {
        let recipe = try #require(recipe)
        let pattern = recipe.versionPattern
        #expect(VendorProbeRecipe.extractVersion(
            from: #"{"version":"0.31","commitSha":"2385d097738b3719"}"#, pattern: pattern) == "0.31")
        #expect(VendorProbeRecipe.extractVersion(
            from: #"{"version":"0.30.0.1","commitSha":"2385d097738b3719"}"#, pattern: pattern)
            == "0.30.0.1")
        #expect(VendorProbeRecipe.extractVersion(
            from: #"{"commitSha":"2385d097738b3719cc5ecd9281a107aa106215f1"}"#, pattern: pattern)
            == nil)
    }

    /// The download page's own button points at
    /// `/updates/download/stable/darwin-arm64/grok-bot-<token>`, which 302s to the
    /// same dmg and publishes no version. Recorded so a later reader doesn't
    /// "simplify" the recipe onto the URL x.ai actually advertises.
    @Test func sendsAHumanToTheVendorPageRatherThanItsRedirect() throws {
        let recipe = try #require(recipe)
        #expect(recipe.downloadURL?.absoluteString == "https://x.ai/bot")
        // xAI publishes no desktop release notes; `x.ai/api/changelog` is the
        // developer console's, on a different product and version scheme.
        #expect(recipe.changelogURL == nil)
    }
}
