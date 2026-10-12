import Foundation
import Testing

@testable import DuoUpdaterCore

/// disktree (`Recipes/io-github-tobi-disktree.swift`): ad-hoc signed, so it
/// installs only on the published-digest route. Each release ships Linux,
/// Windows and macOS builds for both arches, each with a `.sha256` sidecar, and
/// the rule has to land on the macOS zip of the host's arch.
@Suite struct DisktreeGitHubRuleTests {

    private static func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
        names.map { name in
            (name, URL(string: "https://github.com/tobi/disktree/releases/download/v0/\(name)")!, nil)
        }
    }

    /// v0.11.0's asset list as GitHub served it.
    private static let v0_11_0 = assets([
        "disktree-0.11.0-aarch64-linux.tar.gz",
        "disktree-0.11.0-aarch64-linux.tar.gz.sha256",
        "disktree-0.11.0-aarch64-macos.zip",
        "disktree-0.11.0-aarch64-macos.zip.sha256",
        "disktree-0.11.0-aarch64-windows.zip",
        "disktree-0.11.0-aarch64-windows.zip.sha256",
        "disktree-0.11.0-x86_64-linux.tar.gz",
        "disktree-0.11.0-x86_64-linux.tar.gz.sha256",
        "disktree-0.11.0-x86_64-macos.zip",
        "disktree-0.11.0-x86_64-macos.zip.sha256",
        "disktree-0.11.0-x86_64-windows.zip",
        "disktree-0.11.0-x86_64-windows.zip.sha256",
    ])

    /// v0.9.1, a Linux-only release.
    private static let v0_9_1 = assets([
        "disktree-0.9.1-x86_64-linux.tar.gz",
        "disktree-0.9.1-x86_64-linux.tar.gz.sha256",
    ])

    private static func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "io.github.tobi.disktree" })
    }

    @Test func ruleReadsTheBareTagOnTheDigestRoute() throws {
        let rule = try Self.rule()
        #expect(rule.owner == "tobi" && rule.repo == "disktree")
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .zip)
        #expect(rule.installTrust == .publishedDigestOnly)
        #expect(VendorProbeRecipe.extractVersion(from: "v0.11.0", pattern: rule.versionPattern) == "0.11.0")
        #expect(VendorProbeRecipe.extractVersion(from: "v0.12.0-rc.1", pattern: rule.versionPattern) == nil)
    }

    @Test func eachArchGetsItsOwnMacZip() throws {
        let pattern = try #require(try Self.rule().installAssetPattern)
        let arm = GitHubReleaseRule.installableAsset(
            from: Self.v0_11_0, matching: pattern, preferring: .arm64, allowingIntelTranslation: true)
        let intel = GitHubReleaseRule.installableAsset(
            from: Self.v0_11_0, matching: pattern, preferring: .x86_64, allowingIntelTranslation: false)
        #expect(arm?.url.lastPathComponent == "disktree-0.11.0-aarch64-macos.zip")
        #expect(intel?.url.lastPathComponent == "disktree-0.11.0-x86_64-macos.zip")
    }

    @Test func onlyTheMacZipsMatch() throws {
        let pattern = try #require(try Self.rule().installAssetPattern)
        let matched = Self.v0_11_0.map(\.name).filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matched == ["disktree-0.11.0-aarch64-macos.zip", "disktree-0.11.0-x86_64-macos.zip"])
    }

    /// A release without a macOS zip is not this app's release: the source walks
    /// past it instead of offering a version one-click cannot install.
    @Test func linuxOnlyReleaseCarriesNoInstallableAsset() throws {
        let pattern = try #require(try Self.rule().installAssetPattern)
        #expect(!GitHubReleaseRule.carriesInstallableAsset(from: Self.v0_9_1, matching: pattern))
        #expect(GitHubReleaseRule.carriesInstallableAsset(from: Self.v0_11_0, matching: pattern))
    }
}
