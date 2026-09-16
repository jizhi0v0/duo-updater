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
/// **The default state of this shape is stale debris, not a live offer.** Measured
/// on one machine on 2026-09-16: four apps had a parked installer totalling 438 MB,
/// and three of them trailed what was already installed — ChatWise held a build
/// five months old (26.3.36 against 26.8.0 on disk), Warp one two months old, and
/// UURemote one older than a copy that was already current. Only OpenCode's was the
/// release we were about to install. So every gate below is load-bearing: an
/// implementation that reused whatever it found would have performed three silent
/// downgrades for one saved download.
public enum SelfUpdaterStash {

    /// Where electron-updater parks what it has downloaded.
    ///
    /// The layout is the library's, not the vendor's, so one reader covers the
    /// whole electron-builder family rather than a recipe per app (28 of the 179
    /// bundles in `AppScanner.defaultLocations` on one machine). From
    /// `DownloadedUpdateHelper` (electron-updater 6.8.9, read out of a shipped
    /// `app.asar` on 2026-09-16):
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
    ///   copies of one app have the same one. Measured 2026-09-16:
    ///   `T3 Code (Alpha)` 0.0.39 and `T3 Code (Nightly)` 0.0.40-nightly both
    ///   report `com.t3tools.t3code` and both name `t3code-updater`, differing
    ///   only in the `channel` their `app-update.yml` asks for.
    ///
    /// What would be left is the version comparison, and leaning on it here means
    /// betting correctness on a vendor's version-string habits — T3 Code's two
    /// channels happen to be distinguishable only because the nightly carries a
    /// `-nightly.<date>.<n>` suffix. Under this type's contract the loser of that
    /// bet is an install of the wrong channel's bytes over the other copy.
    ///
    /// Note the shape is not new: `SelfUpdaterStaging.sparkleStagedBundle`
    /// documents the same collision for Sparkle's cache and records it as a known
    /// limitation. The difference is what it costs — there it can mislabel a row,
    /// here it would write the wrong bundle to disk.
    ///
    /// Compared by path, so the same bundle appearing twice in `population` (a
    /// caller that concatenated two scans) does not read as a contest.
    public static func attributionIsUnique(
        cacheDirectoryName: String, in population: [InstalledApp]
    ) -> Bool {
        var claimants = Set<String>()
        for app in population where electronCacheDirectoryName(for: app) == cacheDirectoryName {
            claimants.insert(app.path.resolvingSymlinksInPath().standardizedFileURL.path)
        }
        return claimants.count == 1
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

    /// Why a parked installer was not used. Logged rather than surfaced: every
    /// one of these means "download it the usual way", which is what the user
    /// already expects, so none of them is a failure to report.
    enum Rejection: String, Sendable {
        case populationUnknown
        case noCacheDirectoryName
        case attributionAmbiguous
        case noPendingRecord
        case archiveMissing
        case unsupportedKind
        case checksumMismatch
        case unreadableBundle
        case bundleIDMismatch
        case versionMismatch
    }

    /// The installer this app's own updater has already downloaded, when every
    /// gate below passes — otherwise nil, and the caller downloads as usual.
    ///
    /// **What this substitution changes, and what it must not.** The bytes we take
    /// are not the artifact our route resolved: OpenCode's `GitHubReleaseRule`
    /// selects `opencode-desktop-mac-arm64.dmg`, while electron-updater on macOS
    /// only ever downloads a zip (`findFile(files, "zip", ["pkg", "dmg"])`). Same
    /// release, same Team, both notarized — a different container. So everything
    /// the route publishes that describes *its* artifact stops applying, and the
    /// caller must drop it rather than run it against these bytes:
    ///
    /// - `RemoteVersion.expectedSHA512` digests the dmg. Run here it cannot pass,
    ///   and it would fail as `checksumMismatch` — "may be corrupt or tampered" —
    ///   for a file that is neither. Its replacement is gate 6 below, which is the
    ///   stronger statement anyway: it checks the bytes on disk against the digest
    ///   the app's own updater recorded for them.
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
        func reject(_ why: Rejection) -> LocalStagedInstaller? {
            Log.install.debug(
                "local stash unused for \(result.app.name, privacy: .public): \(why.rawValue, privacy: .public)")
            return nil
        }

        guard let remote = result.remote, let installedID = result.app.bundleID
        else { return nil }
        // Gate 1 — we must be able to see the whole population to know whether
        // anyone else claims this cache directory.
        guard let population else { return reject(.populationUnknown) }
        // Gate 2 — the app has to name its own cache directory; we never guess one.
        guard let key = electronCacheDirectoryName(for: result.app)
        else { return reject(.noCacheDirectoryName) }
        // Gate 3 — and has to be the only claimant of it.
        guard attributionIsUnique(cacheDirectoryName: key, in: population)
        else { return reject(.attributionAmbiguous) }

        guard let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let cacheDir = caches.appendingPathComponent(key, isDirectory: true)

        // Gate 4 — a completed-download record, and the file it names still there.
        guard let record = pendingRecord(inCacheDirectory: cacheDir, fileManager: fileManager)
        else { return reject(.noPendingRecord) }
        let archive = cacheDir
            .appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent(record.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: archive.path) else { return reject(.archiveMissing) }

        // Gate 5 — a container this route can actually unpack and swap. In practice
        // always `.zip` for this family; the others are refused rather than assumed
        // because reading a version back out of them is not cheap the way it is for
        // a zip (a dmg has to be mounted), so they cannot clear gate 8 anyway.
        guard archiveKind(for: record.fileName) == .zip else { return reject(.unsupportedKind) }

        let bytes = (try? fileManager.attributesOfItem(atPath: archive.path)[.size]
                     as? NSNumber)?.int64Value ?? 0

        // Gate 6 — the bytes on disk are the ones the app's updater recorded. Off
        // the cooperative pool: hashing 149.6 MB measured 0.31 s, which is a whole
        // thread parked for the duration if run inline (see `OffPool`).
        let path = archive.path
        let digestMatches = await offCooperativePool { () -> Bool in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                       options: .mappedIfSafe) else { return false }
            return Data(SHA512.hash(data: data)).base64EncodedString()
                == record.sha512.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard digestMatches else { return reject(.checksumMismatch) }

        // Gates 7 and 8 — what IS this, and is it what we were about to install?
        // The archive is the only place that can answer: `update-info.json` carries
        // no version, and the file name need not either (OpenCode's is
        // `opencode-desktop-mac-arm64.zip`).
        guard let info = await stagedBundleInfo(inZip: archive) else {
            return reject(.unreadableBundle)
        }
        guard info.bundleID == installedID else { return reject(.bundleIDMismatch) }
        guard VersionComparator.isSame(info.version, as: remote.versionSide) else {
            return reject(.versionMismatch)
        }

        Log.install.notice(
            "local stash hit: \(result.app.name, privacy: .public) \(info.version.text(withBuild: true), privacy: .public) already downloaded by its own updater — \(bytes, privacy: .public) B not fetched")
        return LocalStagedInstaller(
            archiveURL: archive, kind: .zip, version: info.version,
            bundleID: info.bundleID, bytes: bytes)
    }

    /// Identity and version of the top-level `.app` inside a zip, read without
    /// unpacking it.
    ///
    /// A zip's central directory sits at the tail and is randomly addressable, so
    /// this reads roughly 4 KB out of an archive of any size — measured 2026-09-16
    /// at 6.0 ms on a 149.6 MB / 630-entry archive and 2.0 ms on a 113.0 MB one,
    /// against 0.56 s to unpack the same archive in full. The cost tracks the
    /// number of entries, not the number of bytes.
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
