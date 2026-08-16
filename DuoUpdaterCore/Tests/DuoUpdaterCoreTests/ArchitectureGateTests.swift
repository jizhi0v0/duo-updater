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
        // Reads a real Mach-O so the parsing path is exercised, not just the pure
        // decision — and reads the test runner itself rather than some app that
        // happens to be installed, so this holds on a bare checkout or CI box.
        let runner = Bundle.main.bundleURL
        let archs = SignatureVerifier.executableArchitectures(ofAppAt: runner)
        try #require(!archs.isEmpty, "should read at least one slice from the test runner")

        // It passes on the machine it was built for…
        let host = HostArch.current
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: runner, host: host, canRunIntel: false)
        }

        // …and the failure names both sides. A universal runner can run
        // anywhere, so there is no "other" host to refuse it on; only a
        // single-slice build reaches the throw.
        let other: HostArch = host == .arm64 ? .x86_64 : .arm64
        guard archs.count == 1 else { return }
        do {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: runner, host: other, canRunIntel: true)
            Issue.record("a single-architecture bundle must not pass the gate on the other host")
        } catch let error as SignatureVerifier.VerifyError {
            let text = error.errorDescription ?? ""
            #expect(text.contains("arm64"))
            #expect(text.contains("x86_64"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
