import Foundation
import Testing
@testable import DuoUpdaterCore

private func aiVendorRecipe(_ bundleID: String) throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
}

private func aiGitHubRule(_ bundleID: String) throws -> GitHubReleaseRule {
    try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID })
}

@Test func aiDesktopVendorRecipesExtractRealResponseShapes() throws {
    let fixtures: [(String, String, String)] = [
        ("com.electron.wispr-flow",
         #"{"currentRelease":"1.6.531","releases":[]}"#, "1.6.531"),
        ("com.granola.app",
         "version: 7.478.0\nreleaseDate: '2026-08-11T14:00:02.287Z'\n", "7.478.0"),
        ("ai.perplexity.comet",
         "https://storage.example/151.0.7922.247/comet_latest.dmg?signature=x",
         "151.0.7922.247"),
        ("com.exafunction.windsurf",
         #"{"productVersion":"1.126.0","windsurfVersion":"3.7.25"}"#, "3.7.25"),
        ("com.aionui.app",
         "version: 2.1.56\nreleaseDate: '2026-08-14T12:17:37.609Z'\n", "2.1.56"),
        ("MstyStudio",
         "version: 2.9.7\nreleaseDate: '2026-08-05T02:24:40.272Z'\n", "2.9.7"),
    ]

    for (bundleID, body, expected) in fixtures {
        let recipe = try aiVendorRecipe(bundleID)
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == expected)
    }
}

@Test func aiDesktopVendorPatternsRejectNearbyWrongVersions() throws {
    let devin = try aiVendorRecipe("com.exafunction.windsurf")
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"productVersion":"1.126.0","version":"deadbeef"}"#,
        pattern: devin.versionPattern) == nil)

    let wispr = try aiVendorRecipe("com.electron.wispr-flow")
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"version":"9.9.9","releases":[]}"#,
        pattern: wispr.versionPattern) == nil)

    let comet = try aiVendorRecipe("ai.perplexity.comet")
    #expect(VendorProbeRecipe.extractVersion(
        from: "https://storage.example/151.0.7922.247/unrelated.dmg",
        pattern: comet.versionPattern) == nil)
}

@Test func traeRemainsUnmappedUntilItsTwoVersionSchemesCanBeJoined() {
    #expect(VendorProbeRegistry.recipes.contains { $0.bundleID == "com.trae.app" } == false)
    #expect(GitHubReleaseRegistry.rules.contains { $0.bundleID == "com.trae.app" } == false)
}

@Test func aiDesktopGitHubRulesMatchStableTagsAndOnlyMacApps() throws {
    let cases: [(String, String, String, [String])] = [
        ("ai.opencode.desktop", "v1.18.18", "opencode-desktop-mac-arm64.dmg",
         ["opencode-desktop-mac-arm64.zip", "opencode-desktop-win-arm64.exe"]),
        ("dev.openchamber.desktop", "v1.18.4", "OpenChamber-1.18.4-mac-arm64.dmg",
         ["OpenChamber-1.18.4-mac-arm64.zip", "OpenChamber-1.18.4-win-arm64.exe"]),
        ("jan.ai.app", "v0.8.4", "jan-mac-universal-0.8.4.zip",
         ["Jan_0.8.4_universal.dmg", "Jan_0.8.4_amd64.AppImage"]),
    ]

    for (bundleID, tag, wanted, rejected) in cases {
        let rule = try aiGitHubRule(bundleID)
        #expect(VendorProbeRecipe.extractVersion(
            from: tag, pattern: rule.versionPattern) != nil)
        let pattern = try #require(rule.installAssetPattern)
        #expect(wanted.range(of: pattern, options: .regularExpression) != nil)
        for sibling in rejected {
            #expect(sibling.range(of: pattern, options: .regularExpression) == nil)
        }
    }
}

@Test func aiDesktopGitHubRulesChooseTheNativeArchitecture() throws {
    for bundleID in ["ai.opencode.desktop", "dev.openchamber.desktop"] {
        let rule = try aiGitHubRule(bundleID)
        let pattern = try #require(rule.installAssetPattern)
        let prefix = bundleID == "ai.opencode.desktop"
            ? "opencode-desktop-mac-" : "OpenChamber-1.18.4-mac-"
        let assets = ["\(prefix)x64.dmg", "\(prefix)arm64.dmg"].map {
            (name: $0, url: URL(string: "https://example.invalid/\($0)")!, size: Int64?.none)
        }
        #expect(GitHubReleaseRule.installableAsset(
            from: assets, matching: pattern, preferring: .arm64)?.url.lastPathComponent
            == "\(prefix)arm64.dmg")
        #expect(GitHubReleaseRule.installableAsset(
            from: assets, matching: pattern, preferring: .x86_64)?.url.lastPathComponent
            == "\(prefix)x64.dmg")
    }
}
