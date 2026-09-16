import CryptoKit
import Foundation

/// An installer an app's OWN updater has already downloaded and parked on disk,
/// which we may unpack and swap in INSTEAD of fetching the same release again.
///
/// Distinct from `StagedSelfUpdate`, which is about an update the app's updater
/// will apply *by itself* on some trigger. This one is about bytes we take over:
/// nothing here is armed, nothing applies on quit, and the app is not consulted.
/// The two can describe the same release — a Squirrel app that has handed its
/// download to ShipIt is both — but they answer different questions and are read
/// by different callers.
/// `Equatable` rather than `Hashable` because `VersionSide` is — it is compared
/// through `VersionComparator`, never bucketed.
public struct LocalStagedInstaller: Sendable, Equatable {
    /// The archive as the app's updater left it, inside that updater's own cache.
    /// The caller copies it before use and never deletes it: it belongs to the
    /// other updater, which is free to reuse or clear it.
    public let archiveURL: URL
    /// Container format, derived from `archiveURL` itself rather than from the
    /// route. See ``SelfUpdaterStash/resolve(for:population:cachesDirectory:fileManager:)``
    /// for why the route's kind cannot speak for these bytes.
    public let kind: VendorInstallerKind
    /// Both version strings read out of the bundle inside the archive.
    public let version: VersionSide
    /// `CFBundleIdentifier` of the bundle inside the archive.
    public let bundleID: String
    /// Size of `archiveURL`, for the "bytes not spent" line in the install log.
    public let bytes: Int64
}

/// Finds an installer an app's own updater has already downloaded, so a one-click
/// update can use those bytes instead of fetching the same release a second time.
///
/// **The default state of this shape is stale debris, not a live offer**, so every
/// gate below is load-bearing — the version comparison most of all. The copies
/// this was measured against, the shapes deliberately left unimplemented, and what
/// the substitution switches off in `VendorInstaller.applyVerified` are in
/// `docs/engine-notes/self-updater-stash.md` §2, §4 and §6.
public enum SelfUpdaterStash {

    /// Where electron-updater parks what it has downloaded.
    ///
    /// The layout is the library's, not the vendor's, so one reader covers the
    /// whole electron-builder family rather than needing a recipe per app. From
    /// `DownloadedUpdateHelper` (electron-updater 6.8.9, read out of a shipped
    /// `app.asar` on 2026-09-16; how to survey a machine for it is in
    /// `docs/engine-notes/self-updater-stash.md` §1):
    ///
    /// ```js
    /// const cacheDir = path.join(this.app.baseCachePath, dirName || this.app.name)
    /// get cacheDirForPendingUpdate() { return path.join(this.cacheDir, "pending") }
    /// getUpdateInfoFile()            { return path.join(…, "update-info.json") }
    /// ```
    ///
    /// `baseCachePath` is `getAppCacheDir()` — `~/Library/Caches` on macOS — and
    /// `dirName` is `updaterCacheDirName` from the bundle's own `app-update.yml`.
    /// `update-info.json` is written when a download COMPLETES (`setDownloadedFile`)
    /// and is what the app reads on its next launch to decide it already has the
    /// file, so its presence is a real record rather than a leftover temp name.
    ///
    /// Returns nil when the bundle declares no `updaterCacheDirName` — see that
    /// property for why the fallback must not be guessed from here.
    public static func electronCacheDirectoryName(for app: InstalledApp) -> String? {
        guard let name = app.electronUpdate?.updaterCacheDirName, !name.isEmpty
        else { return nil }
        // The value is joined onto a cache path, so a separator or a parent
        // reference in it would reach outside `~/Library/Caches` entirely. No real
        // value needs one (`@opencode-aidesktop-updater`, `com.google.antigravity`,
        // `draw.io-updater` are typical), so this is refusal, not sanitisation.
        guard !name.contains("/"), name != ".", name != ".." else { return nil }
        return name
    }

    /// Whether exactly one installed bundle claims `cacheDirectoryName`.
    ///
    /// **This is the gate that has no substitute.** Two copies of one app share a
    /// cache directory, and the two checks that would otherwise settle ownership
    /// both come up empty there:
    ///
    /// - the directory name cannot, because it is what they share;
    /// - the bundle identifier inside the archive cannot either, because two
    ///   copies of one app have the same one.
    ///
    /// What would be left is the version comparison, and leaning on it means
    /// betting correctness on a vendor's version-string habits. The loser of that
    /// bet is an install of the wrong channel's bytes over the other copy.
    /// `SelfUpdaterStaging.sparkleStagedBundle` documents the same collision for
    /// Sparkle's cache; the difference is what it costs — there it can mislabel a
    /// row, here it would write the wrong bundle to disk. The observed pair of
    /// copies and why Squirrel's `ShipItState.plist` does NOT have this problem
    /// are in `docs/engine-notes/self-updater-stash.md` §3.
    ///
    /// Compared by path, so the same bundle appearing twice in `population` (a
    /// caller that concatenated two scans) does not read as a contest.
    ///
    /// ⚠️ **The sole claimant must be `app` itself, not merely a count of one.**
    /// Counting alone passes when `app` is ABSENT from `population` — an app at a
    /// path the scan did not cover, or one moved between the scan and the
    /// per-install re-check — while some other bundle claims the same directory.
    /// The gate would then hand that other app's `pending/` to this one, leaving
    /// only the archive's bundle identifier to object; and two copies of one app,
    /// the case this gate exists for, share that too.
    public static func isSoleClaimant(
        _ app: InstalledApp, of cacheDirectoryName: String, in population: [InstalledApp]
    ) -> Bool {
        var claimants = Set<String>()
        for candidate in population
        where electronCacheDirectoryName(for: candidate) == cacheDirectoryName {
            claimants.insert(canonicalPath(candidate.path))
        }
        return claimants == [canonicalPath(app.path)]
    }

    /// The one spelling of a bundle path this type compares on — resolved and
    /// standardized, so a home directory reached through a symlink does not read
    /// as a different bundle. Mirrors `SelfUpdaterStaging.normalizedPath`.
    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// What `pending/update-info.json` records. Deliberately only the fields
    /// electron-updater actually writes — `setDownloadedFile` stores exactly
    /// `fileName`, `sha512` and `isAdminRightsRequired`, and **no version**, which
    /// is why the version has to be read out of the archive itself.
    struct PendingRecord: Sendable, Hashable {
        let fileName: String
        let sha512: String
    }

    static func pendingRecord(
        inCacheDirectory cacheDir: URL, fileManager: FileManager
    ) -> PendingRecord? {
        let url = cacheDir
            .appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent("update-info.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileName = json["fileName"] as? String, !fileName.isEmpty,
              let sha512 = json["sha512"] as? String, !sha512.isEmpty
        else { return nil }
        // electron-updater itself reduces the download URL to `path.basename` before
        // storing it, with a comment naming the traversal it is avoiding. The value
        // still arrives here from a file, so the same reduction is re-applied rather
        // than assumed.
        guard !fileName.contains("/"), fileName != ".", fileName != ".."
        else { return nil }
        return PendingRecord(fileName: fileName, sha512: sha512)
    }

    /// The archive format, from the file name the vendor's own updater chose.
    ///
    /// Returns nil for anything else, `.pkg` included: a package is not swapped in
    /// place by this route at all (`VendorInstaller.download` rejects `.pkg` and
    /// `PackageInstaller` handles it), so admitting one here would hand the wrong
    /// installer a file it cannot use.
    static func archiveKind(for fileName: String) -> VendorInstallerKind? {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".zip") { return .zip }
        if lower.hasSuffix(".dmg") { return .dmg }
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tarGz }
        return nil
    }
}

extension SelfUpdaterStash {

    /// Why a parked installer was not used. None of these is a failure to report
    /// to the user — every one means "download it the usual way", which is what
    /// they already expect — but they are not all equally interesting to a reader.
    enum Rejection: String, Sendable, CaseIterable, Error {
        case populationUnknown
        case noCacheDirectoryName
        case noPendingRecord
        case archiveMissing
        case attributionAmbiguous
        case unsupportedKind
        case unreadableBundle
        case bundleIDMismatch
        case versionMismatch
        case checksumMismatch

        /// Whether this answer means "there IS a parked download and we refused
        /// it", as opposed to "this app has nothing parked".
        ///
        /// Decides the log level in ``SelfUpdaterStash/resolve(for:population:cachesDirectory:fileManager:)``,
        /// and the gate order is arranged so the distinction is exactly true
        /// rather than nearly true: every case below is reached only after an
        /// archive has been found on disk. The cheap "nothing to see" answers are
        /// the ordinary result for almost every app on the machine and would be a
        /// line per app per install for no reader; the refusals are the only thing
        /// that can answer "why did it fetch the whole thing again?", and neither
        /// `.debug` nor `.info` is retained for this subsystem.
        var refusedAnArchiveOnDisk: Bool {
            switch self {
            case .populationUnknown, .noCacheDirectoryName, .noPendingRecord, .archiveMissing:
                return false
            case .attributionAmbiguous, .unsupportedKind, .unreadableBundle,
                 .bundleIDMismatch, .versionMismatch, .checksumMismatch:
                return true
            }
        }
    }

    /// The installer this app's own updater has already downloaded, when every
    /// gate below passes — otherwise nil, and the caller downloads as usual.
    ///
    /// **What this substitution changes, and what it must not.** The bytes we take
    /// are not the artifact our route resolved: a route can select a dmg while
    /// electron-updater on macOS only ever downloads a zip
    /// (`findFile(files, "zip", ["pkg", "dmg"])`). Same release, same Team, both
    /// notarized — a different container. So everything the route publishes that
    /// describes *its* artifact stops applying, and the caller must drop it rather
    /// than run it against these bytes (worked example in
    /// `docs/engine-notes/self-updater-stash.md` §6):
    ///
    /// - `RemoteVersion.expectedSHA512` digests the dmg. Run here it cannot pass,
    ///   and it would fail as `checksumMismatch` — "may be corrupt or tampered" —
    ///   for a file that is neither. Its replacement is the digest gate below (gate
    ///   8), which is the stronger statement anyway: it checks the bytes on disk
    ///   against the digest the app's own updater recorded for them.
    /// - `RemoteVersion.nestedArchivePath` describes where a payload sits inside a
    ///   particular stub installer. A zip of the app is not that stub.
    ///
    /// What does NOT change is everything downstream of the container:
    /// `ArchiveExtractor` dispatches on the suffix, and
    /// `SignatureVerifier.verifyInstallArtifact` — bundle-id pin, Team-ID match
    /// against the installed copy, notarization — runs on the extracted bundle
    /// exactly as it does for a downloaded one. That is the gate that makes this
    /// safe, and it is deliberately the same code path rather than a parallel one.
    ///
    /// - Parameter population: every installed bundle this machine knows about,
    ///   for the attribution gate. **Nil means "not supplied", and is refused**
    ///   rather than treated as "no contest": the whole point of the gate is that
    ///   a contest is invisible from the one app in hand.
    public static func resolve(
        for result: UpdateResult,
        population: [InstalledApp]?,
        cachesDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) async -> LocalStagedInstaller? {
        switch await evaluate(
            for: result, population: population,
            cachesDirectory: cachesDirectory, fileManager: fileManager) {
        case .success(let stash):
            Log.install.notice(
                "local stash hit: \(result.app.name, privacy: .public) \(stash.version.text(withBuild: true), privacy: .public) already downloaded by its own updater — \(stash.bytes, privacy: .public) B not fetched")
            return stash
        case .failure(let why) where why.refusedAnArchiveOnDisk:
            Log.install.notice(
                "local stash refused for \(result.app.name, privacy: .public): \(why.rawValue, privacy: .public) — downloading instead")
            return nil
        case .failure(let why):
            Log.install.debug(
                "local stash not applicable for \(result.app.name, privacy: .public): \(why.rawValue, privacy: .public)")
            return nil
        }
    }

    /// ``resolve(for:population:cachesDirectory:fileManager:)`` without the
    /// logging, and saying WHICH gate answered.
    ///
    /// Separated because a reason that only reaches the log cannot be asserted:
    /// several gates here are each other's fallback — remove the one that checks
    /// the archive exists and the next gate fails on the same input for a
    /// different reason — so a test that only sees nil is measuring "something
    /// refused it", which stays true when the gate under test is deleted. That is
    /// not hypothetical: `aRecordNamingAMissingArchiveIsRefused` passed with its
    /// gate removed until this existed.
    static func evaluate(
        for result: UpdateResult,
        population: [InstalledApp]?,
        cachesDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) async -> Result<LocalStagedInstaller, Rejection> {
        func skip(_ why: Rejection) -> Result<LocalStagedInstaller, Rejection> { .failure(why) }
        let reject = skip

        // Not a `Rejection`: these are "this row cannot be installed by this
        // route at all", which the caller established before asking.
        guard let remote = result.remote, let installedID = result.app.bundleID
        else { return .failure(.noPendingRecord) }
        // Gate 1 — we must be able to see the whole population to know whether
        // anyone else claims this cache directory.
        guard let population else { return skip(.populationUnknown) }
        // Gate 2 — the app has to name its own cache directory; we never guess one.
        guard let key = electronCacheDirectoryName(for: result.app)
        else { return skip(.noCacheDirectoryName) }
        guard let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return .failure(.noPendingRecord) }
        let cacheDir = caches.appendingPathComponent(key, isDirectory: true)

        // Gate 3 — a completed-download record, and the file it names still there.
        guard let record = pendingRecord(inCacheDirectory: cacheDir, fileManager: fileManager)
        else { return skip(.noPendingRecord) }
        let archive = cacheDir
            .appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent(record.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: archive.path) else { return skip(.archiveMissing) }

        // Gate 4 — the directory the archive came out of has to belong to this app
        // alone.
        //
        // Asked AFTER the archive is known to exist, not before, so that the
        // `skip` / `reject` split above is exactly true: this is the first gate
        // that refuses a download which really is sitting on disk. Run earlier it
        // announced `attributionAmbiguous` at `.notice` for two copies of an app
        // whose `pending/` was empty, and a reader chasing "why did it download
        // again?" would go looking for a file that was never there.
        guard isSoleClaimant(result.app, of: key, in: population)
        else { return reject(.attributionAmbiguous) }

        // Gate 5 — a container this route can actually unpack and swap. In practice
        // always `.zip` for this family; the others are refused rather than assumed
        // because reading a version back out of them is not cheap the way it is for
        // a zip (a dmg has to be mounted), so they cannot clear gate 7 — the version
        // comparison — without paying for a mount.
        //
        // ⚠️ NOT gate 8: a whole-file digest does not care what the container is, so
        // a dmg clears that one perfectly well. This comment said "gate 8" while the
        // digest was numbered 6 and the sentence was true; the gates were then
        // reordered and it silently became the argument FOR supporting dmg.
        guard archiveKind(for: record.fileName) == .zip else { return reject(.unsupportedKind) }

        let bytes = (try? fileManager.attributesOfItem(atPath: archive.path)[.size]
                     as? NSNumber)?.int64Value ?? 0

        // Gates 6 and 7 — what IS this, and is it what we were about to install?
        // The archive is the only place that can answer: `update-info.json` carries
        // no version, and the file name need not either (OpenCode's is
        // `opencode-desktop-mac-arm64.zip`).
        //
        // Asked BEFORE the digest, which is the expensive one. The ordering is
        // chosen against the common case, not the interesting one: a parked
        // installer is usually months-old debris (see this type's summary), and
        // hashing a whole archive to learn what a 4 KB read already says spends
        // ~0.31 s against ~2 ms every time such an app is installed
        // (`docs/engine-notes/self-updater-stash.md` §5).
        //
        // The cost of this order, stated because it is not free: `unzip` now reads
        // an archive whose integrity has not been established. That is acceptable
        // here and only here — the file was written by an app already installed and
        // running as this user, so it is not a new trust boundary, and nothing from
        // it is used until the digest below agrees.
        guard let info = await stagedBundleInfo(inZip: archive) else {
            return reject(.unreadableBundle)
        }
        guard info.bundleID == installedID else { return reject(.bundleIDMismatch) }
        guard VersionComparator.isSame(info.version, as: remote.versionSide) else {
            return reject(.versionMismatch)
        }

        // Gate 8 — the bytes on disk are the ones the app's updater recorded. Off
        // the cooperative pool: this is a whole-file hash, and a hash of a download
        // parks a thread for its duration if run inline (see `OffPool`).
        let path = archive.path
        let digestMatches = await offCooperativePool { () -> Bool in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                       options: .mappedIfSafe) else { return false }
            return Data(SHA512.hash(data: data)).base64EncodedString()
                == record.sha512.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard digestMatches else { return reject(.checksumMismatch) }

        return .success(LocalStagedInstaller(
            archiveURL: archive, kind: .zip, version: info.version,
            bundleID: info.bundleID, bytes: bytes))
    }

    /// Identity and version of the top-level `.app` inside a zip, read without
    /// unpacking it.
    ///
    /// A zip's central directory sits at the tail and is randomly addressable, so
    /// this reads roughly 4 KB out of an archive of any size: the cost tracks the
    /// number of entries, not the number of bytes. Timings in
    /// `docs/engine-notes/self-updater-stash.md` §5.
    ///
    /// The entry is anchored to the archive root (`^[^/]+\.app/Contents/Info.plist$`).
    /// Electron bundles carry four nested helper `.app`s with their own
    /// `Info.plist`s — `OpenCode.app/Contents/Frameworks/OpenCode Helper (GPU).app/…`
    /// and siblings — and an unanchored match reaches those first. More than one
    /// root-level match means the archive holds several apps and is not what this
    /// route swaps, so it is refused rather than resolved by picking one.
    static func stagedBundleInfo(
        inZip archive: URL
    ) async -> (bundleID: String, version: VersionSide)? {
        guard let listing = try? await ChildProcess.run(
            "/usr/bin/unzip", ["-Z1", archive.path],
            standardError: .discard, onCancel: .runToCompletion),
              listing.terminationStatus == 0
        else { return nil }
        let entries = String(decoding: listing.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { name in
                name.hasSuffix(".app/Contents/Info.plist")
                    && name.components(separatedBy: "/").count == 3
            }
        guard entries.count == 1, let entry = entries.first else { return nil }

        guard let extracted = try? await ChildProcess.run(
            "/usr/bin/unzip", ["-p", archive.path, entry],
            standardError: .discard, onCancel: .runToCompletion),
              extracted.terminationStatus == 0,
              !extracted.standardOutput.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(
                from: extracted.standardOutput, options: [], format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String
        else { return nil }
        let version = VersionSide(
            marketing: VersionSide.plistVersionField(plist["CFBundleShortVersionString"]),
            build: VersionSide.plistVersionField(plist["CFBundleVersion"]))
        guard !version.isEmpty else { return nil }
        return (bundleID, version)
    }
}
