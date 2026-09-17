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
    /// What makes the app's own updater swap this build in.
    public let appliesOn: StagedApplyTrigger
    /// Which updater staged it, set by the detector that found it. Nil means
    /// nobody said, and a decision keyed on it must take its safe side (see
    /// `ReappearanceWatch.init(for:)`).
    public let updater: StagedUpdater?

    public init(
        version: String, buildVersion: String?, stagedBundlePath: URL,
        appliesOn: StagedApplyTrigger = .quit, updater: StagedUpdater? = nil
    ) {
        self.version = version
        self.buildVersion = buildVersion
        self.stagedBundlePath = stagedBundlePath
        self.appliesOn = appliesOn
        self.updater = updater
    }

    /// What identifies this staged build when the question is "is this a
    /// different build from the one we last saw" — newness comparisons and the
    /// announce-once ledger.
    ///
    /// The build number first, because `version` is a *marketing* string an app
    /// is free to leave alone across any number of builds: Amp shipped ten builds
    /// as "1.0" in one day, Surge shipped four releases as "6.9.0". Keyed on
    /// `version`, an announce-once ledger announces the first of those and then
    /// treats all nine of the rest as already-seen — quiet becoming silence,
    /// which is the exact failure `StagedNudgeLedger` documents itself as
    /// avoiding. Falls back to `version` for a staged bundle with no
    /// `CFBundleVersion`, where it is the only string there is.
    ///
    /// NOT for display: it is a bare build number with no marketing version in
    /// front of it. `UpdateResult.stagedRelaunchLine` is what a row or a
    /// notification should show.
    public var buildIdentity: String { buildVersion ?? version }

    /// Both version strings the staged bundle carries, for comparison against an
    /// installed copy or a remote offer. Prefer this over ``buildIdentity`` where
    /// the other side also has a pair: `buildIdentity` collapses to one string and
    /// so has to assume a namespace, while a pair comparison does not.
    public var versionSide: VersionSide {
        VersionSide(marketing: version, build: buildVersion)
    }
}

/// The event on which an app's own updater applies a build it has staged.
///
/// Decides what Relaunch has to do. For `.quit` we must quit and then keep our
/// hands off until disk moves — reopening early makes ShipIt abort with "App
/// Still Running Error". For `.launch` the quit alone does nothing: disk never
/// moves until someone opens the app again, so waiting for it is a guaranteed
/// timeout.
public enum StagedApplyTrigger: Sendable, Hashable {
    /// Squirrel's ShipIt and Sparkle's parked installer: swap once the app has
    /// quit. They differ on a second instance — see `StagedUpdater`.
    case quit
    /// Spotify: the next launch of the *old* build spawns `sp_relauncher`, which
    /// swaps the bundle and opens the new one.
    case launch
}

/// The updater that staged a `StagedSelfUpdate`. Carried because they do not
/// behave alike once the app is quit, and the difference decides whether an
/// instance that comes back up means the swap is off (`ReappearanceWatch`).
public enum StagedUpdater: Sendable, Hashable {
    /// Squirrel.Mac's ShipIt. Builds that include the running-instances check
    /// refuse to swap while an instance of the target runs: current
    /// `Squirrel/SQRLInstaller.m` (master, read 2026-09-17) lists
    /// `runningApplicationsWithBundleIdentifier` filtered to the target bundle
    /// right before installing, and fails with `SQRLInstallerErrorAppStillRunning`
    /// ("Aborting update attempt because there are %lu running instances of the
    /// target app") if any are left.
    ///
    /// Not every bundled ShipIt has it. Grepped 2026-09-17, per copy: the
    /// `ShipIt` inside one aTrust copy carries "Aborting update" but not that
    /// line (an older Squirrel), and the one inside one Ollama copy is a symlink
    /// to a binary with neither string nor `SQRLInstaller` — not Squirrel.Mac.
    /// UNVERIFIED: what either does when the app is reopened mid-install. The detector cannot tell the builds apart, so it tags them
    /// all `.shipIt`; for one without the check a reappearance can end the
    /// Relaunch wait early with a false "restarted without applying the update".
    case shipIt
    /// Sparkle 2's parked installer. Does not refuse: it watches the one instance
    /// it registered and swaps once that one exits, whatever else is running.
    case sparkle
    /// Spotify's own updater, which applies on the next launch.
    case spotify
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
            //
            // Pair comparison, not `buildIdentity`: both sides here carry a
            // marketing string AND a build, and collapsing each to one string
            // compares the builds alone. A vendor whose builds run monotonically
            // across two trains then hands a staged 1.2.0 (build 2001) over an
            // installed 1.3.0 (build 1990) and this offers Relaunch for a
            // downgrade. Marketing settles direction; the build breaks its ties,
            // which is the whole point of ``StagedSelfUpdate/versionSide``.
            if requireNewerThanInstalled {
                guard VersionComparator.isNewer(staged.versionSide, than: app.versionSide)
                else { return nil }
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

        // Compare the staged bundle against what's installed as a PAIR — same
        // reasoning as the Sparkle branch above: each side carries both strings, and
        // picking one per side compares the builds alone, which reads a trailing
        // release carrying a leading build as an update. Only a strictly newer
        // staged version counts — a leftover state file whose staged bundle equals
        // (or trails) what's on disk has already been applied.
        if requireNewerThanInstalled {
            let stagedSide = VersionSide(marketing: stagedShort, build: stagedBuild)
            guard VersionComparator.isNewer(stagedSide, than: app.versionSide) else { return nil }
        }

        return StagedSelfUpdate(
            version: stagedShort, buildVersion: stagedBuild, stagedBundlePath: staged,
            updater: .shipIt)
    }

    /// Spotify's native staged update. Spotify's own updater downloads the next
    /// build to `~/Library/Application Support/Spotify/PersistentCache/Update/`
    /// (a `spotify-autoupdate-<ver>.tbz` plus an `update.json` carrying
    /// `version_from`/`version_to`/`update_path`) — the "Spotify has been updated
    /// to version X. Please restart to install." state. We surface it as
    /// **Relaunch** rather than letting the vendor probe offer a 164MB re-download
    /// of bytes Spotify already has on disk.
    ///
    /// **It applies on the next launch, not the next quit** — unlike ShipIt.
    /// Measured 2026-09-14 on this machine's copy (1.2.98.301 staged 1.3.0.277,
    /// with the build already unpacked to `Update/temp/Spotify.app`): after a
    /// quit, disk stayed on 1.2.98.301 for the full 180 s the relaunch waited.
    /// The moment the old build was opened again it spawned `sp_relauncher`, the
    /// bundle was swapped and 1.3.0.277 was running two seconds later, with the
    /// `Update/` directory consumed. Hence `appliesOn: .launch`.
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
            // version-lint:allow-marketing-first — `versionTo` IS Spotify's
            // marketing version (its own `update.json` reports nothing else), so
            // both sides are the same namespace here and the marketing-first pick
            // is the correct one rather than the defect the lint hunts.
            guard let installedV = app.shortVersion ?? app.buildVersion,
                  VersionComparator.isNewer(versionTo, than: installedV) else { return nil }
        }

        // stagedBundlePath is informational here (the relaunch action quits and
        // reopens the app and lets Spotify perform the swap), so point it at the
        // staged .tbz.
        return StagedSelfUpdate(
            version: versionTo, buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: updatePath),
            appliesOn: .launch, updater: .spotify)
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
        guard let bundleID = app.bundleID,
              let sparkleRoot = sparkleCacheRoot(
                for: app, cachesDirectory: cachesDirectory, fileManager: fileManager)
        else { return nil }

        // Cheapest discriminator first: no parked installer, nothing to avoid.
        let parked = parkedInstallerBundleURLs ?? liveParkedSparkleInstallers()
        guard hasParkedSparkleInstaller(for: app, sparkleRoot: sparkleRoot, parked: parked)
        else { return nil }

        // Where the installer stages is the cache of the user it RUNS AS, which is
        // not always this one — see `sparkleInstallerArmedWithUnreadableStaging`.
        // This walk can only ever see a same-user install.
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
                  let short = VersionSide.plistVersionField(dict["CFBundleShortVersionString"])
            else { continue }
            return StagedSelfUpdate(
                version: short,
                buildVersion: VersionSide.plistVersionField(dict["CFBundleVersion"]),
                stagedBundlePath: url, updater: .sparkle)
        }
        return nil
    }

    /// An installer is parked on this Sparkle app's next quit, but no staged copy
    /// of it can be read from this user's cache. The row must still offer Relaunch
    /// rather than our own Update, and our install must still stand down — it is
    /// the same collision `sparkleStagedBundle` exists for, with the version unknown.
    ///
    /// **Why the staged build can be unreadable.** Sparkle's `Autoupdate` stages
    /// into `SPULocalCacheDirectory cachePathForBundleIdentifier:` + `Installation`,
    /// and that cache is `NSCachesDirectory` in the user domain of the process
    /// doing it (`AppInstaller.m`, `SPULocalCacheDirectory.m`). When the app's
    /// bundle needs administrator authorisation to replace — a root-owned bundle,
    /// as a `.pkg` install leaves it — `SUInstallerLauncher.m` submits the
    /// installer to the system domain, so it runs as root and stages under
    /// `/var/root/Library/Caches/<bundleID>/`, which this user cannot list.
    /// The launcher itself runs as this user, so its progress agent is still
    /// somewhere `hasParkedSparkleInstaller` accepts — which of its two places
    /// depends on the Sparkle version (see there) — and the parked-installer
    /// evidence is intact while the staging walk finds nothing.
    ///
    /// Observed 2026-09-13 on a mac mini, Tailscale 1.102.3 → 1.102.4 (bundle
    /// `root:wheel`, Sparkle 2.8.0): `Autoupdate` running as root, the `Updater` agent as the
    /// user under `~/Library/Caches/io.tailscale.ipn.macsys/…/Launcher/`, no
    /// `Installation/` in that cache, and the staged `Tailscale.app` found with
    /// `sudo` under `/var/root/…/Installation/`. Quitting the app — which the
    /// vendor `.pkg`'s own preinstall does — let root's `Autoupdate` swap its copy
    /// in mid-install: PackageKit logged `st_ino mismatch (possible TOCTOU swap)`
    /// for 156 files and wrote the pkg's nested bundles into Sparkle's bundle.
    ///
    /// Also true, and wanted, for a same-user install whose staging is not an
    /// `.app` (a package update) or has not finished unpacking: an installer is
    /// parked either way, and either way ours would race it. Deliberately `false`
    /// when a readable staged build exists, older or newer: that case already
    /// carries a version and belongs to `staged(for:)` / `sparkleStagedBundle`.
    public static func sparkleInstallerArmedWithUnreadableStaging(
        for app: InstalledApp,
        cachesDirectory: URL? = nil,
        parkedInstallerBundleURLs: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        // Same admission as `staged(for:)`'s Sparkle branch.
        guard !app.hasSelfUpdater, app.hasSparkleUpdater,
              app.bundleID != spotifyBundleID,
              let sparkleRoot = sparkleCacheRoot(
                for: app, cachesDirectory: cachesDirectory, fileManager: fileManager)
        else { return false }
        let parked = parkedInstallerBundleURLs ?? liveParkedSparkleInstallers()
        guard hasParkedSparkleInstaller(for: app, sparkleRoot: sparkleRoot, parked: parked)
        else { return false }
        return sparkleStagedBundle(
            for: app, cachesDirectory: cachesDirectory,
            parkedInstallerBundleURLs: parked, fileManager: fileManager) == nil
    }

    /// `<Caches>/<bundleID>/org.sparkle-project.Sparkle`, in this user's domain.
    private static func sparkleCacheRoot(
        for app: InstalledApp, cachesDirectory: URL?, fileManager: FileManager
    ) -> URL? {
        guard let bundleID = app.bundleID,
              let caches = cachesDirectory
                ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true)
    }

    /// Whether one of `parked` is waiting on THIS app's quit.
    ///
    /// Two locations, because where Sparkle runs its progress agent from has
    /// changed across releases (`InstallerLauncher/SUInstallerLauncher.m`, read at
    /// each tag on 2026-09-13):
    ///
    ///   - **≤ 2.9.5**: always copied into `<Caches>/<bundleID>/…/Launcher/<random>/`,
    ///     including for an install needing administrator authorisation (whose
    ///     INSTALLER then runs as root). Observed on Tailscale's Sparkle 2.8.0.
    ///   - **2.9.6**: `BOOL copyProgressTool = !rootUser`, `rootUser` being the
    ///     LAUNCHER's own euid — copied as above unless the launcher is already
    ///     root, in which case it runs out of the host bundle's framework.
    ///   - **2.10.0-beta.1 on**: no copy; the agent runs out of the host bundle's
    ///     `Sparkle.framework` every time.
    ///
    /// So the in-bundle location is the only one from 2.10 on, not a rare case.
    /// Both are accepted, and must be: this gate fails OPEN — no parked installer
    /// found means `.proceed` — so a location we cannot see is not a missing
    /// warning, it is the overwrite bug back again.
    private static func hasParkedSparkleInstaller(
        for app: InstalledApp, sparkleRoot: URL, parked: [URL]
    ) -> Bool {
        let homes = [sparkleRoot, app.path].map { normalizedPath($0) + "/" }
        return parked.contains(where: { installer in
            let path = normalizedPath(installer)
            return homes.contains(where: path.hasPrefix)
        })
    }

    /// The bundle identities a parked Sparkle installer can run under. Its own
    /// bundle *location* is what ties it to an app; these are how it is found at
    /// all.
    ///
    /// `…Updater` is Sparkle 2's progress agent — observed live as pid 27939 at
    /// `…/Caches/com.tinyapp.TablePlus/org.sparkle-project.Sparkle/Launcher/<random>/Updater.app`.
    /// Sparkle 2's own `Autoupdate` ships alongside it as a bare executable with
    /// no bundle (same TablePlus install), so it has no identifier to query.
    ///
    /// Sparkle 1's `Autoupdate.app` — a real bundle, `CFBundleIdentifier =
    /// org.sparkle-project.Sparkle.Autoupdate` (VLC 1.16.0, Eudic 1.27.3) — is
    /// deliberately absent from this list. Not because it is unenumerable: it is
    /// because in the automatic-update path the host process arms the quit hook
    /// itself, and `Autoupdate.app` is only launched from `applicationWillTerminate:`
    /// — after the decision `RestartStandoff` makes has already been acted on, so
    /// it never exists yet when this list would be queried. Querying its bundle
    /// id here could never make the detector answer non-nil and misleadingly made
    /// this list look like coverage. See `RestartStandoff`'s known limitation.
    static let sparkleInstallerBundleIDs = [
        "org.sparkle-project.Sparkle.Updater",
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
