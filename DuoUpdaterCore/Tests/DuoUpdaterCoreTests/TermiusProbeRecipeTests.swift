import Testing
import Foundation
@testable import DuoUpdaterCore

/// Termius stable + beta (issue #91).
///
/// Stable (`com.termius-dmg.mac`) was already registered before this issue was
/// filed — the issue's own claim that Termius stable is "in no registry at all"
/// checked the Mac App Store bundle id (`com.termius.mac`, generically covered by
/// `MacAppStoreSource`, no registry entry needed) rather than the direct-download
/// build's real bundle id. This file covers what the issue actually left
/// unstarted: Beta, an independent bundle id (`com.termius-beta.mac`).
///
/// Every expectation below is checked against response bodies captured verbatim
/// from the vendor on 2026-08-27:
///   - `https://autoupdate.termius.com/mac-beta-universal/latest-mac.yml` (Beta,
///     the feed the new recipe reads)
///   - `https://autoupdate.termius.com/mac-arm64/latest-mac.yml` (Stable, the feed
///     the pre-existing recipe reads — kept here only to show the two feeds are
///     genuinely independent, not to re-test the stable recipe itself)
struct TermiusProbeRecipeTests {

    private static let stableBundleID = "com.termius-dmg.mac"
    private static let betaBundleID = "com.termius-beta.mac"

    /// `https://autoupdate.termius.com/mac-beta-universal/latest-mac.yml`,
    /// 2026-08-27.
    private static let betaBody = """
        version: 9.43.1
        files:
          - url: Termius Beta.zip
            sha512: 08ovSDodx5wGBfp/vLCwf49uVACJ9Xj95aPgn7Lm+Z0exazThLdCOVf/LwrRF4hjY+lBUzm4l45lG8rk6D9cLQ==
            size: 239947907
          - url: Termius Beta.dmg
            sha512: Eo4XFtmNeDRfMA9X9N2yw2jHf7TS2o2GH4pbIbWpl2qEYBoXb7CIgIdQlLRzUb38LXO59/xUciQXgwuExlBE+w==
            size: 249396295
        path: Termius Beta.zip
        sha512: 08ovSDodx5wGBfp/vLCwf49uVACJ9Xj95aPgn7Lm+Z0exazThLdCOVf/LwrRF4hjY+lBUzm4l45lG8rk6D9cLQ==
        releaseDate: '2026-08-12T07:56:45.216Z'
        rollout:
          freeUsers: 100
          paidUsers: 100
        """

    /// `https://autoupdate.termius.com/mac-arm64/latest-mac.yml` (Stable's own
    /// feed), same day — proof the two channels read genuinely separate
    /// endpoints, not a shared one filtered by tag.
    private static let stableBody = """
        version: 9.43.1
        files:
          - url: Termius.zip
            sha512: w3b8pZD4Hb8fp4mqdKq2bOH4jp6k7T1WEpVJH8WivQoCM3dyluI8M0agiPxvy/NE97WOYIh0/kmPBjXQQ4r6PA==
            size: 162402204
          - url: Termius.dmg
            sha512: wwEhambXFuGGS9kTTYjWiMvFXyOkJu+mSs/1noudKnu5yttsTDowQsCbS1E/cTK0nPBleKBj/nsbOYYNWqBY4A==
            size: 169439149
        path: Termius.zip
        sha512: w3b8pZD4Hb8fp4mqdKq2bOH4jp6k7T1WEpVJH8WivQoCM3dyluI8M0agiPxvy/NE97WOYIh0/kmPBjXQQ4r6PA==
        releaseDate: '2026-08-12T08:11:47.041Z'
        rollout:
          freeUsers: 100
          paidUsers: 100
        """

    /// `CFBundleShortVersionString` of `Termius Beta.app`, read off the mounted
    /// dmg (`https://autoupdate.termius.com/mac-beta-universal/Termius%20Beta.dmg`,
    /// same day the bodies above were captured).
    private static let installedBetaShortVersion = "9.43.1"

    /// `shasum -a 512 Termius\ Beta.dmg | base64`, computed on the SAME downloaded
    /// bytes the mount above verified — confirms the feed's declared sha512 is not
    /// stale relative to what the CDN actually serves (unlike Signal Beta, whose
    /// CDN staples the dmg after electron-builder wrote the feed).
    private static let expectedBetaChecksum =
        "Eo4XFtmNeDRfMA9X9N2yw2jHf7TS2o2GH4pbIbWpl2qEYBoXb7CIgIdQlLRzUb38LXO59/xUciQXgwuExlBE+w=="

    private static func betaRecipe() throws -> VendorProbeRecipe {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == betaBundleID }
        #expect(recipes.count == 1, "Termius Beta should have exactly one recipe")
        return try #require(recipes.first)
    }

    // MARK: - registry shape

    /// Two bundle ids, two recipes, one each — no accidental duplicate and no
    /// channel collision (each reads its own feed, on its own bundle id).
    @Test func termiusHasOneStableAndOneBetaRecipe() throws {
        let stable = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.stableBundleID }
        let beta = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.betaBundleID }
        #expect(stable.count == 1)
        #expect(beta.count == 1)
        #expect(try #require(stable.first).channel == .stable)
        #expect(try #require(beta.first).channel == .beta)
        #expect(Self.stableBundleID != Self.betaBundleID,
                "Pattern A: distinct bundle ids, so ReleaseChannel.detect() needs no new rule")
    }

    @Test func betaRecipeIsAResponseBodyRecipeWithNoHostRequirement() throws {
        let recipe = try Self.betaRecipe()
        if case .responseBody = recipe.mode {} else {
            Issue.record("\(recipe.bundleID) is not a body-parsing recipe")
        }
        // Verified 2026-08-27 by `lipo -info` on the downloaded dmg: x86_64 arm64.
        // A universal artifact needs no VendorHostRequirement gate.
        #expect(recipe.hostRequirement == nil)
        #expect(recipe.variant == nil)
        #expect(recipe.identities.isEmpty && recipe.track == nil)
    }

    /// Same host stable already probes (`autoupdate.termius.com`), different path
    /// — found via the vendor's own Homebrew cask `livecheck` block, not guessed.
    @Test func theBetaProbeReadsItsOwnPathOnTheSameHost() throws {
        let recipe = try Self.betaRecipe()
        #expect(recipe.url.absoluteString
            == "https://autoupdate.termius.com/mac-beta-universal/latest-mac.yml")
        #expect(recipe.url.host() == "autoupdate.termius.com")
    }

    // MARK: - the version

    @Test func theBetaVersionComesFromTheRealFeed() throws {
        let recipe = try Self.betaRecipe()
        let version = try #require(
            VendorProbeRecipe.extractVersion(from: Self.betaBody, pattern: recipe.versionPattern))
        #expect(version == Self.installedBetaShortVersion)
        #expect(VersionComparator.compare(version, Self.installedBetaShortVersion)
            == .orderedSame,
            "an up-to-date Termius Beta would be shown a phantom update")
        #expect(!recipe.versionIsBuild)
    }

    /// The beta pattern must not silently also read stable's own feed — not a
    /// cross-channel risk here (different bundle ids gate which recipe even
    /// applies), but a broken pattern that happened to read ANY version-shaped
    /// text would hide a real breakage. Both feeds report 9.43.1 today, which is
    /// exactly the coincidence the issue flagged as worth re-checking later.
    @Test func bothFeedsAgreeTodayButAreReadIndependently() throws {
        let recipe = try Self.betaRecipe()
        let betaVersion = try #require(
            VendorProbeRecipe.extractVersion(from: Self.betaBody, pattern: recipe.versionPattern))
        let stableVersion = try #require(
            VendorProbeRecipe.extractVersion(from: Self.stableBody, pattern: recipe.versionPattern))
        #expect(betaVersion == stableVersion, "true today — 9.43.1 on both tracks")
        #expect(recipe.url != VendorProbeRegistry.recipes
            .first { $0.bundleID == Self.stableBundleID }?.url,
            "the two channels must never share one endpoint")
    }

    // MARK: - the install artifact

    @Test func theInstallResolvesTheFixedUniversalDMG() throws {
        let recipe = try Self.betaRecipe()
        let spec = try #require(recipe.install)
        guard case .fixed(let url) = spec.urlSource else {
            Issue.record("\(recipe.bundleID) install is not a fixed URL")
            return
        }
        #expect(url.absoluteString
            == "https://autoupdate.termius.com/mac-beta-universal/Termius%20Beta.dmg")
        #expect(spec.kind == .dmg)
    }

    /// The checksum line belongs to the dmg, not the zip listed just above it in
    /// the same document — and it matches bytes actually downloaded, not merely
    /// the feed's own internal consistency.
    @Test func theChecksumMatchesTheDownloadedDMGBytes() throws {
        let recipe = try Self.betaRecipe()
        let pattern = try #require(recipe.install?.checksumPattern)
        let digest = try #require(
            VendorProbeRecipe.extractVersion(from: Self.betaBody, pattern: pattern))
        #expect(digest == Self.expectedBetaChecksum)
        #expect(digest != "08ovSDodx5wGBfp/vLCwf49uVACJ9Xj95aPgn7Lm+Z0exazThLdCOVf/LwrRF4hjY+lBUzm4l45lG8rk6D9cLQ==",
                "that is the zip's digest")
        #expect(Data(base64Encoded: digest)?.count == 64, "not a 512-bit digest")
    }

    // MARK: - channel proof (mandatory: this recipe carries a non-stable install)

    @Test func theChannelProofMatchesTheResolvedInstallURL() throws {
        let key = ChannelProofKey(Self.betaBundleID, .beta)
        let proof = try #require(ChannelProofRegistry.proofs[key])
        guard case .artifact(let pattern) = proof else {
            Issue.record("expected an .artifact proof for \(key)")
            return
        }
        let recipe = try Self.betaRecipe()
        guard case .fixed(let url) = recipe.install?.urlSource else {
            Issue.record("install spec is not .fixed")
            return
        }
        #expect(url.absoluteString.range(
            of: pattern, options: [.regularExpression, .caseInsensitive]) != nil)
        // And the guard is not vacuous: stable's own resolved URL must NOT match
        // the beta proof.
        #expect(Self.stableInstallURL().range(
            of: pattern, options: [.regularExpression, .caseInsensitive]) == nil,
            "the beta proof must not also match stable's installer")
    }

    private static func stableInstallURL() -> String {
        guard let stable = VendorProbeRegistry.recipes.first(where: { $0.bundleID == stableBundleID }),
              case .fixed(let url) = stable.install?.urlSource
        else { return "" }
        return url.absoluteString
    }

    // MARK: - detection needs no new rule (the issue's own claim, checked directly)

    /// `CFBundleName`/`CFBundleDisplayName` is "Termius Beta" — the issue's claim
    /// that `ReleaseChannel.detect()` resolves this via the standalone-word
    /// `channelWord` step with no new rule, checked against the real function
    /// rather than taken on faith. This is NOT a change to `ReleaseChannel.swift`
    /// (untouched by this PR) — just a test of its existing behaviour.
    @Test func detectResolvesTermiusBetaFromItsDisplayNameAlone() {
        let channel = ReleaseChannel.detect(
            name: "Termius Beta", bundleID: Self.betaBundleID, keystoneChannel: nil)
        #expect(channel == .beta)
    }

    @Test func detectLeavesStableAlone() {
        let channel = ReleaseChannel.detect(
            name: "Termius", bundleID: Self.stableBundleID, keystoneChannel: nil)
        #expect(channel == .stable)
    }
}
