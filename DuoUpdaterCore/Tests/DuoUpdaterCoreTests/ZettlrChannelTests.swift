import Foundation
import Testing
@testable import DuoUpdaterCore

/// Zettlr: one bundle id, a stable and a beta rule on its GitHub releases, the
/// beta one selected by the app's own `checkForBeta`, and a nightly the bundle's
/// version string names. See `ZettlrChannel` and `Recipes/com-zettlr-app.swift`.
struct ZettlrChannelTests {
    private static let bundleID = "com.zettlr.app"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    /// Real tags (`gh api repos/Zettlr/Zettlr/releases`, 2026-10-16), holding
    /// both prerelease shapes: the cycle's first `-beta` with no number, and the
    /// numbered `-beta.N`.
    private static let tags = [
        "v4.8.0", "v4.1.1", "v4.0.0", "v4.0.0-beta.5", "v4.0.0-beta", "v3.6.0",
        "v3.1.0-beta.3", "v2.3.0", "v1.8.9", "v0.20.0",
    ]

    @Test func bothRulesAreRegisteredAndSplitTheTrains() throws {
        #expect(Self.rules.count == 2)
        let stable = try #require(Self.rules.first { $0.channel == .stable })
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(!stable.usePrereleases)
        #expect(beta.usePrereleases)
        for rule in Self.rules {
            #expect(rule.owner == "Zettlr" && rule.repo == "Zettlr")
            #expect(rule.installerKind == .dmg)
        }
    }

    @Test func theStablePatternRefusesBetasAndTheBetaOneTakesEveryTag() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable })
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        var acceptedByStable = 0
        for tag in Self.tags {
            let bare = String(tag.dropFirst())
            let s = VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern)
            if tag.contains("-beta") {
                #expect(s == nil, "the stable pattern accepted a prerelease: \(tag)")
            } else {
                #expect(s == bare)
                acceptedByStable += 1
            }
            // The suffix stays: a beta build's Info.plist reads `4.0.0-beta.5`.
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: beta.versionPattern) == bare)
        }
        #expect(acceptedByStable == 7)
        // The next major, and an rc the vendor has never shipped, stay apart.
        #expect(VendorProbeRecipe.extractVersion(from: "v5.0.0", pattern: stable.versionPattern) == "5.0.0")
        #expect(VendorProbeRecipe.extractVersion(from: "v5.0.0-rc.1", pattern: stable.versionPattern) == nil)
    }

    @Test func theStableAssetPatternRefusesABetaDMG() throws {
        let stable = try #require(Self.rules.first { $0.channel == .stable }.flatMap(\.installAssetPattern))
        let beta = try #require(Self.rules.first { $0.channel == .beta }.flatMap(\.installAssetPattern))
        func matches(_ pattern: String, _ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }
        for name in ["Zettlr-4.8.0-arm64.dmg", "Zettlr-4.8.0-x64.dmg"] {
            #expect(matches(stable, name))
            #expect(matches(beta, name))
        }
        for name in ["Zettlr-4.0.0-beta.5-arm64.dmg", "Zettlr-4.0.0-beta-x64.dmg"] {
            #expect(!matches(stable, name), "the stable rule must never install \(name)")
            #expect(matches(beta, name))
        }
        for name in ["Zettlr-4.8.0-arm64.AppImage", "Zettlr-4.8.0-x64.exe", "SHA256SUMS.txt"] {
            #expect(!matches(stable, name) && !matches(beta, name))
        }
    }

    @Test func theChannelProofAnchorsTheRequest() throws {
        let proof = try #require(
            ChannelProofRegistry.githubProofs[ChannelProofKey(Self.bundleID, .beta)])
        guard case .recipeAnchor(let pattern, let fields) = proof else {
            Issue.record("expected a recipeAnchor proof, got \(proof)"); return
        }
        #expect(fields.contains("usePrereleases") && fields.contains("versionPattern"))
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(beta.versionPattern.range(of: pattern, options: .regularExpression) != nil)
        #expect(ChannelProofRegistry.channelGitHubRulesWithInstall
            .contains(ChannelProofKey(Self.bundleID, .beta)))
    }

    /// Only a ticked box answers; anything else is nil so `detect()` keeps the
    /// beta build's own version suffix and the nightly's `+nightly`.
    @Test func onlyJSONTrueOptsIn() {
        func read(_ json: String?) -> ResolvedChannel? {
            ZettlrChannel.resolve(checkForBeta: ZettlrChannel.checksForBeta(config: json.map { Data($0.utf8) }))
        }
        #expect(read(#"{"checkForBeta": true, "system": {"checkForUpdates": true}}"#)?.channel == .beta)
        #expect(read(#"{"checkForBeta": false}"#) == nil)
        #expect(read(#"{"checkForBeta": 1}"#) == nil)
        #expect(read(#"{"checkForBeta": "true"}"#) == nil)
        #expect(read(#"{"system": {"checkForBeta": true}}"#) == nil)
        #expect(read("not json") == nil)
        #expect(read(nil) == nil)
    }

    @Test func theBindingIsRegisteredAndReadsTheUserDataConfig() {
        #expect(ChannelBinding.hasResolver(bundleID: Self.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(Self.bundleID))
        #expect(ZettlrChannel.configFileURL.path.hasSuffix(
            "Library/Application Support/Zettlr/config.json"))
    }

    /// Versions as the real bundles read them (4.8.0, 4.0.0-beta.5, and the
    /// 2026-10-12 nightly's `4.8.0+nightly`).
    @Test func theBundleVersionNamesBetaAndNightly() {
        func detect(_ version: String, _ bundleID: String = Self.bundleID) -> ReleaseChannel {
            ReleaseChannel.detect(name: "Zettlr", bundleID: bundleID, keystoneChannel: nil, version: version)
        }
        #expect(detect("4.8.0") == .stable)
        #expect(detect("4.0.0-beta.5") == .beta)
        #expect(detect("4.8.0+nightly") == .nightly)
        #expect(detect("4.0.0-beta+nightly") == .nightly)
        // Scoped to Zettlr: the same shape elsewhere is not read as a channel here.
        #expect(detect("4.8.0+nightly", "com.example.other") == .stable)
    }

    /// Before 1.0.0 the app was com.zettlr.www, unsigned: detection only.
    @Test func thePre1IdIsDetectionOnly() throws {
        let old = GitHubReleaseRegistry.rules.filter { $0.bundleID == "com.zettlr.www" }
        #expect(old.count == 1)
        let rule = try #require(old.first)
        #expect(rule.installAssetPattern == nil && rule.installerKind == nil)
        #expect(rule.channel == .stable && !rule.usePrereleases)
    }
}
