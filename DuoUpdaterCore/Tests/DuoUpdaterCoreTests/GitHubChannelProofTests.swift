import Testing
import Foundation
@testable import DuoUpdaterCore

/// Issue #101 — the gate the GitHub registry did not have.
///
/// `ChannelProofRegistry` exists so a non-stable install-carrying recipe has to
/// state how it knows the artifact it resolves belongs to its own channel. It
/// read `VendorProbeRegistry` only, and `crossChannelArtifact` was typed on
/// `VendorProbeRecipe`, so a GitHub rule could not reach it even in principle:
/// a vendor recipe that skipped its proof got a hard finding, and a GitHub rule
/// in the same situation got silence.
///
/// The live sweep the issue asked for found nothing misresolving — all three
/// rules gate the channel in their `versionPattern` — so what these tests guard
/// is the NEXT rule, written with the registry's default loose pattern and no
/// discriminator at all.
struct GitHubChannelProofTests {

    // MARK: exhaustiveness

    /// Derived from the registry, never a hand-written list: a rule added
    /// tomorrow is covered by construction, which is the whole point.
    @Test func githubProofsCoverEveryChannelRule() {
        let needed = Set(ChannelProofRegistry.channelGitHubRulesWithInstall)
        let have = Set(ChannelProofRegistry.githubProofs.keys)
        let unproven = needed.subtracting(have).map(\.description).sorted()
        let orphaned = have.subtracting(needed).map(\.description).sorted()
        #expect(unproven.isEmpty,
                "non-stable GitHub rules with an install spec but no ChannelProof: \(unproven)")
        #expect(orphaned.isEmpty,
                "ChannelProof entries for GitHub rules that no longer carry a non-stable install spec: \(orphaned)")
    }

    /// The open question the issue raised about reusing `ChannelProofKey`, turned
    /// into a measurement.
    ///
    /// The key is `(bundleID, channel)` and carries no registry, so two rules
    /// from different registries sharing a pair would collide on one entry — and
    /// the exhaustiveness test above would still pass, while checking one
    /// registry's artifact against the other's proof. Two maps make that
    /// impossible; this fails the day the ambiguity becomes real, so nobody has
    /// to rediscover why they are separate.
    @Test func channelProofMapsDoNotCollide() {
        let vendor = Set(ChannelProofRegistry.channelRecipesWithInstall)
        let github = Set(ChannelProofRegistry.channelGitHubRulesWithInstall)
        let shared = vendor.intersection(github).map(\.description).sorted()
        #expect(shared.isEmpty,
                "\(shared) is served by BOTH registries on the same channel — the two proof maps are now genuinely ambiguous and the key needs a registry component")
    }

    // MARK: the check itself

    /// A rule whose asset URL carries its channel token passes.
    ///
    /// The URLs are the real ones (Releases API, 2026-08-28). GitHub builds an
    /// asset URL as `…/releases/download/<tag>/<name>`, so the tag the
    /// `versionPattern` matched is in the path — which is what makes an
    /// `.artifact` proof possible for rules whose asset FILENAME is identical to
    /// stable's (`Zed-aarch64.dmg`, `GitHub.Desktop-arm64.zip`).
    @Test func aChannelTaggedArtifactSatisfiesItsProof() {
        let cases: [(String, String)] = [
            ("dev.zed.Zed-Preview",
             "https://github.com/zed-industries/zed/releases/download/v1.18.0-pre/Zed-aarch64.dmg"),
            ("com.github.GitHubClient",
             "https://github.com/desktop/desktop/releases/download/release-3.6.5-beta1/GitHub.Desktop-arm64.zip"),
            ("com.vscodium.VSCodiumInsiders",
             "https://github.com/VSCodium/vscodium-insiders/releases/download/1.126.04518-insider/VSCodium-darwin-arm64-1.126.04518-insider.zip"),
        ]
        for (bundleID, asset) in cases {
            let rule = try! #require(nonStableRule(bundleID))
            let complaint = RecipeSanity.crossChannelArtifact(
                rule: rule, remote: remote(asset))
            #expect(complaint == nil, "\(bundleID): \(complaint ?? "")")
        }
    }

    /// T3 Code's nightly proof is a tag-path `.artifact` like the others, but it
    /// can't live in the tables above: the bundle id has TWO non-stable rules
    /// (alpha first in the registry), and `nonStableRule` would hand the nightly
    /// URL to the alpha proof, which does not inspect URLs at all.
    @Test func t3CodeNightlyProofKeysOnTheTagPath() {
        let nightly = try! #require(
            GitHubReleaseRegistry.rules.first {
                $0.bundleID == "com.t3tools.t3code" && $0.channel == .nightly
            })
        #expect(RecipeSanity.crossChannelArtifact(
            rule: nightly,
            remote: remote("https://github.com/pingdotgg/t3code/releases/download/"
                + "v0.0.37-nightly.20260830.1227/T3-Code-0.0.37-nightly.20260830.1227-arm64.dmg"))
            == nil)
        // The alpha train's tag under the nightly rule — same repo, same asset
        // naming, only the tag differs.
        #expect(RecipeSanity.crossChannelArtifact(
            rule: nightly,
            remote: remote("https://github.com/pingdotgg/t3code/releases/download/"
                + "v0.0.36/T3-Code-0.0.36-arm64.dmg")) != nil)
    }

    /// The alpha proof must be able to fail on the only drift it exists to
    /// catch: the install pattern loosened enough to swallow the nightly train's
    /// asset names. A synthetic rule with a `.*` version run exercises the
    /// registered proof exactly as the runtime would.
    @Test func t3CodeAlphaProofFailsWhenThePatternCanMatchNightlyAssets() {
        let loosened = GitHubReleaseRule(
            bundleID: "com.t3tools.t3code",
            owner: "pingdotgg", repo: "t3code",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^T3-Code-.*-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .alpha)
        #expect(RecipeSanity.crossChannelArtifact(
            rule: loosened,
            remote: remote("https://github.com/pingdotgg/t3code/releases/download/"
                + "v0.0.37-nightly.20260830.1227/T3-Code-0.0.37-nightly.20260830.1227-arm64.dmg"))
            != nil)

        let anchored = try! #require(
            GitHubReleaseRegistry.rules.first {
                $0.bundleID == "com.t3tools.t3code" && $0.channel == .alpha
            })
        #expect(RecipeSanity.crossChannelArtifact(
            rule: anchored,
            remote: remote("https://github.com/pingdotgg/t3code/releases/download/"
                + "v0.0.36/T3-Code-0.0.36-arm64.dmg")) == nil)
    }

    /// The failure this whole mechanism exists for: the rule still resolves, the
    /// asset is a real notarized build from the same vendor with the same Team
    /// ID — and it is stable's. Every one of these is the SAME repository and the
    /// SAME asset filename as the passing case above; only the tag differs.
    @Test func stablesArtifactUnderAChannelRuleIsCaughtEveryTime() {
        let cases: [(String, String)] = [
            ("dev.zed.Zed-Preview",
             "https://github.com/zed-industries/zed/releases/download/v1.17.2/Zed-aarch64.dmg"),
            ("com.github.GitHubClient",
             "https://github.com/desktop/desktop/releases/download/release-3.6.4/GitHub.Desktop-arm64.zip"),
            ("com.vscodium.VSCodiumInsiders",
             "https://github.com/VSCodium/vscodium/releases/download/1.126.04518/VSCodium-darwin-arm64-1.126.04518.zip"),
        ]
        for (bundleID, asset) in cases {
            let rule = try! #require(nonStableRule(bundleID))
            #expect(RecipeSanity.crossChannelArtifact(rule: rule, remote: remote(asset)) != nil,
                    "\(bundleID) resolved stable's artifact and nothing complained")
        }
    }

    /// A proof must be able to FAIL. The one that could not.
    ///
    /// Every GitHub asset URL carries `owner/repo` in its path, so for
    /// `VSCodium/vscodium-insiders` a bare `-insider` pattern matched the
    /// repository name and therefore matched every URL the rule could ever
    /// resolve — a proof that acquits unconditionally. No amount of live data
    /// shows this, because every real tag in that repo also carries `-insider`;
    /// only an artifact that is wrong in the way the proof exists to catch
    /// separates the two patterns.
    ///
    /// Written per-registry rather than as a loop over `githubProofs`, because
    /// the falsifying URL is different for each proof — a generic "does some
    /// string fail" test would be its own tautology.
    /// Every `.artifact` proof, derived from the registry: the pattern must not
    /// match the part of the URL that is FIXED for its rule.
    ///
    /// GitHub builds every asset URL for a rule as
    /// `https://github.com/<owner>/<repo>/releases/download/<tag>/<name>`, so the
    /// prefix through `/download/` is a constant this rule cannot vary. A proof
    /// that matches inside that constant is satisfied by every URL the rule can
    /// ever resolve — including stable's — and can therefore never fail. That is
    /// the failure `aProofMustBeAbleToFailOnItsOwnRepository` below describes,
    /// but it names ONE bundle id, and `stablesArtifactUnderAChannelRuleIsCaught`
    /// hand-lists three; neither sees a rule added later. This one is derived, so
    /// it covers the next one automatically.
    ///
    /// Caught in practice: writing the Vorssaint beta proof, a mutation to the
    /// bare token `vorssaint` — which sits in BOTH the owner (`vorssaintapp`) and
    /// the repo (`vorssaint-utils`), so it matches every URL this rule builds —
    /// passed the entire suite. It fails here.
    @Test func anArtifactProofCannotMatchItsRulesInvariantURLPrefix() {
        for (key, proof) in ChannelProofRegistry.githubProofs {
            guard case .artifact(let pattern) = proof else { continue }
            guard let rule = GitHubReleaseRegistry.rules.first(where: {
                $0.bundleID == key.bundleID && $0.channel == key.channel
            }) else {
                Issue.record("no GitHubReleaseRule for \(key)")
                continue
            }
            let invariant = "https://github.com/\(rule.slug)/releases/download/"
            #expect(
                invariant.range(
                    of: pattern, options: [.regularExpression, .caseInsensitive]) == nil,
                """
                \(key)'s proof /\(pattern)/ matches the invariant prefix                 \(invariant) — it is satisfied by every URL this rule can build,                 stable's included, so it can never fail
                """)
        }
    }

    @Test func aProofMustBeAbleToFailOnItsOwnRepository() {
        let rule = try! #require(nonStableRule("com.vscodium.VSCodiumInsiders"))
        // Same repository, same host, a tag with no channel token: the shape a
        // vendor reorganising their tags would produce.
        let stableShaped = remote(
            "https://github.com/VSCodium/vscodium-insiders/releases/download/1.126.04518/VSCodium-darwin-arm64-1.126.04518.zip")
        #expect(RecipeSanity.crossChannelArtifact(rule: rule, remote: stableShaped) != nil,
                "the proof matched the repository name rather than the artifact — it can never fail")
    }

    /// The shape the issue's revised reading named: the registry's DEFAULT
    /// version pattern, `usePrereleases: true`, a non-stable channel, and no
    /// discriminator anywhere. Before this, that rule shipped in silence.
    @Test func anUnregisteredChannelRuleIsAHardFinding() {
        let loose = GitHubReleaseRule(
            bundleID: "com.example.SomethingBeta",
            owner: "example", repo: "something",
            usePrereleases: true,
            installAssetPattern: #"^Something-arm64\.zip$"#,
            installerKind: .zip,
            channel: .beta)
        let complaint = RecipeSanity.crossChannelArtifact(
            rule: loose,
            remote: remote("https://github.com/example/something/releases/download/v4.1.0/Something-arm64.zip"))
        let text = try! #require(complaint)
        #expect(text.contains("no channel proof registered"))
    }

    /// Two ways to have nothing to judge, and both must stay quiet rather than
    /// accumulate a streak against a rule that resolves no artifact at all.
    @Test func thereIsNothingToJudgeWithoutAnInstallSpec() {
        // Detection-only: `downloadURL` is the releases PAGE, not a build.
        let detectionOnly = GitHubReleaseRule(
            bundleID: "com.example.SomethingNightly",
            owner: "example", repo: "something",
            usePrereleases: true,
            channel: .nightly)
        #expect(RecipeSanity.crossChannelArtifact(
            rule: detectionOnly,
            remote: remote("https://github.com/example/something/releases")) == nil)

        // Stable: `/releases/latest` is computed by GitHub with prereleases
        // excluded, and the mirror check the vendor side runs cannot be run here
        // — see the comment in `crossChannelArtifact(rule:remote:)`.
        let stable = GitHubReleaseRule(
            bundleID: "com.example.Something",
            owner: "example", repo: "something-beta-tools",
            installAssetPattern: #"^Something-arm64\.zip$"#,
            installerKind: .zip)
        #expect(RecipeSanity.crossChannelArtifact(
            rule: stable,
            remote: remote("https://github.com/example/something-beta-tools/releases/download/v4.1.0/Something-arm64.zip")) == nil,
            "a stable rule in a repo whose NAME contains a pre-release word must not be accused")
    }

    // MARK: the `.recipeAnchor` surface

    /// Adding a field to `GitHubReleaseRule` must be a decision, not an omission
    /// — the same guard the vendor side has, for the same reason: a hand-written
    /// surface goes on passing while inspecting less, so nothing reads as broken.
    /// The fix on failure is one line either way — bump the count (the field is
    /// part of what the rule reads) or add the label to `nonAnchorFields` (it
    /// only labels the rule).
    @Test func channelAnchorSurfaceCoversEveryGitHubRuleField() {
        let rule = GitHubReleaseRegistry.rules[0]
        let labels = Mirror(reflecting: rule).children.compactMap(\.label)
        #expect(labels.count == 11,
                "GitHubReleaseRule gained or lost a field (now \(labels.count): \(labels.sorted())) — decide whether it belongs in the .recipeAnchor surface or in nonAnchorFields, then update this count")
        for excluded in GitHubReleaseRule.nonAnchorFields {
            #expect(labels.contains(excluded),
                    "nonAnchorFields names '\(excluded)', which is not a field of GitHubReleaseRule any more")
        }
    }

    /// The tautology `nonAnchorFields` exists to prevent: a `.beta` rule carries
    /// the literal string "beta" in `channel`, so an anchor of `beta` must NOT be
    /// satisfied by the mere fact that it is a beta rule.
    @Test func theChannelLabelItselfCannotSatisfyAnAnchor() {
        let rule = GitHubReleaseRule(
            bundleID: "com.example.SomethingBeta",
            owner: "example", repo: "something",
            usePrereleases: true,
            channel: .beta)
        #expect(!rule.channelAnchorSurface.contains("beta"),
                "the surface leaks the channel label, which would make every .recipeAnchor(\"beta\") vacuous")
    }

    /// And the surface does see the fields that carry a real discriminator.
    ///
    /// Zed is the honest witness: `repo` is `"zed"`, so `-pre` can only have come
    /// from `versionPattern`. VSCodium is asserted against the FIELD rather than
    /// the joined surface, because its `repo` and `installAssetPattern` both
    /// contain `insider` — a `surface.contains("insider")` check passes even with
    /// the discriminator deleted from the version pattern, which is the same
    /// vacuous shape as the proof in `aProofMustBeAbleToFailOnItsOwnRepository`.
    @Test func theAnchorSurfaceSeesTheVersionAndAssetPatterns() {
        let zed = try! #require(nonStableRule("dev.zed.Zed-Preview"))
        #expect(!zed.repo.contains("-pre"), "this rule is only a witness while its repo name is not")
        #expect(zed.channelAnchorSurface.contains("-pre"))
        let codium = try! #require(nonStableRule("com.vscodium.VSCodiumInsiders"))
        #expect(codium.versionPattern.contains("insider"))
        #expect(codium.channelAnchorSurface.contains(codium.versionPattern))
    }

    /// Select by bundle id AND non-stable channel, never by bundle id alone.
    ///
    /// GitHub Desktop ships two rules under `com.github.GitHubClient` — stable
    /// and beta — and `first(where: bundleID)` returns the stable one, whose
    /// channel makes `crossChannelArtifact` return nil before it checks
    /// anything. Written the lazy way, the positive test above passed while
    /// asserting nothing at all; the negative test is what caught it.
    private func nonStableRule(_ bundleID: String) -> GitHubReleaseRule? {
        GitHubReleaseRegistry.rules.first {
            $0.bundleID == bundleID && $0.channel != .stable
        }
    }

    private func remote(_ url: String) -> RemoteVersion {
        RemoteVersion(
            shortVersion: "1.0.0", version: "1.0.0",
            downloadURL: URL(string: url)!, sourceName: "GitHub")
    }
}
