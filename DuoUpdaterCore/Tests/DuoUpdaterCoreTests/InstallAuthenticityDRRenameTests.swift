import Foundation
import Testing
@testable import DuoUpdaterCore

/// The two places gate 3b's requirement must name an identifier other than the
/// installed copy's: a `BundleIDMigration` rename, and a vendor installer stub
/// (whose id is a sibling of the app's). The signer must still be the installed
/// copy's. Fixtures from `SelfSignedCodeSigner`.
@Suite struct InstallAuthenticityDRRenameTests {

    /// Mutations: drop the bare-identifier alternative → the second line, red;
    /// replace without escaping → the third, red.
    @Test func theIdentifierClauseIsReaimedAndNothingElse() {
        #expect(SignatureVerifier.requirement(
            "identifier \"com.old.app\" and anchor apple generic and certificate leaf[subject.OU] = ABC",
            reaimedFrom: "com.old.app", to: "com.new.app")
            == "identifier \"com.new.app\" and anchor apple generic and certificate leaf[subject.OU] = ABC")
        #expect(SignatureVerifier.requirement(
            "identifier old and certificate root = H\"00\"", reaimedFrom: "old", to: "new.app")
            == "identifier \"new.app\" and certificate root = H\"00\"")
        #expect(SignatureVerifier.requirement(
            "identifier \"a\" or identifier \"ab\"", reaimedFrom: "a", to: "x\"y")
            == "identifier \"x\\\"y\" or identifier \"ab\"")
        // Never named: unchanged, so it has to be met as written.
        #expect(SignatureVerifier.requirement(
            "anchor apple", reaimedFrom: "com.old.app", to: "com.new.app") == "anchor apple")
    }

    /// A renamed build signed by the installed copy's certificate passes; the
    /// same rename signed by another certificate claiming the same Team does
    /// not. Mutation: drop the re-aim → the first, red (the installed DR names
    /// the old identifier).
    @Test func aRenameIsJudgedByTheSignerNotTheOldIdentifier() async throws {
        let dir = try DigestOnlyInstallTests.scratch("dr-rename")
        defer { try? FileManager.default.removeItem(at: dir) }
        let team = "ZZTEAM0002"
        let vendor = try await SelfSignedCodeSigner.mint(team: team, label: "vendor", in: dir)
        let other = try await SelfSignedCodeSigner.mint(team: team, label: "other", in: dir)
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("installed/App.app"), identifier: "zz.duo.old",
            team: team, with: vendor)
        let renamed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("renamed/App.app"), identifier: "zz.duo.new",
            team: team, with: vendor)
        let forged = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("forged/App.app"), identifier: "zz.duo.new",
            team: team, with: other)

        try await offCooperativePool {
            try SignatureVerifier.verifySignedLikeInstalledCopy(installedApp: installed, downloadedApp: renamed)
        }
        await #expect {
            try await offCooperativePool {
                try SignatureVerifier.verifySignedLikeInstalledCopy(installedApp: installed, downloadedApp: forged)
            }
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }
    }

    /// The vendor installer stub (`nestedArchivePath`): same Team string is not
    /// enough. Mutation: drop `verifySignedLikeInstalledCopy` from
    /// `stubSignedByTeam` → the forged stub passes, red.
    @Test func anInstallerStubMustBeSignedLikeTheInstalledCopy() async throws {
        let dir = try DigestOnlyInstallTests.scratch("dr-stub")
        defer { try? FileManager.default.removeItem(at: dir) }
        let team = "ZZTEAM0003"
        let vendor = try await SelfSignedCodeSigner.mint(team: team, label: "vendor", in: dir)
        let other = try await SelfSignedCodeSigner.mint(team: team, label: "other", in: dir)
        let installed = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("installed/App.app"), identifier: "zz.duo.app",
            team: team, with: vendor)
        let stub = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("stub/Installer.app"), identifier: "zz.duo.app.installer",
            team: team, with: vendor)
        let forgedStub = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("forged/Installer.app"), identifier: "zz.duo.app.installer",
            team: team, with: other)
        let vet = VendorInstaller.stubSignedByTeam(of: installed)

        try await offCooperativePool { try vet(stub) }
        await #expect {
            try await offCooperativePool { try vet(forgedStub) }
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }
    }
}
