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

/// How a `duo verify-install` item reaches `Baseline` and `Reconcile`.
@Suite struct InstallVerifyFindingTests {

    private func item(
        _ status: InstallVerify.Status, stage: ArtifactInspection.Stage? = nil,
        warnings: [String] = []
    ) -> InstallVerify.Item {
        var item = InstallVerify.Item(
            recipeID: "vendor:com.example.app:stable", registry: "vendor",
            bundleID: "com.example.app", probeHost: "example.com", status: status)
        item.stage = stage
        item.detail = stage == nil ? nil : "it went wrong"
        item.warnings = warnings
        item.url = "https://cdn.example.com/App.dmg"
        item.version = "1.0"
        return item
    }

    /// Its own namespace, so it never shares a streak or an issue with the
    /// sweep's finding for the same recipe.
    @Test func idsAreNamespaced() {
        let finding = InstallVerify.finding(item(.ok))
        #expect(finding.recipeID == "install:vendor:com.example.app:stable")
        #expect(finding.registry == .install)
        #expect(finding.endpointHost == "cdn.example.com")
    }

    @Test func statusesMapToWhatTheBaselineCounts() {
        #expect(InstallVerify.finding(item(.ok)).status == .ok)
        #expect(InstallVerify.finding(item(.warn, warnings: ["identityChanged: …"])).status == .warn)
        // A dropped transfer is the network until a run of them says otherwise.
        #expect(InstallVerify.finding(item(.failed, stage: .download)).status == .infra)
        // A refusal is the link, not the network; a 5xx, 408 or 429 may pass.
        for (status, expected) in [(404, FindingStatus.broken), (403, .broken), (410, .broken),
                                   (500, .infra), (503, .infra), (408, .infra), (429, .infra)] {
            var refused = item(.failed, stage: .download)
            refused.httpStatus = status
            #expect(InstallVerify.finding(refused).status == expected, "HTTP \(status)")
        }
        #expect(InstallVerify.finding(item(.failed, stage: .checksum)).status == .broken)
        #expect(InstallVerify.finding(item(.failed, stage: .unpack)).status == .broken)
        #expect(InstallVerify.finding(item(.failed, stage: .signature)).status == .broken)
        // Resolving the installer is the sweep's finding to file.
        #expect(InstallVerify.finding(item(.unresolved)).status == .skipped)
        #expect(InstallVerify.finding(item(.skipped)).status == .skipped)
    }

    @Test func aFailureCarriesItsStage() {
        let finding = InstallVerify.finding(item(.failed, stage: .checksum))
        #expect(finding.failureKind == "install.checksum")
        #expect(finding.failureDetail == "it went wrong")
    }

    /// No version: the baseline would otherwise repeat the sweep's own
    /// "went backwards" check under a second id.
    @Test func noVersionReachesTheBaseline() {
        #expect(InstallVerify.finding(item(.ok)).version == nil)
    }

    /// An installer issue reproduces with the command that found it.
    @Test func anInstallerIssueSaysHowToReproduceIt() {
        let finding = InstallVerify.finding(item(.failed, stage: .checksum))
        #expect(Reconcile.reproduce(finding, samples: true).contains("duo verify-install --only com.example.app"))
        let body = Reconcile.body(for: finding, entry: Baseline.Entry())
        #expect(body.contains("`duo verify-install`"))
        #expect(!body.contains("duo verify --install"))
    }
}
