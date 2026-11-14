import Foundation
import Testing
@testable import DuoUpdaterCore

/// The stable v3 manifest's version and zip entries, fetched 2026-11-14.
/// x64 comes first: its digest must not be used for the arm64 installer.
private let mstyV3Manifest = #"""
version: 3.0.0
files:
  - url: MstyStudio_x64.zip
    sha512: S1Ve9NzLar/LXSwdRPNZdYz/d16nbvRtIX1Kv49nxr/RzpWZAfcQZpuU4cjK+/TRecf2d+1H9611GuIu4qyk/Q==
    size: 255140873
  - url: MstyStudio_arm64.zip
    sha512: 6aGLTaC/6Lq1qLAXvL6Bx2UHaQXWfRcyvU2dhXfikh46sV4Sm3sWVtYKdZ2U1p2JLaZ561sJ95VvWX2fO65HMA==
    size: 247420514
releaseDate: '2026-11-05T01:34:33.588Z'
"""#

@Suite struct MstyProbeRecipeTests {
    @Test func stableVersionInstallerAndDigestAllFollowTheV3Directory() throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "MstyStudio" })
        #expect(VendorProbeRecipe.extractVersion(from: mstyV3Manifest, pattern: recipe.versionPattern) == "3.0.0")
        #expect(recipe.url.absoluteString == "https://next-assets.msty.studio/app/latest/v3/mac/latest-mac.yml")
        let spec = try #require(recipe.install)
        guard case .fixed(let url) = spec.urlSource else {
            Issue.record("expected Msty Studio's fixed-name zip"); return
        }
        #expect(spec.kind == .zip)
        #expect(url.deletingLastPathComponent() == recipe.url.deletingLastPathComponent())
        #expect(url.lastPathComponent == "MstyStudio_arm64.zip")
        let pattern = try #require(spec.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(from: mstyV3Manifest, pattern: pattern)
            == "6aGLTaC/6Lq1qLAXvL6Bx2UHaQXWfRcyvU2dhXfikh46sV4Sm3sWVtYKdZ2U1p2JLaZ561sJ95VvWX2fO65HMA==")
    }
}
