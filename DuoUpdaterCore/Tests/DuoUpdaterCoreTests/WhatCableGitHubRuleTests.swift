import Foundation
import Testing

@testable import DuoUpdaterCore

/// WhatCable publishes its stable and beta trains out of one repository, under
/// one asset name, with the same bundle id and the same app name. The only thing
/// that tells the two apart after the fact is the tag in the download path — so
/// these tests are mostly about the seams that keeps intact.
@Suite struct WhatCableGitHubRuleTests {

    private static let bundleID = "uk.whatcable.whatcable"

    /// Every asset on a real WhatCable release: the app zip and the standalone
    /// CLI zip, nothing else. Names taken verbatim off v1.4.0 and v1.5.0-beta.8
    /// (2026-09-06).
    private func assets(tag: String, cliVersion: String)
        -> [(name: String, url: URL, size: Int64?)] {
        ["WhatCable.zip", "whatcable-cli-\(cliVersion).zip"].map { name in
            (name,
             URL(string: "https://github.com/darrylmorley/whatcable/releases/download/\(tag)/\(name)")!,
             Int64(17_166_182))
        }
    }

    private func rule(_ channel: ReleaseChannel) throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first {
            $0.bundleID == Self.bundleID && $0.channel == channel
        })
    }

    // MARK: - Which release each rule accepts

    /// The stable rule reads `/releases/latest`, which GitHub never answers with a
    /// prerelease — but the pattern is anchored anyway, because the list fallback
    /// (a release with no macOS asset) walks raw tags.
    @Test func stableRuleTakesPlainTagsAndRefusesBetaOnes() throws {
        let rule = try rule(.stable)
        #expect(rule.usePrereleases == false)
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.4.0", pattern: rule.versionPattern) == "1.4.0")
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.5.0-beta.8", pattern: rule.versionPattern) == nil)
    }

    /// The beta rule keeps the `-beta.<N>` suffix in the extracted version,
    /// because the installed bundle keeps it too: a real v1.5.0-beta.8 build
    /// reports `CFBundleShortVersionString` "1.5.0-beta.8". Truncating to "1.5.0"
    /// would read every beta as newer than itself.
    @Test func betaRuleKeepsTheSuffixTheBundleAlsoCarries() throws {
        let rule = try rule(.beta)
        #expect(rule.usePrereleases == true)
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.5.0-beta.8", pattern: rule.versionPattern) == "1.5.0-beta.8")
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.4.0", pattern: rule.versionPattern) == nil)
    }

    /// The reason the beta rule has to exist at all: a beta build detects as
    /// `.beta`, so the stable rule's channel gate refuses it. Without a `.beta`
    /// rule such an install would have no source and read "Failed" forever.
    @Test func aBetaBuildDetectsAsBetaAndSoNeedsItsOwnRule() {
        #expect(ReleaseChannel.detect(
            name: "WhatCable", bundleID: Self.bundleID, keystoneChannel: nil,
            version: "1.5.0-beta.8") == .beta)
        #expect(ReleaseChannel.detect(
            name: "WhatCable", bundleID: Self.bundleID, keystoneChannel: nil,
            version: "1.4.0") == .stable)
    }

    /// Ordering the two trains share one scale: a graduated stable outranks the
    /// betas it came from, and `beta.10` outranks `beta.9` numerically rather
    /// than lexically. Neither rule offers across the boundary today, but the
    /// comparison is what a future loosening would rest on.
    @Test func stableOutranksItsOwnBetasAndBetasOrderNumerically() {
        #expect(VersionComparator.isNewer("1.5.0", than: "1.5.0-beta.8"))
        #expect(VersionComparator.isNewer("1.5.0-beta.10", than: "1.5.0-beta.9"))
        #expect(VersionComparator.isNewer("1.5.0-beta.1", than: "1.4.0"))
    }

    // MARK: - Which asset each rule installs

    /// `WhatCable.zip` and nothing else. The CLI zip beside it is a different
    /// artifact — the app bundle ships its own copy internally — and it is the
    /// only decoy a WhatCable release has ever contained.
    @Test func bothRulesInstallTheAppZipAndNotTheCLIZip() throws {
        for channel in [ReleaseChannel.stable, .beta] {
            let rule = try rule(channel)
            let pattern = try #require(rule.installAssetPattern)
            #expect(rule.installerKind == .zip)
            let tag = channel == .stable ? "v1.4.0" : "v1.5.0-beta.8"
            let cli = channel == .stable ? "1.4.0" : "1.5.0-beta.8"
            let asset = GitHubReleaseRule.installableAsset(
                from: assets(tag: tag, cliVersion: cli), matching: pattern)
            #expect(asset?.url.lastPathComponent == "WhatCable.zip")
            #expect(asset?.url.absoluteString.contains("/download/\(tag)/") == true)
        }
    }

    // MARK: - The channel proof

    /// The registered proof has to pass on the beta rule's own artifact and fail
    /// on stable's. Both are `WhatCable.zip`; the tag segment is the whole of the
    /// difference, which is exactly why the proof is anchored there.
    @Test func theChannelProofSeparatesTheTwoTrainsByTagSegment() throws {
        let key = ChannelProofKey(Self.bundleID, .beta)
        let proof = try #require(ChannelProofRegistry.githubProofs[key])
        guard case .artifact(let pattern) = proof else {
            Issue.record("expected an artifact proof"); return
        }
        let beta = "https://github.com/darrylmorley/whatcable/releases/download/v1.5.0-beta.8/WhatCable.zip"
        let stable = "https://github.com/darrylmorley/whatcable/releases/download/v1.4.0/WhatCable.zip"
        #expect(beta.range(of: pattern, options: .regularExpression) != nil)
        #expect(stable.range(of: pattern, options: .regularExpression) == nil)
    }
}
