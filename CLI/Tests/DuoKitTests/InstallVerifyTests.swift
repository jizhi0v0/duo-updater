import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// What `duo verify-install` calls a fault in a download it read successfully.
/// The download itself is measured against the real vendor (WorkBuddy CN, keyed
/// back to its pre-5.5.4 id, reads as `bundleIDMismatch`); these pin the
/// judgement so it cannot quietly stop firing.
@Suite struct InstallVerifyJudgementTests {

    private func identity(
        bundleID: String? = "com.example.app", team: String? = "ABCDE12345",
        version: String? = "2.0"
    ) -> ArtifactInspection.Identity {
        ArtifactInspection.Identity(
            signedIdentifier: bundleID, bundleIdentifier: bundleID, teamIdentifier: team,
            shortVersion: version, bundleVersion: nil, architectures: ["arm64"],
            minimumSystemVersion: nil, sparklePublicKey: nil)
    }

    private func remote(
        version: String? = "2.0", trust: InstallTrust = .developerID
    ) -> RemoteVersion {
        RemoteVersion(
            shortVersion: version, version: nil,
            downloadURL: URL(string: "https://example.com/App.dmg"),
            sourceName: "Vendor", vendorInstallerKind: .dmg, installTrust: trust)
    }

    @Test func theDownloadTheRecipeNamesIsClean() {
        #expect(InstallVerify.warnings(
            identity: identity(), remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    /// WorkBuddy CN from 5.5.4 on: same vendor, same Team, another bundle id.
    @Test func anotherBundleIDIsAWarning() {
        let warnings = InstallVerify.warnings(
            identity: identity(bundleID: "com.example.renamed"), remote: remote(),
            recipeBundleID: "com.example.app")
        #expect(warnings.count == 1)
        #expect(warnings.first?.hasPrefix("bundleIDMismatch:") == true)
    }

    /// The plist is what recipes are keyed by; the signed identifier only stands
    /// in when the plist has none.
    @Test func theSignedIdentifierStandsInForAMissingPlistID() {
        var signedOnly = identity()
        signedOnly.bundleIdentifier = nil
        signedOnly.signedIdentifier = "com.example.other"
        #expect(InstallVerify.warnings(
            identity: signedOnly, remote: remote(), recipeBundleID: "com.example.app").count == 1)

        var signedOtherwise = identity()
        signedOtherwise.signedIdentifier = "com.example.app.signed"
        #expect(InstallVerify.warnings(
            identity: signedOtherwise, remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    @Test func noTeamIsAWarningOnTheDeveloperIDRoute() {
        let warnings = InstallVerify.warnings(
            identity: identity(team: nil), remote: remote(), recipeBundleID: "com.example.app")
        #expect(warnings.map { $0.prefix(16) } == ["noTeamIdentifier"])
    }

    /// An ad-hoc build on the digest-only route has no Team by design.
    @Test func noTeamIsExpectedOnTheDigestOnlyRoute() {
        #expect(InstallVerify.warnings(
            identity: identity(team: nil), remote: remote(trust: .publishedDigestOnly),
            recipeBundleID: "com.example.app").isEmpty)
    }

    /// A package has no bundle to read; its Team is reported separately.
    @Test func aPackageHasNothingToJudge() {
        #expect(InstallVerify.warnings(
            identity: nil, remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    @Test func aDifferentVersionIsANoteNotAWarning() {
        #expect(InstallVerify.notes(identity: identity(version: "2.0.1"), remote: remote()).count == 1)
        #expect(InstallVerify.notes(identity: identity(), remote: remote()).isEmpty)
    }
}
