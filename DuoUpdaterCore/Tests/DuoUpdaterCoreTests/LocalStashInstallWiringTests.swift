import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `VendorInstaller.applyVerified`'s two opt-outs for a local stash: the route's
/// `expectedSHA512` and its `nestedArchivePath` describe the artifact the ROUTE
/// publishes, which is a different container from the one the app's own updater
/// downloaded (see `docs/engine-notes/self-updater-stash.md` §6). Running either
/// against the stash fails for a reason that is not true.
///
/// Both cases here end in a refusal — the fixture bundle is unsigned, so the
/// Team/notarization gate rejects it either way, and that is deliberate: the
/// assertion is on WHICH refusal, so "the stash reached the signature gate" and
/// "the stash was rejected as corrupt" cannot be confused for each other. A test
/// that only asserted `apply` throws would pass with the opt-out deleted.
///
/// ⚠️ **Only the checksum opt-out is pinned here. The nested-payload one is not,
/// and cannot be from this fixture** — measured, not assumed. The nested branch's
/// FIRST action is `SignatureVerifier.verifyCodeSignature` on the extracted
/// bundle, so with an unsigned fixture both the "opt-out present" and "opt-out
/// deleted" paths fail identically, as `VerifyError.codeSignatureInvalid(-67062)`.
/// Running that mutation confirms it: the case stays green. Pinning it needs a
/// fixture signed by the same Team as the installed copy, which this suite cannot
/// produce, so the `nestedPayloadMissing` check below is a guard against a future
/// reordering rather than a live discriminator — it is deliberately kept, and
/// deliberately not counted as coverage.
@Suite(.serialized)
struct LocalStashInstallWiringTests {

    private static let bundleID = "com.example.zzfixture.stashwiring"

    /// A zip holding one unsigned `ZZStashWiring.app`, and a stash record for it.
    private static func fixture(
        in scratch: URL
    ) async throws -> (result: UpdateResult, archive: URL, stash: LocalStagedInstaller) {
        let fm = FileManager.default
        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        let app = staging.appendingPathComponent("ZZStashWiring.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": "2.0.0",
                "CFBundleVersion": "2.0.0",
            ], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let archive = scratch.appendingPathComponent("download.zip")
        let made = try await ChildProcess.run(
            "/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, archive.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)

        // Invented, and asserted absent: a real path here would put the signature
        // gate on whatever the host happens to have installed.
        let installedPath = URL(fileURLWithPath: "/Applications/ZZStashWiring-Installed.app")
        #expect(!fm.fileExists(atPath: installedPath.path))
        let installed = InstalledApp(
            name: "ZZStashWiring", bundleID: bundleID,
            shortVersion: "1.0.0", buildVersion: "1",
            path: installedPath, isMASApp: false, sparkleFeedURL: nil)

        // A digest of something else entirely — the point is that it can never
        // match the archive, so reaching the checksum gate is unmistakable.
        let wrongDigest = Data(SHA512.hash(data: Data("not this archive".utf8)))
            .base64EncodedString()
        let remote = RemoteVersion(
            shortVersion: "2.0.0", version: nil,
            downloadURL: URL(string: "https://zzfixture.invalid/app.dmg")!,
            sourceName: "GitHub", vendorInstallerKind: .zip,
            expectedSHA512: wrongDigest,
            nestedArchivePath: "Contents/Resources/nowhere.zip")
        let result = UpdateResult(
            app: installed, remote: remote, status: .updateAvailable(latest: "2.0.0"))

        let stash = LocalStagedInstaller(
            archiveURL: archive, kind: .zip,
            version: VersionSide(marketing: "2.0.0", build: "2.0.0"),
            bundleID: bundleID, bytes: 1)
        return (result, archive, stash)
    }

    private static func failure(
        for download: DownloadedUpdate, result: UpdateResult
    ) async -> Error? {
        do {
            try await VendorInstaller().apply(result, download: download, onStage: { _ in })
            return nil
        } catch {
            return error
        }
    }

    /// Mutation (verified red): drop `download.localStash == nil` from the checksum
    /// guard in `applyVerified` — the stash case then fails as `checksumMismatch`
    /// instead of reaching the signature gate. The same mutation on the
    /// nested-payload guard stays green; see the suite comment for why.
    @Test func theRoutesOwnExpectationsAreNotRunAgainstALocalStash() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZStashWiring-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let (result, archive, stash) = try await Self.fixture(in: scratch)

        // Baseline: an ordinary download DOES get the route's checksum run against
        // it, and stops there. Without this half, the case below could pass because
        // the checksum gate had stopped working for everyone.
        let plain = DownloadedUpdate(
            archiveURL: archive, bytesDownloaded: 1, workDir: scratch)
        let plainError = await Self.failure(for: plain, result: result)
        guard case VendorInstaller.InstallError.checksumMismatch? = plainError else {
            Issue.record("a plain download must still be refused by the route's checksum, got \(String(describing: plainError))")
            return
        }

        // The stash: same archive, same unmatchable digest, same declared nested
        // path — and neither is consulted, so it gets as far as the gate that
        // actually speaks for these bytes.
        let stashed = DownloadedUpdate(
            archiveURL: archive, bytesDownloaded: 0, workDir: scratch,
            finalHost: nil, localStash: stash)
        let stashError = await Self.failure(for: stashed, result: result)

        if case VendorInstaller.InstallError.checksumMismatch? = stashError {
            Issue.record("the route's checksum describes the route's artifact, not the stash — it must not run here")
            return
        }
        if case VendorInstaller.InstallError.nestedPayloadMissing? = stashError {
            Issue.record("the route's nested payload path describes a stub installer, not the stash — it must not run here")
            return
        }
        // Whatever it is, it must still be a refusal: the fixture bundle is
        // unsigned, so skipping the route's expectations must not skip the gate
        // that checks who signed it.
        #expect(stashError != nil, "an unsigned bundle must still be refused")
    }

    /// `adopt` — the download-phase half of the substitution.
    ///
    /// Mutations (each verified red): report `stash.bytes` instead of 0; hand back
    /// `stash.archiveURL` instead of the copy; drop `localStash` from the returned
    /// `DownloadedUpdate` (which is what turns the apply-side opt-outs back on).
    @Test func adoptingAStashCopiesItAndSpendsNoNetworkBytes() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZStashAdopt-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // Stands in for the other updater's cache: a directory we must not write to
        // or delete from.
        let theirCache = scratch.appendingPathComponent("their-cache", isDirectory: true)
        try fm.createDirectory(at: theirCache, withIntermediateDirectories: true)
        let theirArchive = theirCache.appendingPathComponent("zzfixture-mac-arm64.zip")
        try Data("pretend this is an installer".utf8).write(to: theirArchive)

        let workDir = scratch.appendingPathComponent("workdir", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let stash = LocalStagedInstaller(
            archiveURL: theirArchive, kind: .zip,
            version: VersionSide(marketing: "2.0.0", build: "2.0.0"),
            bundleID: Self.bundleID, bytes: 27)
        let adopted = try await VendorInstaller().adopt(stash, into: workDir)

        #expect(adopted.bytesDownloaded == 0, "nothing went over the network")
        #expect(adopted.finalHost == nil, "no host served these bytes")
        #expect(adopted.localStash == stash, "the apply phase has to know these are not the route's artifact")
        #expect(adopted.appliedPatch == nil)

        // The copy is ours and lives in our scratch; the original is untouched.
        #expect(adopted.archiveURL != theirArchive)
        #expect(adopted.archiveURL.path.hasPrefix(workDir.path + "/"),
                "the archive must live in the directory our caller owns and deletes")
        #expect(fm.fileExists(atPath: theirArchive.path),
                "the other updater's file must still be there")
        #expect(try Data(contentsOf: adopted.archiveURL) == Data(contentsOf: theirArchive))
    }
}
