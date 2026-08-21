import Foundation
import Observation
import ServiceManagement
import DuoUpdaterCore

/// User-tunable settings, persisted in `UserDefaults` and observed by the UI.
///
/// A single shared instance is the source of truth: `AppListModel` reads it on
/// every refresh (token, concurrency, ignore list) and the Settings window binds
/// to it directly. Stored properties persist themselves through `didSet`, so a
/// change made anywhere is durable immediately — no explicit save step.
@MainActor
@Observable
final class Preferences {

    static let shared = Preferences()

    /// How often the app checks for updates on its own, in the background.
    enum CheckFrequency: String, CaseIterable, Identifiable, Sendable {
        case manual
        case every5Min
        case every30Min
        case hourly
        case every6Hours
        case daily

        var id: String { rawValue }

        var label: String {
            switch self {
            case .manual:      return "Only when I check"
            case .every5Min:   return "Every 5 minutes"
            case .every30Min:  return "Every 30 minutes"
            case .hourly:      return "Every hour"
            case .every6Hours: return "Every 6 hours"
            case .daily:       return "Once a day"
            }
        }

        /// Seconds between automatic checks, or nil for manual (no timer).
        var interval: TimeInterval? {
            switch self {
            case .manual:      return nil
            case .every5Min:   return 5 * 60
            case .every30Min:  return 30 * 60
            case .hourly:      return 3600
            case .every6Hours: return 6 * 3600
            case .daily:       return 24 * 3600
            }
        }

        /// True only for the 5-minute cadence, where the unauthenticated GitHub
        /// rate limit (60 req/hour/IP) can actually bite: each GitHub-mapped app
        /// costs one request per cycle, so 12 cycles/hour caps out at ~5 GitHub
        /// apps before 403s. Every 30 min is just 2 cycles/hour (~30 apps before
        /// the cap — safe for any realistic library), and hourly/slower safer
        /// still, so only the 5-min cadence warrants the "configure a token" nudge.
        var isHighFrequency: Bool {
            guard let interval else { return false }
            return interval < 30 * 60
        }
    }

    /// Re-exported so existing `Preferences.AppStoreUpdateStrategy` /
    /// `Preferences.VendorInstallPolicy` references keep resolving — the
    /// definitions moved to DuoUpdaterCore so the CLI shares the same types.
    typealias AppStoreUpdateStrategy = DuoUpdaterCore.AppStoreUpdateStrategy
    typealias VendorInstallPolicy = DuoUpdaterCore.VendorInstallPolicy

    private enum Key {
        static let githubToken = "GitHubToken"   // legacy plaintext key — migration-only (read once, then removed; token now lives in the Keychain)
        static let githubTokenAccount = "GitHubTokenAccount"   // login the token verified as
        static let checkFrequency = "CheckFrequency"
        static let launchAtLogin = "LaunchAtLogin"
        static let maxConcurrency = "MaxConcurrency"
        static let keepBackups = "KeepBackups"
        static let pruneOrphanBackups = "PruneOrphanBackups"
        static let notifyOnUpdates = "NotifyOnUpdates"
        static let autoRestartAfterUpdate = "AutoRestartAfterUpdate"
        static let hideDockIcon = "HideDockIcon"
        static let appStoreUpdateStrategy = UpdateSettings.appStoreUpdateStrategyKey
        static let vendorInstallPolicy = UpdateSettings.vendorInstallPolicyKey
        static let customScanPaths = "CustomScanPaths"
        static let ignoredKeys = UpdateSettings.ignoredKeysKey
        static let declinedElevationKeys = UpdateSettings.declinedElevationKeysKey
        static let skippedVersions = UpdateSettings.skippedVersionsKey
        static let lastCheckDate = "LastCheckDate"
        static let notifiedVersions = "NotifiedVersions"
        static let notificationBaselineSeeded = "NotificationBaselineSeeded"
        static let marketingByBuild = "MarketingVersionByBuild"
        static let stagedPackages = "StagedPackages"
    }

    private let defaults: UserDefaults
    /// Held for its lifetime: KVO registrations are torn down when this is
    /// released, and a released observer that is still registered crashes.
    private var externalObserver: DefaultsKeyObserver?

    // MARK: - Stored settings

    /// Keychain account under which the GitHub token is stored. The token is a live
    /// credential, so it lives in the Keychain — never in the plaintext defaults plist.
    static let githubTokenKeychainAccount = "github-token"

    /// Keychain accounts for Alcove's licensed-update credentials. Alcove pushes new
    /// builds to its licensed API channel before any public mirror, so the only
    /// authoritative version surface needs the user's permanent license key plus this
    /// machine's activation instance id (see `AlcoveUpdateSource`). Both are live
    /// secrets → Keychain, not the plaintext plist. Seeded once; absent → the public
    /// vendor probe still answers.
    static let alcoveLicenseKeyKeychainAccount = "alcove-license-key"
    static let alcoveInstanceIDKeychainAccount = "alcove-instance-id"

    /// A GitHub API token the user pasted in. Empty means "fall back to env /
    /// `gh` CLI" — `GitHubToken.resolve` treats empty as no explicit value. Persisted
    /// to the Keychain (an empty value clears it).
    var githubToken: String {
        didSet { Keychain.set(githubToken, account: Self.githubTokenKeychainAccount) }
    }

    /// The GitHub login the saved token last verified as, for display in
    /// Settings. Empty when the token wasn't pasted-and-verified here (e.g. it
    /// came from env / `gh` CLI, or predates verification).
    var githubTokenAccount: String {
        didSet { defaults.set(githubTokenAccount, forKey: Key.githubTokenAccount) }
    }

    /// The user's Alcove license key. Empty = not configured (Alcove then falls
    /// back to the public, lagging vendor probe). A live credential → Keychain,
    /// never the plist. See `AlcoveUpdateSource` / `AlcoveLicenseService`.
    var alcoveLicenseKey: String {
        didSet { Keychain.set(alcoveLicenseKey, account: Self.alcoveLicenseKeyKeychainAccount) }
    }

    /// This machine's Alcove activation instance id (resolved from the license key,
    /// or pasted manually for at-limit licenses). Keychain-backed like the key.
    var alcoveInstanceID: String {
        didSet { Keychain.set(alcoveInstanceID, account: Self.alcoveInstanceIDKeychainAccount) }
    }

    var checkFrequency: CheckFrequency {
        didSet { defaults.set(checkFrequency.rawValue, forKey: Key.checkFrequency) }
    }

    /// Start DuoUpdater at login. Backed by `SMAppService`; the stored bool is
    /// just our remembered intent (the system is the real source of truth).
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    /// How many apps to check concurrently. The Settings stepper is bounded to
    /// 1...32 and `init` clamps any stored value, so we just persist here (and
    /// `UpdateChecker` floors it at 1 regardless) — no re-entrant clamp.
    var maxConcurrency: Int {
        didSet { defaults.set(maxConcurrency, forKey: Key.maxConcurrency) }
    }

    /// Keep a one-deep backup of each app before an in-place update so it can be
    /// rolled back.
    var keepBackups: Bool {
        didSet { defaults.set(keepBackups, forKey: Key.keepBackups) }
    }

    /// Automatically delete a backup once its app is no longer installed at the
    /// path it was taken from — retention per app is already one, so orphans
    /// left behind by an uninstall or move are the only unbounded growth.
    var pruneOrphanBackups: Bool {
        didSet { defaults.set(pruneOrphanBackups, forKey: Key.pruneOrphanBackups) }
    }

    /// Post a notification when a background check finds updates.
    var notifyOnUpdates: Bool {
        didSet { defaults.set(notifyOnUpdates, forKey: Key.notifyOnUpdates) }
    }

    /// After an in-place install of a *running* app, automatically quit and
    /// relaunch it so the new version takes effect — instead of leaving a "Restart"
    /// badge for a second click. Uses the same graceful quit as the manual button
    /// (honors save prompts; a refused/blocked quit just leaves the badge), so it
    /// never force-kills or loses unsaved work. Default ON — an opt-out convenience.
    var autoRestartAfterUpdate: Bool {
        didSet { defaults.set(autoRestartAfterUpdate, forKey: Key.autoRestartAfterUpdate) }
    }

    /// Run without a Dock icon — menu bar only. **On by default**: this is a
    /// menu-bar app, and the popover is how it is actually driven, so the Dock
    /// slot is mostly noise. Turning it off brings back the Dock tile — and with
    /// it the pending-update badge, which needs a tile to sit on. Applied
    /// immediately so the Dock reacts to the toggle, not to the next launch.
    var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: Key.hideDockIcon)
            DockIcon.apply(hidden: hideDockIcon)
        }
    }

    /// Which route to use for Mac App Store updates. See `AppStoreUpdateStrategy`.
    var appStoreUpdateStrategy: AppStoreUpdateStrategy {
        didSet { defaults.set(appStoreUpdateStrategy.rawValue, forKey: Key.appStoreUpdateStrategy) }
    }

    /// How to apply self-updating vendor-app updates. See `VendorInstallPolicy`.
    var vendorInstallPolicy: VendorInstallPolicy {
        didSet { defaults.set(vendorInstallPolicy.rawValue, forKey: Key.vendorInstallPolicy) }
    }

    /// Extra folders the user added to the scan, beyond the built-in roots
    /// (`AppScanner.defaultLocations`). Apps installed outside the standard
    /// locations — a developer build folder, a tool dir — aren't found otherwise.
    /// Stored as standardized absolute directory paths; the scan appends them via
    /// `AppScanner(extraLocations:)`. Mutated only through `addScanPath`/
    /// `removeScanPath`, which normalize and dedupe.
    private(set) var customScanPaths: [String] {
        didSet { defaults.set(customScanPaths, forKey: Key.customScanPaths) }
    }

    /// Apps the user has chosen to hide from update checks entirely, keyed by
    /// `key(for:)`.
    private(set) var ignoredKeys: Set<String> {
        didSet { defaults.set(Array(ignoredKeys), forKey: Key.ignoredKeys) }
    }

    /// Installs whose administrator prompt the user dismissed, keyed by
    /// `key(for:)`. Persisted so one refusal isn't re-asked on every release; see
    /// `ElevationRules` for why it is a sticky flag rather than a per-version one.
    private(set) var declinedElevationKeys: Set<String> {
        didSet { defaults.set(Array(declinedElevationKeys), forKey: Key.declinedElevationKeys) }
    }

    /// Per-app version the user chose to skip (key → the version string they were
    /// offered and declined). A newer version than the skipped one still surfaces.
    private(set) var skippedVersions: [String: String] {
        didSet { defaults.set(skippedVersions, forKey: Key.skippedVersions) }
    }

    /// When the last full networked check completed. Persisted so the background
    /// scheduler survives relaunches — it schedules the next check relative to this
    /// rather than restarting the interval from zero on every launch.
    var lastCheckDate: Date? {
        didSet { defaults.set(lastCheckDate, forKey: Key.lastCheckDate) }
    }

    /// Per-app version we've already posted a "new update available" notification
    /// for (key → the offered version). Persisted so the banner fires regardless
    /// of *which* refresh path first surfaces the update — manual menu-open or
    /// scheduled background — instead of the in-memory list silently becoming the
    /// baseline; and so the same version isn't re-announced across relaunches.
    private(set) var notifiedVersions: [String: String] {
        didSet { defaults.set(notifiedVersions, forKey: Key.notifiedVersions) }
    }

    /// Whether we've recorded an initial notification baseline yet. The first run
    /// adopts whatever's already pending *silently* — notifications are for updates
    /// that appear *after* the user first sees today's list, not a launch-time dump
    /// of everything already outstanding.
    var notificationBaselineSeeded: Bool {
        didSet { defaults.set(notificationBaselineSeeded, forKey: Key.notificationBaselineSeeded) }
    }

    /// Overwrite the notified-version baseline (the model recomputes the whole map
    /// each check, keyed by `key(for:)`).
    func setNotifiedVersions(_ versions: [String: String]) {
        notifiedVersions = versions
    }

    /// Records the marketing version each on-disk *build* was last seen with, keyed
    /// by `"<resolved path>\n<CFBundleVersion>"`. `lsappinfo` preserves a running
    /// process's build but never its marketing version, so after an app self-updates
    /// on disk the still-running old build would otherwise show as a bare build number
    /// in the restart line ("20260622.183424 → 1.9.0 (…)"). Looking the running build
    /// up here recovers its marketing version ("1.8.x (20260622.183424)") so both
    /// sides of the arrow read in the same namespace. The model rewrites the whole map
    /// each scan (pruned to currently-installed builds), so it never grows unbounded.
    private(set) var marketingByBuild: [String: String] {
        didSet { defaults.set(marketingByBuild, forKey: Key.marketingByBuild) }
    }

    /// Compose the `marketingByBuild` key from an install's resolved path and build.
    static func marketingByBuildKey(path: String, build: String) -> String {
        "\(path)\n\(build)"
    }

    /// Overwrite the build→marketing history (the model recomputes it each scan).
    func setMarketingByBuild(_ map: [String: String]) {
        marketingByBuild = map
    }

    /// Installer packages we downloaded and handed to the system installer, keyed by
    /// the install's resolved path (per-install, not bundle id — see the ignore/skip
    /// keys for why). Each value records the version the package installs and where
    /// it sits on disk.
    ///
    /// Persisted rather than kept in memory so the offer survives a DuoUpdater
    /// relaunch: `PackageInstaller` keeps its work directories for a day, and these
    /// packages run to hundreds of megabytes — forgetting about one on relaunch means
    /// downloading it all over again. Entries are pruned by the model whenever the
    /// file is gone or the version on offer has moved on.
    private(set) var stagedPackages: [String: [String: String]] {
        didSet { defaults.set(stagedPackages, forKey: Key.stagedPackages) }
    }

    static let stagedPackageVersionField = "version"
    static let stagedPackagePathField = "path"
    /// When the package was handed to macOS's installer, as an epoch-seconds string.
    /// Drives the launch-time staleness check that decides whether a landed pkg
    /// leaves a running copy needing a restart (see `PackageRestartState`). Absent on
    /// entries persisted before this field existed — treated as the distant past, so
    /// a running copy that launched at any plausible time counts as already fresh
    /// (no false restart prompt on upgrade).
    static let stagedPackageStagedAtField = "stagedAt"

    /// Overwrite the staged-package map (the model recomputes it each rescan).
    func setStagedPackages(_ map: [String: [String: String]]) {
        stagedPackages = map
    }

    /// Read the GitHub token, migrating a pre-existing plaintext copy out of
    /// UserDefaults into the Keychain on the first launch after this upgrade (then
    /// scrubbing the plist so the secret no longer sits there in the clear).
    private static func loadGitHubToken(defaults: UserDefaults) -> String {
        if let legacy = defaults.string(forKey: Key.githubToken), !legacy.isEmpty {
            Keychain.set(legacy, account: githubTokenKeychainAccount)
            defaults.removeObject(forKey: Key.githubToken)
            return legacy
        }
        return Keychain.string(account: githubTokenKeychainAccount) ?? ""
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.githubToken = Self.loadGitHubToken(defaults: defaults)
        self.githubTokenAccount = defaults.string(forKey: Key.githubTokenAccount) ?? ""
        self.alcoveLicenseKey = Keychain.string(account: Self.alcoveLicenseKeyKeychainAccount) ?? ""
        self.alcoveInstanceID = Keychain.string(account: Self.alcoveInstanceIDKeychainAccount) ?? ""
        self.checkFrequency = CheckFrequency(
            rawValue: defaults.string(forKey: Key.checkFrequency) ?? "") ?? .every6Hours
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let storedConcurrency = defaults.integer(forKey: Key.maxConcurrency)
        self.maxConcurrency = storedConcurrency == 0 ? 12 : min(32, max(1, storedConcurrency))
        // Default ON for these — all opt-out conveniences.
        self.keepBackups = defaults.object(forKey: Key.keepBackups) as? Bool ?? true
        self.pruneOrphanBackups = defaults.object(forKey: Key.pruneOrphanBackups) as? Bool ?? true
        self.notifyOnUpdates = defaults.object(forKey: Key.notifyOnUpdates) as? Bool ?? true
        self.autoRestartAfterUpdate = defaults.object(forKey: Key.autoRestartAfterUpdate) as? Bool ?? true
        self.hideDockIcon = defaults.object(forKey: Key.hideDockIcon) as? Bool ?? true
        let storedAppStoreStrategy = AppStoreUpdateStrategy(
            rawValue: defaults.string(forKey: Key.appStoreUpdateStrategy) ?? "") ?? .full
        self.appStoreUpdateStrategy = storedAppStoreStrategy == .incremental ? .full : storedAppStoreStrategy
        if storedAppStoreStrategy == .incremental {
            defaults.set(AppStoreUpdateStrategy.full.rawValue, forKey: Key.appStoreUpdateStrategy)
        }
        self.vendorInstallPolicy = VendorInstallPolicy(
            rawValue: defaults.string(forKey: Key.vendorInstallPolicy) ?? "") ?? UpdateSettings.vendorInstallPolicyDefault
        self.customScanPaths = defaults.stringArray(forKey: Key.customScanPaths) ?? []
        self.ignoredKeys = Set(defaults.stringArray(forKey: Key.ignoredKeys) ?? [])
        self.declinedElevationKeys = Set(defaults.stringArray(forKey: Key.declinedElevationKeys) ?? [])
        self.skippedVersions = defaults.dictionary(forKey: Key.skippedVersions) as? [String: String] ?? [:]
        self.lastCheckDate = defaults.object(forKey: Key.lastCheckDate) as? Date
        self.notifiedVersions = defaults.dictionary(forKey: Key.notifiedVersions) as? [String: String] ?? [:]
        self.notificationBaselineSeeded = defaults.bool(forKey: Key.notificationBaselineSeeded)
        self.marketingByBuild = defaults.dictionary(forKey: Key.marketingByBuild) as? [String: String] ?? [:]
        self.stagedPackages =
            defaults.dictionary(forKey: Key.stagedPackages) as? [String: [String: String]] ?? [:]
        observeExternalWrites()
    }

    // MARK: - Cross-process changes

    /// Re-read the ignore and skip lists when **another process** changes them —
    /// today that means `duo ignore` / `duo skip`.
    ///
    /// Necessary because this class caches both in memory and writes the cache
    /// back on `didSet`. Without this, the app's next toggle would persist its
    /// stale copy straight over whatever the CLI wrote, and the CLI would look
    /// like it had silently done nothing.
    ///
    /// KVO rather than `didChangeNotification`: that notification is explicitly
    /// documented as *not* posted for changes made outside the current process,
    /// while KVO on a defaults key is documented to fire "regardless of whether
    /// changes are made within or outside the current process". Developer-forum
    /// reports say the cross-process half does not work; measured on macOS 27.0
    /// (26A5388g) it does — a `defaults write` from another process fires the
    /// observer here. Recorded because the two disagree and the observation is
    /// what this depends on.
    private func observeExternalWrites() {
        externalObserver = DefaultsKeyObserver(
            defaults: defaults, keys: [Key.ignoredKeys, Key.skippedVersions]
        ) { [weak self] in
            // Already hopped to the main actor by the observer.
            MainActor.assumeIsolated { self?.reloadVisibilityLists() }
        }
    }

    /// Pull the two lists back off disk. Assignment goes through `didSet`, which
    /// writes the identical value back — harmless, and cheaper than a second code
    /// path — but only when something actually changed, so this cannot ping-pong
    /// with the observer that triggered it.
    private func reloadVisibilityLists() {
        let freshIgnored = Set(defaults.stringArray(forKey: Key.ignoredKeys) ?? [])
        if freshIgnored != ignoredKeys {
            ignoredKeys = freshIgnored
            Log.app.info("prefs: ignore list changed externally — \(freshIgnored.count, privacy: .public) entries")
        }
        let freshSkipped =
            defaults.dictionary(forKey: Key.skippedVersions) as? [String: String] ?? [:]
        if freshSkipped != skippedVersions {
            skippedVersions = freshSkipped
            Log.app.info("prefs: skip list changed externally — \(freshSkipped.count, privacy: .public) entries")
        }
    }

    // MARK: - Per-app keys

    /// A stable per-install identity for an app's preferences (ignore, skip,
    /// notification baseline). Keys on the on-disk path — exactly like
    /// `InstalledApp.id`, and deliberately NOT the bundle id: several installed
    /// apps can legitimately share one (the JetBrains-Toolbox Android Studio
    /// channels, Thunderbird stable/esr, …), and a bundle-id key collapses them
    /// so ignoring/skipping one applied to every copy. Kept separate from
    /// `BackupStore.key`: rollback storage has its own compatibility and
    /// collision-avoidance rules, while preferences must preserve old ignore/skip
    /// identities exactly.
    func key(for app: InstalledApp) -> String {
        InstallPreferenceKey.key(for: app)
    }

    /// The previous bundle-id-preferred identity. Entries written before the
    /// switch to per-path keys live under this; we still honour them on read so
    /// an existing ignore/skip never silently resurfaces, and migrate them to the
    /// new key the next time the app is toggled.
    func legacyKey(for app: InstalledApp) -> String {
        InstallPreferenceKey.legacyKey(for: app)
    }

    // MARK: - Custom scan folders

    /// The custom scan folders as URLs, for `AppScanner(extraLocations:)`.
    var customScanLocations: [URL] {
        customScanPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Add a folder to the scan. A picked `.app` resolves to its *parent* folder
    /// (the scan looks for `.app` entries inside a location, never at one). The
    /// path is standardized, then dropped if it's empty, already a built-in root,
    /// or already added. Returns whether it was actually added (so the UI can flag
    /// a no-op duplicate).
    @discardableResult
    func addScanPath(_ url: URL) -> Bool {
        let dir = url.pathExtension == "app" ? url.deletingLastPathComponent() : url
        let path = dir.standardizedFileURL.path
        guard !path.isEmpty, path != "/" else { return false }
        let builtIn = Set(AppScanner.defaultLocations.map { $0.standardizedFileURL.path })
        guard !builtIn.contains(path), !customScanPaths.contains(path) else { return false }
        customScanPaths.append(path)
        return true
    }

    func removeScanPath(_ path: String) {
        customScanPaths.removeAll { $0 == path }
    }

    // MARK: - Ignore

    func isIgnored(_ app: InstalledApp) -> Bool {
        VisibilityRules.isIgnored(app, ignoredKeys: ignoredKeys)
    }

    /// Whether a refresh should spend a request on this app. See
    /// `VisibilityRules.deservesCheck` for why a skipped version still is one.
    func deservesCheck(_ app: InstalledApp) -> Bool {
        VisibilityRules.deservesCheck(app, ignoredKeys: ignoredKeys)
    }

    func setIgnored(_ ignored: Bool, _ app: InstalledApp) {
        if ignored {
            ignoredKeys.insert(key(for: app))
        } else {
            // Drop both forms so unignoring clears any legacy (possibly shared) entry too.
            ignoredKeys.remove(key(for: app))
            ignoredKeys.remove(legacyKey(for: app))
        }
    }

    // MARK: - Declined administrator prompts

    func isElevationDeclined(_ app: InstalledApp) -> Bool {
        ElevationRules.isDeclined(app, declinedKeys: declinedElevationKeys)
    }

    func setElevationDeclined(_ declined: Bool, _ app: InstalledApp) {
        if declined {
            declinedElevationKeys.insert(key(for: app))
        } else {
            // Drop both forms, exactly as un-ignoring does: a legacy bundle-id
            // entry left behind would keep the row demoted to "Open" with no way
            // left in the UI to clear it.
            declinedElevationKeys.remove(key(for: app))
            declinedElevationKeys.remove(legacyKey(for: app))
        }
    }

    // MARK: - Skip version

    func isVersionSkipped(_ app: InstalledApp, version: String?) -> Bool {
        VisibilityRules.isVersionSkipped(app, version: version, skippedVersions: skippedVersions)
    }

    func skipVersion(_ version: String, _ app: InstalledApp) {
        skippedVersions[key(for: app)] = version
    }

    func clearSkip(_ app: InstalledApp) {
        skippedVersions[key(for: app)] = nil
        skippedVersions[legacyKey(for: app)] = nil
    }

    /// Key-based removals for the Settings list, where we only have the stored key
    /// (the app may not be in the current scan).
    func removeIgnored(key: String) { ignoredKeys.remove(key) }
    func clearSkip(key: String) { skippedVersions[key] = nil }

    // MARK: - Launch at login

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Non-fatal: an ad-hoc-signed dev build can't always register a login
            // item. Keep the remembered intent; the system simply won't honor it.
            Log.app.error("launch-at-login \(self.launchAtLogin ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
