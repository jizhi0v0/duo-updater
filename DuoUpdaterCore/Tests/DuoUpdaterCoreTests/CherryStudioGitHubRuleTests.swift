import Foundation
import Testing

@testable import DuoUpdaterCore

/// `com.kangfenmao.CherryStudio` publishes one release carrying every platform, so
/// the install pattern has to pick the Apple-silicon dmg out of a list that also
/// holds Linux and Windows arm64 artifacts, the Intel dmg, the update zip and the
/// China edition.
///
/// v2.0.10 renamed the macOS artifacts from `Cherry-Studio-<ver>-arm64.dmg` to
/// `Cherry-Studio-<ver>-mac-arm64.dmg`. The pattern admitted only the old
/// spelling, so from that release on it matched nothing — and the walk back past
/// asset-less releases, bounded at five
/// (`GitHubReleasesSource.maxReleasesWithoutMacOSAsset`), then answered **2.0.9**
/// for a repository whose newest release was 2.0.14, offering the 2.0.9 dmg as the
/// one-click while every copy on 2.0.10–2.0.13 read "up to date". The asset names
/// below are the live ones (release list read 2026-09-17); `verify/baseline.json`
/// was recording the same `2.0.9`.
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

    /// Both spellings, so a release published before the rename still installs.
    @Test func bothMacOSSpellingsResolve() throws {
        #expect(try picked(["Cherry-Studio-2.0.9-arm64.dmg"]) == "Cherry-Studio-2.0.9-arm64.dmg")
        #expect(try picked(["Cherry-Studio-2.0.14-mac-arm64.dmg"])
            == "Cherry-Studio-2.0.14-mac-arm64.dmg")
    }

    /// The rename is the whole bug: the newest release's own asset list, as the
    /// live API returns it, must yield the Apple-silicon dmg rather than nothing.
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
        #expect(try picked(live) == "Cherry-Studio-2.0.14-mac-arm64.dmg")
    }

    /// The CN edition is a different build for a different store, and the Intel
    /// dmg is the wrong architecture: neither may be offered to a global install.
    @Test func theChinaEditionAndTheIntelBuildAreNotInstallable() throws {
        #expect(try picked(["Cherry-Studio-CN-2.0.14-mac-arm64.dmg"]) == nil)
        #expect(try picked(["Cherry-Studio-2.0.14-mac-x64.dmg"]) == nil)
        // With both spellings present, the global Apple-silicon dmg wins.
        #expect(try picked(["Cherry-Studio-CN-2.0.14-mac-arm64.dmg",
                            "Cherry-Studio-2.0.14-mac-arm64.dmg"])
            == "Cherry-Studio-2.0.14-mac-arm64.dmg")
    }

    /// No dmg at all is still a miss, so the source falls through to its
    /// asset-less walk instead of inventing an installer out of a zip.
    @Test func aReleaseWithoutAMacDmgIsStillAMiss() throws {
        #expect(try picked(["Cherry-Studio-2.0.14-mac-arm64.zip",
                            "Cherry-Studio-2.0.14-linux-x64.AppImage"]) == nil)
    }
}
