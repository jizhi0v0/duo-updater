import Foundation
import Testing
@testable import DuoUpdaterCore

/// Gate 7: the Sparkle route refuses a download whose `CFBundleVersion` is older
/// than the installed copy's, or that has none — Sparkle's own
/// `SUPlainInstaller performInitialInstallation:` check. See
/// `SignatureVerifier.verifyNoBundleVersionDowngrade`.
///
/// The rule is pinned on bare bundles (a directory and an `Info.plist`, which is
/// all the gate reads). The wiring is pinned through `SparkleInstaller.apply`
/// with a real Team-signed app, the only way to reach the gate past gates 2–6.
@Suite struct BundleVersionDowngradeGateTests {

    private static func scratch(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZBundleVersionGate-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A bundle whose `Info.plist` carries `CFBundleVersion: build`, or no such
    /// key when `build` is nil.
    private static func bundle(_ name: String, in dir: URL, build: Any?) throws -> URL {
        let app = dir.appendingPathComponent("\(name).app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": "zz.bundle-version.fixture"]
        plist["CFBundleVersion"] = build
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    /// Runs the gate over `installed` → `downloaded` builds; nil means "passed".
    private static func gate(installed: Any?, downloaded: Any?) throws -> SignatureVerifier.VerifyError? {
        let dir = try scratch("rule")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try SignatureVerifier.verifyNoBundleVersionDowngrade(
                installedApp: try bundle("Installed", in: dir, build: installed),
                downloadedApp: try bundle("Downloaded", in: dir, build: downloaded))
            return nil
        } catch let error as SignatureVerifier.VerifyError {
            return error
        }
    }

    private static func isDowngrade(_ error: SignatureVerifier.VerifyError?, installed: String, downloaded: String) -> Bool {
        guard case .bundleVersionDowngrade(installed, downloaded)? = error else { return false }
        return true
    }

    private static func isMissing(_ error: SignatureVerifier.VerifyError?) -> Bool {
        guard case .bundleVersionMissing? = error else { return false }
        return true
    }

    // MARK: - The rule

    /// The relabelled-feed case: an archive of build 88413 offered as newer over
    /// an installed 88758. The numbers are Arc's two builds from one
    /// `duo check` (88413 installed, 88758 offered), swapped to make the attack.
    /// Mutation: drop the `throw` or invert the comparison → it passes.
    @Test func anOlderBuildIsRefusedNamingBothBuilds() throws {
        let error = try Self.gate(installed: "88758", downloaded: "88413")
        #expect(Self.isDowngrade(error, installed: "88758", downloaded: "88413"), "got \(String(describing: error))")
        #expect(error?.errorDescription?.contains("88413") == true)
        #expect(error?.errorDescription?.contains("88758") == true)
    }

    /// Sparkle refuses only `NSOrderedDescending`, so a reinstall of the same
    /// build passes there; it must pass here too.
    /// Mutation: `!= .orderedAscending` in place of `== .orderedDescending` → refused.
    @Test func theSameBuildPasses() throws {
        #expect(try Self.gate(installed: "88413", downloaded: "88413") == nil)
        // Equal to the comparator, not as strings: "1.0" and "1.0.0".
        #expect(try Self.gate(installed: "1.0", downloaded: "1.0.0") == nil)
    }

    @Test func aNewerBuildPasses() throws {
        #expect(try Self.gate(installed: "88413", downloaded: "88758") == nil)
    }

    /// Numeric, not lexical: "100" is newer than "99", and "1.9" older than "1.10".
    @Test func buildsCompareByNumberNotByText() throws {
        #expect(try Self.gate(installed: "99", downloaded: "100") == nil)
        let error = try Self.gate(installed: "1.10", downloaded: "1.9")
        #expect(Self.isDowngrade(error, installed: "1.10", downloaded: "1.9"), "got \(String(describing: error))")
    }

    /// Sparkle refuses an update with no `CFBundleVersion` (`!updateVersion`).
    /// An empty or non-string value is no version either.
    /// Mutation: return instead of throwing when the download has none → passes.
    @Test func aDownloadWithoutABuildIsRefused() throws {
        #expect(Self.isMissing(try Self.gate(installed: "100", downloaded: nil)))
        #expect(Self.isMissing(try Self.gate(installed: "100", downloaded: "")))
        #expect(Self.isMissing(try Self.gate(installed: "100", downloaded: "  ")))
        #expect(Self.isMissing(try Self.gate(installed: "100", downloaded: 200)))
        // Refused even with nothing installed to compare against: it is the
        // download that is unreadable.
        #expect(Self.isMissing(try Self.gate(installed: nil, downloaded: nil)))
    }

    /// Nothing to compare against, and the feed cannot change the installed copy.
    @Test func anInstalledCopyWithoutABuildLetsTheDownloadThrough() throws {
        #expect(try Self.gate(installed: nil, downloaded: "1") == nil)
        #expect(try Self.gate(installed: "", downloaded: "1") == nil)
    }

    /// Sparkle's comparator stops at the first `-`; `VersionComparator` reads on.
    /// Without the cut, "1234-def" over "1234-abc" reads as a downgrade here and
    /// as the same build to the app's own Sparkle.
    /// Mutation: compare the whole strings → the first expectation fails.
    @Test func everythingFromTheFirstDashOnIsIgnoredAsSparkleDoes() throws {
        #expect(try Self.gate(installed: "1234-def", downloaded: "1234-abc") == nil)
        #expect(try Self.gate(installed: "1234-9", downloaded: "1234-10") == nil)
        let error = try Self.gate(installed: "1235-a", downloaded: "1234-z")
        #expect(Self.isDowngrade(error, installed: "1235-a", downloaded: "1234-z"), "got \(String(describing: error))")
    }

    /// The gate's refusal is final on the patch route: the full archive comes from
    /// the same feed entry. Mutation: classify it as retryable → fails.
    @Test func aDowngradeOnThePatchRouteIsNotRetriedWithTheFullArchive() {
        #expect(!deltaRouteFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.bundleVersionDowngrade(installed: "2", downloaded: "1")))
        #expect(!deltaRouteFailureIsWorthRetrying(SignatureVerifier.VerifyError.bundleVersionMissing))
    }

    // MARK: - Wiring

    /// `SparkleInstaller.apply` reaches gate 7 and refuses there. The download is
    /// an unmodified Team-signed app from inside Xcode, so gates 2–6 pass it; the
    /// installed copy is the same app with a higher `CFBundleVersion` written
    /// in. Editing the installed copy breaks its seal, which no gate checks:
    /// gates 3 and 4 read the installed side's signing information, not its
    /// validity. No `SUPublicEDKey` on the installed app, so this takes the
    /// unsigned-feed path and needs no Ed25519 keypair.
    ///
    /// Mutation: delete the `verifyNoBundleVersionDowngrade` call from
    /// `SparkleInstaller.applyVerified` → the swap goes ahead (into this scratch
    /// directory) and the test fails.
    @Test func sparkleInstallerRefusesAnOlderBuildBeforeTheSwap() async throws {
        guard let source = await DigestOnlyInstallTests.teamSignedApp() else { return }
        let dir = try Self.scratch("wiring")
        defer { try? FileManager.default.removeItem(at: dir) }

        let installedDir = dir.appendingPathComponent("installed")
        let downloadDir = dir.appendingPathComponent("download-src")
        for sub in [installedDir, downloadDir] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        let installed = installedDir.appendingPathComponent(source.lastPathComponent)
        let downloaded = downloadDir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: installed)
        try FileManager.default.copyItem(at: source, to: downloaded)

        let downloadedBuild = try #require(
            SignatureVerifier.infoPlist(of: downloaded)["CFBundleVersion"] as? String)
        let higher = "99999999"
        #expect(VersionComparator.isNewer(higher, than: downloadedBuild))
        let plistURL = installed.appendingPathComponent("Contents/Info.plist")
        var plist = SignatureVerifier.infoPlist(of: installed)
        plist["CFBundleVersion"] = higher
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: plistURL)

        let archive = dir.appendingPathComponent("download.zip")
        try await DigestOnlyInstallTests.zip(downloaded, to: archive)

        let app = InstalledApp(
            name: installed.deletingPathExtension().lastPathComponent,
            bundleID: plist["CFBundleIdentifier"] as? String,
            shortVersion: plist["CFBundleShortVersionString"] as? String, buildVersion: higher,
            path: installed, isMASApp: false, sparkleFeedURL: nil)
        // The feed's claim: a newer build than the one installed.
        let remote = RemoteVersion(
            shortVersion: "999.0", version: "999999999", downloadURL: archive, sourceName: "Sparkle")
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "999.0"))
        let download = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 0, workDir: dir)

        do {
            try await SparkleInstaller().apply(result, download: download, onStage: { _ in })
            Issue.record("SparkleInstaller.apply must refuse an older CFBundleVersion than the installed one")
        } catch {
            guard case SignatureVerifier.VerifyError.bundleVersionDowngrade(higher, downloadedBuild) = error else {
                Issue.record("expected .bundleVersionDowngrade(\(higher), \(downloadedBuild)), got \(error) — is gate 7 still called from apply()?")
                return
            }
        }
        // Refused before the swap: the installed copy is the one written above.
        #expect(SignatureVerifier.infoPlist(of: installed)["CFBundleVersion"] as? String == higher)
    }
}
