import Foundation
import Testing

@testable import DuoUpdaterCore

/// Lokii (`Recipes/com-lokii-app.swift`): ad-hoc signed, so it installs only on
/// the published-digest route, and its dmgs carry an arch but no version.
@Suite struct LokiiGitHubRuleTests {

    @Test func ruleReadsTheBareTagAndBothArchDmgsOnTheDigestRoute() throws {
        let rule = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "com.lokii.app" })
        #expect(rule.owner == "huangy7" && rule.repo == "lokii")
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .dmg)
        #expect(rule.installTrust == .publishedDigestOnly)
        let pattern = try #require(rule.installAssetPattern)
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }

        #expect(VendorProbeRecipe.extractVersion(from: "v0.1.1", pattern: rule.versionPattern) == "0.1.1")
        #expect(VendorProbeRecipe.extractVersion(from: "v0.2.0-beta.1", pattern: rule.versionPattern) == nil)
        #expect(matches("Lokii-arm64.dmg"))
        #expect(matches("Lokii-x86_64.dmg"))
        #expect(!matches("Lokii-arm64.dmg.sha256"))
        #expect(!matches("Lokii-arm64.zip"))
    }
}
