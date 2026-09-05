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

/// PROOF that Gate 5b is actually wired into the two installers' real `apply()`
/// — not just that the predicate is correct in isolation (that's what the two
/// suites above already cover). Deleting the `verifyNoArchitectureDowngrade`
/// call from `VendorInstaller`/`SparkleInstaller` must turn these tests red;
/// nothing else in this file can, because they never call `isArchitectureDowngrade`
/// or `verifyNoArchitectureDowngrade` directly — only the installers' public
/// `apply()`. (A gate no code path calls is worse than no gate at all: the next
/// reader trusts `SignatureVerifier`'s doc comment listing it. Issue #196.)
///
/// The trick is a REAL, already-installed, Developer-ID-signed universal
/// (`x86_64 arm64`) app found on this machine, copied twice:
///  - "installed" — copied as-is (still universal), standing in for
///    `result.app.path`.
///  - "downloaded" — a second copy, `lipo -thin x86_64`'d, then re-zipped the
///    same way `ArchiveExtractor` unpacks a real download (`ditto -c/-x -k`).
///
/// `lipo -thin` only EXTRACTS an existing slice's bytes; it does not touch
/// them. Confirmed empirically on a real fixture (`NotchBadge.app`,
/// 2026-09-01): `codesign --verify --deep --strict` still passes on the
/// thinned, zip-round-tripped copy, with the SAME Team ID and bundle
/// identifier as the untouched original. That is what lets this call all the
/// way into the real `apply()` and past Gates 2–4 without forging a
/// code-signing identity of our own — a genuine architecture downgrade is the
/// ONLY thing left for Gate 5b to catch.
struct ArchitectureDowngradeWiringTests {

    private static let arm = NSBundleExecutableArchitectureARM64
    private static let intel = NSBundleExecutableArchitectureX86_64

    /// Runs `argv[0]` with the rest as arguments; throws on a non-zero exit.
    private static func run(_ argv: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        if let directory { process.currentDirectoryURL = directory }
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ArchitectureDowngradeWiringTests", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: errData, as: UTF8.self)])
        }
    }

    /// A real installed universal (`arm64 + x86_64`) app, signed by a team and
    /// small enough to copy and zip twice per test — or nil, which is a failure.
    ///
    /// Searched in TWO passes, because a top-level `/Applications` entry is not the
    /// only shape a complete signed bundle comes in, and on a hosted runner it is
    /// not a shape that exists at all. Measured on `macos-latest` 2026-09-04 (run
    /// 33930802607): zero candidates, so both tests below passed having executed
    /// none of the code they exist for — #339. The image is not short of universal
    /// apps; Chrome, Edge and Firefox all ship one. They are simply hundreds of
    /// megabytes, and the size cap — added the day before to stop a 593-second
    /// Xcode copy — rejected every one of them.
    ///
    /// A vendor's nested helper is the same thing an order of magnitude smaller: a
    /// separately signed, complete bundle carrying its parent's Team ID. Measured
    /// here 2026-09-05, `Google Chrome Helper.app` is 184 KB, `[x86_64 arm64]`,
    /// team `EQHXZ8M8AV`, and drives both tests to Gate 5b's refusal in 0.657 s.
    /// So pass 1 takes a small top-level app when one exists (the author's Mac),
    /// and pass 2 descends into exactly the apps the cap rejected (the runner).
    private static func findUniversalFixture() -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil
        ) else {
            Issue.record("ARCH DOWNGRADE FIXTURE: /Applications could not be listed.")
            return nil
        }
        // Resolved before anything else, because /Applications can hold SYMLINKS to
        // apps and every step below behaves differently on one. Measured on a
        // GitHub runner 2026-09-05: `/Applications/Xcode_26.2.0.app` is a link to
        // `/Applications/Xcode_26.2.app`, and that single fact produced every
        // symptom in #336 — `enumerator` does not descend a link, so a 20 GB Xcode
        // passed a 200 MB cap with a measured size of zero; `cp -R` copies the link
        // rather than the tree, so the "scratch copy" pointed back at the original;
        // and `ditto -c -k` followed it, which is where 593 seconds went.
        //
        // Sorted so two runs on one machine choose the SAME fixture. Directory
        // order is not defined, and a suite that silently swaps its fixture between
        // runs turns any fixture-shaped failure into a flake.
        let candidates = entries
            .filter { $0.pathExtension == "app" }
            .map { $0.resolvingSymlinksInPath() }
            .sorted { $0.path < $1.path }

        // Pass 1 — a top-level app already under the copy budget.
        var rejected: [URL] = []
        for app in candidates {
            guard bundleIsUnder(sizeCap, at: app), isUsableFixture(app) else {
                rejected.append(app)
                continue
            }
            print("ARCH DOWNGRADE FIXTURE: \(app.lastPathComponent)")
            return app
        }

        // Pass 2 — descend into EVERYTHING pass 1 turned down, not only what the
        // cap turned down. The narrower version was written first, on the reasoning
        // that a small app rejected for its architecture or its signature has
        // nothing usable inside it either, since a helper inherits its parent's
        // team and architecture set. That reasoning is unmeasured, and it is the
        // same shape of "throughout" claim this repository keeps getting wrong:
        // nothing stops an arm64-only app from bundling a universal Sparkle
        // updater, and one wrong guess here brings back the silent-hole this whole
        // change exists to close. The small ones are under the cap by definition,
        // so walking them costs almost nothing, and the budget bounds the rest.
        var budget = nestedSearchBudget
        for host in rejected {
            guard let nested = firstUsableNestedFixture(in: host, budget: &budget)
            else { continue }
            print("""
                ARCH DOWNGRADE FIXTURE: \(nested.lastPathComponent) \
                (nested in \(host.lastPathComponent))
                """)
            return nested
        }

        // FAILS, where it used to print and return nil. Both callers treat nil as
        // "nothing to prove with" and return, so that branch was the two tests
        // passing while executing none of the code they exist for — and a green
        // run is exactly what a fixture-shaped hole looks like from outside. The
        // printed warning was not enough: it went by on 2026-09-04 and #339 was
        // filed off a log nobody would have read otherwise.
        //
        // The honest cost: the fixture now comes from someone else's disk image,
        // and `macos-latest` will eventually move to a newer one. If that image
        // ships no universal team-signed bundle at any depth, this turns red for a
        // reason unrelated to the code under test. That is the trade — a red that
        // names its own cause, over a green that means nothing. The message says
        // which pass came up empty so the next person does not have to rediscover
        // this comment.
        Issue.record("""
            ARCH DOWNGRADE FIXTURE: none found. No universal, team-signed bundle \
            under \(sizeCap / 1024 / 1024) MB among \(candidates.count) apps in \
            /Applications, and none nested inside any of the \(rejected.count) \
            turned down (\(nestedSearchBudget - budget) entries walked\
            \(budget <= 0 ? ", BUDGET EXHAUSTED — raise nestedSearchBudget" : "")). \
            The two downgrade-wiring tests can prove nothing without one, so this \
            fails rather than passing silently — see #339.
            """)
        return nil
    }

    /// Universal AND signed by a real team — both halves are requirements of the
    /// gate under test, not conveniences.
    ///
    /// Team ID matters because Gate 3 runs BEFORE the gate these tests aim at, so a
    /// teamless fixture is refused upstream and the tests fail naming the wrong
    /// reason (measured 2026-09-05: `noTeamIdentifier(which: "installed")` from
    /// both installers, on the hermetic ad-hoc fixture #339 proposed). It is also
    /// the only thing keeping Safari out: `/Applications/Safari.app` is a symlink
    /// into `/System/Volumes/Preboot/Cryptexes/App/…`, and the real bundle behind
    /// it reads as `[x86_64, arm64]` and sits under the cap — it clears every other
    /// filter here and is excluded solely by answering nil for a team.
    private static func isUsableFixture(_ app: URL) -> Bool {
        SignatureVerifier.executableArchitectures(ofAppAt: app) == [arm, intel]
            && (try? SignatureVerifier.teamIdentifier(at: app)) != nil
    }

    /// The first nested `.app` inside `host` that would serve as a fixture,
    /// charging what it walks against a shared `budget`.
    ///
    /// FIRST, not smallest: picking the smallest means evaluating every candidate,
    /// which is a full walk of an app the cap already called too big — most of what
    /// the cap exists to avoid. The cap is re-applied to each nested bundle, so
    /// "first" is still bounded by the same copy budget.
    private static func firstUsableNestedFixture(in host: URL, budget: inout Int) -> URL? {
        guard let walk = FileManager.default.enumerator(
            at: host, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }
        for case let entry as URL in walk {
            guard budget > 0 else { return nil }
            budget -= 1
            guard entry.pathExtension == "app" else { continue }
            // Do not descend into a bundle already being considered. This prune is
            // most of why the walk is cheap: with it, Chrome costs 1,122 entries
            // instead of its whole tree.
            walk.skipDescendants()
            let nested = entry.resolvingSymlinksInPath()
            guard bundleIsUnder(sizeCap, at: nested), isUsableFixture(nested) else { continue }
            return nested
        }
        return nil
    }

    /// Directory entries pass 2 may visit in total, across every oversized app.
    ///
    /// A bound rather than a target: pass 2 stops at the first usable bundle, so
    /// this only decides how long a fruitless search may run. Measured here
    /// 2026-09-05 with nested `.app` descendants pruned — Google Chrome 1,122
    /// entries / 0.03 s, CapCut 6,148, Microsoft Word 50,582, and the worst case on
    /// the machine, Xcode-beta, 164,777 / 3.56 s. 400,000 lets even that finish and
    /// still holds the whole pass near ten seconds however many such apps are
    /// installed. Exhausting it is reported in the failure message, because
    /// "searched everywhere and found nothing" and "ran out of budget" are
    /// different problems with different fixes.
    private static let nestedSearchBudget = 400_000

    /// The copy budget for a fixture: it is copied twice and zipped once per test,
    /// by two tests. 200 MB of that is already generous; Xcode is a hundred times
    /// it. Measured on the author's Mac 2026-09-05: 55 universal signed candidates
    /// in /Applications, 17 of them under 50 MB, the largest 2.8 GB — so the cap
    /// removes the tail without emptying the population.
    ///
    /// On a hosted runner it DID empty the population, which is #339 — every
    /// universal app on the image is over it. That does not make the cap wrong,
    /// and raising it is the wrong repair: 593 seconds of a copy is what it was
    /// added to prevent. Its job simply grew a second half — it now also decides
    /// which apps pass 2 descends into — so an app being over the cap is no longer
    /// the end of the search for a fixture inside it.
    private static let sizeCap: Int64 = 200 * 1024 * 1024

    /// Whether `url`'s regular files total less than `cap`, **giving up as soon as
    /// they don't**. The early exit is the point: without it, deciding to reject a
    /// 20 GB app costs a full recursive walk of 20 GB, which is most of what the
    /// cap was added to avoid.
    private static func bundleIsUnder(_ cap: Int64, at url: URL) -> Bool {
        guard let walk = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return false }
        var total: Int64 = 0
        for case let file as URL in walk {
            guard let v = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  v.isRegularFile == true else { continue }
            total += Int64(v.fileSize ?? 0)
            if total >= cap { return false }
        }
        return true
    }

    /// Builds the "installed universal / downloaded x86_64-only" fixture pair
    /// shared by both installer tests below. `scratch` is the caller's scratch dir,
    /// removed by the caller.
    ///
    /// nil means the fixture could not be built, and an issue has already been
    /// recorded by then — callers return rather than reporting it a second time.
    private static func makeDowngradeFixture(in scratch: URL) throws -> (
        installed: InstalledApp, download: DownloadedUpdate
    )? {
        guard let fixture = findUniversalFixture() else { return nil }

        let installedDir = scratch.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        let installedApp = installedDir.appendingPathComponent(fixture.lastPathComponent)
        try run(["/bin/cp", "-R", fixture.path, installedApp.path])

        let thinDir = scratch.appendingPathComponent("thin-src")
        try FileManager.default.createDirectory(at: thinDir, withIntermediateDirectories: true)
        let thinApp = thinDir.appendingPathComponent(fixture.lastPathComponent)
        try run(["/bin/cp", "-R", fixture.path, thinApp.path])
        // Read off the COPY's own Info.plist and joined onto the COPY's URL, so the
        // path is structurally incapable of naming anything outside `thinDir`.
        //
        // Everything below rewrites `exe` in place, and on the first CI run
        // (2026-09-05) it was not the copy: the error carried
        // `NSSourceFilePathErrorKey=/Applications/Xcode_26.2.app/Contents/MacOS/Xcode.thin`,
        // so `lipo`, `removeItem` and `moveItem` had been aimed at a real installed
        // application. That line asked `Bundle(url: thinApp)?.executableURL` — a
        // lookup that answers with whatever the frameworks resolve to, which is a
        // question this code has no reason to ask. The symlink that run tripped
        // over is handled at the source now (see `findUniversalFixture`), and the
        // mechanism was never confirmed; this construction does not need it to be.
        let infoURL = thinApp.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: infoData, options: [], format: nil) as? [String: Any],
              let exeName = info["CFBundleExecutable"] as? String, !exeName.isEmpty
        else {
            Issue.record("fixture \(thinApp.lastPathComponent) declares no CFBundleExecutable")
            return nil
        }
        let exe = thinApp
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(exeName)
        // Kept as the backstop, not as the guard: the construction above already
        // rules this out, and a precondition that can no longer fire is the cheapest
        // insurance there is against the next person reintroducing a lookup.
        let scratchRoot = scratch.resolvingSymlinksInPath().path
        guard exe.resolvingSymlinksInPath().path.hasPrefix(scratchRoot + "/") else {
            Issue.record("""
                fixture executable resolved outside the scratch copy — refusing to \
                rewrite it. exe=\(exe.path) scratch=\(scratchRoot)
                """)
            return nil
        }
        try run(["/usr/bin/lipo", "-thin", "x86_64", exe.path, "-output", exe.path + ".thin"])
        try FileManager.default.removeItem(at: exe)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: exe.path + ".thin"), to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let zip = scratch.appendingPathComponent("download.zip")
        try run(
            ["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
             fixture.lastPathComponent, zip.path],
            in: thinDir)

        let installedInfo = InstalledApp(
            name: fixture.deletingPathExtension().lastPathComponent,
            bundleID: Bundle(url: installedApp)?.bundleIdentifier,
            shortVersion: "0.0.0", buildVersion: "0",
            path: installedApp, isMASApp: false, sparkleFeedURL: nil)
        let download = DownloadedUpdate(archiveURL: zip, bytesDownloaded: 0, workDir: scratch)
        return (installedInfo, download)
    }

    /// Asserts `error` is Gate 5b's refusal, naming the fixture's own message
    /// wording (distinct from Gate 5's, per #196) — anything else, including a
    /// silent success, means the gate is no longer reached from `apply()`.
    private static func expectArchitectureDowngrade(_ error: Error, from label: String) {
        guard case SignatureVerifier.VerifyError.architectureDowngrade(let installed, let downloaded) = error
        else {
            Issue.record("\(label): expected .architectureDowngrade, got \(error) — is Gate 5b still called from apply()?")
            return
        }
        #expect(installed.contains("arm64"), "\(label): installed side should still name arm64")
        #expect(downloaded == "x86_64", "\(label): downloaded side should be exactly x86_64")
    }

    @Test func vendorInstallerApplyRefusesTheDowngrade() async throws {
        guard HostArch.current == .arm64, HostArch.canRunIntelBuilds else {
            // Without Rosetta, Gate 5 itself would refuse an Intel-only download
            // here — that would prove Gate 5 works, not Gate 5b specifically.
            return
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-downgrade-wiring-vendor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let fixture = try Self.makeDowngradeFixture(in: scratch) else { return }

        let remote = RemoteVersion(
            shortVersion: "0.0.1", version: "0.0.1", downloadURL: fixture.download.archiveURL,
            sourceName: "Vendor", vendorInstallerKind: .zip)
        let result = UpdateResult(
            app: fixture.installed, remote: remote, status: .updateAvailable(latest: "0.0.1"))

        do {
            try await VendorInstaller().apply(result, download: fixture.download, onStage: { _ in })
            Issue.record("VendorInstaller.apply must refuse an arm64→x86_64-only swap")
        } catch {
            Self.expectArchitectureDowngrade(error, from: "VendorInstaller")
        }
    }

    @Test func sparkleInstallerApplyRefusesTheDowngrade() async throws {
        guard HostArch.current == .arm64, HostArch.canRunIntelBuilds else { return }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-downgrade-wiring-sparkle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let fixture = try Self.makeDowngradeFixture(in: scratch) else { return }

        // No `SUPublicEDKey` on the installed app (default nil), so
        // `SparkleInstaller` takes the unsigned-feed path (code signature +
        // Team ID + bundle id, same as Vendor/GitHub) rather than needing a
        // real Ed25519 keypair just to reach Gate 5b.
        let remote = RemoteVersion(
            shortVersion: "0.0.1", version: "0.0.1",
            downloadURL: fixture.download.archiveURL, sourceName: "Sparkle")
        let result = UpdateResult(
            app: fixture.installed, remote: remote, status: .updateAvailable(latest: "0.0.1"))

        do {
            try await SparkleInstaller().apply(result, download: fixture.download, onStage: { _ in })
            Issue.record("SparkleInstaller.apply must refuse an arm64→x86_64-only swap")
        } catch {
            Self.expectArchitectureDowngrade(error, from: "SparkleInstaller")
        }
    }
}
