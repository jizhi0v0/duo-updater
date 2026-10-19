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

    private static func zipApp(
        at destination: URL, scratch: URL, bundleID: String = bundleID
    ) async throws {
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

    private static func scratchDirectory() throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZStashFallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    private static func installedApp(
        name: String, bundleID: String, electronUpdate: ElectronUpdateConfig?
    ) -> InstalledApp {
        // Invented, and asserted absent: a real path here would put the gates on
        // whatever the host happens to have installed. Unique per run: the
        // installer's scratch dir in `$TMPDIR` is named off this path and the
        // version, and two test processes sharing one (concurrent CI jobs on the
        // same runner user) deleted and filled it under each other.
        let path = URL(fileURLWithPath: "/Applications/\(name)-\(UUID().uuidString).app")
        #expect(!FileManager.default.fileExists(atPath: path.path))
        return InstalledApp(
            name: name, bundleID: bundleID,
            shortVersion: "1.0.0", buildVersion: "1",
            path: path, isMASApp: false, sparkleFeedURL: nil,
            electronUpdate: electronUpdate,
            hasSelfUpdater: true,
            releaseChannel: .stable)
    }

    /// Installs `app` through the coordinator with `vendor`'s stash in place, and
    /// asserts the install reached the route's own download. Both layouts share
    /// this: the fallback keys on `DownloadedUpdate.localStash`, not on where the
    /// stash was parked.
    private static func expectFallback(
        app: InstalledApp, stashArchive: URL, vendor: VendorInstaller, scratch: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let fm = FileManager.default
        let stashBytes = try Data(contentsOf: stashArchive)

        // The route's own artifact, served from disk, with a published digest it
        // can never match.
        let routeArchive = scratch.appendingPathComponent("route-artifact.zip")
        try await zipApp(at: routeArchive, scratch: scratch, bundleID: app.bundleID ?? "")
        let wrongDigest = Data(SHA512.hash(data: Data("not this archive".utf8)))
            .base64EncodedString()
        let result = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: offered, version: nil,
                downloadURL: routeArchive,
                sourceName: "GitHub", vendorInstallerKind: .zip,
                expectedSHA512: wrongDigest),
            status: .updateAvailable(latest: offered))

        // Baseline, both halves: the download phase does take this stash (so the
        // install below starts on it), and skips it when told to.
        let taken = try await vendor.download(result, population: [app], onStage: { _ in })
        #expect(taken.localStash != nil, "the fixture must be a stash the gates accept",
                sourceLocation: sourceLocation)
        #expect(taken.bytesDownloaded == 0, sourceLocation: sourceLocation)
        try? fm.removeItem(at: taken.workDir)
        let skipped = try await vendor.download(
            result, useLocalStash: false, population: [app], onStage: { _ in })
        #expect(skipped.localStash == nil, sourceLocation: sourceLocation)
        #expect(skipped.bytesDownloaded == Int64(try Data(contentsOf: routeArchive).count),
                sourceLocation: sourceLocation)
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
            Issue.record("the stash's refusal must lead to the route's own download, whose checksum gate refuses it here — got \(String(describing: thrown))",
                         sourceLocation: sourceLocation)
            return
        }
        // The stash belongs to the other updater: still there, byte for byte.
        #expect(try Data(contentsOf: stashArchive) == stashBytes, sourceLocation: sourceLocation)
    }

    /// electron-updater's layout: `<caches>/<updaterCacheDirName>/pending/`.
    ///
    /// Mutations (each verified red): delete the `catch let failure as
    /// LocalStashFailure` branch in `InstallCoordinator.performRoute` (the install
    /// ends in the stash's own signature refusal); make `applyVerified` stop
    /// wrapping a stash failure (the same); ignore `useLocalStash` in `download`
    /// (the retry takes the stash again).
    @Test func anElectronStashThatFailsVerificationEndsInTheRoutesOwnDownload() async throws {
        let fm = FileManager.default
        let scratch = try Self.scratchDirectory()
        defer { try? fm.removeItem(at: scratch) }

        let caches = scratch.appendingPathComponent("caches", isDirectory: true)
        let pending = caches
            .appendingPathComponent(Self.cacheDirName, isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try fm.createDirectory(at: pending, withIntermediateDirectories: true)
        let stashArchive = pending.appendingPathComponent("zzfixture-mac-arm64.zip")
        try await Self.zipApp(at: stashArchive, scratch: scratch)
        try JSONSerialization
            .data(withJSONObject: [
                "fileName": stashArchive.lastPathComponent,
                "sha512": Data(SHA512.hash(data: try Data(contentsOf: stashArchive)))
                    .base64EncodedString(),
                "isAdminRightsRequired": false,
            ])
            .write(to: pending.appendingPathComponent("update-info.json"))

        let app = Self.installedApp(
            name: "ZZStashFallback", bundleID: Self.bundleID,
            electronUpdate: ElectronUpdateConfig(
                provider: "github", url: nil, owner: "zzfixture", repo: "zzfixture",
                channel: "latest", updaterCacheDirName: Self.cacheDirName))
        // An empty Application Support root, so only the electron spot can answer.
        let emptySupport = scratch.appendingPathComponent("support", isDirectory: true)
        try await Self.expectFallback(
            app: app, stashArchive: stashArchive,
            vendor: VendorInstaller(
                stashCachesDirectory: caches, stashApplicationSupportDirectory: emptySupport),
            scratch: scratch)
    }

    /// Cindy's hotfix layout: `<Application Support>/CindyGlobal/updates/`.
    /// Mutations (each verified red): delete the coordinator's `LocalStashFailure`
    /// branch; stop passing `stashApplicationSupportDirectory` to `resolve` (only
    /// the baseline catches that one — without a stash the install downloads
    /// straight away and ends in the same refusal).
    @Test func aCindyHotfixThatFailsVerificationEndsInTheRoutesOwnDownload() async throws {
        let fm = FileManager.default
        let scratch = try Self.scratchDirectory()
        defer { try? fm.removeItem(at: scratch) }

        // The real bundle ID: Cindy's spot is chosen by it.
        let cindyID = CindyChannel.globalBundleID
        let support = scratch.appendingPathComponent("support", isDirectory: true)
        let updates = support
            .appendingPathComponent(try #require(CindyChannel.userDataDirectoryName(forBundleID: cindyID)),
                                    isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
        try fm.createDirectory(at: updates, withIntermediateDirectories: true)
        let stashArchive = updates.appendingPathComponent("cindy-\(Self.offered)-arm64-hotfix.zip")
        try await Self.zipApp(at: stashArchive, scratch: scratch, bundleID: cindyID)
        try JSONSerialization
            .data(withJSONObject: [
                "version": Self.offered, "fileName": stashArchive.lastPathComponent,
                "sha256": SHA256.hash(data: try Data(contentsOf: stashArchive))
                    .map { String(format: "%02x", $0) }.joined(),
                "requireRelogin": false, "enableBeta": false,
            ])
            .write(to: updates.appendingPathComponent("patch-info.json"))

        let app = Self.installedApp(name: "ZZCindyFallback", bundleID: cindyID, electronUpdate: nil)
        // An empty caches root, so only Cindy's spot can answer.
        let emptyCaches = scratch.appendingPathComponent("caches", isDirectory: true)
        try await Self.expectFallback(
            app: app, stashArchive: stashArchive,
            vendor: VendorInstaller(
                stashCachesDirectory: emptyCaches, stashApplicationSupportDirectory: support),
            scratch: scratch)
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
