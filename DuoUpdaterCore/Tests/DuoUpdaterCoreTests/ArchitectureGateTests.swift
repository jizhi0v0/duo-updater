import Testing
import Foundation
@testable import DuoUpdaterCore

/// Gate 5: the downloaded bundle must be a build this Mac can launch.
///
/// Which asset gets downloaded is decided by FILENAME, and filenames lie — three
/// real registry cases (`Goose.zip`, `anki-<ver>-mac-apple.dmg`,
/// `MarkEdit-<ver>-apple-silicon.dmg`) were arm64-only builds whose names carried
/// no architecture marker at all. This gate reads the real Mach-O slices after the
/// download, so a mis-named artifact is refused rather than swapped in.
struct ArchitectureGateTests {

    private let arm = NSBundleExecutableArchitectureARM64
    private let intel = NSBundleExecutableArchitectureX86_64

    @Test func nativeBuildsRunOnTheirOwnMachine() {
        #expect(SignatureVerifier.canRun(architectures: [arm], on: .arm64, canRunIntel: false))
        #expect(SignatureVerifier.canRun(architectures: [intel], on: .x86_64, canRunIntel: false))
    }

    @Test func universalBuildsRunEverywhere() {
        #expect(SignatureVerifier.canRun(
            architectures: [arm, intel], on: .arm64, canRunIntel: false))
        #expect(SignatureVerifier.canRun(
            architectures: [arm, intel], on: .x86_64, canRunIntel: false))
    }

    @Test func armOnlyBuildIsNeverRunnableOnIntel() {
        // No reverse translation has ever existed, so `canRunIntel` cannot rescue
        // this — the flag is about running Intel code on Apple silicon.
        #expect(!SignatureVerifier.canRun(
            architectures: [arm], on: .x86_64, canRunIntel: true))
    }

    @Test func intelOnlyBuildDependsOnTranslation() {
        // While Rosetta covers apps…
        #expect(SignatureVerifier.canRun(
            architectures: [intel], on: .arm64, canRunIntel: true))
        // …and after it stops (macOS 28), or where it was never installed.
        #expect(!SignatureVerifier.canRun(
            architectures: [intel], on: .arm64, canRunIntel: false))
    }

    @Test func unreadableArchitectureIsAllowedThrough() {
        // A bundle whose executable isn't a Mach-O (a script, say) reads as empty.
        // The gate proves a build is WRONG; it is not a proof of correctness, so an
        // unreadable header must not start refusing updates that install fine today.
        #expect(SignatureVerifier.canRun(architectures: [], on: .arm64, canRunIntel: false))
        #expect(SignatureVerifier.canRun(architectures: [], on: .x86_64, canRunIntel: false))
    }

    @Test func verifyThrowsWithBothArchitecturesNamed() throws {
        // Uses a real bundle on this machine so the Mach-O reading path is
        // exercised, not just the pure decision.
        let duo = URL(fileURLWithPath: "/Applications/DuoUpdater.app")
        try #require(FileManager.default.fileExists(atPath: duo.path))
        let archs = SignatureVerifier.executableArchitectures(ofAppAt: duo)
        #expect(!archs.isEmpty, "should read at least one slice from a real bundle")

        // It passes on the machine it was built for…
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: duo, host: .arm64, canRunIntel: false)
        }
        // …and is refused on the other one, with the failure naming both sides.
        do {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: duo, host: .x86_64, canRunIntel: true)
            Issue.record("an arm64-only bundle must not pass the gate on Intel")
        } catch let error as SignatureVerifier.VerifyError {
            let text = error.errorDescription ?? ""
            #expect(text.contains("arm64"))
            #expect(text.contains("x86_64"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
