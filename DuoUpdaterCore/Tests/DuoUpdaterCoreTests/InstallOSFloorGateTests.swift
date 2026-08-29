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
}
