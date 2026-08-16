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

    /// A bundle whose executable is a real (if minimal) Mach-O built for exactly
    /// `cputype`. 32 bytes of header is all `executableArchitectures` reads, so
    /// this needs no compiler and no app installed on the machine — the test
    /// then holds identically on a bare checkout, on CI, and on either
    /// architecture.
    private func bundle(cputype: Int32, subtype: Int32, in dir: URL) throws -> URL {
        var header = Data()
        func word(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        word(0xfeed_facf)                        // MH_MAGIC_64
        word(UInt32(bitPattern: cputype))
        word(UInt32(bitPattern: subtype))
        word(2)                                  // MH_EXECUTE
        word(0); word(0); word(0x0020_0085); word(0)   // ncmds/sizeofcmds/flags/reserved

        let app = dir.appendingPathComponent("Fixture-\(cputype).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try header.write(to: macOS.appendingPathComponent("fixture"))
        let info: [String: String] = [
            "CFBundleExecutable": "fixture",
            "CFBundleIdentifier": "test.fixture.\(cputype)",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test func readsRealMachOSlicesAndNamesBothSidesWhenRefusing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let armApp = try bundle(cputype: 0x0100_000c, subtype: 0, in: dir)
        let intelApp = try bundle(cputype: 0x0100_0007, subtype: 3, in: dir)

        // The slices come back out of the Mach-O, not out of the filename.
        #expect(SignatureVerifier.executableArchitectures(ofAppAt: armApp) == [arm])
        #expect(SignatureVerifier.executableArchitectures(ofAppAt: intelApp) == [intel])

        // Each runs on its own machine…
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: armApp, host: .arm64, canRunIntel: false)
        }
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: intelApp, host: .x86_64, canRunIntel: false)
        }
        // …and an Intel build still runs on Apple silicon while translation lasts.
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: intelApp, host: .arm64, canRunIntel: true)
        }

        // The refusal names the build and the machine, so the log says which way
        // round the mismatch went.
        do {
            try SignatureVerifier.verifyRunnableArchitecture(
                appAt: armApp, host: .x86_64, canRunIntel: true)
            Issue.record("an arm64-only bundle must not pass the gate on Intel")
        } catch let error as SignatureVerifier.VerifyError {
            let text = error.errorDescription ?? ""
            #expect(text.contains("built for arm64"))
            #expect(text.contains("Mac runs x86_64"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
