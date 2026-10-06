import Foundation
import Testing
@testable import DuoUpdaterCore

/// magpie's own updater: `SelfUpdaterStaging.magpieStaged`, the policy that
/// clears a staged build older than the latest, and `MagpieStagingClearance`.
///
/// The case all three exist for, measured 2026-10-06: 0.1.1080 running with
/// 0.1.1082 staged, we installed 0.1.1084, `duo restart` left 0.1.1082 on disk.
struct MagpieStagingTests {

    /// `<root>/magpie.app` installed, and optionally a staging directory beside it.
    private struct Fixture {
        let root: URL
        var app: InstalledApp
        var stagingDir: URL { root.appendingPathComponent(".magpie-update", isDirectory: true) }

        init(installed: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("magpie-staging-\(UUID().uuidString)", isDirectory: true)
            let bundle = root.appendingPathComponent("magpie.app", isDirectory: true)
            try FileManager.default.createDirectory(
                at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            app = InstalledApp(
                name: "magpie", bundleID: "com.yetone.magpie",
                shortVersion: installed, buildVersion: installed,
                path: bundle, isMASApp: false, sparkleFeedURL: nil,
                hasSelfUpdater: false, hasSparkleUpdater: false)
        }

        /// What magpie's `Stage` leaves once it is done: `app/magpie.app`, no zip.
        func stage(_ version: String, bundleID: String = "com.yetone.magpie", zip: Bool = false) throws {
            let contents = stagingDir.appendingPathComponent("app/magpie.app/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": version,
                "CFBundleVersion": version,
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            if zip {
                try Data().write(to: stagingDir.appendingPathComponent("magpie-darwin-arm64.zip"))
            }
        }

        func staged(running: Bool = true, requireNewer: Bool = false) -> StagedSelfUpdate? {
            SelfUpdaterStaging.staged(
                for: app, requireNewerThanInstalled: requireNewer,
                isRunning: { _ in running })
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func readsTheBuildMagpieStagedWhileItRuns() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        let staged = try #require(f.staged())
        #expect(staged.version == "0.1.1082")
        #expect(staged.updater == .magpie)
        #expect(staged.appliesOn == .quit)
        #expect(SelfUpdaterStaging.mayHaveStaging(f.app))
    }

    /// Whether the build gets applied lives in the running process's memory; a
    /// directory left by a magpie that is gone is applied by nobody.
    @Test func nothingIsStagedWithoutARunningMagpie() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        #expect(f.staged(running: false) == nil)
    }

    @Test func aDownloadInProgressIsNotYetStaged() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082", zip: true)
        #expect(f.staged() == nil)
    }

    @Test func anotherBundleInTheStagingDirectoryIsNotMagpies() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082", bundleID: "com.example.other")
        #expect(f.staged() == nil)
    }

    /// The Relaunch affordance asks for newer-than-installed only; the install
    /// gate asks for anything, because a trailing staged build is applied too.
    @Test func olderThanInstalledCountsOnlyForTheInstallGate() throws {
        let f = try Fixture(installed: "0.1.1084")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        #expect(f.staged(requireNewer: true) == nil)
        #expect(f.staged(requireNewer: false)?.version == "0.1.1082")
    }

    // MARK: - policy

    private func result(_ app: InstalledApp, latest: String) -> UpdateResult {
        UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: latest, version: latest,
                downloadURL: URL(string: "https://example.com/m.zip"), sourceName: "GitHub"),
            status: .updateAvailable(latest: latest))
    }

    @Test func clearsOnlyAStagedBuildThatIsNotTheLatest() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        let staged = try #require(f.staged())
        #expect(UpdatePolicy.clearsStagedBuild(result(f.app, latest: "0.1.1084"), staged: staged),
                "trailing the latest — cleared, and our install goes ahead")
        #expect(!UpdatePolicy.clearsStagedBuild(result(f.app, latest: "0.1.1082"), staged: staged),
                "the latest is staged — a Relaunch away, yielded to")
    }

    // MARK: - clear

    @Test func clearingRemovesTheStagingDirectoryAndNothingElse() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        let staged = try #require(f.staged())
        #expect(MagpieStagingClearance.clear(for: f.app, staged: staged) == .cleared)
        #expect(!FileManager.default.fileExists(atPath: f.stagingDir.path))
        #expect(FileManager.default.fileExists(atPath: f.app.path.path))
        let left = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
        #expect(left == ["magpie.app"], "the moved-aside copy is deleted too")
        #expect(f.staged() == nil)
    }

    @Test func aStagingFromElsewhereIsNotTouched() throws {
        let f = try Fixture(installed: "0.1.1080")
        defer { f.cleanup() }
        try f.stage("0.1.1082")
        let foreign = StagedSelfUpdate(
            version: "0.1.1082", buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/elsewhere/magpie.app"),
            updater: .magpie)
        guard case .notCleared(_, touchedInstaller: false) =
            MagpieStagingClearance.clear(for: f.app, staged: foreign)
        else { Issue.record("cleared a staging it did not read"); return }
        #expect(FileManager.default.fileExists(atPath: f.stagingDir.path))
    }
}
