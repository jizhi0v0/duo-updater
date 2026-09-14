import Testing
import Foundation
@testable import DuoUpdaterCore

/// Gate 6: a downloaded bundle declaring an OS floor above this Mac must be
/// refused rather than swapped in.
///
/// Why the artifact and not the source: measured across the 143 apps installed
/// on one real machine (2026-08-30), the 42 answered by `GitHubReleasesSource`
/// have no OS field published anywhere — a GitHub release simply does not carry
/// one — and only 5 of the ~140 `VendorProbeRegistry` recipes pin a floor by
/// hand. The bundle's own `LSMinimumSystemVersion` is the first place the answer
/// exists for those routes, and 140 of those 143 bundles declare one.
@Suite struct InstallOSFloorGateTests {

    // MARK: - The comparison itself

    /// Real floors read off this machine's own bundles (2026-08-30) against a
    /// macOS 27 host: two-component and three-component spellings both occur, so
    /// both are exercised rather than one normalized shape.
    @Test func aFloorAtOrBelowTheHostIsRunnable() {
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "13.1", on: "27.0.0"))
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "10.15.7", on: "27.0.0"))
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "27.0", on: "27.0.0"))
        // Equal is runnable: "requires 14.0" on exactly 14.0 is the supported
        // configuration, not a near miss.
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "14.0", on: "14.0.0"))
    }

    @Test func aFloorAboveTheHostIsNotRunnable() {
        #expect(!SignatureVerifier.canRun(minimumSystemVersion: "27.0", on: "26.6.0"))
        #expect(!SignatureVerifier.canRun(minimumSystemVersion: "14.0", on: "13.7.1"))
        // A patch-level floor above the host still counts — Bombich ships exactly
        // this shape ("13.1", not "13.0") for CCC 7.
        #expect(!SignatureVerifier.canRun(minimumSystemVersion: "13.1", on: "13.0.0"))
    }

    /// The old-vs-new macOS numbering does not need a special case: the jump from
    /// 15 to 26 is monotonic, so a Sequoia-era floor reads as satisfied on a
    /// macOS 26/27 host through ordinary numeric comparison.
    @Test func theRenumberedMacOSVersionsCompareMonotonically() {
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "15.0", on: "26.0.0"))
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "10.13", on: "27.0.0"))
        #expect(!SignatureVerifier.canRun(minimumSystemVersion: "26.0", on: "15.6.1"))
    }

    /// Fails open on anything unreadable, exactly as gate 5 does for an
    /// unreadable Mach-O header: this gate refuses builds it can PROVE are wrong,
    /// so an absent or nonsense value must keep behaving the way today's build
    /// does — install it.
    @Test func anUnreadableFloorFailsOpen() {
        #expect(SignatureVerifier.canRun(minimumSystemVersion: nil, on: "10.13.0"))
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "", on: "10.13.0"))
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "   ", on: "10.13.0"))
        #expect(SignatureVerifier.canRun(
            minimumSystemVersion: "$(MACOSX_DEPLOYMENT_TARGET)", on: "10.13.0"))
    }

    // MARK: - Reading it off a real bundle on disk

    /// Builds a throwaway `.app` and reads the value back through the same
    /// function the installer calls — not through a hand-made dictionary, so a
    /// change to the path or the plist format is caught here.
    private func makeBundle(
        floor: String?, wrapped: Bool = false, in dir: URL
    ) throws -> URL {
        let app = dir.appendingPathComponent("Subject.app")
        // A wrapped iPhone/iPad app has no `Contents/` at all: the real bundle
        // sits at `Wrapper/<Inner>.app` behind a `WrappedBundle` symlink.
        let interior = wrapped
            ? app.appendingPathComponent("Wrapper/Inner.app")
            : app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: interior, withIntermediateDirectories: true)
        if wrapped {
            try FileManager.default.createSymbolicLink(
                atPath: app.appendingPathComponent("WrappedBundle").path,
                withDestinationPath: "Wrapper/Inner.app")
        }
        var plist: [String: Any] = ["CFBundleIdentifier": "com.example.subject"]
        if wrapped {
            // What a REAL wrapped bundle carries. Read off the two on this
            // machine 2026-08-30 (`Amp 2.app`, `Aqara Home.app`): both declare
            // `CFBundleSupportedPlatforms = [iPhoneOS]` and state their floor as
            // `MinimumOSVersion` (26.0 and 18.0), with NO
            // `LSMinimumSystemVersion` at all. A fixture that wrote the macOS key
            // into a wrapped layout would be testing a bundle that does not exist.
            plist["CFBundleSupportedPlatforms"] = ["iPhoneOS"]
            if let floor { plist["MinimumOSVersion"] = floor }
        } else if let floor {
            plist["LSMinimumSystemVersion"] = floor
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: interior.appendingPathComponent("Info.plist"))
        return app
    }

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duo-gate6-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func readsTheDeclaredFloorFromABundleOnDisk() throws {
        try withTempDir { dir in
            let app = try makeBundle(floor: "13.1", in: dir)
            #expect(SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app) == "13.1")

            let bare = try makeBundle(floor: nil, in: dir.appendingPathComponent("bare"))
            #expect(SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: bare) == nil)
        }
    }

    /// An iOS-on-Mac bundle is declined DELIBERATELY, not by accident.
    ///
    /// The first version of this gate claimed `BundleLayout` was what kept
    /// wrapped apps from being waved through. It is not: real wrapped bundles
    /// carry no `LSMinimumSystemVersion` at all, so reaching the right plist
    /// finds nothing either way. Reading their `MinimumOSVersion` instead would
    /// be worse — an iOS version compared against a macOS one, the
    /// cross-namespace comparison this repo forbids, which looks fine only while
    /// iOS 26 / macOS 26 happen to line up.
    ///
    /// So the gate declines by platform, and this pins that it declines for the
    /// stated reason rather than by failing to find a file: the fixture DOES
    /// carry a floor (in the key real bundles use) and it is still not read.
    @Test func anIOSAppOnMacIsDeclinedByPlatformNotByAccident() throws {
        try withTempDir { dir in
            let app = try makeBundle(floor: "26.0", wrapped: true, in: dir)
            #expect(FileManager.default.fileExists(
                atPath: app.appendingPathComponent("Contents/Info.plist").path) == false,
                "premise: a wrapped bundle has no Contents/Info.plist")
            let interior = app.appendingPathComponent("Wrapper/Inner.app/Info.plist")
            #expect(FileManager.default.fileExists(atPath: interior.path),
                "premise: the fixture really does declare a floor, at the real path")
            #expect(SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app) == nil)
            // And therefore the gate passes it, on any host.
            try SignatureVerifier.verifyRunnableSystemVersion(appAt: app, osVersion: "15.0.0")
        }
    }

    // MARK: - The gate as the installers call it

    @Test func theGateThrowsNamingBothVersions() throws {
        try withTempDir { dir in
            let app = try makeBundle(floor: "27.0", in: dir)
            #expect(throws: SignatureVerifier.VerifyError.self) {
                try SignatureVerifier.verifyRunnableSystemVersion(appAt: app, osVersion: "26.6.0")
            }
            do {
                try SignatureVerifier.verifyRunnableSystemVersion(appAt: app, osVersion: "26.6.0")
                Issue.record("expected the gate to refuse")
            } catch let error as SignatureVerifier.VerifyError {
                // Both numbers have to survive into the message: "refusing to
                // install" without naming the floor sends the user hunting.
                let described = try #require(error.errorDescription)
                #expect(described.contains("27.0"))
                #expect(described.contains("26.6.0"))
            }
        }
    }

    @Test func theGateAcceptsABundleThisMacCanRun() throws {
        try withTempDir { dir in
            let app = try makeBundle(floor: "13.1", in: dir)
            try SignatureVerifier.verifyRunnableSystemVersion(appAt: app, osVersion: "27.0.0")
        }
    }

    /// `HostOS.numericVersion()`'s FORMAT, which is the part another reading
    /// could get wrong. (Asserting it equals
    /// `SparkleAppcastSource.numericSystemVersion()` would be a tautology — that
    /// function is now literally a call to this one — and would stay green even
    /// if someone re-inlined `ProcessInfo` there, since both spellings produce
    /// the same string on any given machine. Format is the falsifiable part.)
    ///
    /// Three components, so a two-component vendor floor ("13.1") compares
    /// against it with no special case, and it matches what Sparkle itself sends
    /// its own comparator (`SUOperatingSystem.m` formats `"%ld.%ld.%ld"`).
    @Test func theHostVersionIsThreeNumericComponents() {
        let host = HostOS.numericVersion()
        let parts = host.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.allSatisfy(\.isNumber) }, "got \(host)")
        #expect(SignatureVerifier.canRun(minimumSystemVersion: "10.13", on: host))
    }

    // MARK: - Not worth a second full download

    /// A gate-6 refusal must NOT be dressed up as a recoverable delta-route
    /// failure. `InstallCoordinator` responds to `DeltaRouteFailure` by fetching
    /// the whole archive and running the identical gates — and the OS floor is a
    /// property of the version, so the retry is guaranteed to fail the same way
    /// after spending the full download. (Gate 5 has the same shape and is
    /// classified with it.) Trust gates stay retryable: a bad patch really can
    /// produce a bundle whose signature is broken where the full archive's is not.
    @Test func aLivenessRefusalIsNotWorthRefetchingTheFullArchive() {
        #expect(!deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.unsupportedSystemVersion(required: "27.0", host: "26.6.0")))
        #expect(!deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.unrunnableArchitecture(built: "x86_64", host: "arm64")))

        #expect(deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.edSignatureInvalid))
        #expect(deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.codeSignatureInvalid(-67062)))
        #expect(deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.teamIdentifierMismatch(
                installed: "AAA", downloaded: "BBB")))
        // Anything that is not a gate failure at all — an unpack error, a disk
        // error — keeps the old behaviour: retry with the full archive.
        #expect(deltaRouteFailureIsWorthRetrying(URLError(.timedOut)))
    }

    /// Grounding: every app bundle installed on this machine either declares no
    /// floor or declares one this Mac satisfies — i.e. the gate would refuse
    /// nothing that is already installed and working. A gate that mis-compares
    /// would surface to users as "everything suddenly cannot update".
    ///
    /// Walks all of `AppScanner.defaultRoots`, not just `/Applications` — the
    /// first version of this test missed `~/Applications` and `/Library/Input
    /// Methods`, which is where the bundles least likely to state a modern floor
    /// actually live.
    ///
    /// Skips rather than fails when a root has nothing in it, so this is not a
    /// machine-shaped landmine on a bare CI runner; and it carries its own
    /// non-vacuity control, because on a fail-open gate "nothing was refused" is
    /// also what a completely disabled gate looks like.
    @Test func noAppAlreadyInstalledOnThisMacWouldBeRefused() throws {
        let host = HostOS.numericVersion()

        // Non-vacuity: the same call that must pass everything below must still
        // refuse something. Without this, replacing `canRun` with `return true`
        // leaves this test green.
        #expect(!SignatureVerifier.canRun(minimumSystemVersion: "99.0", on: host))

        let roots = ["/Applications", "/Applications/Utilities",
                     NSHomeDirectory() + "/Applications", "/Library/Input Methods"]
        var checked = 0
        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? []
            for app in entries where app.pathExtension == "app" {
                checked += 1
                let declared = SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app)
                #expect(
                    SignatureVerifier.canRun(minimumSystemVersion: declared, on: host),
                    "\(app.lastPathComponent) declares \(declared ?? "nil") and runs on \(host)")
            }
        }
        if checked == 0 {
            // A runner with no apps installed proves nothing either way; say so
            // rather than passing as if it had.
            Issue.record(
                "no installed bundles found in any scan root — this test proved nothing here",
                severity: .warning)
        }
    }

    // MARK: - Gate 6 on the pkg route (#639)

    /// Until #639 the pkg route ran no OS-floor gate at all: a package whose
    /// payload declared a floor above this Mac installed to completion, was
    /// reported as a success, and then would not launch.
    ///
    /// These build real flat packages with `pkgbuild` (and one product archive
    /// with `productbuild`), the way `InstallChildProcessTests` already builds
    /// one for the destination gate. Every path is invented (`ZZFixture…`) and
    /// nothing is read from any installed app, so the answers do not depend on
    /// the machine — `osVersion` is pinned at each call site rather than read
    /// from the host.
    ///
    /// **Mutations, each run for real on 2026-09-15.** Every one of them
    /// compiles; none of them is caught by a compiler error.
    ///
    /// | # | Mutation | Red |
    /// | --- | --- | --- |
    /// | 1 | `plistMember` needle → `"/\(appName).app/Info.plist"` | 1, 2, 3, 6 |
    /// | 2 | `plistMember` loosened to `contains("\(appName).app") && hasSuffix("Info.plist")` | 6 |
    /// | 3 | `payloadMinimumSystemVersion` filters `$0 == "Payload"` only | 2 |
    /// | 4 | `runCapturingBytes` → `runCapturing` + `Data(output.utf8)` | 1, 2 |
    /// | 5 | `verifyPayloadSystemVersion` drops the `!` on `canRun` | 1, 3, 4 |
    /// | 6 | `declaredMinimumSystemVersion(inInfoPlist:)` drops the iPhoneOS decline | 5 |
    /// | 7 | `verifyDestination`'s `/Applications/` prefix guard removed | 7 |
    /// | 8 | `scratchMember` returns the joined URL without the containment check | 8 |
    ///
    /// Mutation 4 leaves test 3 GREEN, and that is the reason test 3 exists as a
    /// separate case: an XML plist survives being round-tripped through a UTF-8
    /// `String`, a binary one does not. A suite that used only one plist format
    /// would have measured whichever half it happened to pick.
    ///
    /// **Not covered by any of them, and deliberately said out loud:** the one
    /// line in `verifyOpenable` that CALLS `verifyPayloadSystemVersion`. Deleting
    /// it leaves every test here green. Reaching that line needs a package with a
    /// valid Developer ID Installer signature whose Team ID matches a signed
    /// installed app, which cannot be built in a test — the same reason no test
    /// covers the Team-ID or destination gates through `verifyOpenable` either.
    /// Test 7 guards the refactor that moved the destination check out of it
    /// (its three accept/refuse paths used to `return` straight out of the gate,
    /// so a check appended after them would silently not run for two of three).

    /// A payload app in an XML plist, a payload app in a binary plist, and one
    /// with no floor at all — all three built the same way.
    private func makePayloadRoot(
        floor: String?, format: PropertyListSerialization.PropertyListFormat, in dir: URL
    ) throws -> URL {
        let root = dir.appendingPathComponent("root", isDirectory: true)
        let contents = root.appendingPathComponent(
            "Applications/ZZFixture Suite.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: contents.appendingPathComponent("stub"))
        var plist: [String: Any] = ["CFBundleIdentifier": "com.zzfixture.suite"]
        if let floor { plist["LSMinimumSystemVersion"] = floor }
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: format, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }

    private func buildFlatPackage(
        floor: String?,
        format: PropertyListSerialization.PropertyListFormat = .binary,
        in dir: URL
    ) async throws -> URL {
        let root = try makePayloadRoot(floor: floor, format: format, in: dir)
        let pkg = dir.appendingPathComponent("ZZFixtureSuite.pkg")
        let built = try await ChildProcess.run(
            "/usr/bin/pkgbuild",
            ["--root", root.path, "--identifier", "com.zzfixture.suite",
             "--version", "1.0", "--install-location", "/", pkg.path],
            onCancel: .runToCompletion)
        #expect(built.succeeded, "\(String(decoding: built.standardError, as: UTF8.self))")
        return pkg
    }

    /// The installed app this gate is asked about. Invented and non-existent on
    /// purpose: `verifyPayloadSystemVersion` must derive the payload bundle name
    /// from the path alone, so a fixture that pointed at a real app would be
    /// measuring the filesystem (CLAUDE.md).
    private var installedFixtureApp: URL {
        let app = URL(fileURLWithPath: "/ZZFixture-Apps/ZZFixture Suite.app", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        return app
    }

    private func withPkgTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duo-gate6-pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// Test 1: a flat package whose payload declares 99.0, read out of a BINARY
    /// plist — which is what a real payload ships, and what mutation 4 destroys.
    /// Equal-is-runnable is asserted on the same package so a gate that simply
    /// refused everything with a floor would not pass.
    @Test func aPkgPayloadFloorAboveThisMacIsRefused() async throws {
        try await withPkgTempDir { dir in
            let pkg = try await buildFlatPackage(floor: "99.0", in: dir)
            #expect(await PackageInstaller.payloadMinimumSystemVersion(
                pkg, appName: "ZZFixture Suite") == "99.0")

            let below = PackageInstaller(opener: { _ in }, osVersion: "26.0.0")
            var thrown: PackageInstaller.PackageError?
            do {
                try await below.verifyPayloadSystemVersion(pkg, installedApp: installedFixtureApp)
            } catch let error as PackageInstaller.PackageError {
                thrown = error
            }
            guard case .packageRequiresNewerSystem(let required, let host) = thrown else {
                Issue.record("expected a gate-6 refusal, got \(String(describing: thrown))")
                return
            }
            #expect(required == "99.0")
            #expect(host == "26.0.0")

            let atFloor = PackageInstaller(opener: { _ in }, osVersion: "99.0.0")
            try await atFloor.verifyPayloadSystemVersion(pkg, installedApp: installedFixtureApp)
        }
    }

    /// Test 2: a product archive keeps its component's `Payload` one directory
    /// down (`ZZFixtureSuite.pkg/Payload`), which is the shape 15 of the 16 pkg
    /// recipes' packages have and which a bare `== "Payload"` filter misses.
    @Test func aProductArchivePayloadIsFoundUnderItsComponent() async throws {
        try await withPkgTempDir { dir in
            let component = try await buildFlatPackage(floor: "99.0", in: dir)
            let product = dir.appendingPathComponent("ZZFixtureProduct.pkg")
            let built = try await ChildProcess.run(
                "/usr/bin/productbuild",
                ["--package", component.path, product.path],
                onCancel: .runToCompletion)
            #expect(built.succeeded, "\(String(decoding: built.standardError, as: UTF8.self))")

            #expect(await PackageInstaller.payloadMinimumSystemVersion(
                product, appName: "ZZFixture Suite") == "99.0")
        }
    }

    /// Test 3: an XML plist reads the same as a binary one — the two formats
    /// share `PropertyListSerialization`'s sniffing, and mutation 4 breaks only
    /// one of them, so both are exercised rather than assumed equivalent.
    @Test func aPkgPayloadFloorReadsFromAnXMLPlistToo() async throws {
        try await withPkgTempDir { dir in
            let pkg = try await buildFlatPackage(floor: "99.0", format: .xml, in: dir)
            #expect(await PackageInstaller.payloadMinimumSystemVersion(
                pkg, appName: "ZZFixture Suite") == "99.0")

            let below = PackageInstaller(opener: { _ in }, osVersion: "26.0.0")
            await #expect(throws: PackageInstaller.PackageError.self) {
                try await below.verifyPayloadSystemVersion(
                    pkg, installedApp: installedFixtureApp)
            }
        }
    }

    /// Test 4: fail-open, the branch that keeps this gate from breaking installs
    /// that work today. A payload declaring nothing must install on a host far
    /// below anything — and the reader must say `nil` rather than some default.
    @Test func aPkgPayloadWithNoDeclaredFloorInstalls() async throws {
        try await withPkgTempDir { dir in
            let pkg = try await buildFlatPackage(floor: nil, in: dir)
            #expect(await PackageInstaller.payloadMinimumSystemVersion(
                pkg, appName: "ZZFixture Suite") == nil)

            let ancient = PackageInstaller(opener: { _ in }, osVersion: "10.13.0")
            try await ancient.verifyPayloadSystemVersion(pkg, installedApp: installedFixtureApp)

            // A package whose payload holds no bundle by this name is the same
            // fail-open answer, not a refusal.
            #expect(await PackageInstaller.payloadMinimumSystemVersion(
                pkg, appName: "ZZFixture Other") == nil)
        }
    }

    /// Test 5: the plist rule is `SignatureVerifier`'s one rule, over bytes.
    /// Without the shared entry point the pkg route would need its own copy of
    /// the iPhoneOS decline, and an iOS floor compared against a macOS version is
    /// the cross-namespace comparison this repo forbids.
    @Test func thePlistRuleIsTheSameOneOverRawBytes() throws {
        let mac = try PropertyListSerialization.data(
            fromPropertyList: ["LSMinimumSystemVersion": "13.1"], format: .binary, options: 0)
        #expect(SignatureVerifier.declaredMinimumSystemVersion(inInfoPlist: mac) == "13.1")

        let padded = try PropertyListSerialization.data(
            fromPropertyList: ["LSMinimumSystemVersion": "  13.1  "], format: .xml, options: 0)
        #expect(SignatureVerifier.declaredMinimumSystemVersion(inInfoPlist: padded) == "13.1")

        let wrapped = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "LSMinimumSystemVersion": "26.0",
            ], format: .binary, options: 0)
        #expect(SignatureVerifier.declaredMinimumSystemVersion(inInfoPlist: wrapped) == nil)

        #expect(SignatureVerifier.declaredMinimumSystemVersion(
            inInfoPlist: Data("not a plist".utf8)) == nil)
    }

    /// Test 6: picking the member out of a payload listing, on invented paths.
    /// The `._Info.plist` sidecar carries another file's extended attributes and
    /// is not a plist; `pkgbuild` emits one beside every file it packages.
    @Test func thePayloadPlistMemberIsTheBundlesOwn() {
        let listing = """
        .
        ./Applications
        ./Applications/ZZFixture Suite.app
        ./Applications/ZZFixture Suite.app/Contents
        ./Applications/ZZFixture Suite.app/Contents/._Info.plist
        ./Applications/ZZFixture Suite.app/Contents/Info.plist
        ./Applications/ZZFixture Suite.app/Contents/Library/LoginItems/ZZFixture Helper.app/Contents/Info.plist
        ./Applications/ZZFixture Other.app/Contents/Info.plist
        """
        #expect(PackageInstaller.plistMember(
            inPayloadListing: listing, appName: "ZZFixture Suite")
            == "./Applications/ZZFixture Suite.app/Contents/Info.plist")
        #expect(PackageInstaller.plistMember(
            inPayloadListing: listing, appName: "ZZFixture Helper")
            == "./Applications/ZZFixture Suite.app/Contents/Library/LoginItems/ZZFixture Helper.app/Contents/Info.plist")
        #expect(PackageInstaller.plistMember(
            inPayloadListing: listing, appName: "ZZFixture Absent") == nil)
        // A payload whose root IS the bundle has no `/Applications` prefix to
        // anchor on, which is why this matches the tail and not a whole path.
        #expect(PackageInstaller.plistMember(
            inPayloadListing: "./ZZFixture Suite.app/Contents/Info.plist",
            appName: "ZZFixture Suite") == "./ZZFixture Suite.app/Contents/Info.plist")
    }

    /// Test 8: a package names its own members, and the loop that extracts them
    /// deletes each one afterwards — so a member called `../…` would let a
    /// package pick a file outside the scratch directory to have removed.
    @Test func aPayloadMemberNameCannotEscapeTheScratchDirectory() {
        let scratch = URL(fileURLWithPath: "/ZZFixture-scratch/osfloor", isDirectory: true)

        #expect(PackageInstaller.scratchMember(named: "Payload", under: scratch)?.path
            == "/ZZFixture-scratch/osfloor/Payload")
        #expect(PackageInstaller.scratchMember(named: "ZZFixture.pkg/Payload", under: scratch)?.path
            == "/ZZFixture-scratch/osfloor/ZZFixture.pkg/Payload")

        #expect(PackageInstaller.scratchMember(named: "../Payload", under: scratch) == nil)
        #expect(PackageInstaller.scratchMember(
            named: "a/../../../ZZFixture-Apps/Payload", under: scratch) == nil)
        // The scratch directory itself is not a member either: removing it mid-loop
        // would take the next component's extraction with it.
        #expect(PackageInstaller.scratchMember(named: ".", under: scratch) == nil)
    }

    /// Test 7: the destination check, now that it is its own function rather
    /// than three `return`s inside the gate. The name fallback exists for an app
    /// kept outside `/Applications`, and must NOT apply to one inside it.
    @Test func theDestinationCheckStillAcceptsAndRefusesWhatItDid() throws {
        try PackageInstaller.verifyDestination(
            target: "/Applications/ZZFixture Suite.app",
            destinations: ["/Applications/ZZFixture Suite.app"])

        // Outside /Applications: the bundle name stands in for the path.
        try PackageInstaller.verifyDestination(
            target: "/ZZFixture-Apps/ZZFixture Suite.app",
            destinations: ["/Applications/ZZFixture Suite.app"])

        // Inside /Applications: a like-named bundle somewhere else does not.
        #expect(throws: PackageInstaller.PackageError.self) {
            try PackageInstaller.verifyDestination(
                target: "/Applications/ZZFixture Suite.app",
                destinations: ["/Library/Application Support/ZZ/ZZFixture Suite.app"])
        }
        #expect(throws: PackageInstaller.PackageError.self) {
            try PackageInstaller.verifyDestination(
                target: "/ZZFixture-Apps/ZZFixture Suite.app",
                destinations: ["/Applications/ZZFixture Other.app"])
        }
    }
}
