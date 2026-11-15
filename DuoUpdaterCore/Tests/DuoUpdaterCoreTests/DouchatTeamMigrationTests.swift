import CryptoKit
import Foundation
import Security
import Testing
@testable import DuoUpdaterCore

/// Douchat 0.1.28 is signed by JU9K7W6T6W, but its designated requirement
/// already authorizes 8PL52G56V9. Exercise that signed handover with in-memory
/// test certificates; no installed app, keychain identity or network is needed.
struct DouchatTeamMigrationTests {
    private static let bundleID = "ai.thinkany.douchat"
    private static let oldTeam = "JU9K7W6T6W"
    private static let newTeam = "8PL52G56V9"

    private func certificateRequirement(_ identity: SelfSignedCodeSigner.Identity) throws -> String {
        var certificate: SecCertificate?
        try #require(SecIdentityCopyCertificate(identity.ref, &certificate) == errSecSuccess)
        let data = SecCertificateCopyData(try #require(certificate)) as Data
        let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "certificate leaf = H\"\(hash)\""
    }

    @Test func theAuthorizedHandoverPassesTheInstallGatesAndStagedSwap() async throws {
        let dir = try DigestOnlyInstallTests.scratch("douchat-handover")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try await SelfSignedCodeSigner.mint(team: Self.oldTeam, label: "old", in: dir)
        let new = try await SelfSignedCodeSigner.mint(team: Self.newTeam, label: "new", in: dir)
        let handover = "identifier \"\(Self.bundleID)\" and ("
            + (try certificateRequirement(old)) + " or " + (try certificateRequirement(new)) + ")"
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("Douchat.app"), identifier: Self.bundleID, build: "28",
            team: Self.oldTeam, with: old, designatedRequirement: handover)
        let downloaded = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("download/Douchat.app"), identifier: Self.bundleID, build: "29",
            team: Self.newTeam, with: new)

        // The transition is granted by the installed signature, not by a Team
        // string in the download. Prove that premise before running the gates.
        try await offCooperativePool {
            #expect(try SignatureVerifier.teamIdentifier(at: installed) == Self.oldTeam)
            #expect(try SignatureVerifier.teamIdentifier(at: downloaded) == Self.newTeam)
            try SignatureVerifier.verifySatisfiesDesignatedRequirement(
                installedApp: installed, downloadedApp: downloaded)
        }
        let check = try #require(await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: downloaded, installedApp: installed))
        let originalRequirement = try await offCooperativePool {
            try SignatureVerifier.installedSignerRequirement(
                installedApp: installed, downloadedApp: downloaded)
        }
        #expect(check.text == originalRequirement)
        #expect(check.pinnedCdhash != nil)
        let shell = InPlaceSwap.privilegedReplacementShell(
            newApp: downloaded, target: installed, requirement: check)
        #expect(try await SelfSignedCodeSigner.shell(shell) == 0)
        #expect(SignatureVerifier.infoPlist(of: installed)["CFBundleVersion"] as? String == "29")
    }

    /// This calls the Team gate itself: the later signer gate must not conceal
    /// a missing authorization check in the migration exception.
    @Test func aNewTeamClaimWithoutTheInstalledSignersAuthorizationIsRefused() async throws {
        let dir = try DigestOnlyInstallTests.scratch("douchat-no-grant")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try await SelfSignedCodeSigner.mint(team: Self.oldTeam, label: "old", in: dir)
        let new = try await SelfSignedCodeSigner.mint(team: Self.newTeam, label: "new", in: dir)
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("installed/Douchat.app"), identifier: Self.bundleID,
            team: Self.oldTeam, with: old)
        let downloaded = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("download/Douchat.app"), identifier: Self.bundleID,
            team: Self.newTeam, with: new)

        await #expect {
            try await offCooperativePool {
                try SignatureVerifier.verifyTeamIdentifierMatch(
                    installedApp: installed, downloadedApp: downloaded)
            }
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }
    }

    /// A permissive DR deliberately removes that gate as a reason to refuse.
    /// Each case must still fail the exact product and forward-Team constraints.
    @Test(arguments: [
        (bundleID, bundleID, newTeam, oldTeam),
        (bundleID, bundleID, oldTeam, "OTHERTEAM1"),
        (bundleID, bundleID, "OTHERTEAM1", newTeam),
        ("ai.thinkany.other", "ai.thinkany.other", oldTeam, newTeam),
        ("ai.thinkany.other", bundleID, oldTeam, newTeam),
        (bundleID, "ai.thinkany.other", oldTeam, newTeam),
    ])
    func theHandoverDoesNotAuthorizeOtherTeamsProductsOrTheReverseDirection(
        installedID: String, downloadedID: String, installedTeam: String, downloadedTeam: String
    ) async throws {
        let dir = try DigestOnlyInstallTests.scratch("douchat-scope")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try await SelfSignedCodeSigner.mint(team: installedTeam, label: "old", in: dir)
        let new = try await SelfSignedCodeSigner.mint(team: downloadedTeam, label: "new", in: dir)
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("installed/App.app"), identifier: installedID,
            team: installedTeam, with: old, designatedRequirement: "always")
        let downloaded = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("download/App.app"), identifier: downloadedID,
            team: downloadedTeam, with: new)

        try await offCooperativePool {
            try SignatureVerifier.verifyCodeSignature(appAt: downloaded)
            try SignatureVerifier.verifySatisfiesDesignatedRequirement(
                installedApp: installed, downloadedApp: downloaded)
        }
        await #expect {
            try await offCooperativePool {
                try SignatureVerifier.verifyTeamIdentifierMatch(
                    installedApp: installed, downloadedApp: downloaded)
            }
        } throws: {
            if case SignatureVerifier.VerifyError.teamIdentifierMismatch = $0 { return true }
            return false
        }
    }

    @Test(arguments: [oldTeam, newTeam])
    func ordinaryUpdatesKeepWorkingForEachTeam(team: String) async throws {
        let dir = try DigestOnlyInstallTests.scratch("douchat-same-team")
        defer { try? FileManager.default.removeItem(at: dir) }
        let identity = try await SelfSignedCodeSigner.mint(team: team, label: "vendor", in: dir)
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("installed/Douchat.app"), identifier: Self.bundleID,
            team: team, with: identity)
        let downloaded = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("download/Douchat.app"), identifier: Self.bundleID,
            team: team, with: identity)
        _ = try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: downloaded, installedApp: installed)
    }
}
