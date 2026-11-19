import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite struct Top50BatchRuleTests {
    private func rule(_ bundleID: String) throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID })
    }

    @Test func hiddenBarUsesTheCanonicalRepositoryForLegacyCopies() throws {
        let rule = try self.rule("com.dwarvesv.minimalbar")
        #expect(rule.owner == "consolelabs")
        #expect(rule.repo == "hidden")
        #expect(VendorProbeRecipe.extractVersion(from: "v1.10", pattern: rule.versionPattern)
            == "1.10")
        #expect(rule.installerKind == .zip)
    }

    @Test func hiddenBarAssetPatternMatchesOnlyTheMacZip() throws {
        let pattern = try #require(try rule("com.dwarvesv.minimalbar").installAssetPattern)
        let assets = ["appcast.xml", "Hidden-Bar-macos.zip", "Hidden-Bar-v1.13.1-macos.zip",
                      "Source code (zip)", "hidden-1.13.1.tar.gz"]
        let matched = assets.filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matched == ["Hidden-Bar-v1.13.1-macos.zip"])
    }

    /// XQuartz installs a whole X11 stack (`/opt/X11`, launchd jobs), not just an
    /// app bundle, so it must stay on the pkg route — an in-place bundle swap
    /// would leave everything except `XQuartz.app` at the old version.
    @Test func xquartzUsesThePackageRoute() throws {
        let rule = try self.rule("org.xquartz.X11")
        #expect(rule.installerKind == .pkg)
        #expect(VendorProbeRecipe.extractVersion(
            from: "XQuartz-2.8.6", pattern: rule.versionPattern) == "2.8.6")
    }

    /// The 2.8.6 release carries the pkg plus dSYMs and two checksum files per
    /// artifact. Only the pkg may ever be handed to the installer.
    @Test func xquartzAssetPatternRejectsTheSiblings() throws {
        let pattern = try #require(try rule("org.xquartz.X11").installAssetPattern)
        let assets = [
            "XQuartz-2.8.6.dSYMS.tar.bz2", "XQuartz-2.8.6.dSYMS.tar.bz2.sha256sum",
            "XQuartz-2.8.6.pkg", "XQuartz-2.8.6.pkg.sha256sum", "XQuartz-2.8.6.pkg.sha512sum",
        ]
        let matched = assets.filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matched == ["XQuartz-2.8.6.pkg"])
    }
}
