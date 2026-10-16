import Foundation
import Testing

@testable import DuoUpdaterCore

/// Loop's Development build, told apart from stable only by the "🧪 <version>"
/// marketing version its `dev-build.yml` stamps — `ReleaseChannel.detect` step 0.995.
///
/// The inputs are each package's own Info.plist values: both share
/// `com.MrKai77.Loop`, the name "Loop" and Team `5F967GYF84`. Development build of
/// 2026-10-13: "🧪 1.4.3" / 1783; stable release: 1.4.2 / 1693.
@Suite struct LoopChannelTests {

    private static let bundleID = "com.MrKai77.Loop"
    private static let devVersion = "🧪 1.4.3"

    private func detect(_ version: String, bundleID: String = Self.bundleID) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Loop", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "Loop.app")
    }

    @Test func theDevelopmentBuildReadsAsDev() {
        #expect(detect(Self.devVersion) == .dev)
    }

    @Test func releasesStayStable() {
        for version in ["1.4.2", "1.4.1", "1.3.0", "1.0.0", "2.0.0"] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    @Test func otherBundleIDsAreNotReadByThisRule() {
        #expect(detect(Self.devVersion, bundleID: "com.example.app") == .stable)
    }

    /// The point of the rule: the real registry's stable rule must not answer for a
    /// Development copy (it offered 1.4.2 to "🧪 1.4.3" before). Skipped before any
    /// fetch — a network call here is a bug on its own.
    @Test func stableRuleIsNotOfferedToTheDevelopmentBuild() async throws {
        let rule = try #require(
            GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
        #expect(rule.channel == .stable)

        let source = GitHubReleasesSource(rules: [rule])
        let dev = InstalledApp(
            name: "Loop", bundleID: Self.bundleID,
            shortVersion: Self.devVersion, buildVersion: "1783",
            path: URL(fileURLWithPath: "/Applications/Loop.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: detect(Self.devVersion))

        #expect(dev.releaseChannel == .dev)
        #expect(try await source.latestVersion(for: dev) == nil)
    }
}
