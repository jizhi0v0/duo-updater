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
        ("com.FluidApp.app", "v1.6.9", "Fluid-oss-1.6.9.dmg",
         ["Fluid-oss-1.6.9.zip", "Fluid-oss-1.5.11-beta.3.dmg",
          "FluidVoice_0.0.9_x64-setup.exe"]),
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

/// Comet and Msty gained one-click on 2026-08-29, each by using the machinery
/// that was already there rather than by adding a `URLSource` case.
///
/// Comet's install URL is the GATEWAY, not the signed R2 URL its probe resolves.
/// Every install URL is resolved at check time and held on the row until the user
/// clicks; that signature lives an hour (`X-Amz-Expires=3600`), which is shorter
/// than every check frequency except hourly. Pointing the download at the gateway
/// moves the redirect to download time. `.redirect` is not an option either: this
/// vendor answers HEAD with `Location: https://www.example.com?status=ok`.
@Test func cometInstallsThroughTheGatewaySoTheSignatureIsAlwaysFresh() throws {
    let recipe = try aiVendorRecipe("ai.perplexity.comet")
    let spec = try #require(recipe.install)
    #expect(spec.kind == .dmg)
    guard case .fixed(let url) = spec.urlSource else {
        Issue.record("Comet must not template the signed URL its probe resolved")
        return
    }
    #expect(url.absoluteString
        == "https://www.perplexity.ai/rest/browser/download?channel=stable&platform=mac_arm64")
    // The signed artifact URL must never become the thing we store.
    #expect(!url.absoluteString.contains("X-Amz-"))
    #expect(!url.absoluteString.contains("r2.cloudflarestorage.com"))
    // And it must be the SAME endpoint the probe reads, not a second copy of the
    // string. Retargeting one and not the other offers a version from one channel
    // and installs the other — both correctly signed, so no gate would object.
    #expect(url == recipe.url)
}

/// Msty's manifest lists four artifacts and the x64 zip is FIRST, so the digest a
/// naive `^\s+sha512:` finds belongs to the build this recipe does not download.
/// The pattern has to be anchored on the arm64 filename. These are the real
/// digests from the 2.9.8 manifest, in the vendor's own order.
@Test func mstyChecksumIsPairedWithTheArm64EntryAndNotTheFirstOne() throws {
    let recipe = try aiVendorRecipe("MstyStudio")
    let spec = try #require(recipe.install)
    #expect(spec.kind == .zip)
    guard case .fixed(let url) = spec.urlSource else {
        Issue.record("Msty's filenames carry no version — the URL is a constant")
        return
    }
    #expect(url.lastPathComponent == "MstyStudio_arm64.zip")

    let manifest = """
        version: 2.9.8
        files:
          - url: MstyStudio_x64.zip
            sha512: X64_ZIP_DIGEST==
            size: 254799864
          - url: MstyStudio_arm64.zip
            sha512: ARM64_ZIP_DIGEST==
            size: 248234928
          - url: MstyStudio_x64.dmg
            sha512: X64_DMG_DIGEST==
            size: 264934032
          - url: MstyStudio_arm64.dmg
            sha512: ARM64_DMG_DIGEST==
            size: 258344557
        path: MstyStudio_x64.zip
        sha512: X64_ZIP_DIGEST==
        releaseDate: '2026-08-28T04:41:05.703Z'
        """
    let pattern = try #require(spec.checksumPattern)
    #expect(VendorProbeRecipe.extractVersion(from: manifest, pattern: pattern)
        == "ARM64_ZIP_DIGEST==")

    // `path:` — what an electron-builder recipe would normally follow — names the
    // x64 zip here, which is why neither it nor the first `files:` entry may drive
    // this recipe.
    #expect(manifest.contains("path: MstyStudio_x64.zip"))
}

/// TRAE is still the one app from this batch with no recipe at all, and the two
/// registries must keep agreeing about that.
@Test func everyAppFromTheAIDesktopBatchNowInstallsExceptTheOneThatCannot() throws {
    for bundleID in [
        "com.electron.wispr-flow", "com.aionui.app", "com.exafunction.windsurf",
        "ai.perplexity.comet", "MstyStudio",
    ] {
        let recipe = try aiVendorRecipe(bundleID)
        #expect(recipe.install != nil, "\(bundleID) lost its one-click")
    }
    #expect(VendorProbeRegistry.recipes.contains { $0.bundleID == "com.trae.app" } == false)
}

// MARK: - The check that would have caught this batch

/// `oneClickCandidate` is the sweep's answer to the failure this file documents:
/// a recipe that only detects while its own response hands us an installer.
@Test func oneClickCandidateFlagsDetectionOnlyRecipesThatNameAnArtifact() throws {
    // A detection-only recipe whose body names a zip — Antigravity's real shape.
    let detectionOnly = try #require(
        VendorProbeRegistry.recipes.first { $0.install == nil })
    #expect(RecipeSanity.oneClickCandidate(
        recipe: detectionOnly,
        bodySample: #"{"url":"https://edgedl.example.com/App-2.5.5-darwin-arm.zip"}"#) != nil)

    // Nothing to say when the body carries no artifact at all.
    #expect(RecipeSanity.oneClickCandidate(
        recipe: detectionOnly, bodySample: #"{"version":"2.5.5"}"#) == nil)
    #expect(RecipeSanity.oneClickCandidate(
        recipe: detectionOnly, bodySample: nil) == nil)

    // And never for a recipe that already installs — the three from this batch
    // would otherwise each carry a permanent note.
    for bundleID in ["com.electron.wispr-flow", "com.aionui.app", "com.exafunction.windsurf"] {
        let wired = try aiVendorRecipe(bundleID)
        #expect(RecipeSanity.oneClickCandidate(
            recipe: wired,
            bodySample: "https://example.com/App-1.2.3.dmg") == nil,
            "\(bundleID) has an install spec and must not be flagged")
    }
}

/// Narrow on purpose: a false positive here sends someone to investigate a recipe
/// that is fine, and the note cannot be dismissed by fixing anything.
@Test func artifactDetectionDoesNotFireOnProseOrPagesOrPlainHosts() {
    #expect(RecipeSanity.firstArtifactURL(in: "see https://example.com/download") == nil)
    // `http` is not a disqualifier: Sogou's endpoint publishes its zip over plain
    // http, and the install path upgrades the scheme. Refusing it here reported
    // nothing for the one recipe that most needed reporting.
    #expect(RecipeSanity.firstArtifactURL(in: "update_pack_url=http://cdn.example.com/autosetup6.zip")
        == "http://cdn.example.com/autosetup6.zip")
    #expect(RecipeSanity.firstArtifactURL(in: "App-1.2.3.dmg") == nil)
    #expect(RecipeSanity.firstArtifactURL(
        in: #"<a href="https://cdn.example.com/App_2.0.pkg">"#)
        == "https://cdn.example.com/App_2.0.pkg")
    // A signed URL keeps its query — that is the whole artifact, and truncating it
    // would print a link nobody can follow.
    #expect(RecipeSanity.firstArtifactURL(
        in: "https://r2.example.com/151/comet_latest.dmg?X-Amz-Expires=3600 trailing")
        == "https://r2.example.com/151/comet_latest.dmg?X-Amz-Expires=3600")
}

/// A forge's release JSON always carries `tarball_url`/`zipball_url`, and on
/// LibreWolf's real Codeberg response that source archive is the FIRST match in
/// the document — ahead of the macOS dmg. Measured 2026-08-29: the first version
/// of this check reported `…/bsys6/archive/154.0.1-3.tar.gz`, sending a reader to
/// the project's source instead of its installer.
@Test func sourceArchivesAreNotMistakenForInstallers() {
    let releaseJSON = #"""
        {"tag_name":"154.0.1-3",
         "tarball_url":"https://codeberg.org/librewolf/bsys6/archive/154.0.1-3.tar.gz",
         "zipball_url":"https://codeberg.org/librewolf/bsys6/archive/154.0.1-3.zip",
         "assets":[
           {"browser_download_url":"https://dl.librewolf.net/librewolf/154.0.1-3/librewolf-154.0.1-3-macos-arm64-package.dmg"}]}
        """#
    #expect(RecipeSanity.firstArtifactURL(in: releaseJSON)
        == "https://dl.librewolf.net/librewolf/154.0.1-3/librewolf-154.0.1-3-macos-arm64-package.dmg")

    // Nothing but source archives means nothing to report.
    #expect(RecipeSanity.firstArtifactURL(
        in: #"{"tarball_url":"https://codeberg.org/o/r/archive/1.0.tar.gz"}"#) == nil)
}

/// The match must stop at a quote. Without that it runs out of one JSON string
/// and through the following keys, and the "artifact URL" in the note becomes
/// hundreds of characters of unrelated feed.
@Test func anArtifactMatchStopsAtTheEndOfItsOwnJSONString() {
    let body = #"{"a":"https://example.com/App.dmg","b":"https://example.com/other.zip"}"#
    #expect(RecipeSanity.firstArtifactURL(in: body) == "https://example.com/App.dmg")
}

/// A detached signature sits beside every build in most feeds, and the match is
/// lazy, so without a boundary after the extension `App-1.0.dmg.sig` yields
/// `App-1.0.dmg` — a URL invented by truncation rather than read from the body.
@Test func aDetachedSignatureDoesNotBecomeAnInventedArtifactURL() {
    #expect(RecipeSanity.firstArtifactURL(
        in: "https://dl.example.com/App-1.0.dmg.sig") == nil)
    #expect(RecipeSanity.firstArtifactURL(
        in: "https://dl.example.com/App-1.0.dmg.sha256sum") == nil)
    // The real artifact still reads, with or without a query.
    #expect(RecipeSanity.firstArtifactURL(in: "https://dl.example.com/App-1.0.dmg")
        == "https://dl.example.com/App-1.0.dmg")
    #expect(RecipeSanity.firstArtifactURL(in: "https://dl.example.com/App.zip?token=1 x")
        == "https://dl.example.com/App.zip?token=1")
    #expect(RecipeSanity.firstArtifactURL(in: "https://dl.example.com/App-1.0.tar.gz")
        == "https://dl.example.com/App-1.0.tar.gz")
}
