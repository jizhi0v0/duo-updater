import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `SparkleInstaller`'s route for an installed copy without a Team ID: the only
/// anchor is the `SUPublicEDKey` in the installed copy, as for the app's own
/// Sparkle (an ad-hoc copy's designated requirement is its own cdhash, so
/// Sparkle's code-signing check can never pass for it either).
///
/// As in `DigestOnlyInstallTests`, every installer-level case is a REFUSAL, and
/// each fixture that is meant to get past the gate under test carries a second
/// defect behind it — the download's build is older than the installed one, so
/// gate 7 refuses it — so no mutation of the gate under test can carry the
/// install through to the swap. Fixtures are built with that suite's helpers:
/// ad-hoc signing needs no identity and touches no keychain.
@Suite struct SparkleKeyOnlyRouteTests {

    private static let bundleID = DigestOnlyInstallTests.bundleID

    private static func key(_ privateKey: Curve25519.Signing.PrivateKey) -> String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// An installed ad-hoc copy at build 3 carrying `installedKey`, and a zipped
    /// download at build 2 (gate 7's backstop) carrying `downloadKey`, signed by
    /// `signer` — the vendor, unless a case says otherwise.
    private func fixture(
        _ dir: URL,
        installedKey: String?,
        downloadKey: String? = nil,
        downloadCarriesKey: Bool = true,
        downloadBundleID: String = bundleID,
        download: DigestOnlyInstallTests.Signing = .sealed(identifier: nil),
        sign: (Data) throws -> String?
    ) async throws -> (UpdateResult, DownloadedUpdate) {
        let installed = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("installed/App.app"), version: "1.0.0", build: "3",
            info: installedKey.map { ["SUPublicEDKey": $0] } ?? [:],
            signing: .sealed(identifier: nil))
        let source = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("src/App.app"), bundleID: downloadBundleID, build: "2",
            info: downloadCarriesKey ? ((downloadKey ?? installedKey).map { ["SUPublicEDKey": $0] } ?? [:]) : [:],
            signing: download)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("download.zip")
        try await DigestOnlyInstallTests.zip(source, to: archive)
        let result = UpdateResult(
            app: InstalledApp(
                name: "App", bundleID: Self.bundleID, shortVersion: "1.0.0", buildVersion: "3",
                path: installed, isMASApp: false,
                sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
                sparkleEdPublicKey: installedKey),
            remote: RemoteVersion(
                shortVersion: "2.0.0", version: "2", downloadURL: archive,
                edSignature: try sign(try Data(contentsOf: archive)), sourceName: "Sparkle"),
            status: .updateAvailable(latest: "2.0.0"))
        return (result, DownloadedUpdate(archiveURL: archive, bytesDownloaded: 0, workDir: work))
    }

    private func applyError(_ result: UpdateResult, _ download: DownloadedUpdate) async -> Error? {
        do {
            try await SparkleInstaller().apply(result, download: download, onStage: { _ in })
            return nil
        } catch {
            return error
        }
    }

    /// Nothing was unpacked: the gate ran before the archive was extracted.
    private func extracted(_ download: DownloadedUpdate) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: download.workDir.path)) ?? []
        return items.contains { $0 != "download.zip" }
    }

    // MARK: - The route

    /// The backstop itself: a download signed by the installed copy's key, from
    /// an ad-hoc copy, gets through gate 1 and the identity gate and is refused
    /// only for its build. The row's `installedLacksTeamIdentifier` is left false
    /// on purpose: the installer reads the Team ID off the bundle on disk.
    /// Mutations: route by `result.installedLacksTeamIdentifier` instead of the
    /// disk read → `noTeamIdentifier`, red; pass `.developerID` to the artifact
    /// gate → `noTeamIdentifier`, red; drop gate 7 → a swap is attempted.
    @Test func aDownloadSignedWithTheInstalledKeyReachesGateSeven() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-keyonly")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(dir, installedKey: Self.key(vendor)) {
            try vendor.signature(for: $0).base64EncodedString()
        }
        #expect(!result.installedLacksTeamIdentifier)
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.bundleVersionDowngrade? = error else {
            Issue.record("expected gate 7's refusal, got \(String(describing: error))")
            return
        }
    }

    /// No key in the installed copy: nothing ties a download to it, and there is
    /// no Team-ID gate to fall back on as the unsigned-feed route does. Refused
    /// before anything is unpacked. Mutation: fall into the unsigned-feed path
    /// when the key is missing → extracted, then refused for a Team ID, red.
    @Test func aCopyWithNoUpdateKeyIsRefusedBeforeUnpacking() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-nokey")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, download) = try await fixture(dir, installedKey: nil) { _ in "c2ln" }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.noTeamIdentifierOrUpdateKey? = error else {
            Issue.record("expected noTeamIdentifierOrUpdateKey, got \(String(describing: error))")
            return
        }
        #expect(!extracted(download))
    }

    /// A key'd copy and a feed item with no signature. Mutation: treat a missing
    /// signature as "unsigned feed" → red.
    @Test func aMissingSignatureIsRefused() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-nosig")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(dir, installedKey: Self.key(vendor)) { _ in nil }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.edSignatureMissing? = error else {
            Issue.record("expected edSignatureMissing, got \(String(describing: error))")
            return
        }
        #expect(!extracted(download))
    }

    /// The attack the Team-ID route's rotation fallback would let through here:
    /// a download that ships the ATTACKER's key and is signed with it. On the
    /// Team-ID route `isEdKeyRotation` says yes and gate 3 then refuses; this
    /// route has no gate 3, so it must refuse at gate 1 and never extract.
    /// Mutations: hold `edSignatureInvalid` and call `isEdKeyRotation` as the
    /// Team-ID route does → extracted, and refused only at gate 7 (or swapped,
    /// with gate 7 gone), red; verify against the downloaded bundle's key → red.
    @Test func aDownloadSignedWithItsOwnNewKeyIsRefusedAtGateOne() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-rotation")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let attacker = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(
            dir, installedKey: Self.key(vendor), downloadKey: Self.key(attacker)
        ) { try attacker.signature(for: $0).base64EncodedString() }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.edSignatureInvalid? = error else {
            Issue.record("expected edSignatureInvalid, got \(String(describing: error))")
            return
        }
        #expect(!extracted(download))
    }

    /// An update whose bundle dropped its `SUPublicEDKey`, signed with the
    /// installed key: Sparkle refuses it ("only supports rotation, but not
    /// removal"), and installed it would leave the copy with no Team ID and no
    /// key — nothing could update it again. Mutation: drop the key check in
    /// `verifySparkleKeyOnlyIdentity` → refused only at gate 7, red.
    @Test func anUpdateThatDropsItsKeyIsRefused() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-keyremoved")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(
            dir, installedKey: Self.key(vendor), downloadCarriesKey: false
        ) { try vendor.signature(for: $0).base64EncodedString() }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.updateKeyRemoved? = error else {
            Issue.record("expected updateKeyRemoved, got \(String(describing: error))")
            return
        }
    }

    /// A rotation done Sparkle's way — the update ships the vendor's NEW key and
    /// is signed with the installed (old) one — is not a removal and goes on, as
    /// it does for the app's own Sparkle (refused here only by gate 7).
    /// Mutation: require the download's key to equal the installed one → red.
    @Test func aRotationSignedWithTheInstalledKeyGoesOn() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-rotation-ok")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = Curve25519.Signing.PrivateKey()
        let new = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(
            dir, installedKey: Self.key(old), downloadKey: Self.key(new)
        ) { try old.signature(for: $0).base64EncodedString() }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.bundleVersionDowngrade? = error else {
            Issue.record("expected gate 7's refusal, got \(String(describing: error))")
            return
        }
    }

    /// Another app signed with the same key — a vendor shipping two apps under
    /// one key, or a feed pointed at the wrong one. Sparkle itself has no such
    /// check. Mutation: drop the `CFBundleIdentifier` comparison → refused only
    /// at gate 7, red.
    @Test func anotherAppSignedWithTheSameKeyIsRefused() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-otherapp")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let (result, download) = try await fixture(
            dir, installedKey: Self.key(vendor), downloadBundleID: "zz.digest.other"
        ) { try vendor.signature(for: $0).base64EncodedString() }
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.infoPlistIdentifierMismatch? = error else {
            Issue.record("expected infoPlistIdentifierMismatch, got \(String(describing: error))")
            return
        }
    }

    /// A patch is checked against its own signature with the installed key, and
    /// a non-Sparkle patch never runs on this route. Mutations: verify the
    /// archive's signature for a patch download → the patch's signature is never
    /// checked, red; drop the format check → a MyGo patch gets as far as the
    /// patch tool, red.
    @Test func aPatchIsCheckedAgainstItsOwnSignatureWithTheInstalledKey() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-patch")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vendor = Curve25519.Signing.PrivateKey()
        let (result, full) = try await fixture(dir, installedKey: Self.key(vendor)) {
            try vendor.signature(for: $0).base64EncodedString()
        }
        let patchFile = full.workDir.appendingPathComponent("update.delta")
        let patchBytes = Data("not really a patch".utf8)
        try patchBytes.write(to: patchFile)
        func patched(_ patch: DeltaPatch) -> DownloadedUpdate {
            DownloadedUpdate(archiveURL: patchFile, bytesDownloaded: 0, workDir: full.workDir, appliedPatch: patch)
        }
        func underlying(_ error: Error?) -> Error? { (error as? DeltaRouteFailure)?.underlying ?? error }

        // Signed with another key: refused at gate 1. The archive's own signature
        // is the vendor's, so verifying that instead would wrongly pass.
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: patchBytes).base64EncodedString()
        let wrong = await applyError(result, patched(DeltaPatch(
            fromBuild: "3", url: URL(string: "https://example.com/p.delta")!, size: nil, edSignature: stranger)))
        guard case SignatureVerifier.VerifyError.edSignatureInvalid? = underlying(wrong) else {
            Issue.record("expected edSignatureInvalid, got \(String(describing: wrong))")
            return
        }
        // Unsigned: refused at gate 1.
        let none = await applyError(result, patched(DeltaPatch(
            fromBuild: "3", url: URL(string: "https://example.com/p.delta")!, size: nil, edSignature: nil)))
        guard case SignatureVerifier.VerifyError.edSignatureMissing? = underlying(none) else {
            Issue.record("expected edSignatureMissing, got \(String(describing: none))")
            return
        }
        // A MyGo-format patch on the Sparkle route: refused before any check.
        let myGo = await applyError(result, patched(DeltaPatch(
            fromBuild: "3", url: URL(string: "https://example.com/p.delta")!, size: nil,
            edSignature: try vendor.signature(for: patchBytes).base64EncodedString(),
            format: .myGo, publicKey: Self.key(vendor))))
        guard case SignatureVerifier.VerifyError.edSignatureMissing? = underlying(myGo) else {
            Issue.record("expected the MyGo patch refused, got \(String(describing: myGo))")
            return
        }
    }

    // MARK: - The identity gate (no swap: `verifyInstallArtifact` never swaps)

    /// A copy with a Team ID is never judged on the key alone, and a Team ID
    /// that appears only on the download is refused — signing never changes
    /// kind. Mutations: return early for `.teamGate` → a Team copy replaced by an
    /// ad-hoc one, red; accept `.teamAppeared` → red.
    @Test func signingNeverChangesKind() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-kind")
        defer { try? FileManager.default.removeItem(at: dir) }
        let team = try #require(await DigestOnlyInstallTests.teamSignedApp())
        let adHoc = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("adhoc/App.app"), signing: .sealed(identifier: nil))

        #expect(throws: SignatureVerifier.VerifyError.self) {
            try SignatureVerifier.verifySparkleKeyOnlyIdentity(installedApp: team, downloadedApp: adHoc)
        }
        #expect {
            try SignatureVerifier.verifySparkleKeyOnlyIdentity(installedApp: adHoc, downloadedApp: team)
        } throws: {
            if case SignatureVerifier.VerifyError.teamIdentifierAppeared = $0 { return true }
            return false
        }
    }

    /// An installed copy that is signed but not ad-hoc (here: not signed at all,
    /// the shape no certificate covers) takes no ad-hoc download. Mutation: skip
    /// the kind comparison → red.
    @Test func anAdHocDownloadDoesNotReplaceACopyThatIsNotAdHoc() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-unsigned")
        defer { try? FileManager.default.removeItem(at: dir) }
        let unsigned = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("unsigned/App.app"), signing: .unsigned)
        let adHoc = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("adhoc/App.app"), signing: .sealed(identifier: nil))
        #expect {
            try SignatureVerifier.verifySparkleKeyOnlyIdentity(installedApp: unsigned, downloadedApp: adHoc)
        } throws: {
            if case SignatureVerifier.VerifyError.signingKindChanged = $0 { return true }
            return false
        }
    }

    /// The certificate-signed case's check is the designated requirement:
    /// a build satisfies its own and not another signer's. (No self-signed
    /// certificate is minted here — that needs a keychain — so a Developer ID app
    /// stands in for "signed with a certificate".) Mutation: make
    /// `verifySatisfiesDesignatedRequirement` check the download against its OWN
    /// requirement → the ad-hoc build passes, red.
    @Test func theDesignatedRequirementPinsTheCertificate() async throws {
        let dir = try DigestOnlyInstallTests.scratch("sparkle-dr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let team = try #require(await DigestOnlyInstallTests.teamSignedApp())
        let adHoc = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("adhoc/App.app"), signing: .sealed(identifier: nil))
        try SignatureVerifier.verifySatisfiesDesignatedRequirement(installedApp: team, downloadedApp: team)
        #expect {
            try SignatureVerifier.verifySatisfiesDesignatedRequirement(installedApp: team, downloadedApp: adHoc)
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }
        // An ad-hoc copy's requirement is its own cdhash: no other build meets it,
        // which is why the ad-hoc case cannot use this check.
        let other = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("other/App.app"), build: "9", signing: .sealed(identifier: nil))
        #expect {
            try SignatureVerifier.verifySatisfiesDesignatedRequirement(installedApp: adHoc, downloadedApp: other)
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }
    }
}
