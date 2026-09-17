import Foundation
import Testing

@testable import DuoUpdaterCore

/// Tinycast ships stable and beta as two apps with two bundle ids out of one
/// repository, and signs both with a self-signed identity. These tests pin the
/// seams that keep the two rules from reading each other's tags, and that keep
/// both detection-only. See `docs/app-audits/com-tinycast-app.md`.
@Suite struct TinycastGitHubRuleTests {

    private static let stableID = "com.tinycast.app"
    private static let betaID = "com.tinycast.app.beta"

    /// Every rule of the family, required non-empty so a renamed id or an
    /// unregistered family fails loudly instead of leaving the suite vacuous.
    private static var rules: [GitHubReleaseRule] {
        get throws {
            let found = GitHubReleaseRegistry.rules.filter {
                $0.bundleID == stableID || $0.bundleID == betaID
            }
            try #require(found.count == 2, "expected one stable and one beta Tinycast rule")
            return found
        }
    }

    private func rule(_ bundleID: String) throws -> GitHubReleaseRule {
        try #require(Self.rules.first { $0.bundleID == bundleID })
    }

    private func extract(_ tag: String, _ bundleID: String) throws -> String? {
        VendorProbeRecipe.extractVersion(from: tag, pattern: try rule(bundleID).versionPattern)
    }

    /// Both release trains are signed "Tinycast Self-Signed" with no Team
    /// Identifier (real 0.10.23 and 0.11.1-beta.96 zips, 2026-09-17), so
    /// `SignatureVerifier` would refuse the swap: an install pattern could only
    /// ever produce an Update button that fails.
    @Test func bothRulesStayDetectionOnly() throws {
        for rule in try Self.rules {
            #expect(rule.installAssetPattern == nil, "\(rule.bundleID) must stay detection-only")
            #expect(rule.installerKind == nil, "\(rule.bundleID) must stay detection-only")
        }
    }

    @Test func eachRuleServesItsOwnChannel() throws {
        #expect(try rule(Self.stableID).channel == .stable)
        #expect(try rule(Self.stableID).usePrereleases == false)
        #expect(try rule(Self.betaID).channel == .beta)
        #expect(try rule(Self.betaID).usePrereleases == true)
    }

    /// Real tag shapes from the repo (2026-09-17). The stable pattern has to
    /// refuse every non-stable shape the repo publishes — betas, the macOS 15
    /// `-sequoia` builds (same bundle id) and the old `-alpha.N` tags — so that
    /// one arriving from `/releases/latest` without its prerelease flag is not
    /// read as a stable version.
    @Test func stableRuleTakesOnlyPlainTags() throws {
        #expect(try extract("v0.10.23", Self.stableID) == "0.10.23")
        for tag in ["v0.11.1-beta.96", "v0.9.7-sequoia", "v0.5.7-alpha.22"] {
            #expect(try extract(tag, Self.stableID) == nil, "\(tag)")
        }
    }

    /// The beta pattern keeps the `-beta.N` suffix, because the installed bundle
    /// does (`CFBundleShortVersionString` "0.11.1-beta.96"); and it refuses
    /// plain tags, because a stable release is a different app, not the build a
    /// beta copy graduates into.
    @Test func betaRuleKeepsTheSuffixAndRefusesStableTags() throws {
        #expect(try extract("v0.11.1-beta.96", Self.betaID) == "0.11.1-beta.96")
        for tag in ["v0.10.23", "v0.9.7-sequoia", "v0.5.7-alpha.22"] {
            #expect(try extract(tag, Self.betaID) == nil, "\(tag)")
        }
    }

    /// Identities read off the real artifacts: the beta copy has to detect as
    /// `.beta` (or the beta rule never applies to it), the stable copy as
    /// `.stable`.
    @Test func realIdentitiesDetectToTheirRulesChannel() {
        #expect(ReleaseChannel.detect(
            name: "Tinycast Beta", bundleID: Self.betaID, keystoneChannel: nil,
            version: "0.11.1-beta.96") == .beta)
        #expect(ReleaseChannel.detect(
            name: "Tinycast", bundleID: Self.stableID, keystoneChannel: nil,
            version: "0.10.23") == .stable)
    }

    /// The beta counter is the Actions run number and keeps climbing across
    /// base versions, so `beta.10` must beat `beta.9` numerically and a newer
    /// base must win regardless of the counter.
    @Test func betaVersionsOrderNumerically() {
        #expect(VersionComparator.isNewer("0.11.1-beta.96", than: "0.11.0-beta.95"))
        #expect(VersionComparator.isNewer("0.10.23-beta.100", than: "0.10.23-beta.94"))
        #expect(!VersionComparator.isNewer("0.11.1-beta.96", than: "0.11.1-beta.96"))
    }
}
