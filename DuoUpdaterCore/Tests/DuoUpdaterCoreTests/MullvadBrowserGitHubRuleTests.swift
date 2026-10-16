import Foundation
import Testing

@testable import DuoUpdaterCore

/// Mullvad Browser publishes stable and alpha out of one repository
/// (mullvad/mullvad-browser), under two bundle ids. Tags and asset names below
/// are verbatim from the release list (2026-10-16).
@Suite struct MullvadBrowserGitHubRuleTests {

    private func rule(_ bundleID: String) throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID })
    }

    /// Stable tags are bare versions, two-part ones included (`15.0`); alpha
    /// tags (`16.0a13`) must never read as stable.
    @Test func stableRuleTakesBareTagsOnly() throws {
        let rule = try rule("net.mullvad.mullvadbrowser")
        #expect(rule.channel == .stable)
        #expect(rule.usePrereleases == false)
        for tag in ["15.0.25", "15.0", "14.0", "12.5.6", "13.0.16"] {
            #expect(VendorProbeRecipe.extractVersion(
                from: tag, pattern: rule.versionPattern) == tag)
        }
        for tag in ["16.0a13", "15.0a4", "14.5a6"] {
            #expect(VendorProbeRecipe.extractVersion(
                from: tag, pattern: rule.versionPattern) == nil)
        }
    }

    /// The installed alpha reports `CFBundleShortVersionString` "16.0a13", the
    /// tag verbatim, so the `a<N>` stays in the extracted version.
    @Test func alphaRuleKeepsTheAlphaSuffixAndRefusesStableTags() throws {
        let rule = try rule("net.mullvad.mullvadbrowseralpha")
        #expect(rule.channel == .alpha)
        #expect(rule.usePrereleases == true)
        #expect(VendorProbeRecipe.extractVersion(
            from: "16.0a13", pattern: rule.versionPattern) == "16.0a13")
        #expect(VendorProbeRecipe.extractVersion(
            from: "15.0.25", pattern: rule.versionPattern) == nil)
    }

    /// Each release lists one macOS dmg beside Linux/Windows packages and
    /// signatures; only the dmg of the rule's own track matches.
    @Test func installPatternsPickOnlyTheirTracksDmg() throws {
        let stableAssets = [
            "mullvad-browser-15.0.25-1.x86_64.rpm", "mullvad-browser-linux-x86_64-15.0.25.tar.xz",
            "mullvad-browser-macos-15.0.25.dmg", "mullvad-browser-macos-15.0.25.dmg.asc",
            "mullvad-browser-windows-x86_64-15.0.25.exe", "mullvad-browser_15.0.25-1_amd64.deb",
            "sha256sums-signed-build.txt"]
        let alphaAssets = [
            "mullvad-browser-alpha-16.0a13-1.aarch64.rpm", "mullvad-browser-linux-aarch64-16.0a13.tar.xz",
            "mullvad-browser-macos-16.0a13.dmg", "mullvad-browser-macos-16.0a13.dmg.asc",
            "mullvad-browser-windows-x86_64-16.0a13.exe", "sha256sums-signed-build.txt"]
        let stable = try #require(try rule("net.mullvad.mullvadbrowser").installAssetPattern)
        let alpha = try #require(try rule("net.mullvad.mullvadbrowseralpha").installAssetPattern)
        func matches(_ pattern: String, _ names: [String]) -> [String] {
            names.filter { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        #expect(matches(stable, stableAssets) == ["mullvad-browser-macos-15.0.25.dmg"])
        #expect(matches(stable, alphaAssets).isEmpty)
        #expect(matches(alpha, alphaAssets) == ["mullvad-browser-macos-16.0a13.dmg"])
        #expect(matches(alpha, stableAssets).isEmpty)
    }
}
