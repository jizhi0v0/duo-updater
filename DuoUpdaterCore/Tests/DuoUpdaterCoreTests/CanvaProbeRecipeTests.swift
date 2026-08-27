import Testing
import Foundation
@testable import DuoUpdaterCore

/// Canva's electron-updater probe.
///
/// The recipe is looked up from the registry rather than restated here, and every
/// expectation is checked against two response bodies captured verbatim from the
/// vendor on 2026-08-27 — the stable feed the recipe reads, and the `-beta` feed
/// sitting on the same host that it must refuse to read anything out of.
struct CanvaProbeRecipeTests {

    private static let bundleID = "com.canva.CanvaDesktop"

    /// `https://desktop-release.canva.com/latest-mac.yml`, 2026-08-27. The dmg is
    /// listed three times by the vendor; kept as-is so first-match behaviour is
    /// exercised on the real shape.
    private static let stableBody = """
        version: 1.124.0
        files:
          - url: Canva-1.124.0-universal-mac.zip
            sha512: rf69D6q9ZBW6Vd7/oHXwPH6twOpVrOqz0yHdjABjszJLTVirvGFcsHx+iAqMU4mJph0Ju9fhWCAv1ku+AmEqbw==
            size: 220713510
          - url: Canva-1.124.0-universal.dmg
            sha512: XfyF0nxkrfpd7tQudevNMSPxDQ07YHywwSoK55hJ2aLydzVOU5VVcdtJWJt7n6/EMnV7fWV7BsJb3zW4S0epCg==
            size: 229528957
          - url: Canva-1.124.0-universal.dmg
            sha512: XfyF0nxkrfpd7tQudevNMSPxDQ07YHywwSoK55hJ2aLydzVOU5VVcdtJWJt7n6/EMnV7fWV7BsJb3zW4S0epCg==
            size: 229528957
        path: Canva-1.124.0-universal-mac.zip
        sha512: rf69D6q9ZBW6Vd7/oHXwPH6twOpVrOqz0yHdjABjszJLTVirvGFcsHx+iAqMU4mJph0Ju9fhWCAv1ku+AmEqbw==
        releaseDate: '2026-08-25T02:56:23.561Z'
        """

    /// `https://desktop-release.canva.com/beta-mac.yml`, same host, same day —
    /// still serving a build from November 2024.
    private static let betaBody = """
        version: 1.98.0-beta
        files:
          - url: Canva-1.98.0-beta-universal-mac.zip
            sha512: EPqtGRQlAsHsqHQtXzZWgOm1le5cS1GvjcVS8N6HfqlR1NRrPShbAiTUgc32uMjXCMz4yfVmgzKuL34oEabRsA==
            size: 181427293
          - url: Canva-1.98.0-beta-universal.dmg
            sha512: luJVZ/AvA+ldxSEutPW480OBGrySBRk9Gfkoj8XI06PskMgvNp+WRFrsKKGrLB5LrXTvEoZQFdC1In9IfwVG6A==
            size: 188813458
        path: Canva-1.98.0-beta-universal-mac.zip
        sha512: EPqtGRQlAsHsqHQtXzZWgOm1le5cS1GvjcVS8N6HfqlR1NRrPShbAiTUgc32uMjXCMz4yfVmgzKuL34oEabRsA==
        releaseDate: '2024-11-12T05:14:58.028Z'
        """

    /// `CFBundleShortVersionString` of the bundle inside
    /// `Canva-1.124.0-universal.dmg`, read off the mounted dmg.
    private static let installedShortVersion = "1.124.0"

    /// `CFBundleVersion` of that same bundle — deliberately unlike the marketing
    /// version, and absent from the feed.
    private static let installedBuildVersion = "3597652.392500792"

    private static let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }

    private enum RecipeShapeError: Error { case notARelativeBodyPattern(String) }

    /// The install spec's filename pattern and the base it resolves against.
    private static func installArtifact(
        _ recipe: VendorProbeRecipe
    ) throws -> (pattern: String, base: URL) {
        let spec = try #require(recipe.install)
        guard case .bodyPatternRelative(let pattern, let base) = spec.urlSource else {
            throw RecipeShapeError.notARelativeBodyPattern(recipe.recipeID)
        }
        return (pattern, base)
    }

    private static func theRecipe() throws -> VendorProbeRecipe {
        #expect(recipes.count == 1, "Canva should have exactly one recipe")
        return try #require(recipes.first)
    }

    // MARK: - registry shape

    /// One stable recipe, no channel and no variant. The beta feed is abandoned
    /// (see the registry comment), so growing a channel here would need its own
    /// evidence — and its own `ChannelProofRegistry` entry — rather than a copy
    /// of this one.
    @Test func canvaIsASingleStableRecipe() throws {
        let recipe = try Self.theRecipe()
        #expect(recipe.channel == .stable)
        #expect(recipe.variant == nil)
        #expect(recipe.hostRequirement == nil)  // the vendor ships one universal build
        #expect(recipe.identities.isEmpty && recipe.track == nil)
        if case .responseBody = recipe.mode {} else {
            Issue.record("\(recipe.recipeID) is not a body-parsing recipe")
        }
    }

    /// The endpoint is the one the app's own `app-update.yml` names, not a URL
    /// found by guessing at the host's layout.
    @Test func theProbeReadsTheAppsOwnUpdateFeed() throws {
        let recipe = try Self.theRecipe()
        #expect(recipe.url.absoluteString
            == "https://desktop-release.canva.com/latest-mac.yml")
        let (_, base) = try Self.installArtifact(recipe)
        #expect(base.host() == recipe.url.host(),
                "the installer must come off the same host the version was read from")
    }

    // MARK: - the version

    /// The feed's `version` is the marketing string the bundle reports, so an
    /// up-to-date install compares equal.
    @Test func theFeedVersionMatchesTheInstalledMarketingVersion() throws {
        let recipe = try Self.theRecipe()
        let version = try #require(
            VendorProbeRecipe.extractVersion(
                from: Self.stableBody, pattern: recipe.versionPattern))
        #expect(version == Self.installedShortVersion)
        #expect(VersionComparator.compare(version, Self.installedShortVersion)
            == .orderedSame,
            "an up-to-date Canva would be shown a phantom update")
    }

    /// `CFBundleVersion` is nothing like the feed's version, so routing this into
    /// the build field would compare `1.124.0` against `3597652.392500792` and
    /// report an update that can never be satisfied.
    @Test func theVersionIsMarketingNotBuild() throws {
        let recipe = try Self.theRecipe()
        #expect(!recipe.versionIsBuild)
        #expect(recipe.displayVersionPattern == nil)
        #expect(!Self.stableBody.contains(Self.installedBuildVersion))
    }

    /// The pattern reads the feed's own top-level `version:` line and not one of
    /// the version-shaped numbers scattered through the filenames and sizes.
    @Test func theVersionComesFromTheVersionLine() throws {
        let recipe = try Self.theRecipe()
        let body = """
            version: 2.0.1
            files:
              - url: Canva-9.9.9-universal.dmg
                size: 229528957
            """
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == "2.0.1")
    }

    // MARK: - the abandoned beta train

    /// The whole point of ending every pattern at a digits-and-dots run: fed the
    /// `-beta` feed, this recipe resolves NOTHING. Capturing `1.98.0` instead
    /// would report a two-year-old prerelease as the stable release — and read as
    /// a downgrade against 1.124.0, which no later check would clear.
    @Test func theBetaTrainIsRefusedRatherThanTruncated() throws {
        let recipe = try Self.theRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.betaBody, pattern: recipe.versionPattern) == nil,
            "the recipe read a version out of the beta feed")

        let (pattern, _) = try Self.installArtifact(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: Self.betaBody, pattern: pattern) == nil,
                "the recipe would install the beta dmg")

        let checksum = try #require(recipe.install?.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(from: Self.betaBody, pattern: checksum) == nil)
    }

    /// The same refusal stated on the axis that would actually bite: a `-beta`
    /// version published into the STABLE feed. "Unknown" is the correct outcome.
    @Test func aPrereleaseInTheStableFeedReadsAsUnknown() throws {
        let recipe = try Self.theRecipe()
        let body = Self.stableBody.replacingOccurrences(
            of: "version: 1.124.0", with: "version: 1.125.0-beta")
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == nil)
    }

    // MARK: - the install artifact

    /// The universal dmg, resolved against the feed's own directory. The vendor
    /// lists it three times identically, so first-match is unambiguous.
    @Test func theInstallResolvesTheUniversalDMG() throws {
        let recipe = try Self.theRecipe()
        let (pattern, base) = try Self.installArtifact(recipe)
        let filename = try #require(
            VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: pattern))
        #expect(filename == "Canva-1.124.0-universal.dmg")
        // Resolved the way `VendorProbeSource.resolveInstall` resolves it —
        // `relativeTo:` then `.absoluteURL` — so a change to that joining rule
        // shows up here rather than only in production.
        #expect(URL(string: filename, relativeTo: base)?.absoluteURL.absoluteString
            == "https://desktop-release.canva.com/Canva-1.124.0-universal.dmg")
        #expect(recipe.install?.kind == .dmg)
    }

    /// The mac zip is listed FIRST in the feed and is what electron-updater itself
    /// consumes; the pattern must skip past it to the dmg the spec declares.
    /// Resolving the zip while declaring `.dmg` would hand `ArchiveExtractor` a
    /// file it would try to mount.
    ///
    /// Asserted against a body holding ONLY zips, so it is the pattern under
    /// test and not the fixture's ordering: on the real feed the dmg happens to
    /// be where first-match lands, which a loosened pattern would still satisfy.
    @Test func theZipEntryIsNotMistakenForTheDMG() throws {
        let recipe = try Self.theRecipe()
        let (pattern, _) = try Self.installArtifact(recipe)
        let zipsOnly = """
            version: 1.124.0
            files:
              - url: Canva-1.124.0-universal-mac.zip
                size: 220713510
            path: Canva-1.124.0-universal-mac.zip
            """
        #expect(VendorProbeRecipe.extractVersion(from: zipsOnly, pattern: pattern) == nil,
                "the pattern accepted a zip while the spec declares .dmg")
        #expect(recipe.install?.kind == .dmg)
    }

    /// The checksum is the dmg's, not the zip's — the two sit in the same document
    /// and the zip's is quoted twice, including on the trailing top-level `sha512`
    /// line. Verifying the zip's digest against downloaded dmg bytes would abort
    /// every install.
    @Test func theChecksumBelongsToTheDMGAndNotTheZip() throws {
        let recipe = try Self.theRecipe()
        let pattern = try #require(recipe.install?.checksumPattern)
        let digest = try #require(
            VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: pattern))
        // Captured from the real dmg: `shasum -a 512` over
        // Canva-1.124.0-universal.dmg, base64-encoded, equals the feed's value.
        #expect(digest
            == "XfyF0nxkrfpd7tQudevNMSPxDQ07YHywwSoK55hJ2aLydzVOU5VVcdtJWJt7n6/EMnV7fWV7BsJb3zW4S0epCg==")
        #expect(digest != "rf69D6q9ZBW6Vd7/oHXwPH6twOpVrOqz0yHdjABjszJLTVirvGFcsHx+iAqMU4mJph0Ju9fhWCAv1ku+AmEqbw==",
                "that is the zip's digest")
        #expect(Data(base64Encoded: digest)?.count == 64, "not a 512-bit digest")
    }

    // MARK: - the publish date

    /// electron-builder writes `releaseDate` in single-quoted ISO8601 with
    /// fractional seconds, which is what lets the Release Log place this release
    /// exactly instead of inside an estimated window.
    @Test func theReleaseDateParses() throws {
        let recipe = try Self.theRecipe()
        let pattern = try #require(recipe.publishedAtPattern)
        let raw = try #require(
            VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: pattern))
        #expect(raw == "2026-08-25T02:56:23.561Z")
        let date = try #require(ReleaseDate.parse(raw), "'\(raw)' did not parse")
        #expect(date > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(date < Date(timeIntervalSince1970: 2_000_000_000))
    }

    // MARK: - where the user is sent

    /// The endpoint is a yml manifest, so the manual-download link must not fall
    /// back to it. No changelog is registered at all — Canva publishes no desktop
    /// release notes, and the canva.dev changelogs are a different product.
    @Test func theUserIsSentToTheDownloadPageAndNowhereElse() throws {
        let recipe = try Self.theRecipe()
        let download = try #require(recipe.downloadURL)
        #expect(download != recipe.url)
        #expect(!download.absoluteString.hasSuffix(".yml"))
        #expect(download.host() != recipe.url.host(),
                "the manual link must be a page a user can read, not the release CDN")
        #expect(recipe.changelogURL == nil)
    }
}
