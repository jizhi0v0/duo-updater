import Foundation
import Testing
@testable import DuoUpdaterCore

struct DisktreeNSHRecipeTests {
    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first {
            $0.bundleID == "com.huacnlee.disktree"
        })
    }

    @Test func theIndependentProductUsesItsOwnReleaseRepository() throws {
        let nsh = try rule()
        let gpui = try #require(GitHubReleaseRegistry.rules.first {
            $0.bundleID == "io.github.tobi.disktree"
        })
        #expect(nsh.owner == "huacnlee")
        #expect(nsh.repo == "disktree")
        #expect(nsh.channel == .stable)
        #expect(gpui.owner == "tobi")
        #expect(BundleIDMigration.recipeBundleID(
            for: nsh.bundleID, installedVersion: "0.1.7") == nsh.bundleID)
        #expect(BundleIDMigration.recipeBundleID(
            for: gpui.bundleID, installedVersion: "0.11.0") == gpui.bundleID)
    }

    @Test func tagsUseTheAppsVersionAndRejectOtherChannels() throws {
        let rule = try rule()
        #expect(VendorProbeRecipe.extractVersion(from: "v0.1.8", pattern: rule.versionPattern) == "0.1.8")
        for other in ["v0.1.8-beta.1", "v0.1.8-nightly.1", "v0.1.8-preview.1"] {
            #expect(VendorProbeRecipe.extractVersion(from: other, pattern: rule.versionPattern) == nil)
        }
    }

    @Test func onlyTheNormalAppleSiliconArchiveIsInstallable() throws {
        let rule = try rule()
        let pattern = try #require(rule.installAssetPattern)
        #expect(rule.installerKind == .tarGz)
        #expect(rule.installTrust == .publishedDigestOnly)
        #expect("disktree-v0.1.8-aarch64-apple-darwin.tar.gz".range(
            of: pattern, options: .regularExpression) != nil)
        for other in [
            "disktree-v0.1.8-aarch64-apple-darwin-updater.tar.gz",
            "disktree-v0.1.8-x86_64-apple-darwin.tar.gz",
            "disktree-v0.1.8-x86_64-unknown-linux-gnu.tar.gz",
            "disktree-v0.1.8-aarch64-apple-darwin.tar.gz.sha256",
            "disktree-0.11.0-aarch64-macos.zip",
        ] {
            #expect(other.range(of: pattern, options: .regularExpression) == nil)
        }
    }
}
