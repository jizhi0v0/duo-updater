import Foundation
import Testing

@testable import DuoUpdaterCore

/// Cherry Studio's macOS ZIP must remain separate from Windows/Linux arm64,
/// Intel and CN artifacts. The current artifact set is pinned independently by
/// ElectronZIPMigrationTests; these cases attack edition and fallback guards.
@Suite struct CherryStudioGitHubRuleTests {

    private static let bundleID = "com.kangfenmao.CherryStudio"

    /// Required, so a renamed bundle id or a dropped rule fails loudly instead of
    /// leaving the suite vacuous.
    private static var rule: GitHubReleaseRule {
        get throws {
            let found = GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
            try #require(found.count == 1, "expected exactly one Cherry Studio rule")
            return found[0]
        }
    }

    /// What the source would install for a release carrying exactly `names` — on
    /// this Mac's architecture, the way `GitHubReleasesSource` asks.
    private func picked(_ names: [String]) throws -> String? {
        let pattern = try #require(try Self.rule.installAssetPattern)
        let assets = names.map {
            (name: $0, url: URL(string: "https://example.test/\($0)")!, size: Int64(1))
        }
        return GitHubReleaseRule.installableAsset(
            from: assets, matching: pattern, preferring: .arm64)?.url.lastPathComponent
    }

    @Test func theZIPSpellingResolvesAndLegacyDMGsDoNot() throws {
        #expect(try picked(["Cherry-Studio-2.2.2-mac-arm64.zip"]) == "Cherry-Studio-2.2.2-mac-arm64.zip")
        #expect(try picked(["Cherry-Studio-2.0.9-arm64.dmg"]) == nil)
        #expect(try picked(["Cherry-Studio-2.0.14-mac-arm64.dmg"]) == nil)
    }

    /// A release containing both containers selects the ZIP.
    @Test func theNewestReleasesAssetsStillResolve() throws {
        let live = [
            "Cherry-Studio-2.0.14-linux-arm64.deb",
            "Cherry-Studio-2.0.14-linux-x64.AppImage",
            "Cherry-Studio-2.0.14-mac-arm64.dmg",
            "Cherry-Studio-2.0.14-mac-arm64.zip",
            "Cherry-Studio-2.0.14-mac-arm64.zip.blockmap",
            "Cherry-Studio-2.0.14-mac-x64.dmg",
            "Cherry-Studio-2.0.14-win-arm64-setup.exe",
        ]
        #expect(try picked(live) == "Cherry-Studio-2.0.14-mac-arm64.zip")
    }

    /// Neither CN nor Intel may be offered to a global Apple Silicon copy.
    @Test func theChinaEditionAndTheIntelBuildAreNotInstallable() throws {
        #expect(try picked(["Cherry-Studio-CN-2.2.2-mac-arm64.zip"]) == nil)
        #expect(try picked(["Cherry-Studio-2.2.2-mac-x64.zip"]) == nil)
        #expect(try picked(["Cherry-Studio-CN-2.2.2-mac-arm64.zip",
                            "Cherry-Studio-2.2.2-mac-arm64.zip"])
            == "Cherry-Studio-2.2.2-mac-arm64.zip")
    }

    /// A release with only the DMG and Linux artifacts still has no selected ZIP.
    @Test func aReleaseWithoutAMacZIPIsStillAMiss() throws {
        #expect(try picked(["Cherry-Studio-2.2.2-mac-arm64.dmg",
                            "Cherry-Studio-2.2.2-linux-x64.AppImage"]) == nil)
    }
}
