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

/// Gate 5b: a build that DOES launch (Gate 5 passes it) must still be refused
/// if it drops the arm64 slice the INSTALLED bundle already has — Gate 5 alone
/// answers "can this Mac run it", not "is this worse than what's there", so an
/// Intel-only download quietly downgrades a native install to translated on
/// every future check too. See issue #196.
struct ArchitectureDowngradeGateTests {

    private let arm = NSBundleExecutableArchitectureARM64
    private let intel = NSBundleExecutableArchitectureX86_64

    // MARK: `isArchitectureDowngrade` — the six boundaries from #196

    @Test func universalToArmOnlyIsNormalThinningNotADowngrade() {
        // Installed universal → downloaded arm64-only: the download still runs
        // natively. Not a downgrade.
        #expect(!SignatureVerifier.isArchitectureDowngrade(
            installed: [arm, intel], downloaded: [arm]))
    }

    @Test func armOnlyToUniversalIsAllowed() {
        #expect(!SignatureVerifier.isArchitectureDowngrade(
            installed: [arm], downloaded: [arm, intel]))
    }

    @Test func armOnlyToIntelOnlyIsTheOneNewRejection() {
        #expect(SignatureVerifier.isArchitectureDowngrade(
            installed: [arm], downloaded: [intel]))
    }

    @Test func universalToIntelOnlyIsAlsoADowngrade() {
        // Not one of the six enumerated boundaries, but the same rule: a
        // universal install losing its arm64 slice is exactly as much a
        // downgrade as an arm64-only one losing it.
        #expect(SignatureVerifier.isArchitectureDowngrade(
            installed: [arm, intel], downloaded: [intel]))
    }

    @Test func unreadableInstalledArchitectureIsAllowedThrough() {
        // Same shape as Gate 5's own fail-open: an unreadable header must not
        // start refusing swaps that install fine today, and this predicate
        // proves a downgrade, not the absence of one.
        #expect(!SignatureVerifier.isArchitectureDowngrade(installed: [], downloaded: [intel]))
    }

    @Test func unreadableDownloadedArchitectureIsAllowedThrough() {
        #expect(!SignatureVerifier.isArchitectureDowngrade(installed: [arm], downloaded: []))
    }

    @Test func bothSidesUnreadableIsAllowedThrough() {
        #expect(!SignatureVerifier.isArchitectureDowngrade(installed: [], downloaded: []))
    }

    @Test func intelOnlyToIntelOnlyIsNotADowngrade() {
        // Nothing arm64 was ever there to lose.
        #expect(!SignatureVerifier.isArchitectureDowngrade(installed: [intel], downloaded: [intel]))
    }

    // MARK: `verifyNoArchitectureDowngrade` — real Mach-O fixtures, through the throwing gate

    /// A bundle whose executable is a real (if minimal) Mach-O built for exactly
    /// the given cputypes — one slice per type, so a "universal" fixture is one
    /// call with two types. Mirrors `ArchitectureGateTests.bundle(cputype:subtype:in:)`
    /// but this gate needs to construct BOTH an installed and a downloaded
    /// bundle per test, so it takes a set of slices instead of one.
    private func bundle(cputypes: [Int32], in dir: URL, name: String) throws -> URL {
        let app = dir.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        if cputypes.count <= 1 {
            var header = Data()
            func word(_ value: UInt32) {
                withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
            }
            word(0xfeed_facf)                                     // MH_MAGIC_64
            word(UInt32(bitPattern: cputypes.first ?? 0x0100_000c))
            word(0)                                                // subtype
            word(2)                                                // MH_EXECUTE
            word(0); word(0); word(0x0020_0085); word(0)
            try header.write(to: macOS.appendingPathComponent(name))
        } else {
            // A fat (universal) binary: FAT_MAGIC header followed by one
            // `fat_arch` entry per slice, each pointing at a trivial Mach-O.
            var slices: [Data] = []
            for cputype in cputypes {
                var header = Data()
                func word(_ value: UInt32) {
                    withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
                }
                word(0xfeed_facf)
                word(UInt32(bitPattern: cputype))
                word(0)
                word(2)
                word(0); word(0); word(0x0020_0085); word(0)
                slices.append(header)
            }
            var fat = Data()
            func bigWord(_ value: UInt32, into data: inout Data) {
                withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
            }
            bigWord(0xcafe_babe, into: &fat)                       // FAT_MAGIC
            bigWord(UInt32(cputypes.count), into: &fat)
            var offset = UInt32(fat.count) + UInt32(cputypes.count) * 20
            for (index, cputype) in cputypes.enumerated() {
                bigWord(UInt32(bitPattern: cputype), into: &fat)
                bigWord(0, into: &fat)                             // cpusubtype
                bigWord(offset, into: &fat)
                bigWord(UInt32(slices[index].count), into: &fat)
                bigWord(0, into: &fat)                             // align
                offset += UInt32(slices[index].count)
            }
            for slice in slices { fat.append(slice) }
            try fat.write(to: macOS.appendingPathComponent(name))
        }

        let info: [String: String] = [
            "CFBundleExecutable": name,
            "CFBundleIdentifier": "test.downgrade.\(name)",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    @Test func throwingGateRefusesArmInstalledIntelOnlyDownload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-downgrade-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let installed = try bundle(cputypes: [0x0100_000c], in: dir, name: "installed")
        let downloaded = try bundle(cputypes: [0x0100_0007], in: dir, name: "downloaded")

        // The real Mach-O read confirms the fixtures are shaped as intended.
        #expect(SignatureVerifier.executableArchitectures(ofAppAt: installed) == [arm])
        #expect(SignatureVerifier.executableArchitectures(ofAppAt: downloaded) == [intel])

        do {
            try SignatureVerifier.verifyNoArchitectureDowngrade(
                installedApp: installed, downloadedApp: downloaded, host: .arm64)
            Issue.record("an arm64 install must not be swapped for an x86_64-only download")
        } catch let error as SignatureVerifier.VerifyError {
            let text = error.errorDescription ?? ""
            // The wording must not read like Gate 5's "cannot launch" — this
            // build DOES launch, just translated, so a user reading the two
            // messages side by side must be able to tell them apart.
            #expect(text.contains("arm64"))
            #expect(text.contains("x86_64"))
            #expect(!text.contains("cannot launch"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func throwingGateAllowsUniversalDownloadOverArmInstall() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-downgrade-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let installed = try bundle(cputypes: [0x0100_000c], in: dir, name: "installed")
        let downloaded = try bundle(
            cputypes: [0x0100_000c, 0x0100_0007], in: dir, name: "downloaded")
        #expect(SignatureVerifier.executableArchitectures(ofAppAt: downloaded) == [arm, intel])

        #expect(throws: Never.self) {
            try SignatureVerifier.verifyNoArchitectureDowngrade(
                installedApp: installed, downloadedApp: downloaded, host: .arm64)
        }
    }

    @Test func throwingGateDoesNotApplyOnAnIntelHost() throws {
        // No Intel host ever ships this product (arm64-only, `App/project.yml`),
        // but the gate still states the boundary explicitly rather than assume
        // it — an Intel Mac never had an arm64 slice to lose in the first place.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-downgrade-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let installed = try bundle(cputypes: [0x0100_000c], in: dir, name: "installed")
        let downloaded = try bundle(cputypes: [0x0100_0007], in: dir, name: "downloaded")

        #expect(throws: Never.self) {
            try SignatureVerifier.verifyNoArchitectureDowngrade(
                installedApp: installed, downloadedApp: downloaded, host: .x86_64)
        }
    }
}
