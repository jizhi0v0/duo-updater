import AppKit
import Foundation

/// A Squirrel (Electron) self-update that has been fully downloaded and unpacked
/// into the ShipIt staging cache, but not yet swapped into `/Applications`. This
/// is the "Relaunch to update" state the app shows in its own UI: the new bytes
/// are on disk, the on-disk bundle is still the old version, and the swap happens
/// only on the app's next quit.
public struct StagedSelfUpdate: Sendable, Hashable {
    /// `CFBundleShortVersionString` of the staged bundle — the version that will
    /// be live after a relaunch.
    public let version: String
    /// `CFBundleVersion` of the staged bundle, when present.
    public let buildVersion: String?
    /// The staged `.app` inside the ShipIt cache (not yet installed).
    public let stagedBundlePath: URL

    public init(version: String, buildVersion: String?, stagedBundlePath: URL) {
        self.version = version
        self.buildVersion = buildVersion
        self.stagedBundlePath = stagedBundlePath
    }
}

/// Detects updates that an app's *own* Squirrel updater (Electron's
/// Squirrel.Mac / ShipIt) has already downloaded and staged, pending a relaunch.
///
/// This is the gap `computeRestartInfo` (disk-vs-running) can't see: there the
/// bundle has already been swapped; here it hasn't — the new version sits in
/// `~/Library/Caches/<bundleID>.ShipIt/` waiting for the next quit. Surfacing it
/// lets us show "Relaunch" instead of offering our own one-click Update, which
/// would re-download the same bytes and collide with the pending ShipIt swap.
///
/// One generic detector covers every Squirrel app — it keys on the standard
/// ShipIt cache layout, not a per-app recipe.
public enum SelfUpdaterStaging {

    /// Cheap predicate for whether `app` could have a staged self-update at all —
    /// the candidate filter before doing per-app filesystem work. Covers Squirrel
    /// apps (the generic ShipIt path) plus the handful of vendors that ship their
    /// own staging layout (Spotify). Keeps `computeSelfUpdateStaging` from
    /// stat-ing every installed app.
    public static func mayHaveStaging(_ app: InstalledApp) -> Bool {
        app.hasSelfUpdater || app.hasSparkleUpdater || app.bundleID == spotifyBundleID
    }

    private static let spotifyBundleID = "com.spotify.client"

    /// The staged self-update for `app`, or nil when there isn't one. Returns nil
    /// unless: the app ships a self-updater, a ShipIt state file names *this exact
    /// bundle* as its target, the staged bundle still exists on disk, and its
    /// version is strictly newer than what's installed. All filesystem access is
    /// best-effort — any malformed/missing piece yields nil, never a throw.
    ///
    /// Spotify ships its OWN (non-Squirrel) updater, so it's handled by a separate
    /// branch reading its native staging layout — same "Relaunch, no re-download"
    /// outcome, different on-disk format.
    /// - Parameter requireNewerThanInstalled: keep only a staged build that would
    ///   move the app forward. True for the Relaunch affordance, which must never
    ///   offer a downgrade. **False when deciding whether to install at all**: a
    ///   staged build that trails what is on disk still gets applied on the next
    ///   quit, so it overwrites whatever we install in the meantime.
    ///
    ///   That an older staged build really does win is not theoretical: on
    ///   2026-08-22 the mini installed 6971 and ChatGPT's own updater later applied
    ///   6962, leaving the machine on the OLDER version. (In that instance the
    ///   staging happened *after* our install, so no gate here could have seen it —
    ///   what it establishes is that a trailing staged build gets applied, which is
    ///   why filtering on "newer" is the wrong question when one IS visible.)
    public static func staged(
        for app: InstalledApp,
        requireNewerThanInstalled: Bool = true,
        cachesDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        parkedInstallerBundleURLs: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> StagedSelfUpdate? {
        guard let bundleID = app.bundleID else { return nil }

        if bundleID == spotifyBundleID {
            return spotifyStaged(
                for: app, requireNewerThanInstalled: requireNewerThanInstalled,
                applicationSupportDirectory: applicationSupportDirectory,
                fileManager: fileManager)
        }

        // Sparkle apps reach the same answer by a different cache layout. Asked
        // second because an app embeds one framework or the other, never both, so
        // whichever guard fails costs a single `hasSelfUpdater` read.
        guard app.hasSelfUpdater else {
            guard app.hasSparkleUpdater,
                  let staged = sparkleStagedBundle(
                    for: app, cachesDirectory: cachesDirectory,
                    parkedInstallerBundleURLs: parkedInstallerBundleURLs,
                    fileManager: fileManager)
            else { return nil }
            // `sparkleStagedBundle` deliberately returns a staged build of ANY
            // version, because the restart check needs the ones that are older
            // (see `RestartStandoff`). This caller wants the opposite question —
            // "is there an update waiting that a relaunch would apply?" — so the
            // strictly-newer filter belongs here, matching the two branches below.
            // Offering Relaunch for an older staged build would be offering a
            // downgrade, which is exactly the ChatGPT case.
            if requireNewerThanInstalled {
                let stagedV = staged.buildVersion ?? staged.version
                guard let installedV = app.buildVersion ?? app.shortVersion,
                      VersionComparator.isNewer(stagedV, than: installedV) else { return nil }
            }
            return staged
        }

        // Squirrel writes its staging area to ~/Library/Caches/<bundleID>.ShipIt/.
        let caches = cachesDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return nil }
        let stateURL = caches
            .appendingPathComponent("\(bundleID).ShipIt", isDirectory: true)
            .appendingPathComponent("ShipItState.plist", isDirectory: false)

        guard let data = try? Data(contentsOf: stateURL),
              let state = dictionary(from: data) else { return nil }

        // The swap target must be *this* app's bundle — guard against a stale
        // ShipIt state pointed at a different install that happens to share the
        // cache namespace, or a moved app.
        guard let target = fileURL(from: state["targetBundleURL"]),
              samePath(target, app.path, fileManager) else { return nil }

        guard let staged = fileURL(from: state["updateBundleURL"]),
              fileManager.fileExists(atPath: staged.path) else { return nil }

        let info = staged.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let infoData = try? Data(contentsOf: info),
              let infoDict = dictionary(from: infoData),
              let stagedShort = infoDict["CFBundleShortVersionString"] as? String
        else { return nil }
        let stagedBuild = infoDict["CFBundleVersion"] as? String

        // Compare the staged build against what's installed, mirroring
        // `computeRestartInfo`'s build-then-short preference. Only a strictly newer
        // staged version counts — a leftover state file whose staged bundle equals
        // (or trails) what's on disk has already been applied.
        if requireNewerThanInstalled {
            let stagedV = stagedBuild ?? stagedShort
            guard let installedV = app.buildVersion ?? app.shortVersion,
                  VersionComparator.isNewer(stagedV, than: installedV) else { return nil }
        }

        return StagedSelfUpdate(
            version: stagedShort, buildVersion: stagedBuild, stagedBundlePath: staged)
    }

    /// Spotify's native staged update. Spotify's own updater downloads the next
    /// build to `~/Library/Application Support/Spotify/PersistentCache/Update/`
    /// (a `spotify-autoupdate-<ver>.tbz` plus an `update.json` carrying
    /// `version_from`/`version_to`/`update_path`) and applies it on the app's next
    /// quit — the "Spotify has been updated to version X. Please restart to
    /// install." state. That's the same situation as a ShipIt staged update, so we
    /// surface it as **Relaunch** rather than letting the vendor probe offer a
    /// 164MB re-download of bytes Spotify already has on disk.
    private static func spotifyStaged(
        for app: InstalledApp,
        requireNewerThanInstalled: Bool = true,
        applicationSupportDirectory: URL?,
        fileManager: FileManager
    ) -> StagedSelfUpdate? {
        let appSupport = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else { return nil }
        let stateURL = appSupport
            .appendingPathComponent("Spotify/PersistentCache/Update", isDirectory: true)
            .appendingPathComponent("update.json", isDirectory: false)

        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        // CRUCIAL: update.json is NOT valid JSON — its `installation_id` carries raw
        // (non-UTF8) bytes, so a full `JSONSerialization` parse fails on the whole
        // file. Decode leniently (bad bytes → replacement chars) and regex out only
        // the clean ASCII fields we need; the version/path are unaffected.
        let text = String(decoding: data, as: UTF8.self)
        guard
            let versionTo = VendorProbeRecipe.extractVersion(
                from: text, pattern: #""version_to"\s*:\s*"([0-9][0-9.]*)""#),
            let updatePath = VendorProbeRecipe.extractVersion(
                from: text, pattern: #""update_path"\s*:\s*"([^"]+)""#)
        else { return nil }

        // The staged archive update.json names must still be on disk — guard a
        // leftover update.json after the .tbz was consumed or cleared.
        guard fileManager.fileExists(atPath: updatePath) else { return nil }

        // `version_to` is Spotify's marketing version, so compare it against the
        // installed marketing string (the installed value may carry a trailing
        // `.gHASH`, but they already differ at the build component). Only a
        // strictly newer staged version counts — once applied, on-disk equals
        // `version_to` and this returns nil. Mirrors the ShipIt branch.
        if requireNewerThanInstalled {
            guard let installedV = app.shortVersion ?? app.buildVersion,
                  VersionComparator.isNewer(versionTo, than: installedV) else { return nil }
        }

        // stagedBundlePath is informational here (the relaunch action quits the
        // app and lets Spotify perform the swap), so point it at the staged .tbz.
        return StagedSelfUpdate(
            version: versionTo, buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: updatePath))
    }

    /// Parse a string-keyed dictionary from either a property list or JSON.
    /// Current Squirrel.Mac writes `ShipItState.plist` as **JSON** despite the
    /// `.plist` extension (older builds used a real plist), while a bundle's
    /// `Info.plist` is a true plist — so we try both encodings.
    private static func dictionary(from data: Data) -> [String: Any]? {
        if let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil), let dict = plist as? [String: Any] {
            return dict
        }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let dict = json as? [String: Any] {
            return dict
        }
        return nil
    }

    /// A bundle **Sparkle** has downloaded, unpacked and parked in its
    /// installation cache, waiting for this app to quit. Returns it whatever its
    /// version, including one OLDER than what is installed — which is not an
    /// oversight but the case that matters most, so the version comparison is
    /// deliberately the caller's:
    ///
    ///   - "should the row offer Relaunch instead of our own Update?" wants a
    ///     staged build strictly newer than what is on disk, the way the Squirrel
    ///     and Spotify branches above answer it.
    ///   - "is it safe to quit this app to apply what we just installed?" wants
    ///     any staged build that DIFFERS. On 2026-08-22 ChatGPT had 26.818.41509
    ///     staged while disk held the 26.818.41705 we had just written; quitting
    ///     it handed Sparkle the signal it was parked on and the older build
    ///     landed on top of ours. A "strictly newer" filter here would have
    ///     returned nil for exactly that.
    ///
    /// Layout, as observed: `Installation/<random>/<random>/<Name>.app`, beside
    /// the `.dmg` it came from. `Launcher/` is deliberately not searched — it
    /// holds Sparkle's own `Updater.app`, which is not a staged copy of anything;
    /// the bundle-identifier check below independently rejects it.
    ///
    /// **An unpacked bundle in the cache is not on its own evidence of anything.**
    /// The Squirrel branch above demands a `ShipItState.plist` naming this bundle
    /// as its target — positive proof an installer was armed. Sparkle writes no
    /// such record, and it only garbage-collects its staging directory for entries
    /// older than ten days, and then only when a new staging run happens
    /// (`OLD_ITEM_DELETION_INTERVAL` in Sparkle's `SPULocalCacheDirectory.m`). So
    /// an extraction abandoned by a reboot, a killed installer or a failed apply
    /// stays on disk, and treating it as live meant a Restart button that held
    /// back — pointing at an update that no longer existed — for up to ten days.
    ///
    /// The evidence used instead is the thing that actually does the work: an
    /// installer process parked on this app's termination. Nothing applies on quit
    /// without one, so where there is no parked installer there is nothing to
    /// avoid, whatever is lying in the cache.
    ///
    /// **Known limitation.** Sparkle's cache is keyed by bundle identifier alone,
    /// and so is the parked installer's own location, so two copies of one app
    /// (this project's verification workflow keeps an older one in
    /// `~/Applications`) share one cache and cannot be told apart here. For the
    /// restart check that errs safe — both copies hold back. For the Relaunch
    /// offer it can attribute a staged build to the wrong copy. The installer's
    /// argv does name its target bundle, which would settle it, but that ordering
    /// is undocumented and not worth depending on yet.
    public static func sparkleStagedBundle(
        for app: InstalledApp,
        cachesDirectory: URL? = nil,
        parkedInstallerBundleURLs: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> StagedSelfUpdate? {
        guard let bundleID = app.bundleID else { return nil }
        let caches = cachesDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return nil }
        let sparkleRoot = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)

        // Cheapest discriminator first: no parked installer, nothing to avoid.
        //
        // Two locations, because Sparkle picks between them. `SUInstallerLauncher.m`
        // does `BOOL rootUser = (geteuid() == 0)` and then
        // `BOOL copyProgressTool = !rootUser` — so the usual case, including an
        // install that needs administrator authorisation (that one is
        // `inSystemDomain && !rootUser`), copies the agent into this app's staging
        // cache. Only a launcher already running as euid 0 skips the copy and
        // launches the agent out of the host bundle's own framework.
        //
        // That second case is rare, and accepting it is cheap. It is worth the two
        // lines because this gate fails OPEN — no parked installer found means
        // `.proceed` — so a location we cannot see is not a missing warning, it is
        // the overwrite bug back again.
        let parked = parkedInstallerBundleURLs ?? liveParkedSparkleInstallers()
        let homes = [sparkleRoot, app.path].map { normalizedPath($0) + "/" }
        guard parked.contains(where: { installer in
            let path = normalizedPath(installer)
            return homes.contains(where: path.hasPrefix)
        }) else { return nil }

        let root = sparkleRoot.appendingPathComponent("Installation", isDirectory: true)

        // The directory itself survives every install — it is empty when nothing
        // is staged, which is why its existence proves nothing and its mtime
        // (which does not follow its children) proves less.
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }

        for case let url as URL in walker where url.pathExtension == "app" {
            let info = url.appendingPathComponent("Contents/Info.plist", isDirectory: false)
            guard let data = try? Data(contentsOf: info),
                  let dict = dictionary(from: data),
                  // Must be a staged copy of THIS app. Rejects Sparkle's own
                  // Updater.app and anything else sharing the cache namespace.
                  dict["CFBundleIdentifier"] as? String == bundleID,
                  let short = dict["CFBundleShortVersionString"] as? String
            else { continue }
            return StagedSelfUpdate(
                version: short, buildVersion: dict["CFBundleVersion"] as? String,
                stagedBundlePath: url)
        }
        return nil
    }

    /// The bundle identities a parked Sparkle installer can run under. Its own
    /// bundle *location* is what ties it to an app; these are how it is found at
    /// all.
    ///
    /// `…Updater` is Sparkle 2's progress agent — observed live as pid 27939 at
    /// `…/Caches/com.tinyapp.TablePlus/org.sparkle-project.Sparkle/Launcher/<random>/Updater.app`.
    /// `…Autoupdate` is Sparkle 1's, which ships as `Autoupdate.app` inside the
    /// host's framework (VLC 1.16.0 on this machine). Sparkle 2 also has an
    /// `Autoupdate`, but as a bare executable with no bundle — LaunchServices
    /// cannot enumerate it, so it is not a usable signal and is not one of these.
    ///
    /// **Sparkle 1 is nonetheless not covered**, and not because of this list:
    /// `sparkleStagedBundle` walks the `Caches/<id>/org.sparkle-project.Sparkle/`
    /// layout, which is Sparkle 2's. Sparkle 1 apps have no such directory
    /// (checked: VLC has a cache directory and no Sparkle subdirectory), so the
    /// walk finds nothing for them whatever is parked. Listing Sparkle 1's
    /// identity here costs nothing and errs toward holding back, which is the
    /// safe direction; it is not a claim that Sparkle 1 staging is detected.
    static let sparkleInstallerBundleIDs = [
        "org.sparkle-project.Sparkle.Updater",
        "org.sparkle-project.Sparkle.Autoupdate",
    ]

    /// Bundle locations of every Sparkle installer currently parked, for any app.
    ///
    /// Public so a sweep over many apps can ask once and pass the answer down,
    /// rather than repeating one global LaunchServices query per candidate.
    public static func liveParkedSparkleInstallers() -> [URL] {
        sparkleInstallerBundleIDs.flatMap { identifier in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .compactMap(\.bundleURL)
        }
    }

    /// ShipIt stores bundle locations as `file://` URL strings.
    private static func fileURL(from value: Any?) -> URL? {
        guard let string = value as? String, let url = URL(string: string),
              url.isFileURL else { return nil }
        return url
    }

    /// Compare two bundle paths for identity, tolerant of trailing slashes and
    /// symlinks (`/var` vs `/private/var`, etc.).
    private static func samePath(_ a: URL, _ b: URL, _ fm: FileManager) -> Bool {
        normalizedPath(a) == normalizedPath(b)
    }

    /// The one spelling of a path this file compares on. `standardizedFileURL`
    /// alone is not enough: it resolves `..` but leaves symlinks and the
    /// `/private` prefix alone, so a home directory reached through a link makes
    /// `FileManager.urls(for:)` and `NSRunningApplication.bundleURL` describe the
    /// same directory with two different strings.
    private static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
