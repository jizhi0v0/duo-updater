import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Homebrew route downloads before its install (`HomebrewInstaller.fetch`):
/// brew's auto-update and the download run where a cancel still stops them,
/// and the install, the commit, does neither. Each case runs the real code
/// against a stand-in `brew` that logs its arguments and
/// `HOMEBREW_NO_AUTO_UPDATE`, one line a run.
@Suite struct HomebrewFetchFirstTests {

    private struct Fixture {
        let root: URL
        let app: URL
        let brew: URL
        let log: URL

        /// `onFetch` runs in the stand-in when it is asked to `fetch`.
        init(onFetch: String = "") throws {
            let fm = FileManager.default
            root = fm.temporaryDirectory.appendingPathComponent("brew-fetch-first-\(UUID().uuidString)")
            app = root.appendingPathComponent("Zzfixture.app")
            brew = root.appendingPathComponent("brew")
            log = root.appendingPathComponent("brew-log")
            try fm.createDirectory(
                at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try Data("old binary".utf8).write(to: app.appendingPathComponent("Contents/MacOS/Zzfixture"))
            try Data("""
                #!/bin/sh
                echo "$*|${HOMEBREW_NO_AUTO_UPDATE}" >> '\(log.path)'
                [ "$1" = fetch ] && { \(onFetch.isEmpty ? ":" : onFetch); }
                exit 0

                """.utf8).write(to: brew)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        }

        var runs: [String] {
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    /// Only the dry run may auto-update: it is the `brew install` the old single
    /// run auto-updated in, so the same throttle and tap rules apply. `brew fetch`
    /// never auto-updates on its own, and an install that did would refresh
    /// brew's API data inside the commit. Mutations: drop the dry run, set
    /// `HOMEBREW_NO_AUTO_UPDATE` before it, or drop it from `upgrade` → this fails.
    @Test func onlyTheDryRunBeforeTheFetchAutoUpdates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await HomebrewInstaller.$brewPathOverride.withValue(fixture.brew.path) {
            let brew = HomebrewInstaller()
            try await brew.fetch(caskToken: "zzfixture-cask") { _ in }
            // The fixture has no Info.plist, so an untouched bundle is not
            // `unchanged` (see `BundleSnapshot.isUnchanged`).
            try await brew.upgrade(caskToken: "zzfixture-cask", app: fixture.app) { _ in }
        }
        #expect(fixture.runs == [
            "install --cask --force --dry-run -- zzfixture-cask|",
            "fetch --cask -- zzfixture-cask|1",
            "install --cask --force -- zzfixture-cask|1",
        ])
    }

    /// A cancel while brew downloads stops the route there: `CancellationError`,
    /// and brew's install never runs. Mutation: `try?` the coordinator's
    /// `homebrew.fetch` and drop the cancellation check `InstallCommit.run`
    /// makes → the install runs.
    @Test func aCancelDuringTheFetchNeverReachesTheInstall() async throws {
        let fetching = FileManager.default.temporaryDirectory
            .appendingPathComponent("brew-fetch-first-fetching-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fetching) }
        // `exec`, so the SIGINT `.interruptChild` sends ends the stand-in's sleep
        // as it would end brew's download.
        let fixture = try Fixture(onFetch: "/usr/bin/touch '\(fetching.path)'; exec /bin/sleep 30")
        defer { fixture.remove() }
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1), runningProcesses: { [] })
        let result = UpdateResult(
            app: InstalledApp(
                name: "Zzfixture", bundleID: "com.example.zzfixture",
                shortVersion: "1.0", buildVersion: "1", path: fixture.app,
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Homebrew",
                sourceIdentifier: "zzfixture-cask"),
            status: .updateAvailable(latest: "1.1"))
        let brewPath = fixture.brew.path
        let install = Task {
            try await HomebrewInstaller.$brewPathOverride.withValue(brewPath) {
                _ = try await coordinator.perform(
                    result, route: .homebrew, installedPopulation: [], digestOnlyAllowed: false,
                    progress: { _ in })
            }
        }
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: fetching.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: fetching.path))
        install.cancel()
        await #expect(throws: CancellationError.self) { try await install.value }
        #expect(!fixture.runs.contains("install --cask --force -- zzfixture-cask|1"))
    }
}
