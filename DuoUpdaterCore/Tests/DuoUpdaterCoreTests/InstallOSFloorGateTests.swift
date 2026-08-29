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
        if let floor { plist["LSMinimumSystemVersion"] = floor }
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

    /// A wrapped iPhone/iPad app keeps its plist under `Wrapper/<Inner>.app/`.
    /// Reading a hardcoded `Contents/Info.plist` would not throw here — it would
    /// find nothing, report "no floor declared", and wave every wrapped app
    /// through forever. That silence is the whole reason this goes through
    /// `BundleLayout.interiorPrefix`, so it gets its own case.
    @Test func readsTheFloorOutOfAWrappedBundleToo() throws {
        try withTempDir { dir in
            let app = try makeBundle(floor: "26.0", wrapped: true, in: dir)
            #expect(FileManager.default.fileExists(
                atPath: app.appendingPathComponent("Contents/Info.plist").path) == false,
                "premise: a wrapped bundle has no Contents/Info.plist to find")
            #expect(SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app) == "26.0")
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

    /// The gate's default argument must read the host through the same
    /// definition the feed-level filter uses, or the two can disagree and produce
    /// an update that is offered forever and refused at the last step every time.
    @Test func theGateAndTheFeedFilterAgreeOnWhatThisMacIsRunning() {
        #expect(HostOS.numericVersion() == SparkleAppcastSource.numericSystemVersion())
        // Three components, so a two-component vendor floor compares without a
        // special case.
        #expect(HostOS.numericVersion().split(separator: ".").count == 3)
    }

    /// Grounding: every app bundle installed on this machine either declares no
    /// floor or declares one this Mac satisfies — i.e. the gate would refuse
    /// nothing that is already installed and working. A gate that fails this is
    /// mis-comparing, and would surface as "everything suddenly can't update".
    @Test func noAppAlreadyInstalledOnThisMacWouldBeRefused() throws {
        let apps = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil)) ?? []
        let bundles = apps.filter { $0.pathExtension == "app" }
        try #require(!bundles.isEmpty, "premise: this machine has apps in /Applications")
        let host = HostOS.numericVersion()
        for app in bundles {
            let declared = SignatureVerifier.declaredMinimumSystemVersion(ofAppAt: app)
            #expect(
                SignatureVerifier.canRun(minimumSystemVersion: declared, on: host),
                "\(app.lastPathComponent) declares \(declared ?? "nil") and is installed on \(host)")
        }
    }
}
