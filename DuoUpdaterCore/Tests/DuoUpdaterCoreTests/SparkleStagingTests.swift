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

    /// Where Sparkle's parked progress agent lives for this app — the evidence
    /// that an installer is actually waiting on the quit.
    private func parkedInstaller(in caches: URL) -> URL {
        caches.appendingPathComponent(bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("Launcher")
            .appendingPathComponent("jRGjuao1o")
            .appendingPathComponent("Updater.app")
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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)])

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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)])

            #expect(found?.version == "26.818.41509")
            #expect(RestartStandoff.decide(
                staged: found,
                onDiskShortVersion: "26.818.41705", onDiskBuildVersion: "6971")
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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)]) == nil)
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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)]) == nil)
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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)]) == nil)
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
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)])

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

            let parked = [parkedInstaller(in: caches)]
            #expect(SelfUpdaterStaging.staged(
                for: app, cachesDirectory: caches,
                parkedInstallerBundleURLs: parked) == nil)
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app, cachesDirectory: caches,
                parkedInstallerBundleURLs: parked)?.version == "26.818.41509")
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

    /// Regression: an unpacked bundle in the cache is not evidence on its own.
    /// Sparkle keeps abandoned staging for ten days and only sweeps it when a new
    /// staging run happens, so a reboot or a killed installer leaves one behind.
    /// Treating that as live gave a Restart button that held back — citing an
    /// update that no longer existed — for up to ten days, and could quit the
    /// user's app waiting for a swap nobody was going to perform.
    @Test func aLeftoverWithNoParkedInstallerIsIgnored() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")
            let app = sparkleApp(at: installed, short: "26.9.9", build: "765")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app, cachesDirectory: caches,
                parkedInstallerBundleURLs: []) == nil)
            #expect(SelfUpdaterStaging.staged(
                for: app, cachesDirectory: caches,
                parkedInstallerBundleURLs: []) == nil)
        }
    }

    /// An installer parked for a DIFFERENT app is not evidence for this one. Every
    /// Sparkle app's agent shares one bundle identifier, so the location it runs
    /// from is the only thing that ties it to an app.
    @Test func anInstallerParkedForAnotherAppIsNotEvidence() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")
            let elsewhere = caches.appendingPathComponent("com.other.app")
                .appendingPathComponent("org.sparkle-project.Sparkle")
                .appendingPathComponent("Launcher").appendingPathComponent("x")
                .appendingPathComponent("Updater.app")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: sparkleApp(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [elsewhere]) == nil)
        }
    }

    /// Sparkle launches its progress agent out of the HOST BUNDLE's framework
    /// rather than the staging cache when the installer runs as root
    /// (`SUInstallerLauncher.m`: `BOOL copyProgressTool = !rootUser`). Accepting
    /// only the cache location silently disabled the standoff for every
    /// privileged install — and because this gate fails open, that is the
    /// overwrite bug back again rather than a missing warning.
    @Test func anInstallerParkedInsideTheAppsOwnFrameworkIsEvidence() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")
            let inBundle = installed
                .appendingPathComponent("Contents/Frameworks/Sparkle.framework")
                .appendingPathComponent("Versions/B/Updater.app")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: sparkleApp(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [inBundle])?.version == "26.9.11")
        }
    }

    /// The two sides of the location comparison come from different APIs —
    /// `FileManager.urls(for:)` for the cache root, `NSRunningApplication.bundleURL`
    /// for the installer — and a home directory reached through a symlink makes
    /// them spell the same directory differently. `standardizedFileURL` does not
    /// resolve links or the `/private` prefix; only `resolvingSymlinksInPath` does.
    @Test func aParkedInstallerReachedThroughASymlinkStillMatches() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")

            // The installer bundle has to exist: `resolvingSymlinksInPath` resolves
            // nothing on a path that is not on disk (measured — a link in a path
            // whose leaf is missing comes back verbatim). Production always passes
            // a real `NSRunningApplication.bundleURL`, so this is the honest shape.
            try FileManager.default.createDirectory(
                at: parkedInstaller(in: caches), withIntermediateDirectories: true)
            let link = root.appendingPathComponent("CachesLink")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: caches)
            let viaLink = link.appendingPathComponent(bundleID)
                .appendingPathComponent("org.sparkle-project.Sparkle")
                .appendingPathComponent("Launcher").appendingPathComponent("jRGjuao1o")
                .appendingPathComponent("Updater.app")

            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: sparkleApp(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [viaLink])?.version == "26.9.11")
        }
    }

    /// Every other test in this file injects `parkedInstallerBundleURLs`, so none
    /// of them touches the argument production actually uses — the `nil` default
    /// that queries LaunchServices. This exercises that path end to end.
    ///
    /// It is a smoke test and nothing more: a typo in the identifier queried for
    /// would ALSO produce nil here, so this cannot catch one. The two tests below
    /// are what guard the identifiers themselves.
    @Test func theDefaultArgumentReachesTheLiveQuery() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "26.9.11", build: "769")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "26.9.9", build: "765")

            // No real Sparkle installer can be parked under a scratch directory.
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: sparkleApp(at: installed, short: "26.9.9", build: "765"),
                cachesDirectory: caches) == nil)
            // And the query must survive being called with none running at all.
            _ = SelfUpdaterStaging.liveParkedSparkleInstallers()
        }
    }

    /// Checks the identifier we query for against a Sparkle bundle **on disk**,
    /// which is the only thing available here that Sparkle itself authored.
    ///
    /// Skipped rather than failed when the machine has no Sparkle 2 app: this is
    /// opportunistic corroboration, and the tripwire below is what holds on a
    /// machine where it finds nothing.
    @Test func aRealSparkleUpdaterIdentifiesAsOneOfTheIdentitiesWeQueryFor() throws {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        var checked = 0
        for app in apps where app.pathExtension == "app" {
            let updater = app.appendingPathComponent(
                "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/Info.plist")
            guard let data = try? Data(contentsOf: updater),
                  let dict = (try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil)) as? [String: Any],
                  let identifier = dict["CFBundleIdentifier"] as? String
            else { continue }
            #expect(SelfUpdaterStaging.sparkleInstallerBundleIDs.contains(identifier),
                    "\(app.lastPathComponent) ships a Sparkle installer identifying as \(identifier), which this gate does not look for")
            checked += 1
            if checked >= 3 { break }
        }
    }

    /// A tripwire for the machines the test above finds nothing on: changing an
    /// identifier fails loudly instead of turning the standoff off in silence.
    /// `…Updater` was observed live on 2026-08-22 (pid 27939, parked for
    /// TablePlus); `…Autoupdate` is Sparkle 1's, as shipped inside VLC 1.16.0.
    @Test func theInstallerIdentitiesAreTheOnesSparkleShips() {
        #expect(SelfUpdaterStaging.sparkleInstallerBundleIDs == [
            "org.sparkle-project.Sparkle.Updater",
            "org.sparkle-project.Sparkle.Autoupdate",
        ])
    }

    // MARK: - The Amp scenario, end to end

    /// The failure of 2026-08-28, rebuilt on a real filesystem through the real
    /// detector and the real policy — not asserted from remembered numbers.
    ///
    /// Amp had build 128 on disk, its updater had staged 129, and the feed had
    /// already moved to 130. All three are called "1.0". The row offered
    /// **Relaunch**, so the user relaunched into 129 and was still a build behind
    /// — the outcome `actionableStaged`'s own doc comment says the gate exists to
    /// prevent ("relaunching to it would still leave the user a download behind").
    ///
    /// This is the scenario the live test that night could NOT reproduce: by then
    /// the staged build WAS the latest, so it exercised a different path.
    @Test func aStagedBuildTrailingTheFeedIsOfferedAsUpdateNotRelaunch() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            _ = try stage(in: caches, short: "1.0", build: "129")
            let installed = root.appendingPathComponent("Sparkly.app")
            try makeApp(at: installed, identifier: bundleID, short: "1.0", build: "128")

            // `hasSparkleUpdater: true` on purpose — the shared `app(...)` helper
            // leaves it false because the other cases in this suite call
            // `sparkleStagedBundle` directly, below that gate. This one goes
            // through `staged(for:)` so the whole production path is exercised.
            let amp = InstalledApp(
                name: "Sparkly", bundleID: bundleID, shortVersion: "1.0",
                buildVersion: "128", path: installed, isMASApp: false,
                sparkleFeedURL: nil, hasSelfUpdater: false, hasSparkleUpdater: true)

            // The detector must still SEE it — the staged build is genuinely newer
            // than what is installed, so this half is unchanged.
            let staged = SelfUpdaterStaging.staged(
                for: amp,
                cachesDirectory: caches,
                parkedInstallerBundleURLs: [parkedInstaller(in: caches)])
            #expect(staged?.buildVersion == "129", "129 is newer than the installed 128")

            // ...but the feed is at 130, so a relaunch would land a build that is
            // already behind. The row has to fall through to Update.
            let result = UpdateResult(
                app: amp,
                remote: RemoteVersion(
                    shortVersion: "1.0", version: "130",
                    downloadURL: URL(string: "https://example.com/a.dmg"),
                    sourceName: "Sparkle"),
                status: .updateAvailable(latest: "1.0"))
            #expect(UpdatePolicy.actionableStaged(result, staged: staged) == nil,
                    "staged 129 trails feed 130 — Relaunch here strands the user a build behind")

            // And once the feed and the staged build agree, Relaunch is right again.
            let caughtUp = UpdateResult(
                app: amp,
                remote: RemoteVersion(
                    shortVersion: "1.0", version: "129",
                    downloadURL: URL(string: "https://example.com/a.dmg"),
                    sourceName: "Sparkle"),
                status: .updateAvailable(latest: "1.0"))
            #expect(UpdatePolicy.actionableStaged(caughtUp, staged: staged) != nil)
        }
    }
}
