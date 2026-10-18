import Foundation
import Testing
@testable import DuoUpdaterCore

/// An installed copy without a Team ID gets no one-click on a route that pins
/// one (`UpdatePolicy.lacksTeamIdentifierForRoute`), and `UpdateChecker` is what
/// reads that off the bundle. The case behind it: CmdPalm, self-signed, offered
/// a Sparkle Update that could only fail with "Could not read a Team Identifier
/// from the installed app" (user report, 2026-10-18). Every app and source here
/// is invented.
@Suite struct NoTeamIdentifierOfferTests {

    private static func app(path: String = "/Applications/ZZFixtureNoTeam.app", edKey: String? = "key")
        -> InstalledApp {
        InstalledApp(
            name: "ZZFixtureNoTeam", bundleID: "com.example.zzfixture-noteam",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: path), isMASApp: false,
            sparkleFeedURL: nil, sparkleEdPublicKey: edKey)
    }

    private static func result(
        source: String, url: String = "https://example.com/zz.zip",
        kind: VendorInstallerKind? = nil, trust: InstallTrust = .developerID,
        sha: String? = nil, cask: String? = nil, lacksTeam: Bool
    ) -> UpdateResult {
        var row = UpdateResult(
            app: app(),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil, downloadURL: URL(string: url),
                edSignature: "sig", sourceName: source, sourceIdentifier: cask,
                requiresManualInstaller: false, vendorInstallerKind: kind,
                expectedSHA256: sha, installTrust: trust),
            status: .updateAvailable(latest: "2.0"))
        row.installedLacksTeamIdentifier = lacksTeam
        return row
    }

    private static let settings = UpdateSettings(
        appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning,
        declinedElevationKeys: [], allowsDigestOnlyInstalls: true)
    private static let environment = InstallEnvironment(
        isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])

    private static func offered(_ row: UpdateResult) -> Bool {
        UpdatePolicy.canAutoInstall(row, settings: settings, environment: environment, osVersion: "27.0")
    }

    private static func installer(_ row: UpdateResult) -> Bool {
        UpdatePolicy.requiresInstaller(row, environment: environment)
    }

    // MARK: - The offer

    /// The CmdPalm shape. Mutation: drop the check in `canAutoInstall` → red.
    @Test func aSparkleUpdateOverACopyWithoutATeamIDIsNotOffered() {
        #expect(Self.offered(Self.result(source: "Sparkle", lacksTeam: false)))
        #expect(!Self.offered(Self.result(source: "Sparkle", lacksTeam: true)))
    }

    /// A signed Sparkle package goes to `PackageInstaller`, which refuses the
    /// same copy. Mutation: drop the check in `requiresInstaller` → red.
    @Test func aSparklePackageOverACopyWithoutATeamIDIsNotOffered() {
        let pkg = "https://example.com/zz.pkg"
        #expect(Self.installer(Self.result(source: "Sparkle", url: pkg, lacksTeam: false)))
        #expect(!Self.installer(Self.result(source: "Sparkle", url: pkg, lacksTeam: true)))
    }

    /// GitHub, vendor and Electron downloads on `.developerID` run gate 3 too.
    @Test func aDeveloperIDDownloadOverACopyWithoutATeamIDIsNotOffered() {
        for source in ["GitHub", "Vendor", "Electron"] {
            #expect(Self.offered(Self.result(source: source, kind: .zip, lacksTeam: false)), "\(source)")
            #expect(!Self.offered(Self.result(source: source, kind: .zip, lacksTeam: true)), "\(source)")
            #expect(!Self.installer(Self.result(
                source: source, url: "https://example.com/zz.pkg", kind: .pkg, lacksTeam: true)), "\(source)")
        }
    }

    /// The digest-only route exists for a copy without a Team ID and keeps its
    /// own setting. Mutation: return true for every GitHub row in
    /// `lacksTeamIdentifierForRoute` → red.
    @Test func theDigestOnlyRouteIsStillOffered() {
        #expect(Self.offered(Self.result(
            source: "GitHub", kind: .zip, trust: .publishedDigestOnly,
            sha: String(repeating: "a", count: 64), lacksTeam: true)))
    }

    /// Homebrew runs none of our gates. Mutation: return true for every source
    /// in `lacksTeamIdentifierForRoute` → red.
    @Test func homebrewIsStillOffered() {
        #expect(Self.offered(Self.result(source: "Homebrew", cask: "zzfixture", lacksTeam: true)))
    }

    /// A rescan rebuilds every row through `carriedForward`, which is how the
    /// Update button came back on the real machine before this was carried.
    /// Mutation: drop the assignment in `carriedForward` → red; carry it
    /// regardless of `sameCopy` → red.
    @Test func aRescanKeepsTheReadingOnlyForTheSameCopy() {
        let row = Self.result(source: "Sparkle", lacksTeam: true)
        let same = row.carriedForward(onto: row.app, remote: row.remote, status: row.status, proven: nil)
        #expect(same.installedLacksTeamIdentifier)
        #expect(!Self.offered(same))
        let moved = InstalledApp(
            name: row.app.name, bundleID: row.app.bundleID, shortVersion: "1.5", buildVersion: "15",
            path: row.app.path, isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: "key")
        #expect(!row.carriedForward(onto: moved, remote: row.remote, status: row.status, proven: nil)
            .installedLacksTeamIdentifier)
    }

    // MARK: - What UpdateChecker reads

    private struct Answers: UpdateSource {
        let name = "Sparkle"
        let version: String
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            RemoteVersion(
                shortVersion: version, version: version,
                downloadURL: URL(string: "https://example.com/zz.zip"),
                edSignature: "sig", sourceName: name, requiresManualInstaller: false)
        }
    }

    private static func checked(_ path: String, offering version: String) async -> UpdateResult {
        await UpdateChecker(sources: [Answers(version: version)])
            .check(InstalledApp(
                name: "ZZFixtureNoTeam", bundleID: "com.example.zzfixture-noteam",
                shortVersion: "1.0", buildVersion: "1.0",
                path: URL(fileURLWithPath: path), isMASApp: false,
                sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
                sparkleEdPublicKey: "key"))
    }

    /// An ad-hoc signed bundle has no Team ID. Mutation: never set the flag in
    /// `UpdateChecker.check(_:)` → red.
    @Test func theCheckerMarksAnUpdateOverACopyWithoutATeamID() async throws {
        let dir = try DigestOnlyInstallTests.scratch("noteam")
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("ZZFixtureNoTeam.app"), signing: .sealed(identifier: nil))
        let row = await Self.checked(bundle.path, offering: "3.0")
        #expect(row.hasUpdate)
        #expect(row.installedLacksTeamIdentifier)
    }

    /// Xcode carries Apple's Team ID. Mutation: set the flag for every update →
    /// red.
    @Test func theCheckerLeavesACopyWithATeamIDAlone() async throws {
        let xcode = try #require(await Self.xcodeBundle(), "needs the Xcode.app `xcode-select -p` points into")
        let row = await Self.checked(xcode.path, offering: "999.0")
        #expect(row.hasUpdate)
        #expect(!row.installedLacksTeamIdentifier)
    }

    /// The read is only for rows with an update. Mutation: drop `hasUpdate` →
    /// red, since this path does not exist and so reads as having no Team ID.
    @Test func theCheckerDoesNotReadWithoutAnUpdate() async {
        let row = await Self.checked("/Applications/ZZFixtureMissing.app", offering: "1.0")
        #expect(!row.hasUpdate)
        #expect(!row.installedLacksTeamIdentifier)
    }

    // MARK: - Fixtures

    /// The Xcode.app that `xcode-select -p` points into, if it is one.
    private static func xcodeBundle() async -> URL? {
        guard let outcome = try? await ChildProcess.run(
            "/usr/bin/xcode-select", ["-p"], standardOutput: .capture, onCancel: .runToCompletion),
              outcome.terminationStatus == 0 else { return nil }
        let developer = String(decoding: outcome.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard developer.hasSuffix(".app/Contents/Developer") else { return nil }
        return URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent()
    }
}
