import Testing
import Foundation
@testable import DuoUpdaterCore

/// The one-click half of Xcode: which archive the source offers (URL rewrite,
/// architecture, the `Xcode-beta.app` channel rule), whether the policy and the
/// coordinator let it through, and the apply step's pure checks.
///
/// Nothing here downloads, expands a real xip or touches `/Applications`: paths
/// are invented (`/ZZFixture/…`), the host architecture and macOS are passed in,
/// and the downloader is a fake. The one child process any test runs is
/// `pkgutil --check-signature` on a scratch text file, which reads it and says
/// it is not a signed package on every Mac.
@Suite struct XcodeOneClickTests {

    static let host = "26.6.0"

    // MARK: - URL rewrite

    @Test func theCDNURLIsRewrittenToTheAuthorizedEndpoint() throws {
        let url = try #require(XcodeReleasesSource.authorizedDownloadURL(
            fromCDN: "https://download.developer.apple.com/Developer_Tools/Xcode_27.2_beta/Xcode_27.2_beta.xip"))
        #expect(url.absoluteString
            == "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_27.2_beta/Xcode_27.2_beta.xip")
        #expect(XcodeReleasesSource.authorizedDownloadURL(
            fromCDN: "https://download.developer.apple.com/Developer_Tools/Xcode_26.6_Release_Candidate_2/Xcode_26.6_Release_Candidate_2_Apple_silicon.xip") != nil)
    }

    @Test(arguments: [
        // Wrong scheme, host, or look-alike host.
        "http://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip",
        "https://developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip",
        "https://download.developer.apple.com.example.com/Developer_Tools/Xcode_27/Xcode_27.xip",
        "https://download.developer.apple.com:8443/Developer_Tools/Xcode_27/Xcode_27.xip",
        "https://user@download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip",
        // Not Developer_Tools, not a .xip, not <dir>/<file>.
        "https://download.developer.apple.com/ios/Xcode_27/Xcode_27.xip",
        "https://download.developer.apple.com/Developer_Tools/Xcode_12/Xcode_12.dmg",
        "https://download.developer.apple.com/Developer_Tools/Xcode_27.xip",
        "https://download.developer.apple.com/Developer_Tools/a/b/Xcode_27.xip",
        "https://download.developer.apple.com/Developer_Tools/Xcode_27/.xip",
        // Traversal, escapes, and anything riding along after the path.
        "https://download.developer.apple.com/Developer_Tools/../Xcode_27.xip",
        "https://download.developer.apple.com/Developer_Tools/Xcode%2F27/Xcode_27.xip",
        "https://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip?x=1",
        "https://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip#x",
        "not a url",
    ])
    func anythingElseIsNotRewritten(_ raw: String) {
        #expect(XcodeReleasesSource.authorizedDownloadURL(fromCDN: raw) == nil)
    }

    // MARK: - Architecture

    /// The live index's shape for 26.6 (2026-09-22): two entries, one build, one
    /// `_versionOrder`, an arm64-only and a Universal archive.
    static let splitFeed = Data("""
    [
      {"name":"Xcode (Apple Silicon)","_versionOrder":26006000999,"requires":"26.2",
       "version":{"number":"26.6","build":"17F113","release":{"release":true}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_26.6/Xcode_26.6_Apple_silicon.xip","architectures":["arm64"]}}},
      {"name":"Xcode","_versionOrder":26006000999,"requires":"26.2",
       "version":{"number":"26.6","build":"17F113","release":{"release":true}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_26.6/Xcode_26.6_Universal.xip","architectures":["arm64","x86_64"]}}},
      {"name":"Xcode","_versionOrder":26005000999,"requires":"26.2",
       "version":{"number":"26.5","build":"17F42","release":{"release":true}}}
    ]
    """.utf8)

    static func path(_ file: String) -> String {
        "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_26.6/\(file)"
    }

    @Test func appleSiliconGetsTheArm64OnlyArchive() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "17F42", in: XcodeReleasesSource.parse(Self.splitFeed),
            osVersion: Self.host, host: .arm64, followsBetaLine: false, installedBeta: nil))
        #expect(remote.version == "17F113")
        #expect(remote.downloadURL?.absoluteString == Self.path("Xcode_26.6_Apple_silicon.xip"))
        #expect(remote.requiresManualInstaller == false)
    }

    @Test func intelGetsTheUniversalArchive() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "17F42", in: XcodeReleasesSource.parse(Self.splitFeed),
            osVersion: Self.host, host: .x86_64, followsBetaLine: false, installedBeta: nil))
        #expect(remote.downloadURL?.absoluteString == Self.path("Xcode_26.6_Universal.xip"))
        #expect(remote.requiresManualInstaller == false)
    }

    @Test func appleSiliconFallsBackToUniversal() throws {
        let universalOnly = XcodeReleasesSource.parse(Self.splitFeed)
            .filter { $0.architectures != ["arm64"] }
        let chosen = try #require(XcodeReleasesSource.chooseDownload(
            among: universalOnly.filter { $0.build == "17F113" }, host: .arm64))
        #expect(chosen.authorizedURL?.absoluteString == Self.path("Xcode_26.6_Universal.xip"))
    }

    /// The preference is by architecture, not by URL order: here the Universal
    /// archive sorts first ("U" < "a") and arm64-only must still win on arm64.
    @Test func arm64OnlyWinsWhateverTheURLOrder() throws {
        let feed = Data("""
        [{"name":"Xcode","_versionOrder":5,"version":{"number":"5","build":"ZZ5","release":{"release":true}},
          "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/ZZ/Xcode_ZZ_arm64.xip","architectures":["arm64"]}}},
         {"name":"Xcode","_versionOrder":5,"version":{"number":"5","build":"ZZ5","release":{"release":true}},
          "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/ZZ/Xcode_ZZ_Universal.xip","architectures":["arm64","x86_64"]}}}]
        """.utf8)
        let entries = XcodeReleasesSource.parse(feed)
        #expect(XcodeReleasesSource.chooseDownload(among: entries, host: .arm64)?
            .authorizedURL?.absoluteString.hasSuffix("Xcode_ZZ_arm64.xip") == true)
        #expect(XcodeReleasesSource.chooseDownload(among: entries.reversed(), host: .arm64)?
            .authorizedURL?.absoluteString.hasSuffix("Xcode_ZZ_arm64.xip") == true)
        #expect(XcodeReleasesSource.chooseDownload(among: entries, host: .x86_64)?
            .authorizedURL?.absoluteString.hasSuffix("Xcode_ZZ_Universal.xip") == true)
    }

    /// No archive fits (Intel, arm64-only build) or none says what it fits: the
    /// row stays detection-only rather than guessing.
    @Test func noFittingArchiveMeansDetectionOnly() throws {
        let armOnly = XcodeReleasesSource.parse(Self.splitFeed)
            .filter { $0.architectures != ["arm64", "x86_64"] }
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "17F42", in: armOnly,
            osVersion: Self.host, host: .x86_64, followsBetaLine: false, installedBeta: nil))
        #expect(remote.version == "17F113")
        #expect(remote.downloadURL == nil)
        #expect(remote.requiresManualInstaller == true)

        let unlabelled = Data("""
        [{"name":"Xcode","_versionOrder":2,"version":{"number":"2","build":"ZZ2","release":{"release":true}},
          "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/ZZ/ZZ.xip"}}},
         {"name":"Xcode","_versionOrder":1,"version":{"number":"1","build":"ZZ1","release":{"release":true}}}]
        """.utf8)
        let unknown = try #require(XcodeReleasesSource.remote(
            forBuild: "ZZ1", in: XcodeReleasesSource.parse(unlabelled),
            osVersion: Self.host, host: .arm64, followsBetaLine: false, installedBeta: nil))
        #expect(unknown.version == "ZZ2")
        #expect(unknown.downloadURL == nil)
    }

    // MARK: - Channel rule

    /// The live top of the index on 2026-09-22, trimmed: 27.0's RC and GA share
    /// `27A266a`; 27.1 beta 1 (device-specific) and 27.2 beta 1 are parallel lines.
    static let lineFeed = Data("""
    [
      {"name":"Xcode","_versionOrder":27002000001,"requires":"26.6",
       "version":{"number":"27.2","build":"27B5019j","release":{"beta":1}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_27.2_beta/Xcode_27.2_beta.xip","architectures":["arm64"]}}},
      {"name":"Xcode","_versionOrder":27001000001,"requires":"26.6",
       "version":{"number":"27.1","build":"27A9269","release":{"beta":1}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_27.1_beta/Xcode_27.1_beta.xip","architectures":["arm64"]}}},
      {"name":"Xcode","_versionOrder":27000000999,"requires":"26.6",
       "version":{"number":"27.0","build":"27A266a","release":{"release":true}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip","architectures":["arm64"]}}},
      {"name":"Xcode","_versionOrder":27000000901,"requires":"26.6",
       "version":{"number":"27.0","build":"27A266a","release":{"rc":1}},
       "links":{"download":{"url":"https://download.developer.apple.com/Developer_Tools/Xcode_27_Release_Candidate/Xcode_27_Release_Candidate.xip","architectures":["arm64"]}}},
      {"name":"Xcode","_versionOrder":27000000006,"requires":"26.4",
       "version":{"number":"27.0","build":"27A5252f","release":{"beta":6}}}
    ]
    """.utf8)

    /// A beta-path copy that the RC/GA overwrote reads as release — and is still
    /// offered the next beta, the newest line winning over the later-published
    /// 27.1 device beta.
    @Test func aBetaPathCopyOnTheGAIsOfferedTheNextBeta() throws {
        let remote = try #require(XcodeReleasesSource.remote(
            forBuild: "27A266a", in: XcodeReleasesSource.parse(Self.lineFeed),
            osVersion: Self.host, host: .arm64,
            followsBetaLine: XcodeReleasesSource.followsBetaLine(
                installedAt: URL(fileURLWithPath: "/ZZFixture/Xcode-beta.app")), installedBeta: nil))
        #expect(remote.version == "27B5019j")
        #expect(remote.downloadURL?.absoluteString
            == "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_27.2_beta/Xcode_27.2_beta.xip")
    }

    /// The same build anywhere else keeps the stability floor: offered itself.
    @Test func aNonBetaPathCopyOnTheGAIsNotOfferedABeta() throws {
        let (_, offer) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A266a", in: XcodeReleasesSource.parse(Self.lineFeed),
            osVersion: Self.host,
            followsBetaLine: XcodeReleasesSource.followsBetaLine(
                installedAt: URL(fileURLWithPath: "/ZZFixture/Xcode.app"))))
        #expect(offer.build == "27A266a")
        #expect(offer.stability == .release)
    }

    /// A beta on the beta path moves to the newest line (not the 27.1 device beta).
    @Test func aBetaPathBetaIsOfferedTheNewestLine() throws {
        let (_, offer) = try #require(XcodeReleasesSource.offer(
            forBuild: "27A5252f", in: XcodeReleasesSource.parse(Self.lineFeed),
            osVersion: Self.host, followsBetaLine: true))
        #expect(offer.build == "27B5019j")
    }

    @Test(arguments: [
        ("/ZZFixture/Xcode-beta.app", true),
        ("/ZZFixture/Apps/Xcode-beta.app", true),
        ("/ZZFixture/Xcode.app", false),
        ("/ZZFixture/Xcode-beta-2.app", false),
        ("/ZZFixture/Xcode-27.0.0-Beta.app", false),
    ])
    func onlyTheExactBetaNameFollowsTheBetaLine(_ path: String, _ expected: Bool) {
        #expect(XcodeReleasesSource.followsBetaLine(installedAt: URL(fileURLWithPath: path)) == expected)
    }

    // MARK: - Policy and routing

    static func result(
        downloadURL: URL? = URL(string: "https://developer.apple.com/services-account/download?path=/Developer_Tools/ZZ/ZZ.xip"),
        requiresManualInstaller: Bool = false,
        source: String = "Xcode Releases",
        path: String = "/ZZFixture/Xcode-beta.app"
    ) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Xcode", bundleID: "com.apple.dt.Xcode", shortVersion: "27.0",
                buildVersion: "27A266a", path: URL(fileURLWithPath: path),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(
                shortVersion: "27.2 beta 1 (27B5019j)", version: "27B5019j",
                downloadURL: downloadURL, sourceName: source,
                requiresManualInstaller: requiresManualInstaller),
            status: .updateAvailable(latest: "27.2 beta 1 (27B5019j)"))
    }

    static let environment = InstallEnvironment(
        isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
    static let settings = UpdateSettings(
        appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)

    @Test func canAutoInstallNeedsAURLAndNoManualInstaller() {
        func can(_ r: UpdateResult) -> Bool {
            UpdatePolicy.canAutoInstall(
                r, settings: Self.settings, environment: Self.environment, osVersion: Self.host)
        }
        #expect(can(Self.result()))
        #expect(!can(Self.result(downloadURL: nil, requiresManualInstaller: true)))
        #expect(!can(Self.result(downloadURL: nil)))
        #expect(!can(Self.result(requiresManualInstaller: true)))
        // Never a system-installer hand-off.
        #expect(!UpdatePolicy.requiresInstaller(Self.result(), environment: Self.environment))
    }

    @Test func theSourceRoutesToXcodeAndTakesARollbackPoint() {
        #expect(InstallCoordinator.route(for: Self.result(), requiresInstaller: false) == .xcode)
        #expect(InstallCoordinator.wantsBackup(.xcode))
    }

    /// The CLI's case: no downloader, so the route refuses — before any download
    /// or scratch directory — with a reason a user can act on.
    @Test func theCoordinatorRefusesXcodeWithoutADownloader() async {
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        do {
            _ = try await coordinator.perform(
                Self.result(), route: .xcode, installedPopulation: [], progress: { _ in })
            Issue.record("expected a refusal")
        } catch InstallCoordinator.CoordinatorError.routeNotSupportedHere(let route) {
            #expect(route == .xcode)
            #expect(InstallCoordinator.CoordinatorError.routeNotSupportedHere(.xcode)
                .errorDescription?.contains("Apple ID") == true)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    /// With a downloader whose fetch fails, the coordinator surfaces that failure
    /// and the scratch directory it handed out is gone.
    @Test func aFailedDownloadThroughTheCoordinatorLeavesNoScratchDir() async throws {
        let fake = FakeDownloader(mode: .fail)
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1), xcodeDownloader: fake)
        await #expect(throws: ZZDownloadFailed.self) {
            _ = try await coordinator.perform(
                Self.result(), route: .xcode, installedPopulation: [], progress: { _ in })
        }
        let dir = try #require(fake.directory)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - Download phase

    @Test func theDownloadProducesADownloadedUpdateInsideItsWorkDir() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDownloader(mode: .succeed)
        let stages = StageLog()
        let downloaded = try await XcodeInstaller.download(
            Self.result(), using: fake, scratchRoot: root, runningExecutables: { [] }, onStage: { stages.append($0) })
        #expect(fake.receivedURL?.absoluteString
            == "https://developer.apple.com/services-account/download?path=/Developer_Tools/ZZ/ZZ.xip")
        #expect(downloaded.workDir.deletingLastPathComponent().standardizedFileURL
            == root.standardizedFileURL)
        #expect(downloaded.archiveURL == downloaded.workDir.appendingPathComponent(XcodeInstaller.archiveName))
        #expect(FileManager.default.fileExists(atPath: downloaded.archiveURL.path))
        #expect(downloaded.bytesDownloaded == 42)
        #expect(downloaded.finalHost == "zz.example")
        #expect(stages.all.contains(.downloading(fraction: 0.5)))
    }

    @Test func aFailedDownloadRemovesItsWorkDir() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDownloader(mode: .fail)
        await #expect(throws: ZZDownloadFailed.self) {
            _ = try await XcodeInstaller.download(
                Self.result(), using: fake, scratchRoot: root, runningExecutables: { [] }, onStage: { _ in })
        }
        let dir = try #require(fake.directory)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    /// A downloader that writes somewhere else breaks the cleanup contract and
    /// would have the gates run on a file we don't own: refused, dir removed.
    @Test func anArchiveOutsideTheWorkDirIsRefused() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("ZZ-outside.xip")
        try Data("zz".utf8).write(to: outside)
        let fake = FakeDownloader(mode: .writeTo(outside))
        await #expect(throws: XcodeInstaller.InstallError.archiveOutsideWorkDir(outside.path)) {
            _ = try await XcodeInstaller.download(
                Self.result(), using: fake, scratchRoot: root, runningExecutables: { [] }, onStage: { _ in })
        }
        let dir = try #require(fake.directory)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        // Not ours, so not deleted.
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func onlyAnXcodeResultWithAURLIsDownloaded() async throws {
        let fake = FakeDownloader(mode: .succeed)
        await #expect(throws: XcodeInstaller.InstallError.notXcodeUpdate) {
            _ = try await XcodeInstaller.download(
                Self.result(source: "Vendor"), using: fake, runningExecutables: { [] }, onStage: { _ in })
        }
        await #expect(throws: XcodeInstaller.InstallError.noDownloadURL) {
            _ = try await XcodeInstaller.download(
                Self.result(downloadURL: nil), using: fake, runningExecutables: { [] }, onStage: { _ in })
        }
        #expect(fake.directory == nil)
    }

    // MARK: - A running Xcode

    @Test func aRunningCopyIsRefusedByPathNotByBundleID() {
        let beta = "/ZZFixture/Applications/Xcode-beta.app"
        // The App Store Xcode running beside it: same bundle id, other path.
        #expect(XcodeInstaller.runningRefusal(
            installedAt: beta,
            runningExecutables: ["/ZZFixture/Applications/Xcode.app/Contents/MacOS/Xcode",
                                 "/ZZFixture/Applications/Xcode-beta.app.old/Contents/MacOS/Xcode",
                                 "/usr/bin/ZZtool"]) == nil)
        #expect(XcodeInstaller.runningRefusal(
            installedAt: beta,
            runningExecutables: ["/ZZFixture/Applications/Xcode-beta.app/Contents/MacOS/Xcode"])
            == .xcodeRunning(name: "Xcode-beta", process: nil))
        // A tool running out of the bundle counts too, and is named.
        #expect(XcodeInstaller.runningRefusal(
            installedAt: beta,
            runningExecutables: ["/ZZFixture/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild"])
            == .xcodeRunning(name: "Xcode-beta", process: "xcodebuild"))
        #expect(XcodeInstaller.InstallError.xcodeRunning(name: "Xcode-beta", process: nil).errorDescription
            == "Xcode-beta is running. Quit it, then click Update again. Nothing was changed.")
    }

    /// Checked before a byte moves: the downloader is never called and no scratch
    /// directory is made.
    @Test func aRunningCopyIsRefusedBeforeTheDownload() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDownloader(mode: .succeed)
        await #expect(throws: XcodeInstaller.InstallError.xcodeRunning(name: "Xcode-beta", process: nil)) {
            _ = try await XcodeInstaller.download(
                Self.result(), using: fake, scratchRoot: root,
                runningExecutables: { ["/ZZFixture/Xcode-beta.app/Contents/MacOS/Xcode"] },
                onStage: { _ in })
        }
        #expect(fake.directory == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    /// Checked again right before the swap: opened during the download means no
    /// swap; still closed means the swap runs.
    @Test func theSwapIsSkippedIfXcodeWasOpenedMeanwhile() async throws {
        let target = URL(fileURLWithPath: "/ZZFixture/Xcode-beta.app")
        let swaps = StageLog()
        await #expect(throws: XcodeInstaller.InstallError.xcodeRunning(name: "Xcode-beta", process: nil)) {
            try await XcodeInstaller.swapUnlessRunning(
                over: target,
                runningExecutables: { ["/ZZFixture/Xcode-beta.app/Contents/MacOS/Xcode"] },
                swap: { swaps.append(.installing) })
        }
        #expect(swaps.all.isEmpty)
        try await XcodeInstaller.swapUnlessRunning(
            over: target,
            runningExecutables: { ["/ZZFixture/Xcode.app/Contents/MacOS/Xcode"] },
            swap: { swaps.append(.installing) })
        #expect(swaps.all == [.installing])
    }

    // MARK: - Apply phase: pure checks

    /// Captured from the real Xcode 27 RC xip, 2026-09-22 (fingerprint elided).
    static let appleSigned = """
    Package "Xcode_27_Release_Candidate.xip":
       Status: signed Apple Software
       Certificate Chain:
        1. Software Update
           Expires: 2029-04-14 21:28:23 +0000
           SHA256 Fingerprint:
               ZZ ZZ ZZ
           ------------------------------------------------------------------------
        2. Apple Software Update Certification Authority
           Expires: 2029-04-14 21:28:23 +0000
        3. Apple Root CA

    """

    @Test func appleSoftwareUpdateSignatureIsAccepted() {
        #expect(XcodeInstaller.appleSoftwareSignatureProblem(inPkgutilOutput: Self.appleSigned) == nil)
    }

    @Test(arguments: [
        // Unsigned.
        """
        Package "Xcode-download.xip":
           Status: no signature
        """,
        // A Developer ID package.
        """
        Package "Xcode-download.xip":
           Status: signed by a developer certificate issued by Apple for distribution
           Notarization: trusted by the Apple notary service
           Certificate Chain:
            1. Developer ID Installer: Example Corp (ZZ12345678)
            2. Developer ID Certification Authority
            3. Apple Root CA
        """,
        // Apple's status, another leaf.
        """
        Package "Xcode-download.xip":
           Status: signed Apple Software
           Certificate Chain:
            1. Apple Mac OS Application Signing
            2. Apple Worldwide Developer Relations Certification Authority
            3. Apple Root CA
        """,
        // The right leaf NAME under a status that is not Apple's: a locally
        // trusted certificate can be called anything.
        """
        Package "Xcode-download.xip":
           Status: signed by a certificate trusted by macOS
           Certificate Chain:
            1. Software Update
        """,
        // Apple's status and no chain at all.
        """
        Package "Xcode-download.xip":
           Status: signed Apple Software
        """,
        // The right leaf further down, not first.
        """
        Package "Xcode-download.xip":
           Status: signed Apple Software
           Certificate Chain:
            1. Software Update Impostor
            2. Software Update
        """,
        "",
    ])
    func anythingElseIsRejected(_ output: String) {
        #expect(XcodeInstaller.appleSoftwareSignatureProblem(inPkgutilOutput: output) != nil)
    }

    @Test func roomToExpandIsThreeTimesTheArchive() throws {
        let xip: Int64 = 2_010_000_000
        #expect(XcodeInstaller.requiredFreeBytes(archiveBytes: xip) == 6_030_000_000)
        try XcodeInstaller.checkRoomToExpand(archiveBytes: xip, availableBytes: 6_030_000_000)
        #expect(throws: XcodeInstaller.InstallError.notEnoughSpace(
            needed: 6_030_000_000, available: 6_029_999_999)) {
            try XcodeInstaller.checkRoomToExpand(archiveBytes: xip, availableBytes: 6_029_999_999)
        }
        // The measured 3.8 GB bundle alone would not fit: the margin is real.
        #expect(throws: XcodeInstaller.InstallError.self) {
            try XcodeInstaller.checkRoomToExpand(archiveBytes: xip, availableBytes: 3_800_000_000)
        }
        #expect(XcodeInstaller.requiredFreeBytes(archiveBytes: .max) == .max)
    }

    @Test func exactlyOneTopLevelAppIsRequired() throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let none = root.appendingPathComponent("none")
        try fm.createDirectory(at: none, withIntermediateDirectories: true)
        #expect(throws: XcodeInstaller.InstallError.self) { try XcodeInstaller.expandedApp(in: none) }

        let one = root.appendingPathComponent("one")
        try fm.createDirectory(at: one.appendingPathComponent("Xcode.app/Contents"), withIntermediateDirectories: true)
        try Data().write(to: one.appendingPathComponent("ZZ-notes.txt"))
        #expect(try XcodeInstaller.expandedApp(in: one).lastPathComponent == "Xcode.app")

        let two = root.appendingPathComponent("two")
        try fm.createDirectory(at: two.appendingPathComponent("Xcode.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: two.appendingPathComponent("Xcode-beta.app"), withIntermediateDirectories: true)
        #expect(throws: XcodeInstaller.InstallError.self) { try XcodeInstaller.expandedApp(in: two) }

        let link = root.appendingPathComponent("link")
        try fm.createDirectory(at: link, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: link.appendingPathComponent("Xcode.app"),
            withDestinationURL: one.appendingPathComponent("Xcode.app"))
        #expect(throws: XcodeInstaller.InstallError.self) { try XcodeInstaller.expandedApp(in: link) }
    }

    /// The wiring, end to end up to the first gate: a file that is not an
    /// Apple-signed archive is refused by `pkgutil` before anything is expanded.
    @Test func applyRefusesAnArchiveThatIsNotAppleSigned() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent(XcodeInstaller.archiveName)
        try Data("not a xip".utf8).write(to: archive)
        let downloaded = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 9, workDir: root)
        do {
            try await XcodeInstaller.apply(
                Self.result(), download: downloaded, runningExecutables: { [] }, onStage: { _ in })
            Issue.record("expected a refusal")
        } catch XcodeInstaller.InstallError.packageSignatureRejected {
            // pkgutil prints "Could not open package" and no status for this file.
        } catch {
            Issue.record("expected packageSignatureRejected, got \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("expanded").path))
    }

    // MARK: - Helpers

    static func scratchRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-xcode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private struct ZZDownloadFailed: Error {}

private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [InstallStage] = []
    func append(_ stage: InstallStage) { lock.withLock { stages.append(stage) } }
    var all: [InstallStage] { lock.withLock { stages } }
}

private final class FakeDownloader: XcodeArchiveDownloading, @unchecked Sendable {
    enum Mode { case succeed, fail, writeTo(URL) }
    let mode: Mode
    private let lock = NSLock()
    private var _directory: URL?
    private var _url: URL?
    var directory: URL? { lock.withLock { _directory } }
    var receivedURL: URL? { lock.withLock { _url } }

    init(mode: Mode) { self.mode = mode }

    func downloadXcodeArchive(
        from authorizedURL: URL, into directory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> XcodeArchiveDownload {
        lock.withLock { _directory = directory; _url = authorizedURL }
        progress(0.5)
        switch mode {
        case .fail:
            // A partial file, as a real interrupted download leaves.
            try Data("partial".utf8).write(to: directory.appendingPathComponent("ZZ.xip.part"))
            throw ZZDownloadFailed()
        case .succeed:
            let file = directory.appendingPathComponent("ZZ Chosen Name.xip")
            try Data("zz".utf8).write(to: file)
            return XcodeArchiveDownload(fileURL: file, bytesDownloaded: 42, finalHost: "zz.example")
        case .writeTo(let file):
            return XcodeArchiveDownload(fileURL: file, bytesDownloaded: 2, finalHost: nil)
        }
    }
}
