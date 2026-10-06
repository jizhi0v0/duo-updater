import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `VendorInstallSpec.checksumFormat == .sha256Hex`: the probe hands the digest
/// over as `expectedSHA256`, and `VendorInstaller` checks the download against it
/// before unpacking — for a Developer-ID download, on top of the Team-ID gate.
///
/// The fixture bundle is unsigned, so every case ends in a refusal; the assertion
/// is on WHICH one (as in `LocalStashInstallWiringTests`). `checksumMismatch` means
/// the digest gate stopped it; anything else means it got past that gate.
@Suite(.serialized)
struct VendorSHA256GateTests {

    private static let bundleID = "com.example.zzfixture.sha256gate"

    private static func archive(in scratch: URL) async throws -> URL {
        let fm = FileManager.default
        let contents = scratch.appendingPathComponent("staging/ZZSHA256Gate.app/Contents", isDirectory: true)
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
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent", contents.deletingLastPathComponent().path, archive.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
        return archive
    }

    private static func result(sha256: String?) -> UpdateResult {
        // Invented, and asserted absent below: a real path would put the
        // signature gate on whatever the host has installed.
        let installed = InstalledApp(
            name: "ZZSHA256Gate", bundleID: bundleID, shortVersion: "1.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/ZZSHA256Gate-Installed.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "2.0.0", version: nil,
            downloadURL: URL(string: "https://zzfixture.invalid/app.zip")!,
            sourceName: "Vendor", vendorInstallerKind: .zip, expectedSHA256: sha256)
        return UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: "2.0.0"))
    }

    private static func failure(_ result: UpdateResult, _ download: DownloadedUpdate) async -> Error? {
        do {
            try await VendorInstaller().apply(
                result, download: download, digestOnlyAllowed: false, onStage: { _ in })
            return nil
        } catch {
            return error
        }
    }

    private static func isChecksumMismatch(_ error: Error?) -> Bool {
        if case VendorInstaller.InstallError.checksumMismatch? = error { return true }
        return false
    }

    @Test func theDownloadIsCheckedAgainstThePublishedSHA256() async throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: "/Applications/ZZSHA256Gate-Installed.app"))
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZSHA256Gate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let archive = try await Self.archive(in: scratch)
        let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let download = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: scratch)

        // Another file's digest: refused before anything is unpacked.
        let wrong = SHA256.hash(data: Data("not this archive".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(Self.isChecksumMismatch(await Self.failure(Self.result(sha256: wrong), download)))

        // Its own digest, in either case: past the gate, refused later (unsigned).
        for digest in [actual, actual.uppercased()] {
            let error = await Self.failure(Self.result(sha256: digest), download)
            #expect(error != nil)
            #expect(!Self.isChecksumMismatch(error), "the right digest was refused")
        }

        // A local stash is another updater's container, which this digest does not
        // describe — the same opt-out as the SHA-512 gate.
        let stash = LocalStagedInstaller(
            archiveURL: archive, kind: .zip, version: VersionSide(marketing: "2.0.0", build: "2.0.0"),
            bundleID: Self.bundleID, bytes: 1)
        let stashed = DownloadedUpdate(
            archiveURL: archive, bytesDownloaded: 0, workDir: scratch, finalHost: nil, localStash: stash)
        let stashError = await Self.failure(Self.result(sha256: wrong), stashed)
        #expect(stashError != nil)
        #expect(!Self.isChecksumMismatch(stashError))
    }

    /// The probe puts the captured digest in the field its format names, and only
    /// there — a hex SHA-256 handed to the base64 SHA-512 gate could never match.
    @Test func theProbeFilesTheDigestByItsFormat() throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "dev.hyperframes.desktop" })
        let plan = (url: URL(string: "https://zzfixture.invalid/app.zip")!, checksum: Optional("ab12"))
        for (format, sha512, sha256) in [
            (VendorInstallSpec.ChecksumFormat.sha512Base64, Optional("ab12"), String?.none),
            (.sha256Hex, nil, "ab12"),
        ] {
            let spec = VendorInstallSpec(
                urlSource: .fixed(plan.url), kind: .zip, checksumPattern: "(x)", checksumFormat: format)
            let remote = VendorProbeSource.makeRemoteVersion(
                recipe: recipe, version: "271", install: spec, plan: plan, resolvedDownload: plan.url)
            #expect(remote.expectedSHA512 == sha512)
            #expect(remote.expectedSHA256 == sha256)
            #expect(remote.installTrust == .developerID)
        }
    }
}
