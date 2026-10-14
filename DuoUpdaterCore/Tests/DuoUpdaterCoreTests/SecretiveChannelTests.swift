import Foundation
import Testing

@testable import DuoUpdaterCore

/// Secretive's nightly, told apart from stable only by the `0.0.0_nightly-<date>`
/// marketing version its `nightly.yml` stamps — `ReleaseChannel.detect` step 0.99.
///
/// The inputs are each package's own Info.plist values: nightly and stable share
/// `com.maxgoedjen.Secretive.Host`, the name "Secretive" and Team `Z72PRUAWF6`.
/// Nightly artifact of 2026-10-13: `0.0.0_nightly-2026-10-13` / `1.38367930469`;
/// stable release: `4.0.0` / `1.35554366823`.
@Suite struct SecretiveChannelTests {

    private static let bundleID = "com.maxgoedjen.Secretive.Host"
    private static let nightlyVersion = "0.0.0_nightly-2026-10-13"

    private func detect(_ version: String, bundleID: String = Self.bundleID) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Secretive", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "Secretive.app")
    }

    @Test func theNightlyReadsAsNightly() {
        #expect(detect(Self.nightlyVersion) == .nightly)
    }

    @Test func releasesStayStable() {
        for version in ["4.0.0", "3.0.4", "2.4.1", "0.5.1"] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    /// The one-off workflow's `0.0.0_oneoff-<date>` is not a nightly; this rule
    /// does not claim it.
    @Test func otherUnderscoreTailsAreNotReadByThisRule() {
        for version in ["0.0.0_oneoff-2026-09-16", "0.0.0_nightlies", "nightly-2026-10-13", ""] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    @Test func otherBundleIDsAreNotReadByThisRule() {
        #expect(detect(Self.nightlyVersion, bundleID: "com.example.app") == .stable)
    }

    /// The point of the rule: the real registry's stable rule must not answer for a
    /// nightly copy. Skipped before any fetch — a network call here is a bug on its own.
    @Test func stableRuleIsNotOfferedToTheNightly() async throws {
        let rule = try #require(
            GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
        #expect(rule.channel == .stable)

        let source = GitHubReleasesSource(rules: [rule])
        let nightly = InstalledApp(
            name: "Secretive", bundleID: Self.bundleID,
            shortVersion: Self.nightlyVersion, buildVersion: "1.38367930469",
            path: URL(fileURLWithPath: "/Applications/Secretive.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: detect(Self.nightlyVersion))

        #expect(nightly.releaseChannel == .nightly)
        #expect(try await source.latestVersion(for: nightly) == nil)
    }
}
