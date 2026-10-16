import Foundation
import Testing

@testable import DuoUpdaterCore

/// The update service's answer to
/// `www.stremio.com/updater/check?product=stremio-shell-macos&arch=arm64`,
/// fetched 2026-10-16, verbatim.
private let stremioCheckBody = #"""
{"versionDesc":"https://dl.strem.io/stremio-shell-macos/[versions]/v5.1.28_arm64.json?from=website&init=1488695","version":"5.1.28"}
"""#

@Test func stremioReadsTheUpdaterVersionAndBuildsTheArmDmg() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.westbridge.stremio5-mac" })
    #expect(VendorProbeRecipe.extractVersion(
        from: stremioCheckBody, pattern: recipe.versionPattern) == "5.1.28")
    // The `5.1.28` inside the descriptor URL must not be what is read: the
    // pattern binds to the `version` key, whatever the key order.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"version":"5.1.29","versionDesc":"https://dl.strem.io/x/v5.1.28_arm64.json"}"#,
        pattern: recipe.versionPattern) == "5.1.29")
    // Every version shape the vendor has published, and the next major.
    for v in ["5.1.14", "5.1.16", "5.1.26", "5.1.28", "6.0.0", "5.2"] {
        #expect(VendorProbeRecipe.extractVersion(
            from: #"{"version":"\#(v)"}"#, pattern: recipe.versionPattern) == v)
    }
    // A suffixed build is not read as the stable number.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"version":"5.1.29-rc.1"}"#, pattern: recipe.versionPattern) == nil)
    // The service's error envelope.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"error":"unknown product"}"#, pattern: recipe.versionPattern) == nil)

    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case .versionTemplate(let template) = install.urlSource else {
        Issue.record("expected a versionTemplate install source")
        return
    }
    #expect(template == "https://dl.strem.io/stremio-shell-macos/v{version}/Stremio_arm64.dmg")
}

@Test func stremioOldBundleIDIsDetectionOnly() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.stremio.stremio-shell-macos" })
    // Ad-hoc signed, no Team ID: nothing for the install gate to match.
    #expect(recipe.install == nil)
    #expect(VendorProbeRecipe.extractVersion(
        from: stremioCheckBody, pattern: recipe.versionPattern) == "5.1.28")
}
