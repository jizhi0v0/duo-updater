import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// The routes whose only proof of origin is a digest or an update signature over
/// the archive (`publishedDigestOnly`, `myGoSignatureOnly`, Sparkle without a Team
/// ID), over an installed copy with no developer certificate.
///
/// The proof is checked on the archive's path in this user's temporary directory
/// and the archive is unpacked from that path afterwards, so anything running as
/// this user can put another ad-hoc build in its place between the two. Every later
/// gate then runs on the substitute, and root's re-check pins the substitute's own
/// cdhash. So where the swap needs an administrator it is refused, before the
/// password panel; a copy this user owns is replaced as before. And where the
/// installed copy does have a Team ID, the download is pinned to the offered
/// version, because a same-signer older build passes every other gate.
///
/// No password panel is ever raised: the elevated route runs through
/// `InPlaceSwap.elevatedShellOverride`, which records what it was asked to run.
@Suite struct AdHocRoutesNoElevationTests {

    static let team = "ZZTEAM0007"
    static let identifier = "zz.duoupdater.adhoc"

    struct Fixture {
        let dir: URL
        let apps: URL
        let result: UpdateResult
        let download: DownloadedUpdate
        var installed: URL { result.app.path }
    }

    /// A scratch tree: `apps/` holds the installed copy (1.0.0), `work/` a zip of
    /// the download (`offered`) with its published digest. `sign` makes both.
    private func withFixture(
        _ label: String, offered: String = "2.0.0",
        installedSigning: (URL, String) async throws -> Void,
        downloadedSigning: (URL, String) async throws -> Void,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("no-elevation-\(label)")
        let apps = dir.appendingPathComponent("apps", isDirectory: true)
        defer {
            chmod(apps.path, 0o755)
            try? fm.removeItem(at: dir)
        }
        let installed = apps.appendingPathComponent("App.app")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try await installedSigning(installed, "1.0.0")
        let source = dir.appendingPathComponent("src/App.app")
        try await downloadedSigning(source, offered)
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("download.zip")
        try await DigestOnlyInstallTests.zip(source, to: archive)
        let result = UpdateResult(
            app: InstalledApp(
                name: "App", bundleID: Self.identifier, shortVersion: "1.0.0", buildVersion: "1",
                path: installed, isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: offered, version: nil, downloadURL: archive,
                sourceName: "GitHub", requiresManualInstaller: false, vendorInstallerKind: .zip,
                expectedSHA256: try BundleArchive.sha256(of: archive), installTrust: .publishedDigestOnly),
            status: .updateAvailable(latest: offered))
        try await body(Fixture(
            dir: dir, apps: apps, result: result,
            download: DownloadedUpdate(archiveURL: archive, bytesDownloaded: 0, workDir: work)))
    }

    private func adHoc(_ url: URL, _ version: String) async throws {
        try await DigestOnlyInstallTests.makeApp(
            at: url, bundleID: Self.identifier, version: version, signing: .sealed(identifier: nil))
    }

    private func signed(
        _ identity: SelfSignedCodeSigner.Identity
    ) -> (URL, String) async throws -> Void {
        { url, version in
            try await DigestOnlyInstallTests.makeApp(
                at: url, bundleID: Self.identifier, version: version, signing: .unsigned)
            try await SelfSignedCodeSigner.sign(
                url, identifier: Self.identifier, team: Self.team, with: identity)
        }
    }

    private func version(of app: URL) -> String? {
        SignatureVerifier.infoPlist(of: app)["CFBundleShortVersionString"] as? String
    }

    private func apply(_ fixture: Fixture) async throws {
        try await VendorInstaller().apply(
            fixture.result, download: fixture.download, digestOnlyAllowed: true, onStage: { _ in })
    }

    // MARK: - An ad-hoc copy that needs an administrator

    /// The installed copy is ad-hoc signed and its folder is not writable, so the
    /// swap would raise the administrator panel. It must stop before that — the
    /// shell is never asked to run — and say what to do instead.
    ///
    /// Mutation: drop `if refuseElevation { throw … }` in `InPlaceSwap.replace` →
    /// the shell is run once and the error is the shell's.
    @Test func anElevatedInstallOnAnAdHocDigestRouteIsRefusedBeforeTheShellRuns() async throws {
        try await withFixture(
            "refused", installedSigning: adHoc, downloadedSigning: adHoc
        ) { fixture in
            chmod(fixture.apps.path, 0o555)
            #expect(InPlaceSwap.needsElevatedReplace(target: fixture.installed),
                    "the premise: this install would raise the panel")
            let calls = RestoreRootRecheckTests.Calls()
            let record: @Sendable (String) async throws -> ChildProcess.Outcome = { shell in
                calls.add(shell)
                return try await ChildProcess.run("/usr/bin/false", [], onCancel: .runToCompletion)
            }
            var thrown: Error?
            await InPlaceSwap.$elevatedShellOverride.withValue(record) {
                do { try await apply(fixture) } catch { thrown = error }
            }
            #expect(thrown is UnanchoredElevatedInstallError, "got \(String(describing: thrown))")
            let words = (thrown as? LocalizedError)?.errorDescription ?? ""
            #expect(words.contains("App") && words.contains("It was not updated")
                    && words.contains("Update it by hand"), "\(words)")
            #expect(!words.lowercased().contains("restor"), "install-worded, not restore-worded: \(words)")
            #expect(calls.all.isEmpty, "no administrator shell may run: \(calls.all)")
            #expect(version(of: fixture.installed) == "1.0.0")
        }
    }

    /// The same install on a copy this user owns: no administrator, the swap
    /// lands, and the elevated route is never reached.
    @Test func theSameInstallOnACopyTheUserOwnsStillLands() async throws {
        try await withFixture(
            "owned", installedSigning: adHoc, downloadedSigning: adHoc
        ) { fixture in
            #expect(!InPlaceSwap.needsElevatedReplace(target: fixture.installed))
            let calls = RestoreRootRecheckTests.Calls()
            let record: @Sendable (String) async throws -> ChildProcess.Outcome = { shell in
                calls.add(shell)
                return try await ChildProcess.run("/usr/bin/false", [], onCancel: .runToCompletion)
            }
            try await InPlaceSwap.$elevatedShellOverride.withValue(record) {
                try await apply(fixture)
            }
            #expect(version(of: fixture.installed) == "2.0.0")
            #expect(calls.all.isEmpty)
        }
    }

    // MARK: - The same on Sparkle's key-only route

    /// An ad-hoc copy carrying an `SUPublicEDKey`, updated to a download signed
    /// with the matching key (Sparkle's EdDSA over the archive's bytes).
    private func withSparkleFixture(
        _ label: String, _ body: (Fixture) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("no-elevation-\(label)")
        let apps = dir.appendingPathComponent("apps", isDirectory: true)
        defer {
            chmod(apps.path, 0o755)
            try? fm.removeItem(at: dir)
        }
        let key = Curve25519.Signing.PrivateKey()
        let info: [String: Any] = ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
        let installed = apps.appendingPathComponent("App.app")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try await DigestOnlyInstallTests.makeApp(
            at: installed, bundleID: Self.identifier, version: "1.0.0", build: "1", info: info,
            signing: .sealed(identifier: nil))
        let source = dir.appendingPathComponent("src/App.app")
        try await DigestOnlyInstallTests.makeApp(
            at: source, bundleID: Self.identifier, version: "2.0.0", build: "2", info: info,
            signing: .sealed(identifier: nil))
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("download.zip")
        try await DigestOnlyInstallTests.zip(source, to: archive)
        let signature = try key.signature(for: Data(contentsOf: archive)).base64EncodedString()
        let result = UpdateResult(
            app: InstalledApp(
                name: "App", bundleID: Self.identifier, shortVersion: "1.0.0", buildVersion: "1",
                path: installed, isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/appcast.xml")),
            remote: RemoteVersion(
                shortVersion: "2.0.0", version: "2", downloadURL: archive,
                edSignature: signature, sourceName: "Sparkle", requiresManualInstaller: false),
            status: .updateAvailable(latest: "2"))
        try await body(Fixture(
            dir: dir, apps: apps, result: result,
            download: DownloadedUpdate(archiveURL: archive, bytesDownloaded: 0, workDir: work)))
    }

    /// Mutation: pass `refuseElevation: false` from `SparkleInstaller.applyKeyOnly`
    /// → the shell is run once.
    @Test func anElevatedSparkleKeyOnlyInstallOnAnAdHocCopyIsRefusedBeforeTheShellRuns() async throws {
        try await withSparkleFixture("sparkle-refused") { fixture in
            chmod(fixture.apps.path, 0o555)
            #expect(InPlaceSwap.needsElevatedReplace(target: fixture.installed))
            let calls = RestoreRootRecheckTests.Calls()
            let record: @Sendable (String) async throws -> ChildProcess.Outcome = { shell in
                calls.add(shell)
                return try await ChildProcess.run("/usr/bin/false", [], onCancel: .runToCompletion)
            }
            var thrown: Error?
            await InPlaceSwap.$elevatedShellOverride.withValue(record) {
                do {
                    try await SparkleInstaller().apply(
                        fixture.result, download: fixture.download, onStage: { _ in })
                } catch { thrown = error }
            }
            #expect(thrown is UnanchoredElevatedInstallError, "got \(String(describing: thrown))")
            #expect(calls.all.isEmpty, "no administrator shell may run: \(calls.all)")
            #expect(version(of: fixture.installed) == "1.0.0")
        }
    }

    @Test func aSparkleKeyOnlyInstallOnACopyTheUserOwnsStillLands() async throws {
        try await withSparkleFixture("sparkle-owned") { fixture in
            try await SparkleInstaller().apply(
                fixture.result, download: fixture.download, onStage: { _ in })
            #expect(version(of: fixture.installed) == "2.0.0")
        }
    }

    // MARK: - What counts as "the archive alone"

    /// Ad-hoc over any route but `.developerID`, and nothing else: a copy signed
    /// with a certificate has a requirement root can check the staged copy against.
    @Test func onlyAnAdHocCopyOnAnArchiveProvenRouteHasNothingForRootToCheck() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("archive-alone")
        defer { try? fm.removeItem(at: dir) }
        let vendor = try await SelfSignedCodeSigner.mint(team: Self.team, label: "vendor", in: dir)
        let adHocCopy = dir.appendingPathComponent("a/App.app")
        let certCopy = dir.appendingPathComponent("c/App.app")
        let unsignedCopy = dir.appendingPathComponent("u/App.app")
        try await adHoc(adHocCopy, "1.0.0")
        try await signed(vendor)(certCopy, "1.0.0")
        try await DigestOnlyInstallTests.makeApp(
            at: unsignedCopy, bundleID: Self.identifier, signing: .unsigned)
        let routes: [(String, SignatureVerifier.ArtifactTrust)] = [
            ("publishedDigest", .publishedDigest(
                try DigestOnlyInstallTests.proof(in: dir), bundleID: Self.identifier, version: "2.0.0")),
            ("myGoSignature", .myGoSignature(
                try InstallAuthenticityDRTests.myGoProof(), bundleID: Self.identifier, version: "2.0.0")),
        ]
        let answers = await offCooperativePool {
            var out: [String: Bool] = [:]
            for (name, trust) in routes {
                out["\(name) ad-hoc"] = SignatureVerifier.originRestsOnArchiveAlone(trust: trust, installedApp: adHocCopy)
                out["\(name) unsigned"] = SignatureVerifier.originRestsOnArchiveAlone(trust: trust, installedApp: unsignedCopy)
                out["\(name) certificate"] = SignatureVerifier.originRestsOnArchiveAlone(trust: trust, installedApp: certCopy)
            }
            out["developerID ad-hoc"] = SignatureVerifier.originRestsOnArchiveAlone(trust: .developerID, installedApp: adHocCopy)
            return out
        }
        for (name, _) in routes {
            #expect(answers["\(name) ad-hoc"] == true, "\(name) ad-hoc")
            #expect(answers["\(name) unsigned"] == true, "\(name) unsigned")
            #expect(answers["\(name) certificate"] == false, "\(name) certificate")
        }
        #expect(answers["developerID ad-hoc"] == false)
    }

    // MARK: - A copy with a Team ID: the version is pinned

    /// An older build signed by the same signer satisfies the Team ID, the
    /// identifier and the installed copy's designated requirement, so only the
    /// version separates it from the release that was offered. Both archive-proven
    /// routes share the gate.
    ///
    /// Mutation: drop `verifyOfferedVersion` from `verifyDigestOnlyIdentity`'s
    /// `.teamGate` → the 1.5.0 build is accepted on both routes.
    @Test func aSameSignerBuildOfAnotherReleaseIsRefusedOnTheTeamGate() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("team-version")
        defer { try? fm.removeItem(at: dir) }
        let vendor = try await SelfSignedCodeSigner.mint(team: Self.team, label: "vendor", in: dir)
        let installed = dir.appendingPathComponent("i/App.app")
        try await signed(vendor)(installed, "1.0.0")
        let routes: (String) throws -> [(String, SignatureVerifier.ArtifactTrust)] = { offered in
            [("publishedDigest", .publishedDigest(
                try DigestOnlyInstallTests.proof(in: dir), bundleID: Self.identifier, version: offered)),
             ("myGoSignature", .myGoSignature(
                try InstallAuthenticityDRTests.myGoProof(), bundleID: Self.identifier, version: offered))]
        }
        // The premise: the older build passes the Team gates, so a refusal below
        // can only be the version's.
        let older = dir.appendingPathComponent("older/App.app")
        try await signed(vendor)(older, "1.5.0")
        try await offCooperativePool {
            try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: installed, downloadedApp: older)
            try SignatureVerifier.verifyBundleIdentifierMatch(installedApp: installed, downloadedApp: older)
            try SignatureVerifier.verifySignedLikeInstalledCopy(installedApp: installed, downloadedApp: older)
        }
        for (name, trust) in try routes("2.0.0") {
            await #expect("\(name): another release must be refused") {
                try await SignatureVerifier.verifyInstallArtifact(
                    downloadedApp: older, installedApp: installed, trust: trust)
            } throws: {
                if case SignatureVerifier.VerifyError.infoPlistVersionMismatch(
                    expected: "2.0.0", downloaded: "1.5.0") = $0 { return true }
                return false
            }
        }

        // Vacuity guard: the release that was offered passes the same routes.
        let offered = dir.appendingPathComponent("offered/App.app")
        try await signed(vendor)(offered, "2.0.0")
        for (_, trust) in try routes("2.0.0") {
            try await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: offered, installedApp: installed, trust: trust)
        }

        // No offered version to pin to is a refusal, not a pass.
        for (name, trust) in try routes("") {
            await #expect("\(name): nothing to pin to") {
                try await SignatureVerifier.verifyInstallArtifact(
                    downloadedApp: offered, installedApp: installed, trust: trust)
            } throws: {
                if case SignatureVerifier.VerifyError.infoPlistVersionMismatch = $0 { return true }
                return false
            }
        }
    }

    // MARK: - A copy with a Team ID that needs an administrator

    /// Not every elevated install is refused: with a Team ID the staged copy is
    /// held to the installed copy's designated requirement, which a substitute
    /// cannot meet, so the digest route still takes the administrator shell and
    /// the swap lands.
    @Test func aTeamSignedCopyOnTheDigestRouteStillTakesTheElevatedRoute() async throws {
        let fm = FileManager.default
        let keys = try DigestOnlyInstallTests.scratch("team-elevated-keys")
        defer { try? fm.removeItem(at: keys) }
        let vendor = try await SelfSignedCodeSigner.mint(team: Self.team, label: "vendor", in: keys)
        try await withFixture(
            "team-elevated", installedSigning: signed(vendor), downloadedSigning: signed(vendor)
        ) { fixture in
            let apps = fixture.apps
            chmod(apps.path, 0o555)
            #expect(InPlaceSwap.needsElevatedReplace(target: fixture.installed))
            let calls = RestoreRootRecheckTests.Calls()
            // What root would do, as this user: the folder is made writable again
            // first, then the shell runs.
            let asThisUser: @Sendable (String) async throws -> ChildProcess.Outcome = { shell in
                calls.add(shell)
                chmod(apps.path, 0o755)
                return try await ChildProcess.run("/bin/sh", ["-c", shell], onCancel: .runToCompletion)
            }
            try await InPlaceSwap.$elevatedShellOverride.withValue(asThisUser) {
                try await apply(fixture)
            }
            #expect(calls.all.count == 1, "the install must have reached the elevated route")
            #expect(version(of: fixture.installed) == "2.0.0")
        }
    }
}
