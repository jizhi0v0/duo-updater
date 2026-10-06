import Foundation
import Testing
@testable import DuoUpdaterCore

/// The digest-only route end to end, on real bytes: Alacritty v0.16.1 (ad-hoc
/// signed, published with a GitHub digest) unpacked into a scratch directory,
/// then updated by `InstallCoordinator` — the code both hosts call — to whatever
/// `/releases/latest` answers, with the live digest. Nothing under /Applications
/// is read or written; the install target is the scratch copy.
///
/// Off unless asked for, and meant to be run by hand: it downloads two releases
/// (about 12 MB) and REPLACES a real ad-hoc app bundle, which is the one step no
/// other test takes — whether macOS's App Management gate posts a notification
/// for that inside a temporary directory has not been measured. Run it with
///
///     DUO_DIGEST_E2E=1 swift test --package-path DuoUpdaterCore --filter DigestOnlyEndToEndTests
///
/// Red before green, each against the same scratch install: the setting off,
/// then a download that is not the asset whose digest is published, and only
/// then the real update.
@Suite(.serialized, .enabled(
    if: ProcessInfo.processInfo.environment["DUO_DIGEST_E2E"] == "1",
    "downloads real Alacritty releases and swaps an app bundle in a scratch directory — set DUO_DIGEST_E2E=1 to run it"))
struct DigestOnlyEndToEndTests {

    private static let oldDMG = URL(string:
        "https://github.com/alacritty/alacritty/releases/download/v0.16.1/Alacritty-v0.16.1.dmg")!

    /// Read off disk each time — `Bundle(url:)` caches a bundle's Info.plist per
    /// path, and the path is exactly what stays the same across the swap.
    private static func shortVersion(_ app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?[
            "CFBundleShortVersionString"] as? String
    }

    private static func quarantined(_ app: URL) -> Bool {
        getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    @Test func anAdHocAppIsUpdatedOnlyWithTheSettingOnAndThePublishedBytes() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ZZDigestE2E-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        print("digest e2e scratch: \(root.path)")
        let realInstall = URL(fileURLWithPath: "/Applications/Alacritty.app")
        let realBefore = try? fm.attributesOfItem(atPath: realInstall.path)[.modificationDate] as? Date

        // The installed copy: v0.16.1, fetched by curl (no quarantine) and
        // unpacked by the installer's own extractor (mount -nobrowse -readonly,
        // ditto out, detach).
        let dmg = root.appendingPathComponent("Alacritty-v0.16.1.dmg")
        let fetched = try await ChildProcess.run(
            "/usr/bin/curl", ["-sSfL", "-o", dmg.path, Self.oldDMG.absoluteString],
            onCancel: .runToCompletion)
        #expect(fetched.succeeded, "curl \(Self.oldDMG)")
        let unpack = root.appendingPathComponent("unpack", isDirectory: true)
        try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
        let unpacked = try await ArchiveExtractor.extractApp(from: dmg, workDir: unpack)
        let installedDir = root.appendingPathComponent("Applications", isDirectory: true)
        try fm.createDirectory(at: installedDir, withIntermediateDirectories: true)
        let installedPath = installedDir.appendingPathComponent("Alacritty.app")
        try fm.moveItem(at: unpacked, to: installedPath)
        #expect(Self.shortVersion(installedPath) == "0.16.1")
        #expect(try await offCooperativePool { try SignatureVerifier.teamIdentifier(at: installedPath) } == nil)
        #expect(!Self.quarantined(installedPath))

        let app = InstalledApp(
            name: "Alacritty", bundleID: "org.alacritty", shortVersion: "0.16.1", buildVersion: "1",
            path: installedPath, isMASApp: false, sparkleFeedURL: nil)

        // The live answer, from the shipped rule.
        let rule = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "org.alacritty" })
        let remote = try #require(try await GitHubReleasesSource(rules: [rule]).latestVersion(for: app))
        print("digest e2e latest: \(remote.shortVersion ?? "?") \(remote.downloadURL?.absoluteString ?? "?") sha256=\(remote.expectedSHA256 ?? "nil")")
        #expect(remote.installTrust == .publishedDigestOnly)
        #expect(remote.vendorInstallerKind == .dmg)
        let digest = try #require(remote.expectedSHA256)
        let latest = try #require(remote.shortVersion)
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: latest))
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))

        // Red 1 — the setting off, as it stands at click time.
        do {
            _ = try await coordinator.perform(
                result, route: .vendor, installedPopulation: [app], digestOnlyAllowed: false,
                progress: { _ in })
            Issue.record("installed with the setting off")
        } catch VendorInstaller.InstallError.digestOnlyNotAllowed {
        }
        #expect(Self.shortVersion(installedPath) == "0.16.1")

        // Red 2 — bytes that are not the asset the digest was published for.
        let swapped = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: latest, version: nil, downloadURL: Self.oldDMG,
                sourceName: "GitHub", requiresManualInstaller: false, vendorInstallerKind: .dmg,
                expectedSHA256: digest, installTrust: .publishedDigestOnly),
            status: .updateAvailable(latest: latest))
        do {
            _ = try await coordinator.perform(
                swapped, route: .vendor, installedPopulation: [app], digestOnlyAllowed: true,
                progress: { _ in })
            Issue.record("installed bytes whose digest is not the published one")
        } catch SignatureVerifier.VerifyError.publishedDigestMismatch {
        }
        #expect(Self.shortVersion(installedPath) == "0.16.1")

        // Green — the real update.
        let outcome = try await coordinator.perform(
            result, route: .vendor, installedPopulation: [app], digestOnlyAllowed: true,
            progress: { _ in })
        #expect(outcome.applied)
        #expect(Self.shortVersion(installedPath) == latest)
        let (identifier, team) = try await offCooperativePool {
            try SignatureVerifier.verifyCodeSignature(appAt: installedPath)
            return (try SignatureVerifier.signingIdentifier(at: installedPath),
                    try SignatureVerifier.teamIdentifier(at: installedPath))
        }
        #expect(identifier == "org.alacritty")
        #expect(team == nil)
        #expect(!Self.quarantined(installedPath))

        // And the real install, if there is one, was never touched.
        let realAfter = try? fm.attributesOfItem(atPath: realInstall.path)[.modificationDate] as? Date
        #expect(realBefore == realAfter)
    }
}
