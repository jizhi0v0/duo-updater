import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// MyGo's signature of the full archive: read from the manifest for exactly the
/// file being downloaded (`MyGoManifest.archiveSignature`), carried on the
/// `RemoteVersion` when the recipe states a key, and checked by `VendorInstaller`
/// before unpacking.
@Suite(.serialized)
struct MyGoArchiveSignatureTests {

    static let feed = URL(string: "https://cdn.example.com/app/update-darwin-arm64.json")!
    static let archiveURL = URL(string: "https://cdn.example.com/app/app-0.5.3-darwin-arm64.tar.gz")!

    /// The shape of Moshi Go's `update-darwin-arm64.json`, trimmed.
    static func manifest(url: String = archiveURL.absoluteString, signature: String? = "SIG-053") -> String {
        let sig = signature.map { #", "signature": "\#($0)""# } ?? ""
        return #"""
        {
          "version": "0.5.3",
          "date": "2026-10-07T10:16:16Z",
          "url": "\#(url)",
          "size": 15227087\#(sig),
          "deltas": [{"from": "0.5.2", "url": "https://cdn.example.com/app/a.delta", "size": 1, "signature": "SIG-DELTA"}],
          "previous": [{"version": "0.5.2", "url": "https://cdn.example.com/app/app-0.5.2-darwin-arm64.tar.gz", "size": 1, "signature": "SIG-052"}]
        }
        """#
    }

    // MARK: - reading it

    @Test func readsTheSignatureOfTheFileBeingDownloaded() {
        #expect(MyGoManifest.archiveSignature(
            inBody: Self.manifest(), forVersion: "0.5.3", url: Self.archiveURL, feedURL: Self.feed) == "SIG-053")
        // A relative `url` resolves against the feed, as MyGo's updater does.
        #expect(MyGoManifest.archiveSignature(
            inBody: Self.manifest(url: "app-0.5.3-darwin-arm64.tar.gz"), forVersion: "0.5.3",
            url: Self.archiveURL, feedURL: Self.feed) == "SIG-053")
    }

    /// A signature is evidence about one file: none is returned for any other.
    @Test func refusesToPairASignatureWithAnotherFile() {
        // An install URL that is not the manifest's own (here `previous[]`'s).
        #expect(MyGoManifest.archiveSignature(
            inBody: Self.manifest(), forVersion: "0.5.3",
            url: URL(string: "https://cdn.example.com/app/app-0.5.2-darwin-arm64.tar.gz")!,
            feedURL: Self.feed) == nil)
        // A manifest for another version than the one resolved.
        #expect(MyGoManifest.archiveSignature(
            inBody: Self.manifest(), forVersion: "0.5.2", url: Self.archiveURL, feedURL: Self.feed) == nil)
        // No signature published, and a body of another shape.
        #expect(MyGoManifest.archiveSignature(
            inBody: Self.manifest(signature: nil), forVersion: "0.5.3", url: Self.archiveURL) == nil)
        #expect(MyGoManifest.archiveSignature(
            inBody: #"{"version":"0.5.3"}"#, forVersion: "0.5.3", url: Self.archiveURL) == nil)
    }

    // MARK: - the probe

    private static func recipe(url: URL, key: String?) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.mygo", url: url, mode: .responseBody,
            versionPattern: #"\A(?:(?!"deltas"|"previous")[\s\S])*?"version"\s*:\s*"([0-9.]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"\A(?:(?!"deltas"|"previous")[\s\S])*?"url"\s*:\s*"(https://[^"]+\.tar\.gz)""#),
                kind: .tarGz, myGoPublicKey: key))
    }

    @Test func theProbeCarriesTheSignatureOnlyWhenTheRecipeStatesAKey() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.manifest())
        defer { server.stop() }

        let keyed = await VendorProbeSource().probeDiagnostic(Self.recipe(url: server.url, key: "KEY"))
        #expect(keyed.remote?.downloadURL == Self.archiveURL)
        #expect(keyed.remote?.myGoSignature == MyGoSignature(publicKey: "KEY", signature: "SIG-053"))
        #expect(!keyed.warnings.contains(.myGoSignatureNoMatch))

        let unkeyed = await VendorProbeSource().probeDiagnostic(Self.recipe(url: server.url, key: nil))
        #expect(unkeyed.remote?.downloadURL == Self.archiveURL)
        #expect(unkeyed.remote?.myGoSignature == nil)
    }

    /// A stated key and no signature for the file: the version still reads, the
    /// installer will refuse the download, and the sweep is told now.
    @Test func aStatedKeyWithoutASignatureIsFlagged() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.manifest(signature: nil))
        defer { server.stop() }
        let outcome = await VendorProbeSource().probeDiagnostic(Self.recipe(url: server.url, key: "KEY"))
        #expect(outcome.remote?.shortVersion == "0.5.3")
        #expect(outcome.remote?.myGoSignature == MyGoSignature(publicKey: "KEY", signature: nil))
        #expect(outcome.warnings.contains(.myGoSignatureNoMatch))
    }

    // MARK: - the installer

    private static let bundleID = "com.example.zzfixture.mygosig"

    /// An unsigned fixture app in a zip: every install ends in a refusal, and the
    /// assertion is on WHICH one (as in `VendorSHA256GateTests`).
    private static func archive(in scratch: URL) async throws -> URL {
        let fm = FileManager.default
        let contents = scratch.appendingPathComponent("staging/ZZMyGoSig.app/Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": "0.5.3",
                "CFBundleVersion": "0.5.3",
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

    private static func result(_ signature: MyGoSignature?) -> UpdateResult {
        // Invented, and asserted absent below: a real path would put the
        // signature gate on whatever the host has installed.
        let installed = InstalledApp(
            name: "ZZMyGoSig", bundleID: bundleID, shortVersion: "0.5.2", buildVersion: "0.5.2",
            path: URL(fileURLWithPath: "/Applications/ZZMyGoSig-Installed.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "0.5.3", version: nil, downloadURL: archiveURL,
            sourceName: "Vendor", vendorInstallerKind: .zip, myGoSignature: signature)
        return UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: "0.5.3"))
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

    /// The signature gate's own refusals; anything else got past it.
    private static func signatureRefusal(_ error: Error?) -> SignatureVerifier.VerifyError? {
        guard let error = error as? SignatureVerifier.VerifyError else { return nil }
        switch error {
        case .myGoSignatureMissing, .myGoSignatureInvalid: return error
        default: return nil
        }
    }

    @Test func theArchiveIsCheckedAgainstTheStatedKey() async throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: "/Applications/ZZMyGoSig-Installed.app"))
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("ZZMyGoSig-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let archive = try await Self.archive(in: scratch)
        let bytes = try Data(contentsOf: archive)
        let digest = Data(SHA256.hash(data: bytes))
        let download = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: scratch)

        let vendor = Curve25519.Signing.PrivateKey()
        let key = vendor.publicKey.rawRepresentation.base64EncodedString()
        let good = try vendor.signature(for: digest).base64EncodedString()

        // Signed by the stated key: past the gate, refused later (unsigned app).
        let passed = await Self.failure(Self.result(MyGoSignature(publicKey: key, signature: good)), download)
        #expect(passed != nil)
        #expect(Self.signatureRefusal(passed) == nil, "a good signature was refused: \(String(describing: passed))")

        // Another key's signature, and this key's signature over the raw bytes
        // instead of their SHA-256: both refused before anything is unpacked.
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: digest).base64EncodedString()
        let raw = try vendor.signature(for: bytes).base64EncodedString()
        for signature in [stranger, raw] {
            let error = await Self.failure(Self.result(MyGoSignature(publicKey: key, signature: signature)), download)
            guard case .myGoSignatureInvalid? = Self.signatureRefusal(error) else {
                Issue.record("expected myGoSignatureInvalid, got \(String(describing: error))")
                continue
            }
        }

        // A stated key and no signature: refused, never installed unverified.
        let missing = await Self.failure(Self.result(MyGoSignature(publicKey: key, signature: nil)), download)
        guard case .myGoSignatureMissing? = Self.signatureRefusal(missing) else {
            Issue.record("expected myGoSignatureMissing, got \(String(describing: missing))")
            return
        }

        // No key stated: the gate does not run.
        let unkeyed = await Self.failure(Self.result(nil), download)
        #expect(Self.signatureRefusal(unkeyed) == nil)

        // A local stash is another updater's container, which this signature does
        // not describe — the same opt-out as the digest gates.
        let stash = LocalStagedInstaller(
            archiveURL: archive, kind: .zip, version: VersionSide(marketing: "0.5.3", build: "0.5.3"),
            bundleID: Self.bundleID, bytes: 1)
        let stashed = DownloadedUpdate(
            archiveURL: archive, bytesDownloaded: 0, workDir: scratch, finalHost: nil, localStash: stash)
        let stashError = await Self.failure(
            Self.result(MyGoSignature(publicKey: key, signature: stranger)), stashed)
        #expect(Self.signatureRefusal(stashError) == nil)
    }

    /// The MyGo refusals say whose key it is. The Sparkle text ("the app's public
    /// key") would be wrong here: the key is the vendor's MyGo update key, kept in
    /// DuoUpdater's recipe, and the likely benign cause is the vendor changing it.
    /// Both are trust failures, so the delta route retries with the full archive.
    @Test func theRefusalsNameTheVendorsKey() {
        for error in [SignatureVerifier.VerifyError.myGoSignatureMissing, .myGoSignatureInvalid] {
            let text = error.errorDescription ?? ""
            #expect(!text.contains("app's public key") && !text.contains("app’s public key"), "\(text)")
            #expect(!text.contains("EdDSA"), "\(text)")
            #expect(deltaRouteFailureIsWorthRetrying(error))
        }
        #expect(SignatureVerifier.VerifyError.myGoSignatureInvalid.errorDescription?
            .contains("vendor’s update key that DuoUpdater keeps for this app") == true)
        #expect(SignatureVerifier.VerifyError.myGoSignatureMissing.errorDescription?
            .hasPrefix("The update feed gave no signature for this download") == true)
    }
}
