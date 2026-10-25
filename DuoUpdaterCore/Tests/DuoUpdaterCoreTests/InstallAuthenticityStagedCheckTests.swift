import Foundation
import Testing
@testable import DuoUpdaterCore

/// PR #1661 review round 1. What the privileged shell re-checks its staged copy
/// against is fixed at the gate:
///
/// - A shell given no `stagedCheck` adds no check, so a faithful backup of an
///   app that writes inside its own bundle (signature-invalid by nature, see
///   `BackupManifest`) is put back. A restore now passes the resource-blind
///   form, which lets the same backup through (`RestoreRootRecheckTests`).
/// - An install's check comes from `verifyInstallArtifact`; for an ad-hoc
///   installed copy it is the cdhash gate 2 read off the code it validated, so a
///   build put in the scratch copy's place after the gate is refused — signed or
///   not — however late the shell is built.
@Suite struct InstallAuthenticityStagedCheckTests {

    /// Mutation: have `replace`/`placeBack` derive a requirement when given none
    /// (what 228699a6 did) → no codesign-free shell, and the restore fails.
    @Test func aSignatureInvalidBackupIsRestoredByThePrivilegedShells() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("restore-invalid")
        defer { try? fm.removeItem(at: dir) }
        let team = "ZZTEAM0004", identifier = "zz.duoupdater.stateful"
        let vendor = try await SelfSignedCodeSigner.mint(team: team, label: "vendor", in: dir)
        let target = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("ZZStateful.app"), identifier: identifier, build: "2",
            team: team, with: vendor)
        let backup = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("backup/ZZStateful.app"), identifier: identifier, build: "1",
            team: team, with: vendor)
        // State written inside the bundle: both copies now fail `--strict`.
        for app in [target, backup] {
            try Data("state".utf8).write(to: app.appendingPathComponent("Contents/Resources/r.txt"))
        }

        let replace = InPlaceSwap.privilegedReplacementShell(newApp: backup, target: target)
        #expect(!replace.contains("codesign"))
        #expect(try await SelfSignedCodeSigner.shell(replace) == 0)
        #expect(SignatureVerifier.infoPlist(of: target)["CFBundleVersion"] as? String == "1")

        let gone = dir.appendingPathComponent("ZZGone.app")
        let place = InPlaceSwap.privilegedPlacementShell(newApp: backup, target: gone)
        #expect(!place.contains("codesign"))
        #expect(try await SelfSignedCodeSigner.shell(place) == 0)
        #expect(fm.fileExists(atPath: gone.appendingPathComponent("Contents/Info.plist").path))
    }

    /// The gate runs, then the scratch copy is replaced — by another ad-hoc build,
    /// then by an unsigned one — and only then is the shell built, as production
    /// builds it at swap time. Both are refused, because the cdhash was fixed at
    /// the gate. Mutation: read the cdhash off `downloaded`'s path in
    /// `stagedCopyRequirement` at swap time → the substitutes land, red.
    @Test func aBuildSwappedInAfterTheGateIsRefusedByTheCdhashCapturedAtTheGate() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("gate-cdhash")
        defer { try? fm.removeItem(at: dir) }
        let target = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("ZZFixture.app"), version: "1.0.0", build: "1",
            signing: .sealed(identifier: nil))
        let source = dir.appendingPathComponent("src/ZZFixture.app")
        try await DigestOnlyInstallTests.makeApp(at: source, build: "2", signing: .sealed(identifier: nil))
        let check = try #require(
            await InstallAuthenticityDRTests.digestGate(source, over: target, in: dir))
        #expect(check.text == nil && check.pinnedCdhash != nil, "an ad-hoc install takes the cdhash form")

        for substitute in [DigestOnlyInstallTests.Signing.sealed(identifier: nil), .unsigned] {
            try fm.removeItem(at: source)
            try await DigestOnlyInstallTests.makeApp(at: source, build: "9", signing: substitute)
            let shell = InPlaceSwap.privilegedReplacementShell(
                newApp: source, target: target, requirement: check)
            #expect(try await SelfSignedCodeSigner.shell(shell) != 0)
            #expect(SignatureVerifier.infoPlist(of: target)["CFBundleVersion"] as? String == "1")
        }
    }

    /// A universal ad-hoc build that was gated lands. Its cdhash names one
    /// slice, and `codesign --verify` checks every slice unless told otherwise,
    /// so a `cdhash H"…"` requirement refused every universal build — measured
    /// on the Developer ID form with Rectangle 2.0.4 (2026-10-25).
    ///
    /// Mutation: give the ad-hoc form back `text: "cdhash H\"…\""` → build 2
    /// does not land.
    @Test func aUniversalAdHocBuildThatWasGatedLands() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("gate-universal")
        defer { try? fm.removeItem(at: dir) }
        let target = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("ZZFixture.app"), version: "1.0.0", build: "1",
            signing: .sealed(identifier: nil))
        let source = dir.appendingPathComponent("src/ZZFixture.app")
        try await DigestOnlyInstallTests.makeApp(at: source, build: "2", signing: .unsigned)
        let main = dir.appendingPathComponent("main.c")
        try Data("int main(void) { return 0; }\n".utf8).write(to: main)
        try await SelfSignedCodeSigner.run([
            "/usr/bin/xcrun", "clang", "-arch", "arm64", "-arch", "x86_64", "-o",
            source.appendingPathComponent("Contents/MacOS/zz").path, main.path])
        try await SelfSignedCodeSigner.run(["/usr/bin/codesign", "--force", "--sign", "-", source.path])
        let check = try #require(
            await InstallAuthenticityDRTests.digestGate(source, over: target, in: dir))
        let shell = InPlaceSwap.privilegedReplacementShell(newApp: source, target: target, requirement: check)

        #expect(try await SelfSignedCodeSigner.shell(shell) == 0)
        #expect(SignatureVerifier.infoPlist(of: target)["CFBundleVersion"] as? String == "2")
    }
}
