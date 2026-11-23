import Foundation
import Testing
@testable import DuoUpdaterCore

struct MulticaTrinaCoverageTests {
    @Test(arguments: [
        ("ai.multica.desktop", "multica-ai/multica", "v0.11.1", "multica-desktop-0.11.1-mac-arm64.dmg", [
            "multica-cli-0.11.1-darwin-arm64.tar.gz", "multica_darwin_arm64.tar.gz",
            "multica-desktop-0.11.1-mac-x64.dmg", "multica-desktop-0.11.1-mac-arm64.zip",
            "multica-desktop-0.11.1-mac-arm64.dmg.blockmap",
        ]),
        ("com.treesoop.mycel", "trina-app/trina-ax", "v0.14.0", "Trina-AX-0.14.0-mac-universal.dmg", [
            "TrinaAX-office-0.14.0-mac.zip", "TrinaAX-server-0.14.0-linux-arm64.tar.gz",
            "Trina-AX-0.14.0-mac-universal.zip", "Trina-AX-Setup-0.14.0-win-x64.exe",
        ]),
    ])
    func onlyTheStableDesktopAssetIsEligible(
        bundleID: String, slug: String, tag: String, installer: String, siblings: [String]
    ) throws {
        let rule = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID })
        let pattern = try #require(rule.installAssetPattern)
        #expect(rule.slug == slug)
        #expect(rule.installerKind == .dmg)
        #expect(rule.installTrust == .developerID)
        #expect(rule.channel == .stable)
        #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern) == String(tag.dropFirst()))
        for unrelatedTag in [tag + "-beta.1", tag + "-dev.1", "android-v1.0.9"] {
            #expect(VendorProbeRecipe.extractVersion(from: unrelatedTag, pattern: rule.versionPattern) == nil)
        }

        func asset(_ name: String) -> (name: String, url: URL, size: Int64?) {
            (name, URL(string: "https://example.invalid/\(name)")!, nil)
        }
        let siblingAssets = siblings.map(asset)
        #expect(!GitHubReleaseRule.carriesInstallableAsset(from: siblingAssets, matching: pattern))
        let selected = GitHubReleaseRule.installableAsset(
            from: siblingAssets + [asset(installer)], matching: pattern, preferring: .arm64)
        #expect(selected?.url.lastPathComponent == installer)
    }

    @Test func theOriginalMulticaRequiresRewriteConfirmation() {
        let oldID = "com.multica.app"
        let newID = "ai.multica.desktop"
        #expect(BundleIDMigration.recipeBundleID(for: oldID, installedVersion: "0.1.7") == newID)
        #expect(BundleIDMigration.rewrite(installed: oldID, installedVersion: "0.1.7")?.isRewrite == true)
        #expect(BundleIDMigration.recipeBundleID(for: oldID, installedVersion: "0.2.10") == oldID)
        #expect(BundleIDMigration.migration(
            installed: oldID, downloaded: newID, installedVersion: "0.1.7",
            installedTeam: "Q85ULLN279", downloadedTeam: "Q85ULLN279") != nil)
        #expect(BundleIDMigration.migration(
            installed: oldID, downloaded: newID, installedVersion: "0.1.7",
            installedTeam: "OTHERTEAM1", downloadedTeam: "Q85ULLN279") == nil)
    }

    @Test func trinaStoreBundleHasNoGitHubRule() {
        #expect(!GitHubReleaseRegistry.rules.contains { $0.bundleID == "app.trina.ax" })
    }
}
