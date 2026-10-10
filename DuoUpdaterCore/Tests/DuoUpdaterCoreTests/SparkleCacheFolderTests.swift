import Foundation
import Testing
@testable import DuoUpdaterCore

/// Sparkle appends `.sparkle` to the cache folder of a bundle identifier that
/// looks like a bundle directory (`SPULocalCacheDirectory.m`), so for those ids
/// `<Caches>/<bundleID>/org.sparkle-project.Sparkle` is the wrong place — or, for
/// an app on an older Sparkle, the right one. Every lookup has to try both names,
/// and nothing may be read or deleted under a name Sparkle never uses for the id.
///
/// All ids and paths here are invented fixtures.
struct SparkleCacheFolderTests {

    // MARK: - sparkleCacheFolderNames

    /// The rule per Sparkle release, read at each tag on 2026-10-11:
    /// ≤ 2.9.2 none; 2.9.3–2.9.6 `.app` / `.APP`; 2.10.0-beta.1 on, the
    /// lowercased id against eight extensions. The answer is the union.
    ///
    /// Mutations: drop `.lowercased()` (`.App` and `.XPC` go red); drop any one
    /// extension from the list (its row goes red); drop the leading dot of the
    /// suffixes (`zzfixtureapp` goes red); return only the suffixed name, or
    /// only the raw one, for an affected id (every affected row goes red).
    @Test func folderNamesCoverEverySparkleRelease() {
        let unaffected = [
            "com.example.zzfixture",
            "com.example.zzfixtureapp",          // no dot: not an extension
            "com.example.app.zzfixture",         // `.app` not at the end
            "com.example.zzfixture.sparkle",
        ]
        for id in unaffected {
            #expect(SelfUpdaterStaging.sparkleCacheFolderNames(for: id) == [id], "\(id)")
        }
        let affected = [
            // 2.9.3 on
            "com.example.ZZFixture.app", "com.example.ZZFixture.APP",
            // 2.10.0-beta.1 on: case-insensitive, and seven more extensions
            "com.example.ZZFixture.App", "com.example.zzfixture.XPC",
            "com.example.zzfixture.service", "com.example.zzfixture.xpc",
            "com.example.zzfixture.appex", "com.example.zzfixture.bundle",
            "com.example.zzfixture.plugin", "com.example.zzfixture.saver",
            "com.example.zzfixture.kext",
        ]
        for id in affected {
            #expect(SelfUpdaterStaging.sparkleCacheFolderNames(for: id) == [id, id + ".sparkle"], "\(id)")
        }
        #expect(SelfUpdaterStaging.problematicBundleIdentifierExtensions == [
            ".app", ".service", ".xpc", ".appex", ".bundle", ".plugin", ".saver", ".kext",
        ])
    }

    // MARK: - SelfUpdaterStaging lookups

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-SparkleCacheFolder-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func writeBundle(at url: URL, identifier: String, short: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": identifier,
                "CFBundleShortVersionString": short,
                "CFBundleVersion": "1",
            ] as [String: Any],
            format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func sparkleRoot(_ caches: URL, folder: String) -> URL {
        caches.appendingPathComponent(folder).appendingPathComponent("org.sparkle-project.Sparkle")
    }

    /// `<folder>/…/Installation/<random>/<random>/ZZFixture.app`.
    @discardableResult
    private func stage(_ caches: URL, folder: String, bundleID: String, short: String) throws -> URL {
        let staged = sparkleRoot(caches, folder: folder)
            .appendingPathComponent("Installation/qW3rTy7uI/aS9dFg2hJ/ZZFixture.app")
        try writeBundle(at: staged, identifier: bundleID, short: short)
        return staged
    }

    /// The progress agent Sparkle ≤ 2.9.6 copies into `<folder>/…/Launcher/`.
    private func launcherAgent(_ caches: URL, folder: String) -> URL {
        sparkleRoot(caches, folder: folder).appendingPathComponent("Launcher/zX8cV4bN1/Updater.app")
    }

    private func app(_ root: URL, bundleID: String) -> InstalledApp {
        InstalledApp(
            name: "ZZFixture", bundleID: bundleID, shortVersion: "1.0", buildVersion: "1",
            path: root.appendingPathComponent("Applications/ZZFixture.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
    }

    /// Sparkle 2.9.3–2.9.6 with an id ending in `.app`: agent and staging both
    /// under `<id>.sparkle`. Before the fix this was nil — the gate failed open
    /// and we installed over a build Sparkle swaps in on quit.
    ///
    /// Mutations: build the roots from the raw id alone (nil, red); walk only the
    /// first root's `Installation/` (nil, red).
    @Test func findsStagingUnderTheSuffixedFolder() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let id = "com.example.zzfixture.app"
            try stage(caches, folder: id + ".sparkle", bundleID: id, short: "2.0")
            let found = SelfUpdaterStaging.sparkleStagedBundle(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: [launcherAgent(caches, folder: id + ".sparkle")])
            #expect(found?.version == "2.0")
        }
    }

    /// Sparkle 2.10 on, agent in the app's own framework, staging under the
    /// suffixed folder: the Installation walk is what has to reach it.
    ///
    /// Mutation: walk only the first root's `Installation/` (nil, red).
    @Test func findsSuffixedStagingWhenTheAgentRunsFromTheApp() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let id = "com.example.ZZFixture.Bundle"
            let theApp = app(root, bundleID: id)
            try stage(caches, folder: id + ".sparkle", bundleID: id, short: "3.0")
            let agent = theApp.path.appendingPathComponent(
                "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app")
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: theApp, cachesDirectory: caches,
                parkedInstallerBundleURLs: [agent])?.version == "3.0")
        }
    }

    /// The same id on Sparkle ≤ 2.9.2, which never suffixes: the raw folder must
    /// still be looked at.
    ///
    /// Mutation: return only the suffixed name for an affected id (nil, red).
    @Test func stillFindsStagingUnderTheRawFolderForAnAffectedID() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let id = "com.example.zzfixture.app"
            try stage(caches, folder: id, bundleID: id, short: "2.0")
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: [launcherAgent(caches, folder: id)])?.version == "2.0")
        }
    }

    /// An id no Sparkle suffixes: a `<id>.sparkle` folder is not its cache, and
    /// neither its agent nor its staging counts.
    ///
    /// Mutation: always return both names (found, red).
    @Test func ignoresASuffixedFolderForAnIDSparkleNeverSuffixes() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let id = "com.example.zzfixture"
            try stage(caches, folder: id + ".sparkle", bundleID: id, short: "2.0")
            #expect(SelfUpdaterStaging.sparkleStagedBundle(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: [launcherAgent(caches, folder: id + ".sparkle")]) == nil)
        }
    }

    /// The orphan check under the suffixed folder: agent parked there, both
    /// folders' staging gone → orphaned; an archive in the suffixed
    /// `PersistentDownloads/` while the raw folder is empty → not orphaned.
    ///
    /// Mutations: check only the first root in `sparkleStagingIsGone` (the
    /// second expectation goes red); build roots from the raw id alone (the
    /// agent is not seen, the first goes red).
    @Test func orphanCheckLooksUnderBothFolders() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            let id = "com.example.zzfixture.app"
            let suffixed = sparkleRoot(caches, folder: id + ".sparkle")
            try FileManager.default.createDirectory(
                at: sparkleRoot(caches, folder: id).appendingPathComponent("Installation"),
                withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: suffixed.appendingPathComponent("PersistentDownloads"),
                withIntermediateDirectories: true)
            let parked = [launcherAgent(caches, folder: id + ".sparkle")]

            #expect(SelfUpdaterStaging.sparkleInstallerOrphaned(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: parked, installerRunsAsThisUser: true))

            try Data("zz".utf8).write(
                to: suffixed.appendingPathComponent("PersistentDownloads/ZZFixture-2.0.zip"))
            #expect(!SelfUpdaterStaging.sparkleInstallerOrphaned(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: parked, installerRunsAsThisUser: true))
            #expect(SelfUpdaterStaging.sparkleInstallerArmedWithUnreadableStaging(
                for: app(root, bundleID: id), cachesDirectory: caches,
                parkedInstallerBundleURLs: parked, installerRunsAsThisUser: true),
                "a download in flight is a live installer, so the install still yields")
        }
    }

    // MARK: - SparkleStagingClearance

    private final class Removed: @unchecked Sendable {
        var labels: [String] = []
    }

    /// `Autoupdate` (802) from the app's framework, the agent (804) from the
    /// `Launcher/` under `agentFolder`.
    private func system(
        app: InstalledApp, caches: URL, agentFolder: String, removed: Removed
    ) -> SparkleStagingClearance.System {
        let paths: [pid_t: String] = [
            802: app.path.path + "/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
            804: launcherAgent(caches, folder: agentFolder).path + "/Contents/MacOS/Updater",
        ]
        return SparkleStagingClearance.System(
            listJobs: { [
                .init(pid: 802, label: "com.example.zzfixture-sparkle-updater"),
                .init(pid: 804, label: "com.example.zzfixture-sparkle-progress"),
            ] },
            executablePath: { paths[$0] },
            removeJob: { removed.labels.append($0); return true },
            isAlive: { _ in false },
            bundleIdentifier: { $0 == 804 ? "org.sparkle-project.Sparkle.Updater" : nil },
            sleep: { _ in })
    }

    /// The staged-clearance path for a suffixed cache: both jobs go, the agent
    /// last, and the staging run under `<id>.sparkle` is deleted.
    ///
    /// Mutations: build `attempt`'s roots from the raw id alone (refused as
    /// "outside this app's Sparkle cache", red); match jobs against the raw
    /// root alone (the agent is not removed, red).
    @Test func clearsStagingUnderTheSuffixedFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-SparkleCacheFolder-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Caches")
        let id = "com.example.zzfixture.app"
        let theApp = app(root, bundleID: id)
        let staged = try stage(caches, folder: id + ".sparkle", bundleID: id, short: "2.0")
        let run = sparkleRoot(caches, folder: id + ".sparkle")
            .appendingPathComponent("Installation/qW3rTy7uI")
        let removed = Removed()

        let outcome = await SparkleStagingClearance.clear(
            for: theApp,
            staged: StagedSelfUpdate(version: "2.0", buildVersion: "1",
                                     stagedBundlePath: staged, updater: .sparkle),
            cachesDirectory: caches,
            system: system(app: theApp, caches: caches, agentFolder: id + ".sparkle", removed: removed))

        #expect(outcome == .cleared)
        #expect(removed.labels == [
            "com.example.zzfixture-sparkle-updater", "com.example.zzfixture-sparkle-progress",
        ])
        #expect(!FileManager.default.fileExists(atPath: run.path))
    }

    /// Fail-closed: for an id no Sparkle suffixes, a staged path under
    /// `<id>.sparkle` is outside the app's real cache. Nothing is asked of
    /// launchd and nothing is deleted.
    ///
    /// Mutation: always return both names (cleared and deleted, red).
    @Test func refusesASuffixedFolderForAnIDSparkleNeverSuffixes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-SparkleCacheFolder-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Caches")
        let id = "com.example.zzfixture"
        let theApp = app(root, bundleID: id)
        let staged = try stage(caches, folder: id + ".sparkle", bundleID: id, short: "2.0")
        let removed = Removed()

        let outcome = await SparkleStagingClearance.clear(
            for: theApp,
            staged: StagedSelfUpdate(version: "2.0", buildVersion: "1",
                                     stagedBundlePath: staged, updater: .sparkle),
            cachesDirectory: caches,
            system: system(app: theApp, caches: caches, agentFolder: id + ".sparkle", removed: removed))

        #expect(outcome == .notCleared(
            reason: "staged bundle is outside this app's Sparkle cache", touchedInstaller: false))
        #expect(removed.labels.isEmpty)
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    /// The orphaned-installer path for a suffixed cache: the whole
    /// `<id>.sparkle` cache deleted, `Autoupdate` and an agent still parked.
    ///
    /// Mutations: check staging under the raw root alone in `attemptOrphaned`
    /// (cleared although the suffixed `Installation/` holds a run, red — see the
    /// second half); match jobs against the raw root alone (agent not removed,
    /// red).
    @Test func clearsAnOrphanedInstallerUnderTheSuffixedFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-SparkleCacheFolder-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Caches")
        let id = "com.example.zzfixture.app"
        let theApp = app(root, bundleID: id)

        let removed = Removed()
        #expect(await SparkleStagingClearance.clearOrphanedInstaller(
            for: theApp, cachesDirectory: caches,
            system: system(app: theApp, caches: caches, agentFolder: id + ".sparkle", removed: removed))
            == .cleared)
        #expect(removed.labels == [
            "com.example.zzfixture-sparkle-updater", "com.example.zzfixture-sparkle-progress",
        ])

        try stage(caches, folder: id + ".sparkle", bundleID: id, short: "2.0")
        let untouched = Removed()
        #expect(await SparkleStagingClearance.clearOrphanedInstaller(
            for: theApp, cachesDirectory: caches,
            system: system(app: theApp, caches: caches, agentFolder: id + ".sparkle", removed: untouched))
            == .notCleared(reason: "its staging is not gone", touchedInstaller: false))
        #expect(untouched.labels.isEmpty)
    }
}
