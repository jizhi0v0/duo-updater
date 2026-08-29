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

// MARK: - One-click, wired 2026-08-29

private struct InstallURLSourceMismatch: Error { let bundleID: String }

/// Resolve a recipe's install URL the way `VendorProbeSource.resolveInstall` does,
/// for the two url sources these three use. Deliberately re-derived from the
/// registry rather than hand-written: a recipe that switches to a different
/// `URLSource` fails here instead of silently losing its verified URL.
private func aiInstallURL(_ bundleID: String, body: String, version: String) throws -> String {
    let recipe = try aiVendorRecipe(bundleID)
    let spec = try #require(recipe.install, "\(bundleID) lost its install spec")
    switch spec.urlSource {
    case .versionTemplate(let template):
        return template.replacingOccurrences(of: "{version}", with: version)
    case .bodyPattern(let pattern):
        return try #require(
            VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
            "\(bundleID) install pattern matched nothing")
    default:
        throw InstallURLSourceMismatch(bundleID: bundleID)
    }
}

/// The exact URLs these recipes build from the vendors' real responses, each
/// downloaded on 2026-08-29 and verified: right bundle id, `Developer ID
/// Application` for the Team the recipe's comment names, spctl "Notarized
/// Developer ID", stapled.
@Test func aiDesktopOneClickBuildsTheVerifiedArtifactURLs() throws {
    #expect(try aiInstallURL(
        "com.electron.wispr-flow",
        body: #"{"currentRelease":"1.6.721","releases":[]}"#,
        version: "1.6.721")
        == "https://dl.wisprflow.com/wispr-flow/darwin/arm64/"
        + "Wispr%20Flow-darwin-arm64-1.6.721.zip")

    #expect(try aiInstallURL(
        "com.aionui.app",
        body: "version: 2.1.61\n",
        version: "2.1.61")
        == "https://static.aionui.com/releases/2.1.61/AionUi-2.1.61-mac-arm64.zip")

    // Devin's url comes out of the response itself, so the fixture is the shape
    // the endpoint really returns — VS Code base version included, to pin that the
    // install pattern reads the url and not `productVersion`'s neighbourhood.
    #expect(try aiInstallURL(
        "com.exafunction.windsurf",
        body: #"{"url":"https://windsurf-stable.codeiumdata.com/darwin-arm64-dmg/stable/"#
            + #"2d9020110aa91587b3c3b0fcf7d1faaf601fc7b8/Devin-darwin-arm64-3.8.20.dmg","#
            + #""productVersion":"1.126.0","windsurfVersion":"3.8.20"}"#,
        version: "3.8.20")
        == "https://windsurf-stable.codeiumdata.com/darwin-arm64-dmg/stable/"
        + "2d9020110aa91587b3c3b0fcf7d1faaf601fc7b8/Devin-darwin-arm64-3.8.20.dmg")
}

/// AionUi's manifest lists a digest for every artifact it publishes, indented
/// under `files:`, and one more at column 0 for `path:` — the zip the template
/// builds. The install spec's pattern must read the top-level one; the indented
/// list happens to start with the zip's digest today, so a pattern that dropped
/// the anchor would pass on this manifest and quietly verify the dmg's digest
/// against the zip's bytes the day the vendor reorders `files:`.
@Test func aionUIChecksumIgnoresThePerFileDigests() throws {
    let recipe = try aiVendorRecipe("com.aionui.app")
    let spec = try #require(recipe.install)
    let pattern = try #require(spec.checksumPattern)

    let manifest = """
        version: 2.1.61
        files:
          - url: AionUi-2.1.61-mac-arm64.dmg
            sha512: DMG_DIGEST_MUST_NOT_WIN==
            size: 289718367
          - url: AionUi-2.1.61-mac-arm64.zip
            sha512: ZIP_DIGEST==
            size: 293814907
        path: AionUi-2.1.61-mac-arm64.zip
        sha512: ZIP_DIGEST==
        releaseDate: '2026-08-25T03:50:12.514Z'
        """
    #expect(VendorProbeRecipe.extractVersion(from: manifest, pattern: pattern) == "ZIP_DIGEST==")
}

/// The other two apps from the same 2026-08-17 batch stay detection-only, each
/// for a blocker that is NOT the architecture story the comments used to tell:
///
///   * Comet resolves through a 307 whose `Location` is a signed, expiring R2 URL.
///     `.redirect` HEAD-follows, and this vendor traps HEAD — measured 2026-08-29,
///     HEAD answers `Location: https://www.example.com?status=ok` while GET on the
///     same URL returns the real artifact. One-click needs GET-based resolution.
///   * Msty publishes x64 and arm64 in ONE manifest whose `path:` names the x64
///     zip. A pattern can pick the arm64 entry, but `checksumPattern` is a separate
///     first-match over the whole body and would pair it with x64's digest.
///
/// Wiring either without closing its blocker is the failure a signature gate
/// cannot catch, so this test is the reminder rather than a prohibition.
@Test func cometAndMstyRemainDetectionOnlyUntilTheirBlockersAreClosed() throws {
    for bundleID in ["ai.perplexity.comet", "MstyStudio"] {
        let recipe = try aiVendorRecipe(bundleID)
        #expect(recipe.install == nil,
                "\(bundleID) gained a one-click — close the blocker in the comment first")
    }
}
