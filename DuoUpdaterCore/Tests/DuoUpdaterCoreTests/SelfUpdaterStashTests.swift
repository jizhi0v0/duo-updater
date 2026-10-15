import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `SelfUpdaterStash.resolve` against a fabricated electron-updater cache: a real
/// zip built here with `ditto`, a real `update-info.json`, and a real `unzip` read
/// through `ChildProcess`. Nothing on the host is consulted — every bundle path is
/// invented and `fixtureApp` asserts it does not exist, because this type's whole
/// job is deciding what to install over a path (see the CLAUDE.md rule this
/// enforces: a test that asks the host what it has installed answers differently
/// on another machine).
///
/// Each case names the mutation it is pinned to. Every one of those mutations
/// compiles.
@Suite(.serialized)
struct SelfUpdaterStashTests {

    // MARK: - Fixtures

    private static let bundleID = "com.example.zzfixture.stash"
    private static let offered = "9.9.9"

    /// An invented bundle, guarded against ever naming a real one. A path that
    /// exists would put `resolvingSymlinksInPath` (in `isSoleClaimant`) on
    /// the host's filesystem, which is exactly the drift this guard exists for.
    private static func fixtureApp(
        name: String, id: String = bundleID, cacheDirName: String?
    ) -> InstalledApp {
        let path = URL(fileURLWithPath: "/Applications/\(name).app")
        #expect(!FileManager.default.fileExists(atPath: path.path),
                "fixture path must not exist on the host: \(path.path)")
        return InstalledApp(
            name: name, bundleID: id,
            shortVersion: "1.0.0", buildVersion: "1",
            path: path,
            isMASApp: false, sparkleFeedURL: nil,
            electronUpdate: ElectronUpdateConfig(
                provider: "github", url: nil, owner: "zzfixture", repo: "zzfixture",
                channel: "latest", updaterCacheDirName: cacheDirName),
            hasSelfUpdater: true,
            releaseChannel: .stable)
    }

    private static func result(
        _ app: InstalledApp, offering version: String = offered,
        expectedSHA512: String? = nil
    ) -> UpdateResult {
        UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: version, version: nil,
                downloadURL: URL(string: "https://zzfixture.invalid/app.dmg")!,
                sourceName: "GitHub",
                vendorInstallerKind: .dmg,
                expectedSHA512: expectedSHA512),
            status: .updateAvailable(latest: version))
    }

    /// A zip holding `<appName>.app/Contents/Info.plist`, plus — when asked — a
    /// nested helper `.app` with its own `Info.plist`, the way every Electron
    /// bundle ships one.
    private static func makeZip(
        at destination: URL, appName: String, bundleID: String,
        short: String, build: String?, nestedHelper: Bool
    ) async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-stash-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let app = staging.appendingPathComponent("\(appName).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": short,
        ]
        if let build { info["CFBundleVersion"] = build }
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        if nestedHelper {
            // The trap the root anchor exists for: a helper's Info.plist sorts
            // before the app's own in `unzip -Z1` output and carries a DIFFERENT
            // version, so an unanchored match reads the wrong one.
            let helper = contents
                .appendingPathComponent("Frameworks", isDirectory: true)
                .appendingPathComponent("\(appName) Helper (GPU).app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
            try fm.createDirectory(at: helper, withIntermediateDirectories: true)
            try PropertyListSerialization
                .data(fromPropertyList: [
                    "CFBundleIdentifier": "\(bundleID).helper",
                    "CFBundleShortVersionString": "0.0.1",
                ], format: .binary, options: 0)
                .write(to: helper.appendingPathComponent("Info.plist"))
        }

        let made = try await ChildProcess.run(
            "/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, destination.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
    }

    /// Lays out `<caches>/<cacheDirName>/pending/{update-info.json,<archive>}` the
    /// way `DownloadedUpdateHelper.setDownloadedFile` does, and returns the caches
    /// root. `recordedSHA512` defaults to the archive's real digest; a caller
    /// passes something else to fabricate a corrupted file.
    private static func layOutCache(
        cacheDirName: String, archiveName: String = "zzfixture-mac-arm64.zip",
        appName: String = "ZZStash", zipBundleID: String? = nil,
        short: String = offered, build: String? = nil,
        nestedHelper: Bool = false, recordedSHA512: String? = nil,
        writeArchive: Bool = true
    ) async throws -> URL {
        let fm = FileManager.default
        let caches = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-caches-\(UUID().uuidString)", isDirectory: true)
        let pending = caches
            .appendingPathComponent(cacheDirName, isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try fm.createDirectory(at: pending, withIntermediateDirectories: true)

        let archive = pending.appendingPathComponent(archiveName)
        var digest = recordedSHA512 ?? ""
        if writeArchive {
            try await makeZip(
                at: archive, appName: appName, bundleID: zipBundleID ?? bundleID,
                short: short, build: build, nestedHelper: nestedHelper)
            if recordedSHA512 == nil {
                digest = Data(SHA512.hash(data: try Data(contentsOf: archive)))
                    .base64EncodedString()
            }
        }
        try JSONSerialization
            .data(withJSONObject: [
                "fileName": archiveName, "sha512": digest, "isAdminRightsRequired": false,
            ])
            .write(to: pending.appendingPathComponent("update-info.json"))
        return caches
    }

    /// Asserts which gate refused, not merely that something did.
    ///
    /// ⚠️ `#expect(stash == nil)` is immune to the failure these cases exist to
    /// catch: the gates are each other's fallback, so deleting one usually leaves
    /// the next one refusing the same input for a different reason, and the case
    /// stays green while no longer measuring its gate. Two cases in this suite
    /// were vacuous for exactly that reason before this helper existed.
    private static func expectRefusal(
        _ expected: SelfUpdaterStash.Rejection,
        for app: InstalledApp, population: [InstalledApp]?, caches: URL,
        offering version: String = offered,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let outcome = await SelfUpdaterStash.evaluate(
            for: result(app, offering: version), population: population, cachesDirectory: caches)
        switch outcome {
        case .success:
            Issue.record("expected \(expected.rawValue), got a stash", sourceLocation: sourceLocation)
        case .failure(let why):
            #expect(why == expected, "expected \(expected.rawValue), got \(why.rawValue)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: - The happy path

    /// The OpenCode case: the app's own updater has already downloaded exactly the
    /// release we are about to install.
    @Test func aPendingDownloadOfTheOfferedVersionIsUsed() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Hit", cacheDirName: "zzstash-updater")
        let caches = try await Self.layOutCache(cacheDirName: "zzstash-updater")
        defer { try? FileManager.default.removeItem(at: caches) }

        let stash = await SelfUpdaterStash.resolve(
            for: Self.result(app), population: [app], cachesDirectory: caches)

        let found = try #require(stash)
        #expect(found.kind == .zip)
        #expect(found.bundleID == Self.bundleID)
        #expect(found.version.marketing == Self.offered)
        #expect(found.bytes > 0)
        #expect(found.archiveURL.lastPathComponent == "zzfixture-mac-arm64.zip")
    }

    // MARK: - The gates

    /// ChatWise's shape: a five-month-old download still sitting in `pending/`.
    /// Mutation: delete the `VersionComparator.isSame` guard in `resolve`.
    @Test func aPendingDownloadOfAnotherVersionIsRefused() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Stale", cacheDirName: "zzstale-updater")
        let caches = try await Self.layOutCache(
            cacheDirName: "zzstale-updater", short: "1.2.3")
        defer { try? FileManager.default.removeItem(at: caches) }

        await Self.expectRefusal(
            .versionMismatch, for: app, population: [app], caches: caches)
    }

    /// T3 Code's shape: two installed copies naming one cache directory, with the
    /// SAME bundle identifier — so neither the directory nor the archive's id can
    /// say whose download this is.
    /// Mutation: delete the `isSoleClaimant` guard in `evaluate`.
    @Test func aCacheDirectoryTwoCopiesClaimIsRefused() async throws {
        let alpha = Self.fixtureApp(name: "ZZStash-Alpha", cacheDirName: "zzshared-updater")
        let nightly = Self.fixtureApp(name: "ZZStash-Nightly", cacheDirName: "zzshared-updater")
        let caches = try await Self.layOutCache(cacheDirName: "zzshared-updater")
        defer { try? FileManager.default.removeItem(at: caches) }

        #expect(!SelfUpdaterStash.isSoleClaimant(
            alpha, of: .electronUpdater(cacheDirectoryName: "zzshared-updater"), in: [alpha, nightly]))
        await Self.expectRefusal(
            .attributionAmbiguous, for: alpha, population: [alpha, nightly], caches: caches)
        // And the same layout with only one claimant IS used — without this the
        // case above would pass for any reason at all, including a typo in the
        // fixture's cache directory name.
        let alone = await SelfUpdaterStash.resolve(
            for: Self.result(alpha), population: [alpha], cachesDirectory: caches)
        #expect(alone != nil)
    }

    /// One bundle listed twice (a caller that concatenated two scans) is not a
    /// contest. Mutation: count array elements instead of distinct paths.
    @Test func theSameCopyListedTwiceIsNotAContest() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Dup", cacheDirName: "zzdup-updater")
        #expect(SelfUpdaterStash.isSoleClaimant(app, of: .electronUpdater(cacheDirectoryName: "zzdup-updater"), in: [app, app]))
    }

    /// Mutation: `let population = population ?? [result.app]` — the plausible
    /// shortcut, since the one app IS in hand. It passes the attribution gate (one
    /// claimant, itself) and reaches the stash, which is the whole failure: the
    /// contest is invisible from inside one app.
    ///
    /// ⚠️ NOT pinned to `?? []`, which was this case's first claim and is vacuous:
    /// an empty population makes `isSoleClaimant` find zero claimants and
    /// refuse anyway, so that mutation is green and the case would have been
    /// measuring the next gate rather than this one. Verified by running it.
    @Test func anUnsuppliedPopulationIsRefused() async throws {
        let app = Self.fixtureApp(name: "ZZStash-NoPop", cacheDirName: "zznopop-updater")
        let caches = try await Self.layOutCache(cacheDirName: "zznopop-updater")
        defer { try? FileManager.default.removeItem(at: caches) }

        await Self.expectRefusal(
            .populationUnknown, for: app, population: nil, caches: caches)
    }

    /// The bytes on disk are not the ones the app's updater recorded.
    /// Mutation: delete the digest comparison in `resolve`.
    @Test func anArchiveThatDoesNotMatchItsRecordedDigestIsRefused() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Corrupt", cacheDirName: "zzcorrupt-updater")
        let caches = try await Self.layOutCache(
            cacheDirName: "zzcorrupt-updater",
            recordedSHA512: Data(SHA512.hash(data: Data("not this file".utf8)))
                .base64EncodedString())
        defer { try? FileManager.default.removeItem(at: caches) }

        await Self.expectRefusal(
            .checksumMismatch, for: app, population: [app], caches: caches)
    }

    /// A cache directory holding some other app's build.
    /// Mutation: delete the `info.bundleID == installedID` guard.
    @Test func anArchiveOfADifferentAppIsRefused() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Other", cacheDirName: "zzother-updater")
        let caches = try await Self.layOutCache(
            cacheDirName: "zzother-updater", zipBundleID: "com.example.zzfixture.somethingelse")
        defer { try? FileManager.default.removeItem(at: caches) }

        await Self.expectRefusal(
            .bundleIDMismatch, for: app, population: [app], caches: caches)
    }

    /// The nested-helper trap. The helper's Info.plist says 0.0.1 while the app's
    /// says the offered version, so reading the wrong one refuses a stash that
    /// should have been used.
    /// Mutation: drop `components(separatedBy: "/").count == 3` from the entry
    /// filter in `stagedBundleInfo`.
    @Test func aNestedHelperInfoPlistIsNotMistakenForTheApp() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Helper", cacheDirName: "zzhelper-updater")
        let caches = try await Self.layOutCache(
            cacheDirName: "zzhelper-updater", nestedHelper: true)
        defer { try? FileManager.default.removeItem(at: caches) }

        let found = try #require(await SelfUpdaterStash.resolve(
            for: Self.result(app), population: [app], cachesDirectory: caches))
        #expect(found.version.marketing == Self.offered)
        #expect(found.bundleID == Self.bundleID)
    }

    /// Mutation: fall back to the app's own name when `updaterCacheDirName` is
    /// absent. The cache below is laid out under exactly that name, so a guess
    /// finds it.
    @Test func aBundleThatNamesNoCacheDirectoryIsNotGuessedAt() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Unnamed", cacheDirName: nil)
        let caches = try await Self.layOutCache(cacheDirName: "ZZStash-Unnamed")
        defer { try? FileManager.default.removeItem(at: caches) }

        #expect(SelfUpdaterStash.electronCacheDirectoryName(for: app) == nil)
        await Self.expectRefusal(
            .noParkingSpot, for: app, population: [app], caches: caches)
    }

    /// Mutations: drop the separator check in `electronCacheDirectoryName`, and
    /// drop the one in `pendingRecord`. Both values are joined onto a path under
    /// `~/Library/Caches`.
    ///
    /// ⚠️ The `pendingRecord` half asserts on `pendingRecord` itself, NOT on
    /// `resolve`. Going through `resolve` made this case vacuous: the escaping
    /// name points at a file that does not exist, so `resolve` refuses at the
    /// `fileExists` gate whether or not the separator check is there, and the
    /// mutation stayed green. Verified by running it.
    @Test func aSeparatorInEitherNameIsRefused() async throws {
        let escaping = Self.fixtureApp(name: "ZZStash-Esc", cacheDirName: "../../escaped")
        #expect(SelfUpdaterStash.electronCacheDirectoryName(for: escaping) == nil)

        let fm = FileManager.default
        // A non-empty digest matters: `layOutCache` writes "" when it skips the
        // archive, and `pendingRecord` refuses an empty `sha512` BEFORE it looks at
        // the name — which is what made the first attempt at this case vacuous for
        // a second time. The value is never compared here; it only has to exist.
        let caches = try await Self.layOutCache(
            cacheDirName: "zzesc-updater", archiveName: "../../../escaped.zip",
            recordedSHA512: "ZZfixtureDigestNotComparedHere==", writeArchive: false)
        defer { try? fm.removeItem(at: caches) }
        let cacheDir = caches.appendingPathComponent("zzesc-updater", isDirectory: true)

        // The record parses — same file, same shape — and is refused on the name
        // alone. Asserting the control too, so a `pendingRecord` that refused
        // everything could not pass this case.
        #expect(SelfUpdaterStash.pendingRecord(inCacheDirectory: cacheDir, fileManager: fm) == nil)
        let ok = try await Self.layOutCache(cacheDirName: "zzok-updater")
        defer { try? fm.removeItem(at: ok) }
        #expect(SelfUpdaterStash.pendingRecord(
            inCacheDirectory: ok.appendingPathComponent("zzok-updater", isDirectory: true),
            fileManager: fm) != nil)
    }

    /// The claimant has to BE this app, not just be alone.
    /// Mutation: `claimants.count == 1` in place of the set comparison.
    @Test func aCacheDirectoryClaimedOnlyBySomeoneElseIsRefused() async throws {
        let mine = Self.fixtureApp(name: "ZZStash-Absent", cacheDirName: "zzabsent-updater")
        let theirs = Self.fixtureApp(
            name: "ZZStash-Squatter", id: Self.bundleID, cacheDirName: "zzabsent-updater")
        // `mine` is NOT in the population — an app the scan missed, or one moved
        // after it ran. `theirs` is the only claimant, and shares the bundle id, so
        // nothing downstream of this gate can tell the two apart.
        #expect(!SelfUpdaterStash.isSoleClaimant(mine, of: .electronUpdater(cacheDirectoryName: "zzabsent-updater"), in: [theirs]))

        let caches = try await Self.layOutCache(cacheDirName: "zzabsent-updater")
        defer { try? FileManager.default.removeItem(at: caches) }
        await Self.expectRefusal(
            .attributionAmbiguous, for: mine, population: [theirs], caches: caches)
    }

    /// Mutation: admit `.dmg` / `.pkg` from `archiveKind` in `resolve`. A package
    /// is not swapped by this route at all, and a dmg cannot be version-read
    /// without mounting it.
    @Test func onlyAZipIsTakenOver() async throws {
        #expect(SelfUpdaterStash.archiveKind(for: "App-1.2.3-arm64.zip") == .zip)
        #expect(SelfUpdaterStash.archiveKind(for: "App.dmg") == .dmg)
        #expect(SelfUpdaterStash.archiveKind(for: "App.pkg") == nil)

        let app = Self.fixtureApp(name: "ZZStash-Dmg", cacheDirName: "zzdmg-updater")
        let caches = try await Self.layOutCache(
            cacheDirName: "zzdmg-updater", archiveName: "zzfixture.dmg")
        defer { try? FileManager.default.removeItem(at: caches) }
        await Self.expectRefusal(
            .unsupportedKind, for: app, population: [app], caches: caches)
    }

    /// `update-info.json` naming a file that is no longer there — electron-updater
    /// empties `pending/` on its own schedule.
    /// Mutation: drop the `fileExists` guard.
    @Test func aRecordNamingAMissingArchiveIsRefused() async throws {
        let app = Self.fixtureApp(name: "ZZStash-Gone", cacheDirName: "zzgone-updater")
        // Non-empty digest for the same reason the separator case needs one:
        // `layOutCache` writes "" when it skips the archive, and `pendingRecord`
        // refuses an empty `sha512` two gates earlier — which is what made this
        // case vacuous until `evaluate` let it assert WHICH gate answered.
        let caches = try await Self.layOutCache(
            cacheDirName: "zzgone-updater",
            recordedSHA512: "ZZfixtureDigestNotComparedHere==", writeArchive: false)
        defer { try? FileManager.default.removeItem(at: caches) }

        await Self.expectRefusal(
            .archiveMissing, for: app, population: [app], caches: caches)
    }

    /// `app-update.yml` carries the key we now read, and an absent key stays absent
    /// rather than becoming an empty string.
    @Test func theCacheDirectoryNameIsParsedFromAppUpdateYML() throws {
        let withKey = try #require(ElectronUpdateConfig.parse("""
            owner: anomalyco
            repo: opencode
            provider: github
            channel: latest
            updaterCacheDirName: '@opencode-aidesktop-updater'
            """))
        #expect(withKey.updaterCacheDirName == "@opencode-aidesktop-updater")

        let without = try #require(ElectronUpdateConfig.parse("""
            provider: generic
            url: https://zzfixture.invalid
            """))
        #expect(without.updaterCacheDirName == nil)
    }

    // MARK: - Cindy's hotfix updater

    /// A Cindy copy at an invented path. The bundle IDs are the real ones: the
    /// spot is chosen by them, so a fixture ID would test nothing.
    private static func cindyApp(
        name: String = "ZZCindyStash", id: String = CindyChannel.globalBundleID
    ) -> InstalledApp {
        let path = URL(fileURLWithPath: "/Applications/\(name).app")
        #expect(!FileManager.default.fileExists(atPath: path.path),
                "fixture path must not exist on the host: \(path.path)")
        return InstalledApp(
            name: name, bundleID: id,
            shortVersion: "0.1.97", buildVersion: "0.1.97",
            path: path, isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: true, releaseChannel: .stable)
    }

    /// Lays out `<support>/<userData>/updates/{patch-info.json,<archive>}` the way
    /// Cindy's `writePatchInfo` does, and returns the Application Support root.
    /// `recordedSHA256` defaults to the archive's real digest in lowercase hex.
    private static func layOutCindy(
        userData: String = "CindyGlobal",
        fileName: String = "cindy-9.9.9-arm64-hotfix.zip",
        zipBundleID: String = CindyChannel.globalBundleID,
        short: String = offered, recordedSHA256: String? = nil
    ) async throws -> URL {
        let fm = FileManager.default
        let support = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-support-\(UUID().uuidString)", isDirectory: true)
        let updates = support
            .appendingPathComponent(userData, isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
        try fm.createDirectory(at: updates, withIntermediateDirectories: true)
        let archive = updates.appendingPathComponent(fileName)
        try await makeZip(
            at: archive, appName: "Cindy", bundleID: zipBundleID,
            short: short, build: short, nestedHelper: true)
        let actual = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }.joined()
        let digest = recordedSHA256 ?? actual
        try JSONSerialization
            .data(withJSONObject: [
                "version": short, "fileName": fileName, "sha256": digest,
                "requireRelogin": false, "enableBeta": false,
            ])
            .write(to: updates.appendingPathComponent("patch-info.json"))
        return support
    }

    private static func evaluateCindy(
        _ app: InstalledApp, population: [InstalledApp], support: URL,
        offering version: String = offered
    ) async -> Result<LocalStagedInstaller, SelfUpdaterStash.Rejection> {
        // A caches root with nothing in it, so an electron spot can never answer
        // for a Cindy case by accident.
        let emptyCaches = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-nocaches-\(UUID().uuidString)", isDirectory: true)
        return await SelfUpdaterStash.evaluate(
            for: result(app, offering: version), population: population,
            cachesDirectory: emptyCaches, applicationSupportDirectory: support)
    }

    private static func refusal(
        _ outcome: Result<LocalStagedInstaller, SelfUpdaterStash.Rejection>
    ) -> SelfUpdaterStash.Rejection? {
        if case .failure(let why) = outcome { return why }
        return nil
    }

    /// The case this exists for: Cindy running in the background has already
    /// fetched exactly the release we are about to install.
    ///
    /// Mutation: drop the Cindy branch of `parkingSpot(for:)` → `noParkingSpot`.
    @Test func aFinishedCindyHotfixOfTheOfferedVersionIsUsed() async throws {
        let app = Self.cindyApp()
        let support = try await Self.layOutCindy()
        defer { try? FileManager.default.removeItem(at: support) }

        let outcome = await Self.evaluateCindy(app, population: [app], support: support)
        let stash = try outcome.get()
        #expect(stash.kind == .zip)
        #expect(stash.bundleID == CindyChannel.globalBundleID)
        #expect(stash.version.marketing == Self.offered)
        #expect(stash.archiveURL.path.hasSuffix("/CindyGlobal/updates/cindy-9.9.9-arm64-hotfix.zip"))
    }

    /// What this machine actually held on 2026-10-15: a 0.1.99 hotfix while
    /// 0.1.108 was on offer.
    ///
    /// Mutation: drop the version gate in `evaluate`.
    @Test func aCindyHotfixOfAnotherVersionIsRefused() async throws {
        let app = Self.cindyApp()
        let support = try await Self.layOutCindy(short: "0.1.99")
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(Self.refusal(await Self.evaluateCindy(
            app, population: [app], support: support, offering: "0.1.108")) == .versionMismatch)
    }

    /// Mutation: make `RecordedDigest.matches` return true for `.sha256Hex`, or
    /// compare it against a SHA-512.
    @Test func aCindyHotfixThatDoesNotMatchItsRecordedSHA256IsRefused() async throws {
        let app = Self.cindyApp()
        let support = try await Self.layOutCindy(recordedSHA256: String(repeating: "0", count: 64))
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(Self.refusal(await Self.evaluateCindy(app, population: [app], support: support))
                == .checksumMismatch)
    }

    /// The app lowercases the manifest's digest before writing it, so the file is
    /// lowercase in practice; an uppercase one is the same digest, not a mismatch.
    ///
    /// Mutation: drop `.lowercased()` from the hex comparison.
    @Test func theRecordedSHA256IsComparedWithoutRegardToCase() async throws {
        let app = Self.cindyApp()
        let probe = try await Self.layOutCindy()
        let archive = probe.appendingPathComponent("CindyGlobal/updates/cindy-9.9.9-arm64-hotfix.zip")
        let upper = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02X", $0) }.joined()
        // Re-record the same bytes with the digest spelled in uppercase.
        try JSONSerialization
            .data(withJSONObject: [
                "version": Self.offered, "fileName": "cindy-9.9.9-arm64-hotfix.zip", "sha256": upper,
            ])
            .write(to: probe.appendingPathComponent("CindyGlobal/updates/patch-info.json"))
        defer { try? FileManager.default.removeItem(at: probe) }

        #expect(Self.refusal(await Self.evaluateCindy(app, population: [app], support: probe)) == nil)
    }

    /// Each edition parks under its own `userData`: a global copy must not pick up
    /// the CN edition's hotfix, and the CN copy must find its own.
    ///
    /// Mutation: point both editions at one directory in
    /// `CindyChannel.userDataDirectoryName`.
    @Test func eachCindyEditionReadsOnlyItsOwnUpdatesDirectory() async throws {
        let global = Self.cindyApp(name: "ZZCindyGlobal")
        let china = Self.cindyApp(name: "ZZCindyCN", id: CindyChannel.chinaBundleID)
        let support = try await Self.layOutCindy(
            userData: "Cindy", zipBundleID: CindyChannel.chinaBundleID)
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(Self.refusal(await Self.evaluateCindy(
            global, population: [global, china], support: support)) == .noPendingRecord)
        #expect(Self.refusal(await Self.evaluateCindy(
            china, population: [global, china], support: support)) == nil)
    }

    /// Two copies of one edition share `updates/`, exactly as two copies of an
    /// electron-updater app share a cache directory, and the archive's bundle ID
    /// cannot tell them apart. The two editions do not share it, so their
    /// coexisting is not a contest.
    ///
    /// Mutation: compare anything but the parking spot in `isSoleClaimant`.
    @Test func twoCopiesOfOneCindyEditionAreRefused() async throws {
        let one = Self.cindyApp(name: "ZZCindyOne")
        let two = Self.cindyApp(name: "ZZCindyTwo")
        let china = Self.cindyApp(name: "ZZCindyChina", id: CindyChannel.chinaBundleID)
        let support = try await Self.layOutCindy()
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(Self.refusal(await Self.evaluateCindy(
            one, population: [one, two], support: support)) == .attributionAmbiguous)
        #expect(Self.refusal(await Self.evaluateCindy(
            one, population: [one, china], support: support)) == nil)
    }

    /// Mutation: drop `isPlainFileName` from `cindyPatchRecord`. Asserted on the
    /// record reader itself: through `evaluate`, a traversal name would simply
    /// name a file that is not there and be refused as `archiveMissing` anyway.
    @Test func aCindyPatchFileNameThatLeavesUpdatesIsRefused() throws {
        let fm = FileManager.default
        let userData = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-userdata-\(UUID().uuidString)", isDirectory: true)
        let updates = userData.appendingPathComponent("updates", isDirectory: true)
        try fm.createDirectory(at: updates, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: userData) }

        func record(_ fileName: String) throws -> SelfUpdaterStash.PendingRecord? {
            try JSONSerialization
                .data(withJSONObject: ["fileName": fileName, "sha256": "ab"])
                .write(to: updates.appendingPathComponent("patch-info.json"))
            return SelfUpdaterStash.cindyPatchRecord(inUserDataDirectory: userData, fileManager: fm)
        }
        #expect(try record("../escape.zip") == nil)
        #expect(try record("..") == nil)
        #expect(try record("cindy-9.9.9-arm64-hotfix.zip")?.digest == .sha256Hex("ab"))
    }
}
