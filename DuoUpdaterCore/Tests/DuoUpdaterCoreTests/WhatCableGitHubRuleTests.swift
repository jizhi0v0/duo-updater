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
    }

    /// The beta rule ALSO accepts plain stable tags, and that is deliberate — it
    /// is how a copy on `1.5.0-beta.8` is offered the `1.5.0` that graduates from
    /// it, which is what the vendor's own updater does ("a stable always
    /// supersedes its own betas"). An anchored `-beta.`-only pattern would strand
    /// such a copy until the next cycle opened, and would match nothing at all on
    /// the day the vendor pauses the beta train — a red sweep on every machine
    /// for a rule that is working.
    @Test func betaRuleAlsoAcceptsTheStableTagItsBetasGraduateInto() throws {
        let rule = try rule(.beta)
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.5.0", pattern: rule.versionPattern) == "1.5.0")
        // Still anchored: neither a foreign prerelease shape nor a bare tag.
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.5.0-rc.1", pattern: rule.versionPattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: "whatcable-cli-1.5.0", pattern: rule.versionPattern) == nil)
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
    /// than lexically. This is what the beta rule accepting stable tags rests on —
    /// without it, offering `1.5.0` to a `1.5.0-beta.8` copy would be a downgrade
    /// the comparator refused.
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

    /// The proof is a `.recipeAnchor` on `usePrereleases`, not an `.artifact`
    /// one, and the artifact is why: both trains publish one file under one name,
    /// so the tag segment is the only discriminator — and this rule is allowed to
    /// resolve a stable tag on purpose. An artifact proof would therefore fire on
    /// a legitimate resolution. What is left to anchor is the request.
    @Test func theChannelProofAnchorsTheRequestBecauseTheArtifactCannot() throws {
        let key = ChannelProofKey(Self.bundleID, .beta)
        let proof = try #require(ChannelProofRegistry.githubProofs[key])
        guard case .recipeAnchor(let pattern, let fields) = proof else {
            Issue.record("expected a recipe anchor"); return
        }
        #expect(fields == ["usePrereleases", "versionPattern"])

        // It passes on the rule as written…
        let beta = try rule(.beta)
        #expect(RecipeSanity.recipeAnchorFailure(
            pattern: pattern, fields: fields, channel: .beta, subject: beta) == nil)
        // …and fails on EITHER half of the drift it exists to catch. Both make the
        // beta rule quietly behave like a second stable rule, with no error and no
        // missing version — a beta install simply stops being offered betas.
        let notReadingTheList = GitHubReleaseRule(
            bundleID: beta.bundleID, owner: beta.owner, repo: beta.repo,
            usePrereleases: false, listPageSize: beta.listPageSize,
            versionPattern: beta.versionPattern,
            installAssetPattern: beta.installAssetPattern,
            installerKind: beta.installerKind, channel: .beta)
        #expect(RecipeSanity.recipeAnchorFailure(
            pattern: pattern, fields: fields, channel: .beta,
            subject: notReadingTheList) != nil)

        let refusingPrereleaseTags = GitHubReleaseRule(
            bundleID: beta.bundleID, owner: beta.owner, repo: beta.repo,
            usePrereleases: true, listPageSize: beta.listPageSize,
            versionPattern: try rule(.stable).versionPattern,
            installAssetPattern: beta.installAssetPattern,
            installerKind: beta.installerKind, channel: .beta)
        #expect(RecipeSanity.recipeAnchorFailure(
            pattern: pattern, fields: fields, channel: .beta,
            subject: refusingPrereleaseTags) != nil)

        // `usePrereleases: true` is NOT by itself a beta-only property — three
        // stable rules in this registry set it — which is why the anchor names
        // `versionPattern` as well.
        #expect(GitHubReleaseRegistry.rules.contains {
            $0.usePrereleases && $0.channel == .stable
        })
    }

}
