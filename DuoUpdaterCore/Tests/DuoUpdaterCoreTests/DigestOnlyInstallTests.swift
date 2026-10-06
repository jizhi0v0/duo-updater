import Foundation
import Testing
@testable import DuoUpdaterCore

/// The digest-only route: an ad-hoc signed GitHub app (no Team ID to gate on),
/// one-clicked only when the user allowed it, on the strength of the SHA-256
/// GitHub's API publishes for the asset. See `InstallTrust.publishedDigestOnly`.
///
/// Every installer-level case here is a REFUSAL, and each fixture carries a
/// second defect behind the one under test (a version that is not the release's)
/// so that no mutation of the gate under test can carry the install through to
/// the swap: nothing in this suite replaces a bundle, mutated or not. The gates
/// that would need a passing fixture to reach are tested one level down, on
/// `SignatureVerifier.verifyInstallArtifact`, which never swaps anything.
///
/// Fixtures are built here rather than downloaded: `clang` links a one-line
/// executable (which the linker ad-hoc signs, the MarkText shape), and
/// `codesign --sign -` seals the bundle (the Alacritty shape) — ad-hoc signing
/// needs no identity and touches no keychain. The Team-ID side is a small app
/// from inside the Xcode that builds this, read in place and never modified.
@Suite struct DigestOnlyInstallTests {

    static let bundleID = "zz.digest.fixture"

    // MARK: - The digest GitHub publishes

    /// Mutation: drop `hex.count == 64` → a truncated digest is accepted.
    @Test func onlyASha256DigestOfSixtyFourHexDigitsIsRead() {
        let hex = String(repeating: "aB", count: 32)
        #expect(GitHubReleasesSource.sha256Digest("sha256:\(hex)") == hex.lowercased())
        #expect(GitHubReleasesSource.sha256Digest(nil) == nil)
        #expect(GitHubReleasesSource.sha256Digest(NSNull()) == nil)
        #expect(GitHubReleasesSource.sha256Digest("sha512:\(hex)") == nil)
        #expect(GitHubReleasesSource.sha256Digest("sha256:\(hex.dropLast())") == nil)
        #expect(GitHubReleasesSource.sha256Digest("sha256:\(String(repeating: "g", count: 64))") == nil)
        #expect(GitHubReleasesSource.sha256Digest(hex) == nil)
    }

    // MARK: - What the source carries

    static let armDigest = String(repeating: "a", count: 64)
    static let intelDigest = String(repeating: "b", count: 64)

    /// Serves one release per slug from `payloads` — the Intel asset listed
    /// FIRST, so taking the first digest in the release is visibly wrong.
    final class StubReleases: URLProtocol, @unchecked Sendable {
        static let payloads: [String: String] = [
            "zz-digest/both": """
                {"tag_name":"v2.0.0","name":"v2.0.0","draft":false,"prerelease":false,
                 "published_at":"2026-09-01T00:00:00Z","body":"notes","assets":[
                 {"name":"App-2.0.0-x86_64.dmg","size":1,"digest":"sha256:\(intelDigest)",
                  "browser_download_url":"https://github.com/zz-digest/both/releases/download/v2.0.0/App-2.0.0-x86_64.dmg"},
                 {"name":"App-2.0.0-arm64.dmg","size":1,"digest":"sha256:\(armDigest)",
                  "browser_download_url":"https://github.com/zz-digest/both/releases/download/v2.0.0/App-2.0.0-arm64.dmg"}]}
                """,
            "zz-digest/none": """
                {"tag_name":"v2.0.0","name":"v2.0.0","draft":false,"prerelease":false,
                 "published_at":"2026-09-01T00:00:00Z","body":"notes","assets":[
                 {"name":"App-2.0.0-arm64.dmg","size":1,"digest":null,
                  "browser_download_url":"https://github.com/zz-digest/none/releases/download/v2.0.0/App-2.0.0-arm64.dmg"}]}
                """,
        ]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let body = Self.payloads.first { url.contains("/repos/\($0.key)/") }?.value ?? "{}"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func resolve(_ slug: String, trust: InstallTrust) async -> RemoteVersion? {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let parts = slug.split(separator: "/")
        let rule = GitHubReleaseRule(
            bundleID: Self.bundleID, owner: String(parts[0]), repo: String(parts[1]),
            installAssetPattern: #"^App-[0-9.]+-(arm64|x86_64)\.dmg$"#,
            installerKind: .dmg, installTrust: trust)
        let source = GitHubReleasesSource(rules: [rule], session: URLSession(configuration: config))
        return await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false).remote
    }

    /// Mutation: take the release's first digest instead of the chosen asset's →
    /// the Intel asset's digest rides along with the arm64 URL.
    @Test func theDigestCarriedIsTheChosenAssetsOwn() async {
        let remote = await resolve("zz-digest/both", trust: .publishedDigestOnly)
        #expect(remote?.downloadURL?.lastPathComponent == "App-2.0.0-arm64.dmg")
        #expect(remote?.expectedSHA256 == Self.armDigest)
        #expect(remote?.installTrust == .publishedDigestOnly)
        #expect(remote?.vendorInstallerKind == .dmg)
    }

    /// A Team-ID rule carries the chosen asset's digest too, so `VendorInstaller`
    /// checks the download before the Team-ID gate — and it is the arm64 asset's,
    /// not the Intel one listed first.
    /// Mutations: restore `installTrust == .publishedDigestOnly ? digest : nil` →
    /// nil here; take the release's first digest → the Intel digest.
    @Test func aTeamIDRuleCarriesTheChosenAssetsDigestToo() async {
        let remote = await resolve("zz-digest/both", trust: .developerID)
        #expect(remote?.downloadURL?.lastPathComponent == "App-2.0.0-arm64.dmg")
        #expect(remote?.expectedSHA256 == Self.armDigest)
        #expect(remote?.installTrust == .developerID)
        #expect(remote?.vendorInstallerKind == .dmg)
        #expect(remote?.requiresManualInstaller == false)
    }

    /// Mutation: drop `|| digest != nil` from `installable` → a digest-only rule
    /// offers an asset there is nothing to check against.
    @Test func aDigestOnlyAssetWithoutADigestIsDetectionOnly() async {
        let remote = await resolve("zz-digest/none", trust: .publishedDigestOnly)
        #expect(remote?.shortVersion == "2.0.0", "the version is still reported")
        #expect(remote?.vendorInstallerKind == nil)
        #expect(remote?.requiresManualInstaller == true)
        #expect(remote?.expectedSHA256 == nil)
        // A Team-ID rule never needed a digest, and still doesn't.
        let team = await resolve("zz-digest/none", trust: .developerID)
        #expect(team?.vendorInstallerKind == .dmg)
        #expect(team?.requiresManualInstaller == false)
        #expect(team?.expectedSHA256 == nil)
        #expect(team?.installTrust == .developerID)
    }

    // MARK: - The offer

    private func offer(
        trust: InstallTrust, digest: String? = armDigest, kind: VendorInstallerKind = .dmg
    ) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: Self.bundleID, shortVersion: "1.0.0", buildVersion: "1",
                path: URL(fileURLWithPath: "/Applications/ZZDigestFixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "2.0.0", version: nil,
                downloadURL: URL(string: "https://github.com/zz/zz/releases/download/v2.0.0/App.dmg"),
                sourceName: "GitHub", requiresManualInstaller: false,
                vendorInstallerKind: kind, expectedSHA256: digest, installTrust: trust),
            status: .updateAvailable(latest: "2.0.0"))
    }

    private func settings(allowing: Bool) -> UpdateSettings {
        UpdateSettings(
            appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite,
            allowsDigestOnlyInstalls: allowing)
    }

    private let environment = InstallEnvironment(
        isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])

    /// Mutations: drop `settings.allowsDigestOnlyInstalls` → offered while off;
    /// drop `expectedSHA256 != nil` → offered with nothing to check.
    @Test func aDigestOnlyUpdateIsOfferedOnlyWhenAllowedAndDigested() {
        #expect(!UpdatePolicy.canAutoInstall(
            offer(trust: .publishedDigestOnly), settings: settings(allowing: false),
            environment: environment))
        #expect(UpdatePolicy.canAutoInstall(
            offer(trust: .publishedDigestOnly), settings: settings(allowing: true),
            environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(
            offer(trust: .publishedDigestOnly, digest: nil), settings: settings(allowing: true),
            environment: environment))
        // The setting says nothing about a Team-ID update, either way.
        for allowing in [false, true] {
            #expect(UpdatePolicy.canAutoInstall(
                offer(trust: .developerID, digest: nil), settings: settings(allowing: allowing),
                environment: environment))
        }
    }

    /// What the detail pane says. Mutations: drop the `hasUpdate` guard → an
    /// up-to-date row carries a caption about an update that is not there; swap
    /// the order of the setting and digest guards → "no hash" is shown while the
    /// real reason is the setting.
    @Test func theRowSaysWhatItsOneClickRestsOn() {
        let off = settings(allowing: false), on = settings(allowing: true)
        #expect(UpdatePolicy.digestOnlyOffer(offer(trust: .publishedDigestOnly), settings: off) == .turnedOff)
        #expect(UpdatePolicy.digestOnlyOffer(offer(trust: .publishedDigestOnly, digest: nil), settings: off) == .turnedOff)
        #expect(UpdatePolicy.digestOnlyOffer(offer(trust: .publishedDigestOnly, digest: nil), settings: on) == .noPublishedDigest)
        #expect(UpdatePolicy.digestOnlyOffer(offer(trust: .publishedDigestOnly), settings: on) == .offered)
        #expect(UpdatePolicy.digestOnlyOffer(offer(trust: .developerID), settings: on) == nil)
        let current = offer(trust: .publishedDigestOnly)
        let upToDate = UpdateResult(app: current.app, remote: current.remote, status: .upToDate)
        #expect(UpdatePolicy.digestOnlyOffer(upToDate, settings: on) == nil)
    }

    /// Mutation: drop `installTrust != .publishedDigestOnly` from
    /// `requiresInstaller` → a digest-only `.pkg` goes to the system installer,
    /// which no bundle-id or version gate ever sees.
    @Test func aDigestOnlyPackageIsNeverHandedToTheSystemInstaller() {
        let pkg = offer(trust: .publishedDigestOnly, kind: .pkg)
        #expect(!UpdatePolicy.requiresInstaller(pkg, environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(pkg, settings: settings(allowing: true), environment: environment))
        #expect(UpdatePolicy.requiresInstaller(offer(trust: .developerID, kind: .pkg), environment: environment))
    }

    // MARK: - Fixtures

    enum Signing { case sealed(identifier: String?), linkerOnly, unsigned }

    private static func run(_ argv: [String], stdin: String? = nil) async throws {
        let outcome = try await ChildProcess.run(
            argv[0], Array(argv.dropFirst()), standardInput: stdin.map { Data($0.utf8) },
            standardOutput: .discard, onCancel: .runToCompletion)
        guard outcome.terminationStatus == 0 else {
            throw NSError(domain: "DigestOnlyInstallTests", code: Int(outcome.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(argv[0]): " + String(decoding: outcome.standardError, as: UTF8.self)])
        }
    }

    /// A one-executable app bundle at `url`, signed as `signing` says.
    @discardableResult
    static func makeApp(
        at url: URL, bundleID: String = bundleID, version: String = "2.0.0", signing: Signing
    ) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "2",
            "CFBundleExecutable": "zz",
            "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data("resource".utf8).write(to: url.appendingPathComponent("Contents/Resources/r.txt"))
        let exe = url.appendingPathComponent("Contents/MacOS/zz").path
        var clang = ["/usr/bin/xcrun", "clang", "-x", "c", "-", "-o", exe]
        if case .unsigned = signing { clang.append("-Wl,-no_adhoc_codesign") }
        try await run(clang, stdin: "int main(void) { return 0; }\n")
        if case .sealed(let identifier) = signing {
            try await run(["/usr/bin/codesign", "--force", "--sign", "-"]
                + (identifier.map { ["--identifier", $0] } ?? []) + [url.path])
        }
        return url
    }

    static func zip(_ app: URL, to archive: URL) async throws {
        try await run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, archive.path])
    }

    static func scratch(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZDigestOnly-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The smallest Developer-ID app shipped inside the active Xcode — read in
    /// place, never written. Nil is a failure, not a skip: a host that builds
    /// this has Xcode.
    static func teamSignedApp() async -> URL? {
        guard let select = try? await ChildProcess.run(
            "/usr/bin/xcode-select", ["-p"], onCancel: .terminateChild) else { return nil }
        let path = String(decoding: select.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("Applications")
        let apps = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        // One hop for the lot: a Team ID read per app is a Security call each.
        let found = await offCooperativePool { () -> URL? in
            func size(_ url: URL) -> Int {
                let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
                var total = 0
                while let file = files?.nextObject() as? URL {
                    total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                }
                return total
            }
            return apps
                .filter { $0.pathExtension == "app" && (try? SignatureVerifier.teamIdentifier(at: $0)) != nil }
                .map { ($0, size($0)) }
                .min { $0.1 < $1.1 }?.0
        }
        if found == nil { Issue.record("no Team-signed app under \(dir.path) to stand in for a Developer ID build") }
        return found
    }

    /// A real digest proof, over a real file — the only way to get one.
    static func proof(in dir: URL) throws -> SignatureVerifier.VerifiedDigest {
        let file = dir.appendingPathComponent("proof.bin")
        try Data("proof".utf8).write(to: file)
        return try SignatureVerifier.verifyPublishedDigest(
            of: file, expected: try BundleArchive.sha256(of: file))
    }

    // MARK: - The digest gate

    /// Mutation: make `verifyPublishedDigest` skip the comparison → the wrong
    /// digest passes.
    @Test func thePublishedDigestMustMatchTheExactBytes() throws {
        let dir = try Self.scratch("digest")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("asset.dmg")
        try Data("asset bytes".utf8).write(to: file)
        let actual = try BundleArchive.sha256(of: file)
        #expect(throws: Never.self) {
            try SignatureVerifier.verifyPublishedDigest(of: file, expected: actual.uppercased())
        }
        #expect {
            try SignatureVerifier.verifyPublishedDigest(of: file, expected: String(repeating: "0", count: 64))
        } throws: { error in
            if case SignatureVerifier.VerifyError.publishedDigestMismatch = error { return true }
            return false
        }
        #expect {
            try SignatureVerifier.verifyPublishedDigest(of: file, expected: nil)
        } throws: { error in
            if case SignatureVerifier.VerifyError.publishedDigestMissing = error { return true }
            return false
        }
    }

    // MARK: - Identity gates (no swap at this level)

    @Test func whichIdentityGateIsDecidedByBothTeamIDs() {
        #expect(SignatureVerifier.digestOnlyIdentity(installedTeam: "T", downloadedTeam: nil) == .teamGate)
        #expect(SignatureVerifier.digestOnlyIdentity(installedTeam: "T", downloadedTeam: "T") == .teamGate)
        #expect(SignatureVerifier.digestOnlyIdentity(installedTeam: nil, downloadedTeam: "T") == .teamAppeared("T"))
        #expect(SignatureVerifier.digestOnlyIdentity(installedTeam: nil, downloadedTeam: nil) == .adHoc)
    }

    private func gate(
        installed: URL, downloaded: URL, bundleID: String = bundleID, version: String = "2.0.0",
        proofDir: URL
    ) async throws {
        try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: downloaded, installedApp: installed,
            trust: .publishedDigest(try Self.proof(in: proofDir), bundleID: bundleID, version: version))
    }

    private func expectGate(
        _ label: String, _ body: () async throws -> Void,
        _ matches: (SignatureVerifier.VerifyError) -> Bool
    ) async {
        do {
            try await body()
            Issue.record("\(label): expected a refusal")
        } catch let error as SignatureVerifier.VerifyError {
            #expect(matches(error), "\(label): wrong refusal \(error)")
        } catch {
            Issue.record("\(label): unexpected \(error)")
        }
    }

    /// The fixture that passes, so every refusal below is a refusal of its one
    /// difference and not of the fixture.
    @Test func aSealedAdHocBuildOfTheSameAppAndReleasePasses() async throws {
        let dir = try Self.scratch("pass")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("i/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("d/App.app"), signing: .sealed(identifier: nil))
        try await gate(installed: installed, downloaded: downloaded, proofDir: dir)
    }

    /// Mutation: move gate 2 into the `.developerID` case → a linker-only or
    /// unsigned bundle reaches the identity checks instead of being refused here.
    @Test func gateTwoStillRunsOnTheDigestRoute() async throws {
        let dir = try Self.scratch("gate2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("i/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        for (name, signing) in [("linker", Signing.linkerOnly), ("unsigned", .unsigned)] {
            let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("\(name)/App.app"), signing: signing)
            await expectGate(name, { try await gate(installed: installed, downloaded: downloaded, proofDir: dir) }) {
                if case .codeSignatureInvalid = $0 { return true }
                return false
            }
        }
    }

    /// Mutation: drop `if installedTeam != nil { return .teamGate }` → a
    /// Developer ID install is replaced by an ad-hoc build on a hash alone.
    @Test func aTeamSignedInstallIsNeverReplacedOnAHash() async throws {
        let dir = try Self.scratch("team-installed")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try #require(await Self.teamSignedApp())
        let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("d/App.app"), signing: .sealed(identifier: nil))
        await expectGate("team installed", { try await gate(installed: installed, downloaded: downloaded, proofDir: dir) }) {
            if case .noTeamIdentifier(which: "downloaded") = $0 { return true }
            return false
        }
    }

    /// Mutation: route `.teamAppeared` to the plain Team gate → the row says
    /// "Could not read a Team Identifier from the installed app" instead of why.
    @Test func aTeamSignedDownloadOverAnAdHocInstallIsRefusedInWords() async throws {
        let dir = try Self.scratch("team-download")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("i/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        let downloaded = try #require(await Self.teamSignedApp())
        await expectGate("team download", { try await gate(installed: installed, downloaded: downloaded, proofDir: dir) }) {
            guard case .teamIdentifierAppeared(let team) = $0 else { return false }
            return !team.isEmpty && $0.errorDescription?.contains(team) == true
        }
    }

    /// Mutation: drop `signedID == bundleID` → the MarkText shape (signed as
    /// `Electron`, plist says the app) passes on its plist alone.
    @Test func theSignedIdentifierMustBeTheBundleID() async throws {
        let dir = try Self.scratch("signed-id")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("i/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("d/App.app"), signing: .sealed(identifier: "Electron"))
        await expectGate("signed id", { try await gate(installed: installed, downloaded: downloaded, proofDir: dir) }) {
            if case .infoPlistIdentifierMismatch = $0 { return true }
            return false
        }
    }

    /// Mutation: drop `installedID == bundleID` → a download of the rule's app
    /// replaces a different app that happens to sit at this path.
    @Test func theInstalledCopyMustBeTheSameApp() async throws {
        let dir = try Self.scratch("installed-id")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(
            at: dir.appendingPathComponent("i/App.app"), bundleID: "zz.someone.else", version: "1.0.0",
            signing: .sealed(identifier: nil))
        let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("d/App.app"), signing: .sealed(identifier: nil))
        await expectGate("installed id", { try await gate(installed: installed, downloaded: downloaded, proofDir: dir) }) {
            if case .infoPlistIdentifierMismatch = $0 { return true }
            return false
        }
    }

    /// Mutation: drop the version guard → a build of another release, under the
    /// digest of this one, passes.
    @Test func theDownloadMustBeTheReleaseItWasPublishedAs() async throws {
        let dir = try Self.scratch("version")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("i/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        let downloaded = try await Self.makeApp(at: dir.appendingPathComponent("d/App.app"), signing: .sealed(identifier: nil))
        await expectGate("version", {
            try await gate(installed: installed, downloaded: downloaded, version: "2.0.1", proofDir: dir)
        }) {
            if case .infoPlistVersionMismatch(expected: "2.0.1", downloaded: "2.0.0") = $0 { return true }
            return false
        }
    }

    // MARK: - The installer (refusals only — see the suite comment)

    /// An installed ad-hoc app at 1.0.0 and a zipped ad-hoc download that says
    /// 2.0.0 while the result offers 2.0.1: valid in every respect but the
    /// version, so every case below that gets past its own gate stops there.
    private func installerFixture(
        _ dir: URL, downloaded: URL? = nil, digest: String? = "", offered: String = "2.0.1"
    ) async throws -> (UpdateResult, DownloadedUpdate) {
        let installed = try await Self.makeApp(at: dir.appendingPathComponent("installed/App.app"), version: "1.0.0", signing: .sealed(identifier: nil))
        let source: URL
        if let downloaded {
            source = downloaded
        } else {
            source = try await Self.makeApp(at: dir.appendingPathComponent("src/App.app"), signing: .sealed(identifier: nil))
        }
        let work = dir.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("download.zip")
        try await Self.zip(source, to: archive)
        let sha = try BundleArchive.sha256(of: archive)
        let result = UpdateResult(
            app: InstalledApp(
                name: "App", bundleID: Self.bundleID, shortVersion: "1.0.0", buildVersion: "2",
                path: installed, isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: offered, version: nil, downloadURL: archive,
                sourceName: "GitHub", requiresManualInstaller: false, vendorInstallerKind: .zip,
                expectedSHA256: digest == "" ? sha : digest, installTrust: .publishedDigestOnly),
            status: .updateAvailable(latest: offered))
        return (result, DownloadedUpdate(archiveURL: archive, bytesDownloaded: 0, workDir: work))
    }

    private func applyError(
        _ result: UpdateResult, _ download: DownloadedUpdate, allowed: Bool = true
    ) async -> Error? {
        do {
            try await VendorInstaller().apply(
                result, download: download, digestOnlyAllowed: allowed, onStage: { _ in })
            return nil
        } catch {
            return error
        }
    }

    /// The backstop itself: the fixture is refused for its version, through
    /// `apply`, on the digest route. Also kills: `apply` passing `.developerID`
    /// to the artifact gate (→ `noTeamIdentifier`).
    @Test func theInstallerRunsTheDigestRouteGates() async throws {
        let dir = try Self.scratch("apply-route")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, download) = try await installerFixture(dir)
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.infoPlistVersionMismatch? = error else {
            Issue.record("expected the version refusal, got \(String(describing: error))")
            return
        }
    }

    /// Mutation: drop `guard digestOnlyAllowed` → the install goes on although
    /// the user turned the setting off after the row was offered.
    @Test func aSettingTurnedOffSinceTheOfferRefusesTheInstall() async throws {
        let dir = try Self.scratch("apply-off")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, download) = try await installerFixture(dir)
        let error = await applyError(result, download, allowed: false)
        guard case VendorInstaller.InstallError.digestOnlyNotAllowed? = error else {
            Issue.record("expected digestOnlyNotAllowed, got \(String(describing: error))")
            return
        }
    }

    /// Mutation: drop the `verifyPublishedDigest` call from `applyVerified` →
    /// bytes that are not the published asset get unpacked and gated.
    @Test func aDownloadThatIsNotThePublishedAssetIsRefusedBeforeUnpacking() async throws {
        let dir = try Self.scratch("apply-mismatch")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (wrong, download) = try await installerFixture(dir, digest: String(repeating: "0", count: 64))
        let error = await applyError(wrong, download)
        guard case SignatureVerifier.VerifyError.publishedDigestMismatch? = error else {
            Issue.record("expected publishedDigestMismatch, got \(String(describing: error))")
            return
        }
        #expect(!FileManager.default.fileExists(
            atPath: download.workDir.appendingPathComponent("App.app").path),
            "nothing may be unpacked before the digest matches")
    }

    /// Mutation: drop `guard download.localStash == nil` → another updater's
    /// container is checked against a digest that describes something else.
    @Test func aStashIsNeverTakenOnTheDigestRoute() async throws {
        let dir = try Self.scratch("apply-stash")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, plain) = try await installerFixture(dir)
        let stashed = DownloadedUpdate(
            archiveURL: plain.archiveURL, bytesDownloaded: 0, workDir: plain.workDir,
            localStash: LocalStagedInstaller(
                archiveURL: plain.archiveURL, kind: .zip,
                version: VersionSide(marketing: "2.0.1", build: nil),
                bundleID: Self.bundleID, bytes: 1))
        let error = await applyError(result, stashed)
        guard case VendorInstaller.InstallError.digestOnlyNeedsTheAsset? = error else {
            Issue.record("expected digestOnlyNeedsTheAsset, got \(String(describing: error))")
            return
        }
    }

    /// The decided answer for ad-hoc → Developer ID, through `apply`: refused,
    /// and the row's text says why rather than naming a missing Team ID.
    @Test func theInstallerRefusesATeamSignedDownloadOverAnAdHocInstallInWords() async throws {
        let dir = try Self.scratch("apply-team")
        defer { try? FileManager.default.removeItem(at: dir) }
        let team = try #require(await Self.teamSignedApp())
        let (result, download) = try await installerFixture(dir, downloaded: team)
        let error = await applyError(result, download)
        guard case SignatureVerifier.VerifyError.teamIdentifierAppeared? = error else {
            Issue.record("expected teamIdentifierAppeared, got \(String(describing: error))")
            return
        }
        #expect((error as? LocalizedError)?.errorDescription?.contains("no developer signature") == true)
    }

    /// Mutation: have `InstallCoordinator.perform` hand `true` to the vendor
    /// route → the host's "off" never reaches the installer.
    @Test func theCoordinatorForwardsTheSettingAsItStandsNow() async throws {
        let dir = try Self.scratch("coordinator")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, _) = try await installerFixture(dir)
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        do {
            _ = try await coordinator.perform(
                result, route: .vendor, installedPopulation: [], digestOnlyAllowed: false,
                progress: { _ in })
            Issue.record("expected a refusal")
        } catch VendorInstaller.InstallError.digestOnlyNotAllowed {
        } catch {
            Issue.record("expected digestOnlyNotAllowed, got \(error)")
        }
    }
}
