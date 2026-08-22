import Testing
import Foundation
@testable import DuoUpdaterCore

/// Detection of a **Sparkle**-staged build: unpacked into Sparkle's installation
/// cache with an `Autoupdate` parked on the app's next quit. The layout is
/// reproduced from a real one observed on 2026-08-22:
///
///     Caches/com.tinyapp.TablePlus/org.sparkle-project.Sparkle/
///       Installation/S61bE6QMb/<uuid>.dmg
///       Installation/S61bE6QMb/c4KQCuugL/TablePlus.app   ← 26.9.11, disk had 26.9.9
///       Launcher/jRGjuao1o/Updater.app                   ← org.sparkle-project.Sparkle.Updater
struct SparkleStagingTests {

    private let bundleID = "com.example.sparkle"

    private func makeApp(at url: URL, identifier: String, short: String, build: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": short,
            "CFBundleVersion": build,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func app(at path: URL, short: String, build: String) -> InstalledApp {
        // `hasSelfUpdater` stays false on purpose: it is a Squirrel-only signal,
        // and a Sparkle app really does arrive here with it unset. A detector that
        // gated on it would find nothing on any of the apps this is for.
        InstalledApp(
            name: "Sparkly", bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: path, isMASApp: false, sparkleFeedURL: nil, hasSelfUpdater: false)
    }

    /// `Installation/<random>/<random>/<Name>.app`, as Sparkle lays it out.
    private func stage(
        in caches: URL, short: String, build: String, identifier: String? = nil,
        appName: String = "Sparkly.app"
    ) throws -> URL {
        let dir = caches
            .appendingPathComponent(bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("Installation")
            .appendingPathComponent("S61bE6QMb")
            .appendingPathComponent("c4KQCuugL")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let staged = dir.appendingPathComponent(appName)
        try makeApp(at: staged, identifier: identifier ?? bundleID, short: short, build: build)
        return staged
    }

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleStagingTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test func findsTheStagedBundle() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")

            let found = SelfUpdaterStaging.sparkleStagedBundle(
                for: app(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches)

            #expect(found?.version == "26.9.11")
            #expect(found?.buildVersion == "769")
        }
    }

    /// The case the whole check exists for. ChatGPT had 26.818.41509 staged while
    /// disk held the 26.818.41705 we had just installed, and quitting applied the
    /// older one. A detector phrased as "is a newer update pending" — which is what
    /// the Squirrel and Spotify branches ask — returns nothing here.
    @Test func findsAStagedBundleOlderThanWhatIsInstalled() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.818.41509", build: "6962")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.818.41705", build: "6971")

            let found = SelfUpdaterStaging.sparkleStagedBundle(
                for: app(at: installed, short: "26.818.41705", build: "6971"),
                cachesDirectory: caches)

            #expect(found?.version == "26.818.41509")
            #expect(RestartStandoff.decide(
                stagedVersion: found?.version, onDiskVersion: "26.818.41705")
                == .holdBack(stagedVersion: "26.818.41509"))
        }
    }

    /// The directory survives every install and sits there empty. Its presence is
    /// not evidence, and neither is its mtime — which does not follow its children.
    @Test func anEmptyInstallationDirectoryIsNotAStagedUpdate() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let dir = caches.appendingPathComponent(bundleID)
                .appendingPathComponent("org.sparkle-project.Sparkle")
                .appendingPathComponent("Installation")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "1.0", build: "1")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app(at: installed, short: "1.0", build: "1"),
                cachesDirectory: caches) == nil)
        }
    }

    /// Sparkle's own `Updater.app` is a bundle in the same cache tree. It is not a
    /// staged copy of anything, and promoting its version would be nonsense. The
    /// identifier check rejects it even when it is planted where we do look.
    @Test func sparklesOwnUpdaterIsNotMistakenForAStagedBuild() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(
                in: caches, short: "2.9.1", build: "2091",
                identifier: "org.sparkle-project.Sparkle.Updater", appName: "Updater.app")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "1.0", build: "1")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app(at: installed, short: "1.0", build: "1"),
                cachesDirectory: caches) == nil)
        }
    }

    /// Nothing staged at all — no cache tree for this app.
    @Test func noSparkleCacheYieldsNil() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "1.0", build: "1")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app(at: installed, short: "1.0", build: "1"),
                cachesDirectory: caches) == nil)
        }
    }


    // MARK: - Reaching the shared `staged(for:)` entry point

    /// A Sparkle app with a newer build staged now answers the same question a
    /// Squirrel one does, which is what turns the row's Update into Relaunch and
    /// stops us re-downloading bytes already in the cache. TablePlus had 133 MB of
    /// dmg plus a 382 MB unpacked copy sitting there while we offered to fetch it
    /// again.
    @Test func aNewerSparkleStagedBuildIsReportedByStagedFor() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")

            let found = SelfUpdaterStaging.staged(
                for: sparkleApp(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches)

            #expect(found?.version == "26.9.11")
        }
    }

    /// The ChatGPT case must NOT surface here. A staged build older than what is
    /// installed is not an update waiting to be applied — offering Relaunch for it
    /// would be offering a downgrade. The restart check still sees it, via
    /// `sparkleStagedBundle`, because there it is precisely the danger.
    @Test func anOlderSparkleStagedBuildIsNotReportedAsAnUpdate() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.818.41509", build: "6962")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.818.41705", build: "6971")
            let app = sparkleApp(at: installed, short: "26.818.41705", build: "6971")

            #expect(SelfUpdaterStaging.staged(for: app, cachesDirectory: caches) == nil)
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app, cachesDirectory: caches)?.version == "26.818.41509")
        }
    }

    /// The candidate pre-filter has to let Sparkle apps through, or none of the
    /// above is ever asked. It must keep saying no to an app with neither.
    @Test func theCandidateFilterAdmitsSparkleApps() {
        let path = URL(fileURLWithPath: "/Applications/Sparkly.app")
        #expect(SelfUpdaterStaging.mayHaveStaging(
            sparkleApp(at: path, short: "1.0", build: "1")))
        #expect(!SelfUpdaterStaging.mayHaveStaging(
            InstalledApp(
                name: "Plain", bundleID: bundleID, shortVersion: "1.0", buildVersion: "1",
                path: path, isMASApp: false, sparkleFeedURL: nil)))
    }

    private func sparkleApp(at path: URL, short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "Sparkly", bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: path, isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
    }
}
