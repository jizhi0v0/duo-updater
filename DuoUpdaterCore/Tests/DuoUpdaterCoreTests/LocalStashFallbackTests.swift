import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// A local stash that fails before the swap ends in the route's own download.
///
/// Before this, nothing fell back: the install failed, and every retry picked the
/// same stash again until the app's own updater replaced the file. The coordinator
/// now retries once with `useLocalStash: false` on `LocalStashFailure`.
///
/// The discriminator is WHICH refusal the install ends in. The fixture bundle is
/// unsigned, so the stash fails the signature gate; the route's artifact is a
/// file whose published SHA-512 can never match, so the download fails the
/// checksum gate — a gate that is switched off for a stash (§6 of
/// `docs/engine-notes/self-updater-stash.md`). `checksumMismatch` is therefore
/// only reachable through the retry. Nothing on the host is read: the caches
/// directory is scratch and the installed path is invented and asserted absent.
@Suite(.serialized)
struct LocalStashFallbackTests {

    private static let bundleID = "com.example.zzfixture.stashfallback"
    private static let offered = "9.9.9"
    private static let cacheDirName = "zzstash-fallback-updater"

    private static func zipApp(at destination: URL, scratch: URL) async throws {
        let fm = FileManager.default
        let staging = scratch.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let contents = staging
            .appendingPathComponent("ZZStashFallback.app/Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": offered,
                "CFBundleVersion": offered,
            ], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let made = try await ChildProcess.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent",
             staging.appendingPathComponent("ZZStashFallback.app").path, destination.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
    }

    /// Mutations (each verified red): delete the `catch let failure as
    /// LocalStashFailure` branch in `InstallCoordinator.performRoute` (the install
    /// ends in the stash's own signature refusal); make `applyVerified` stop
    /// wrapping a stash failure (the same); ignore `useLocalStash` in `download`
    /// (the retry takes the stash again).
    @Test func aStashThatFailsVerificationEndsInTheRoutesOwnDownload() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZStashFallback-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // The other updater's cache, laid out as electron-updater leaves it.
        let caches = scratch.appendingPathComponent("caches", isDirectory: true)
        let pending = caches
            .appendingPathComponent(Self.cacheDirName, isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try fm.createDirectory(at: pending, withIntermediateDirectories: true)
        let stashArchive = pending.appendingPathComponent("zzfixture-mac-arm64.zip")
        try await Self.zipApp(at: stashArchive, scratch: scratch)
        let stashBytes = try Data(contentsOf: stashArchive)
        try JSONSerialization
            .data(withJSONObject: [
                "fileName": stashArchive.lastPathComponent,
                "sha512": Data(SHA512.hash(data: stashBytes)).base64EncodedString(),
                "isAdminRightsRequired": false,
            ])
            .write(to: pending.appendingPathComponent("update-info.json"))

        // The route's own artifact, served from disk, with a published digest it
        // can never match.
        let routeArchive = scratch.appendingPathComponent("route-artifact.zip")
        try await Self.zipApp(at: routeArchive, scratch: scratch)
        let wrongDigest = Data(SHA512.hash(data: Data("not this archive".utf8)))
            .base64EncodedString()

        let installedPath = URL(fileURLWithPath: "/Applications/ZZStashFallback-Installed.app")
        #expect(!fm.fileExists(atPath: installedPath.path))
        let app = InstalledApp(
            name: "ZZStashFallback", bundleID: Self.bundleID,
            shortVersion: "1.0.0", buildVersion: "1",
            path: installedPath, isMASApp: false, sparkleFeedURL: nil,
            electronUpdate: ElectronUpdateConfig(
                provider: "github", url: nil, owner: "zzfixture", repo: "zzfixture",
                channel: "latest", updaterCacheDirName: Self.cacheDirName),
            hasSelfUpdater: true,
            releaseChannel: .stable)
        let result = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: Self.offered, version: nil,
                downloadURL: routeArchive,
                sourceName: "GitHub", vendorInstallerKind: .zip,
                expectedSHA512: wrongDigest),
            status: .updateAvailable(latest: Self.offered))

        let vendor = VendorInstaller(stashCachesDirectory: caches)

        // Baseline, both halves: the download phase does take this stash (so the
        // install below starts on it), and skips it when told to.
        let taken = try await vendor.download(result, population: [app], onStage: { _ in })
        #expect(taken.localStash != nil, "the fixture must be a stash the gates accept")
        #expect(taken.bytesDownloaded == 0)
        try? fm.removeItem(at: taken.workDir)
        let skipped = try await vendor.download(
            result, useLocalStash: false, population: [app], onStage: { _ in })
        #expect(skipped.localStash == nil)
        #expect(skipped.bytesDownloaded == Int64(try Data(contentsOf: routeArchive).count))
        try? fm.removeItem(at: skipped.workDir)

        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: { [] },
            vendor: vendor)
        var thrown: Error?
        do {
            _ = try await coordinator.perform(
                result, route: .vendor, installedPopulation: [app],
                digestOnlyAllowed: false, progress: { _ in })
        } catch {
            thrown = error
        }

        guard case VendorInstaller.InstallError.checksumMismatch? = thrown else {
            Issue.record("the stash's refusal must lead to the route's own download, whose checksum gate refuses it here — got \(String(describing: thrown))")
            return
        }
        // The stash belongs to the other updater: still there, byte for byte.
        #expect(try Data(contentsOf: stashArchive) == stashBytes)
    }

    /// Which failures on a stash are worth the route's own download.
    ///
    /// Mutations (each verified red): drop the cancellation, free-space, or OS
    /// floor exclusion from `localStashFailureIsWorthRetrying`.
    @Test func onlyFailuresTheDownloadCouldAvoidAreRetried() {
        // Refusals of these particular bytes.
        #expect(localStashFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.teamIdentifierMismatch(installed: "AAAAAAAAAA", downloaded: "BBBBBBBBBB")))
        #expect(localStashFailureIsWorthRetrying(SignatureVerifier.VerifyError.codeSignatureInvalid(-67062)))
        #expect(localStashFailureIsWorthRetrying(ArchiveExtractor.ExtractError.noAppFound))
        #expect(localStashFailureIsWorthRetrying(
            ArchiveExtractor.ExtractError.toolFailed("ditto", 1, "ditto: Couldn't read PKZip signature")))
        #expect(localStashFailureIsWorthRetrying(VendorInstaller.InstallError.digestOnlyNeedsTheAsset))

        // Not about these bytes, or identical on the route's download.
        #expect(!localStashFailureIsWorthRetrying(CancellationError()))
        #expect(!localStashFailureIsWorthRetrying(DiskSpaceGuard.InsufficientSpace(needed: 2, free: 1)))
        #expect(!localStashFailureIsWorthRetrying(CocoaError(.fileWriteOutOfSpace)))
        #expect(!localStashFailureIsWorthRetrying(POSIXError(.ENOSPC)))
        #expect(!localStashFailureIsWorthRetrying(
            ArchiveExtractor.ExtractError.toolFailed("ditto", 1, "ditto: write: No space left on device")))
        #expect(!localStashFailureIsWorthRetrying(VendorInstaller.InstallError.digestOnlyNotAllowed))
        #expect(!localStashFailureIsWorthRetrying(
            SignatureVerifier.VerifyError.unsupportedSystemVersion(required: "99.0", host: "27.2")))
    }
}
