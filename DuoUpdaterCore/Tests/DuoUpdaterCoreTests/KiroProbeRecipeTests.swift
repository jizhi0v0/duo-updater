import Testing
import Foundation
@testable import DuoUpdaterCore

/// Kiro's update metadata, captured verbatim on 2026-08-16 (the whole file is
/// 323 bytes). Note the filename already scopes it to one architecture, so
/// nothing here has to be filtered.
private let kiroMetadataFixture = #"""
{"currentRelease":"1.0.309","releases":[{"version":"1.0.309","updateTo":{"version":"1.0.309","pub_date":"2026-08-13","notes":"Kiro-darwin-arm64-1.0.309","name":"Kiro-darwin-arm64-1.0.309","url":"https://prod.download.desktop.kiro.dev/releases/stable/darwin-arm64/signed/1.0.309/kiro-ide-1.0.309-stable-darwin-arm64.zip"}}]}
"""#

/// The download page this recipe used first, trimmed to its two links — kept so
/// the reason for moving off it stays visible: one version, two architectures.
private let kiroDownloadPageFixture = #"""
<a href="https://prod.download.desktop.kiro.dev/releases/stable/darwin-arm64/signed/1.0.309/kiro-ide-1.0.309-stable-darwin-arm64.dmg">Apple silicon</a>
<a href="https://prod.download.desktop.kiro.dev/releases/stable/darwin-x64/signed/1.0.309/kiro-ide-1.0.309-stable-darwin-x64.dmg">Intel</a>
"""#

struct KiroProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "dev.kiro.desktop" }
    }

    @Test func readsCurrentReleaseFromTheMetadata() throws {
        let recipe = try #require(recipe)
        #expect(recipe.url.absoluteString.hasSuffix("metadata-darwin-arm64-stable.json"))
        #expect(VendorProbeRecipe.extractVersion(
            from: kiroMetadataFixture, pattern: recipe.versionPattern) == "1.0.309")
    }

    @Test func installsTheArtifactTheMetadataNames() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: kiroMetadataFixture, pattern: pattern)
            == "https://prod.download.desktop.kiro.dev/releases/stable/darwin-arm64/"
            + "signed/1.0.309/kiro-ide-1.0.309-stable-darwin-arm64.zip")
        #expect(spec.kind == .zip)
    }

    /// Why the metadata replaced the page: there, the same release appears once
    /// per architecture, so a version read had to name the architecture itself and
    /// trust the markup. The metadata is already per-architecture by filename —
    /// and the page's Intel link no longer satisfies either pattern.
    @Test func noLongerDependsOnTheTwoArchitectureDownloadPage() throws {
        let recipe = try #require(recipe)
        #expect(kiroDownloadPageFixture.contains("darwin-x64"))
        #expect(VendorProbeRecipe.extractVersion(
            from: kiroDownloadPageFixture, pattern: recipe.versionPattern) == nil)
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else { return }
        #expect(VendorProbeRecipe.extractVersion(
            from: kiroDownloadPageFixture, pattern: pattern) == nil)
    }
}
