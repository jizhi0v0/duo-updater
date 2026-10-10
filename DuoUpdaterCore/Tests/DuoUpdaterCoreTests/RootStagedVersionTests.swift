import Testing
import Foundation
@testable import DuoUpdaterCore

/// `SelfUpdaterStaging.rootStagedUpdate`: what an armed row shows once the
/// privileged helper has read, as root, the build Sparkle staged under
/// `/var/root` (#588). Shaped on Tailscale 1.102.3 → 1.102.4 (mac mini,
/// 2026-09-13), with invented identifiers and paths throughout.
struct RootStagedVersionTests {

    private static let bundleID = "com.zzfixture.rootstaged"
    private static let path = URL(fileURLWithPath: "/Applications/ZZFixture-RootStaged.app")

    private func row(installed: (String, String) = ("1.102.3", "101.102.3"),
                     latest: (String, String)? = ("1.102.4", "101.102.4")) -> UpdateResult {
        let app = InstalledApp(
            name: "ZZFixture RootStaged", bundleID: Self.bundleID,
            shortVersion: installed.0, buildVersion: installed.1,
            path: Self.path, isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
        guard let latest else { return UpdateResult(app: app, remote: nil, status: .upToDate) }
        return UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: latest.0, version: latest.1,
                downloadURL: URL(string: "https://example.invalid/ZZFixture.zip"),
                sourceName: "Sparkle"),
            status: .updateAvailable(latest: latest.0))
    }

    private func read(_ identifier: String? = bundleID, _ short: String? = "1.102.4",
                      _ build: String? = "101.102.4") -> SelfUpdaterStaging.RootStagedVersions {
        .init(identifier: identifier, shortVersion: short, buildVersion: build)
    }

    /// The case the helper read exists for: the armed row gets the versioned
    /// staged update, which the rest of the app already knows how to show.
    @Test func anArmedRowGetsTheVersionTheHelperRead() throws {
        let staged = try #require(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read()))
        #expect(staged.version == "1.102.4")
        #expect(staged.buildVersion == "101.102.4")
        #expect(staged.updater == .sparkle)
        #expect(staged.appliesOn == .quit)
    }

    /// Reused end to end, as #588 proposes: put in `pendingSelfUpdate` and taken
    /// out of `armedSelfInstallers`, the row offers the VERSIONED Relaunch and the
    /// version line names the build, not "?".
    @Test func thePromotedRowTakesTheVersionedRelaunchPath() throws {
        let result = row()
        let staged = try #require(SelfUpdaterStaging.rootStagedUpdate(
            for: result, armed: true, read: read()))
        let facts = RowActionFacts.assemble(
            for: result, tables: RowStateTables(pendingSelfUpdate: [result.id: staged]),
            isIgnored: false, isVersionSkipped: false, route: .autoInstall)
        #expect(RowAction.state(for: facts) == .relaunchToApplyStaged(to: "1.102.4"))
        #expect(RowVersionLine.state(
            staged: UpdatePolicy.actionableStaged(result, staged: staged),
            armedWithUnknownVersion: false, pendingBatchRestartMarketing: nil,
            restartFrom: nil, downgradeVersion: nil) == .stagedRelaunch(staged))
    }

    /// Once the id leaves `armedSelfInstallers`, nothing but `canAutoInstall`
    /// keeps the row out of Update All. It does, because the promoted build is
    /// actionable by construction.
    @Test func thePromotedRowStaysOutOfUpdateAll() throws {
        let result = row()
        let staged = try #require(SelfUpdaterStaging.rootStagedUpdate(
            for: result, armed: true, read: read()))
        let settings = UpdateSettings(
            appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
        let withoutStaged = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let withStaged = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [result.id: staged])
        // The fixture is otherwise installable, so the `false` below is the
        // staged build's doing and not some unrelated refusal.
        #expect(UpdatePolicy.canAutoInstall(result, settings: settings, environment: withoutStaged))
        #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: withStaged))
    }

    /// Mutation: drop `armed` from the guard — a read then turns a row with no
    /// parked installer into a Relaunch.
    @Test func aReadNeverStagesAnythingOnARowThatIsNotArmed() {
        #expect(SelfUpdaterStaging.rootStagedUpdate(for: row(), armed: false, read: read()) == nil)
    }

    /// Helper off, helper too old, helper silent or failed: all arrive as no read,
    /// and the row stays version-unknown. (Which of those the client turns into
    /// nil is `HelperProtocolRevision` and `HelperStagedVersionReader`, in the
    /// app's tests and the reader's doc.)
    @Test func noReadLeavesTheRowVersionUnknown() {
        #expect(SelfUpdaterStaging.rootStagedUpdate(for: row(), armed: true, read: nil) == nil)
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read(nil, nil, nil)) == nil)
    }

    /// The helper answers for whatever identifier its plist says; a staged
    /// bundle of something else is not this app's update.
    ///
    /// Mutation: drop `read.identifier == bundleID`.
    @Test func aReadForAnotherIdentifierIsIgnored() {
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read("com.zzfixture.other")) == nil)
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read(Self.bundleID.uppercased())) == nil)
    }

    /// The strings go through `VersionSide.plistVersionField`, as the same-user
    /// read's do: trimmed, and blank is no version.
    ///
    /// Mutation: take `read.shortVersion` as-is — seen red: the padded version no
    /// longer compares as newer, and the row loses a version it could show. (The
    /// blank cases stay nil under that mutation too: `actionableStaged` finds a
    /// blank version not newer than anything.)
    @Test func versionsAreTrimmedAndBlankIsNoVersion() throws {
        let padded = try #require(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read(Self.bundleID, " 1.102.4\n", " 101.102.4 ")))
        #expect(padded.version == "1.102.4")
        #expect(padded.buildVersion == "101.102.4")
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read(Self.bundleID, "   ")) == nil)
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: row(), armed: true, read: read(Self.bundleID, "")) == nil)
    }

    /// A known build that is behind the latest on offer, or not ahead of what is
    /// installed, stays version-unknown. Promoting it would leave the row offering
    /// an Update that the install gate refuses on every click (the gate still sees
    /// the armed installer), or a Relaunch into a downgrade.
    ///
    /// Mutation: return `staged` instead of `UpdatePolicy.actionableStaged(...)`.
    @Test func aKnownButNonActionableBuildStaysVersionUnknown() {
        let trailing = row(latest: ("1.102.5", "101.102.5"))
        #expect(SelfUpdaterStaging.rootStagedUpdate(for: trailing, armed: true, read: read()) == nil)

        let alreadyThere = row(installed: ("1.102.4", "101.102.4"))
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: alreadyThere, armed: true, read: read()) == nil)

        let older = row()
        #expect(SelfUpdaterStaging.rootStagedUpdate(
            for: older, armed: true, read: read(Self.bundleID, "1.102.2", "101.102.2")) == nil)
    }

    /// Reading a version must never open the install gate. The gate takes no
    /// input from the helper: it re-reads the armed state from this user's disk.
    /// So for an armed fixture it still refuses, with the promoted staged build
    /// sitting in the row's tables, and the versioned gate still finds nothing to
    /// clear (root's staging is not in this user's cache).
    ///
    /// No mutation of this change reaches it — there is no seam. It goes red if
    /// someone later wires the read into the gate.
    @Test func theInstallGateStillRefusesAfterARead() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-RootStaged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("Caches")
        let installed = root.appendingPathComponent("ZZFixture-RootStaged.app")
        try FileManager.default.createDirectory(
            at: installed.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let app = InstalledApp(
            name: "ZZFixture RootStaged", bundleID: Self.bundleID,
            shortVersion: "1.102.3", buildVersion: "101.102.3",
            path: installed, isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
        let result = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: "1.102.4", version: "101.102.4",
                downloadURL: URL(string: "https://example.invalid/ZZFixture.pkg"),
                sourceName: "Vendor"),
            status: .updateAvailable(latest: "1.102.4"))
        // Only the Launcher agent in this user's cache, as on the mini.
        let parked = [caches.appendingPathComponent(Self.bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle/Launcher/ZZrand/Updater.app")]

        let armed = SelfUpdaterStaging.sparkleInstallerArmedWithUnreadableStaging(
            for: app, cachesDirectory: caches, parkedInstallerBundleURLs: parked)
        #expect(armed)
        #expect(SelfUpdaterStaging.rootStagedUpdate(for: result, armed: armed, read: read()) != nil)

        #expect(UpdatePolicy.armedInstallerBlocksInstall(result, armed: armed))
        #expect(SelfUpdaterStaging.staged(
            for: app, requireNewerThanInstalled: false, cachesDirectory: caches,
            parkedInstallerBundleURLs: parked) == nil)
    }
}
