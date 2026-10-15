import Foundation
import Testing
@testable import DuoUpdaterCore

/// Mozilla's own updater: where it stages (`SelfUpdaterStaging.mozillaStagingDirectory`),
/// what counts as staged (`mozillaStaged`), and what that means for our install
/// (`UpdatePolicy`). Everything lives under a scratch directory; no path names a
/// real install.
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
        installed: String = "157.0.1",
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
        ini += "Name=\(name)\nVersion=\(installed)\nBuildID=20261005135250\n"
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
            buildVersion: "15725.10.5", path: appPath, isMASApp: false, sparkleFeedURL: nil)
        try body(Fixture(root: root, caches: caches, app: app, stagingDir: stagingDir))
    }

    /// Lays out `updates/0` the way the updater leaves it.
    private static func stage(
        _ f: Fixture, status: String, version: String = "158.0",
        appliedBundle: Bool = true, mar: Bool = true
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: f.stagingDir, withIntermediateDirectories: true)
        try (status + "\n").write(
            to: f.stagingDir.appendingPathComponent("update.status"), atomically: true, encoding: .utf8)
        try version.write(
            to: f.stagingDir.appendingPathComponent("update.version"), atomically: true, encoding: .utf8)
        if appliedBundle {
            try fm.createDirectory(
                at: f.stagingDir.appendingPathComponent("Updated.app/Contents"),
                withIntermediateDirectories: true)
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
        }
    }

    /// A downloaded MAR not yet applied is also applied at launch.
    ///
    /// Mutation: accept only `applied`.
    @Test func aPendingUpdateIsStagedFromItsMAR() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "pending", appliedBundle: false)
            #expect(Self.staged(f)?.stagedBundlePath.lastPathComponent == "update.mar")
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

    // MARK: - Policy

    private static func result(_ f: Fixture, latest: String) -> UpdateResult {
        UpdateResult(
            app: f.app,
            remote: RemoteVersion(
                shortVersion: latest, version: nil,
                downloadURL: URL(string: "https://zzfixture.invalid/Firefox.dmg")!,
                sourceName: "Vendor", vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: latest))
    }

    /// Mozilla's launch skips a staged update older than the app
    /// (`IsOlderVersion`), so one trailing the latest neither blocks our install
    /// nor needs clearing.
    ///
    /// Mutation: drop the Mozilla exemption from `stagedBlocksInstall`.
    @Test func aTrailingMozillaStagingDoesNotHoldTheInstall() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied", version: "157.0.2")
            let s = try #require(Self.staged(f, requireNewer: false))
            let r = Self.result(f, latest: "158.0")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s) == nil)
            #expect(!UpdatePolicy.clearsStagedBuild(r, staged: s))
        }
    }

    /// The latest already staged is a Relaunch away: no download.
    ///
    /// Mutation: exempt every Mozilla staging in `stagedBlocksInstall`.
    @Test func theLatestStagedIsARelaunch() throws {
        try Self.withFixture { f in
            try Self.stage(f, status: "applied", version: "158.0")
            let s = try #require(Self.staged(f))
            let r = Self.result(f, latest: "158.0")
            #expect(UpdatePolicy.stagedBlocksInstall(r, staged: s)?.version == "158.0")
            #expect(UpdatePolicy.actionableStaged(r, staged: s)?.version == "158.0")
        }
    }
}
