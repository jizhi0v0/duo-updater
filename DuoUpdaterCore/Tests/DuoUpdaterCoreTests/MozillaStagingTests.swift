import Foundation
import Testing
@testable import DuoUpdaterCore

/// Mozilla's own updater: where it stages (`SelfUpdaterStaging.mozillaStagingDirectory`),
/// what counts as staged (`mozillaStaged`), what that means for our install
/// (`UpdatePolicy`), and how a staging is cleared (`MozillaStagingClearance`).
/// Everything lives under a scratch directory; no path names a real install.
///
/// Each case names the mutation it is pinned to.
@Suite(.serialized)
struct MozillaStagingTests {

    private struct Fixture {
        let root: URL
        let caches: URL
        let app: InstalledApp
        /// Where the updater stages for `app`, worked out by hand from Mozilla's rule.
        let stagingDir: URL
    }

    private static func withFixture(
        vendor: String? = "Mozilla", name: String = "Firefox", updater: Bool = true,
        installed: String = "157.0.1", installedBuild: String = "20261005135250",
        _ body: (Fixture) throws -> Void
    ) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("MozillaStagingTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let appPath = root.appendingPathComponent("Applications/Firefox.app", isDirectory: true)
        let contents = appPath.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(
            at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        if updater {
            try fm.createDirectory(
                at: contents.appendingPathComponent("MacOS/updater.app"), withIntermediateDirectories: true)
        }
        var ini = "[App]\n"
        if let vendor { ini += "Vendor=\(vendor)\n" }
        ini += "Name=\(name)\nVersion=\(installed)\nBuildID=\(installedBuild)\n"
        try ini.write(
            to: contents.appendingPathComponent("Resources/application.ini"),
            atomically: true, encoding: .utf8)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        // The rule: drop the leading "/", cut at the last ".app".
        let relative = String(appPath.path.dropFirst()).replacingOccurrences(of: ".app", with: "")
        let stagingDir = caches
            .appendingPathComponent(vendor ?? name, isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
            .appendingPathComponent(relative, isDirectory: true)
            .appendingPathComponent("updates/0", isDirectory: true)
        let app = InstalledApp(
            name: "Firefox", bundleID: "org.mozilla.firefox", shortVersion: installed,
            buildVersion: "15725.10.5", vendorBuildVersion: installedBuild,
            path: appPath, isMASApp: false, sparkleFeedURL: nil)
        try body(Fixture(root: root, caches: caches, app: app, stagingDir: stagingDir))
    }

    /// Lays out `updates/0` the way the updater leaves it.
    private static func stage(
        _ f: Fixture, status: String, version: String = "158.0",
        build: String = "20261007201254",
        appliedBundle: Bool = true, mar: Bool = true, activeUpdateBuild: String? = nil
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: f.stagingDir, withIntermediateDirectories: true)
        try (status + "\n").write(
            to: f.stagingDir.appendingPathComponent("update.status"), atomically: true, encoding: .utf8)
        try version.write(
            to: f.stagingDir.appendingPathComponent("update.version"), atomically: true, encoding: .utf8)
        if appliedBundle {
            let resources = f.stagingDir.appendingPathComponent("Updated.app/Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try "[App]\nVendor=Mozilla\nVersion=\(version)\nBuildID=\(build)\n".write(
                to: resources.appendingPathComponent("application.ini"), atomically: true, encoding: .utf8)
        }
        if let activeUpdateBuild {
            // `active-update.xml` sits beside `updates/`, two levels above `updates/0`.
            try "<updates><update appVersion=\"\(version)\" buildID=\"\(activeUpdateBuild)\"/></updates>".write(
                to: f.stagingDir.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("active-update.xml"),
                atomically: true, encoding: .utf8)
        }
        if mar { try Data([1]).write(to: f.stagingDir.appendingPathComponent("update.mar")) }
    }

    private static func staged(_ f: Fixture, requireNewer: Bool = true) -> StagedSelfUpdate? {
        SelfUpdaterStaging.staged(
            for: f.app, requireNewerThanInstalled: requireNewer, cachesDirectory: f.caches)
    }

    // MARK: - Where

    /// Measured: `/Applications/Firefox.app` staged under
    /// `~/Library/Caches/Mozilla/updates/Applications/Firefox/updates/0`.
    ///
    /// Mutations: keep the leading "/", keep ".app", or skip the vendor segment.
    @Test func theStagingDirectoryFollowsMozillasRule() throws {
        try Self.withFixture { f in
            #expect(SelfUpdaterStaging.mozillaStagingDirectory(for: f.app, cachesDirectory: f.caches)
                    == f.stagingDir)
        }
    }

    /// `GetUpdateRootDir` falls back to the app name when no vendor is set.
    ///
    /// Mutation: always use `Vendor`.
    @Test func withoutAVendorTheAppNameIsUsed() throws {
        try Self.withFixture(vendor: nil, name: "Thunderbird") { f in
            #expect(SelfUpdaterStaging.mozillaStagingDirectory(for: f.app, cachesDirectory: f.caches)
                    == f.stagingDir)
            #expect(f.stagingDir.path.contains("/Thunderbird/updates/"))
        }
    }

    /// A bundle without Mozilla's `updater.app` is not read, whatever its id.
    ///
    /// Mutation: drop the `updater.app` check.
    @Test func aBundleWithoutMozillasUpdaterIsNotRead() throws {
        try Self.withFixture(updater: false) { f in
            #expect(SelfUpdaterStaging.mozillaStagingDirectory(for: f.app, cachesDirectory: f.caches) == nil)
        }
    }

    // MARK: - What counts as staged

    /// The measured state: `applied`, `update.version` 158.0, `Updated.app` built.
    ///
    /// Mutation: drop the Mozilla branch from `staged(for:)`.
    @Test func anAppliedUpdateIsStagedForTheNextLaunch() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied")
            let s = try #require(Self.staged(f))
            #expect(s.version == "158.0")
            #expect(s.updater == .mozilla)
            #expect(s.appliesOn == .launch)
            #expect(s.stagedBundlePath.lastPathComponent == "Updated.app")
            #expect(s.vendorBuild == "20261007201254")
        }
    }

    /// A downloaded MAR not yet applied is also applied at launch.
    ///
    /// Mutation: accept only `applied`.
    @Test func aPendingUpdateIsStagedFromItsMAR() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "pending", appliedBundle: false, activeUpdateBuild: "20261007201254")
            let s = try #require(Self.staged(f))
            #expect(s.stagedBundlePath.lastPathComponent == "update.mar")
            // Mutation: read the pending BuildID from anywhere but active-update.xml.
            #expect(s.vendorBuild == "20261007201254")
        }
    }

    /// Mutation: let the fall-through branch return a staging.
    @Test func downloadingAndFinishedStatesAreNotStaged() throws {
        for status in ["downloading", "applying", "succeeded", "failed: 7"] {
            try Self.withFixture { f in
                try Self.stage(f, status: status)
                #expect(Self.staged(f) == nil, "status \(status)")
            }
        }
    }

    /// An `applied` status whose `Updated.app` is gone has nothing to apply.
    ///
    /// Mutation: drop the existence check.
    @Test func anAppliedStatusWithoutTheBundleIsNotStaged() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied", appliedBundle: false, mar: false)
            #expect(Self.staged(f) == nil)
        }
    }

    /// Relaunch is offered only for a newer build; the install gate still sees an
    /// older one, which the next launch would apply over ours.
    ///
    /// Mutation: ignore `requireNewerThanInstalled`.
    @Test func anOlderStagingIsSeenOnlyWhenAskedFor() throws {
        try Self.withFixture(installed: "158.0") { f in
            try Self.stage(f, status: "applied", version: "157.0.1")
            #expect(Self.staged(f, requireNewer: true) == nil)
            #expect(Self.staged(f, requireNewer: false)?.version == "157.0.1")
        }
    }

    /// `pending-elevate` waits for the user; the launch does not apply it.
    ///
    /// Mutation: drop the `pending-elevate` exclusion.
    @Test func aPendingElevateUpdateIsNotStaged() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "pending-elevate", appliedBundle: false)
            #expect(Self.staged(f) == nil)
        }
    }

    /// A beta's `Version` does not move within its cycle, so a staged build of the
    /// same `Version` counts as newer when its BuildID is.
    ///
    /// Mutation: require the marketing version to move.
    @Test func aNewerBuildOfTheSameBetaVersionIsStaged() throws {
        try Self.withFixture(installed: "155.0", installedBuild: "20260819000000") { f in
            try Self.stage(f, status: "applied", version: "155.0", build: "20260826090609")
            #expect(Self.staged(f)?.vendorBuild == "20260826090609")
        }
    }

    // MARK: - Policy

    private static func result(
        _ f: Fixture, latest: String, latestBuild: String? = nil
    ) -> UpdateResult {
        UpdateResult(
            app: f.app,
            remote: RemoteVersion(
                shortVersion: latest, version: latestBuild,
                buildNamespace: latestBuild == nil ? .bundle : .vendor,
                downloadURL: URL(string: "https://zzfixture.invalid/Firefox.dmg")!,
                sourceName: "Vendor", vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: latest))
    }

    /// Release: `Version` moves every release, and Mozilla's launch skips a staged
    /// update older than the app (`IsOlderVersion`), so a trailing staging can
    /// neither undo our install nor needs clearing.
    ///
    /// Mutation: drop the `mozillaStagingSurvivesInstall` check.
    @Test func aTrailingReleaseStagingDoesNotHoldTheInstall() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied", version: "157.0.2", build: "20261006000000")
            let s = try #require(Self.staged(f, requireNewer: false))
            let r = Self.result(f, latest: "158.0")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) == nil)
        }
    }

    /// The latest already staged is a Relaunch away: no download.
    ///
    /// Mutation: always answer "not the latest" in `mozillaStagedIsLatest`.
    @Test func theLatestReleaseStagedIsARelaunch() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied", version: "158.0")
            let s = try #require(Self.staged(f))
            let r = Self.result(f, latest: "158.0")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s)?.version == "158.0")
            #expect(UpdatePolicy.actionableStaged(r, staged: s)?.version == "158.0")
            #expect(!UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// Review round 2, #1340: ESR is offered as `140.17.0esr`, its staged
    /// `update.version` is `140.17.0`. That is the latest: a Relaunch, not a
    /// clearance and a second download.
    ///
    /// Mutation: compare the offered ESR version with its suffix.
    @Test func theLatestEsrStagedIsARelaunch() throws {
        try Self.withFixture(installed: "140.16.0") { f in
            try Self.stage(f, status: "applied", version: "140.17.0")
            let s = try #require(Self.staged(f))
            let r = Self.result(f, latest: "140.17.0esr")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s)?.version == "140.17.0")
            #expect(UpdatePolicy.actionableStaged(r, staged: s)?.version == "140.17.0")
            #expect(!UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// Review round 1, #1340: Beta 155.0b3 installed, its updater staged b4, b5 is
    /// out. All three have `Version` 155.0, so the launch WOULD apply b4 over a b5
    /// we installed. It blocks, is cleared, and is not offered as a Relaunch.
    ///
    /// Mutation: compare a beta staging on the marketing version (it reads as
    /// already applied and lets the install through).
    @Test func anOlderBuildInTheSameBetaCycleIsCleared() throws {
        try Self.withFixture(installed: "155.0", installedBuild: "20260819000000") { f in
            try Self.stage(f, status: "applied", version: "155.0", build: "20260822000000")
            let s = try #require(Self.staged(f, requireNewer: false))
            let r = Self.result(f, latest: "155.0b5", latestBuild: "20260826090609")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) != nil)
            #expect(UpdatePolicy.clearsStagedBuild(r, staged: s))
            #expect(UpdatePolicy.actionableStaged(r, staged: s) == nil)
        }
    }

    /// The beta the track offers, already staged: Relaunch, nothing to clear.
    ///
    /// Mutation: compare BuildIDs with `!=`.
    @Test func theLatestBetaBuildStagedIsARelaunch() throws {
        try Self.withFixture(installed: "155.0", installedBuild: "20260819000000") { f in
            try Self.stage(f, status: "applied", version: "155.0", build: "20260826090609")
            let s = try #require(Self.staged(f))
            let r = Self.result(f, latest: "155.0b5", latestBuild: "20260826090609")
            #expect(UpdatePolicy.actionableStaged(r, staged: s)?.vendorBuild == "20260826090609")
            #expect(!UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// Review round 1, #1340: 155.0 installed, 156.0b1 staged as `156.0`, 156.0b3
    /// the latest. That is not "the latest staged" (it was offered as a Relaunch),
    /// and the launch would apply it over our 156.0b3, so it is cleared.
    ///
    /// Mutation: drop the Mozilla branch from `actionableStaged` (the generic pair
    /// comparison reads "156.0b3" as not newer than "156.0").
    @Test func anEarlierBetaOfTheNextCycleIsNotTheLatest() throws {
        try Self.withFixture(installed: "155.0", installedBuild: "20260826090609") { f in
            try Self.stage(f, status: "applied", version: "156.0", build: "20260902000000")
            let s = try #require(Self.staged(f))
            let r = Self.result(f, latest: "156.0b3", latestBuild: "20260909000000")
            #expect(UpdatePolicy.actionableStaged(r, staged: s) == nil)
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) != nil)
            #expect(UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// Nightly keeps its suffix in `Version` (`157.0a1`), so the suffix has to be
    /// cut on both sides or a same-cycle staging reads as older and slips through.
    ///
    /// Mutation: cut the suffix from the offered side only.
    @Test func aNightlyStagingInTheSameCycleIsCleared() throws {
        try Self.withFixture(installed: "157.0a1", installedBuild: "20260828000000") { f in
            try Self.stage(f, status: "applied", version: "157.0a1", build: "20260829000000")
            let s = try #require(Self.staged(f, requireNewer: false))
            let r = Self.result(f, latest: "157.0a1", latestBuild: "20260829211045")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) != nil)
            #expect(UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// A staging of the build on disk was applied; the launch just has not cleaned
    /// up. It neither blocks nor is offered.
    ///
    /// Mutation: drop `mozillaStagingApplied` from `stagedBlocksInstall`.
    @Test func aStagingOfTheInstalledBuildIsLeftAlone() throws {
        try Self.withFixture(installed: "155.0", installedBuild: "20260822000000") { f in
            try Self.stage(f, status: "applied", version: "155.0", build: "20260822000000")
            let s = try #require(Self.staged(f, requireNewer: false))
            let r = Self.result(f, latest: "155.0b5", latestBuild: "20260826090609")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) == nil)
            #expect(UpdatePolicy.actionableStaged(r, staged: s) == nil)
        }
    }

    // MARK: - Clearance

    /// Mutation: drop the running check.
    @Test func clearanceIsRefusedWhileTheAppRuns() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied")
            let s = try #require(Self.staged(f))
            let outcome = MozillaStagingClearance.attempt(
                for: f.app, staged: s, cachesDirectory: f.caches,
                isRunning: { _ in true }, fileManager: .default)
            guard case .notCleared = outcome else { Issue.record("cleared while running"); return }
            #expect(FileManager.default.fileExists(atPath: f.stagingDir.path))
        }
    }

    /// Mutation: drop the prefix check.
    @Test func clearanceTouchesOnlyTheDirectoryTheStagingCameFrom() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied")
            let elsewhere = StagedSelfUpdate(
                version: "158.0", buildVersion: nil,
                stagedBundlePath: f.root.appendingPathComponent("Elsewhere/Updated.app"),
                appliesOn: .launch, updater: .mozilla)
            let outcome = MozillaStagingClearance.attempt(
                for: f.app, staged: elsewhere, cachesDirectory: f.caches,
                isRunning: { _ in false }, fileManager: .default)
            guard case .notCleared = outcome else { Issue.record("cleared a foreign path"); return }
            #expect(FileManager.default.fileExists(atPath: f.stagingDir.path))
        }
    }

    /// Mutation: skip the move (return `.cleared` without touching anything).
    @Test func clearanceRemovesTheStagedUpdate() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied")
            let s = try #require(Self.staged(f))
            let outcome = MozillaStagingClearance.attempt(
                for: f.app, staged: s, cachesDirectory: f.caches,
                isRunning: { _ in false }, fileManager: .default)
            guard case .cleared = outcome else { Issue.record("not cleared: \(outcome)"); return }
            #expect(!FileManager.default.fileExists(atPath: f.stagingDir.path))
            #expect(Self.staged(f, requireNewer: false) == nil)
            let leftovers = try FileManager.default.contentsOfDirectory(
                atPath: f.stagingDir.deletingLastPathComponent().path)
            #expect(leftovers.isEmpty, "left behind: \(leftovers)")
        }
    }
}
