import Foundation
import Testing

@testable import DuoUpdaterCore

/// SuperCmd ships two unrelated apps under one name: v1 (open-source Electron,
/// `com.supercmd.app`, read from GitHub by the rule under test) and v2 (native,
/// `com.supercmd.SuperCmd`, covered by its own Sparkle feed with no recipe). See
/// `docs/app-audits/com-supercmd-SuperCmd.md`.
@Suite struct SupercmdGitHubRuleTests {

    private static let v1ID = "com.supercmd.app"
    private static let v2IDs = ["com.supercmd.SuperCmd", "com.supercmd.SuperCmd.beta"]

    private func rule() throws -> GitHubReleaseRule {
        let found = GitHubReleaseRegistry.rules.filter { $0.bundleID == Self.v1ID }
        try #require(found.count == 1, "expected exactly one SuperCmd v1 rule")
        return found[0]
    }

    @Test func v1RuleIsStableAndDetectionOnly() throws {
        let rule = try rule()
        #expect(rule.owner == "SuperCmdLabs" && rule.repo == "SuperCmd")
        #expect(rule.channel == .stable)
        #expect(rule.usePrereleases == false)
        #expect(rule.installAssetPattern == nil)
        #expect(rule.installerKind == nil)
    }

    /// Tags are bare `X.Y.Z` and equal the bundle's `CFBundleShortVersionString`
    /// (real 1.0.26 dmg, 2026-09-17). Anything else is not a v1 release.
    @Test func v1PatternTakesOnlyBareTags() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "1.0.26", pattern: pattern) == "1.0.26")
        for tag in ["v1.0.26", "1.0.8-beta", "beta-v1.0.8-beta-1", "1.0"] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: pattern) == nil, "\(tag)")
        }
    }

    /// v2 and its beta each declare their own `SUFeedURL`, and the generic Sparkle
    /// source resolves both (checked with `channel-verify` on the real 1.0.7 and
    /// 1.0.8-beta bundles). The v1 rule must not be copied onto a v2 id: that repo
    /// holds v1 tags, and `1.0.0`…`1.0.7` exist in both version lines.
    @Test func v2HasNoRecipeOfItsOwn() {
        for id in Self.v2IDs {
            #expect(!GitHubReleaseRegistry.rules.contains { $0.bundleID == id }, "\(id)")
            #expect(!VendorProbeRegistry.recipes.contains { $0.bundleID == id }, "\(id)")
        }
    }
}
