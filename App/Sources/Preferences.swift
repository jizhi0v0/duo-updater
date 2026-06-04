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
        case hourly
        case every6Hours
        case daily

        var id: String { rawValue }

        var label: String {
            switch self {
            case .manual:      return "Only when I check"
            case .hourly:      return "Every hour"
            case .every6Hours: return "Every 6 hours"
            case .daily:       return "Once a day"
            }
        }

        /// Seconds between automatic checks, or nil for manual (no timer).
        var interval: TimeInterval? {
            switch self {
            case .manual:      return nil
            case .hourly:      return 3600
            case .every6Hours: return 6 * 3600
            case .daily:       return 24 * 3600
            }
        }
    }

    /// How Mac App Store updates are applied.
    ///
    /// Both routes drive the store's own `storedownloadd`, so neither mixes
    /// channels — they differ in dependency and bandwidth, hence a user choice:
    ///   • `.full` — the `mas` CLI replays the store purchase and redownloads the
    ///     whole app. No extra permission, but needs `mas` (brew) and more traffic.
    ///   • `.incremental` — drives App Store.app's own Update button via the
    ///     Accessibility API, so the store fetches a delta. No `mas` needed and less
    ///     traffic, but requires an Accessibility grant (guided via PermissionFlow).
    /// Default is `.full`: it asks for no sensitive permission up front.
    enum AppStoreUpdateStrategy: String, CaseIterable, Identifiable, Sendable {
        case full
        case incremental

        var id: String { rawValue }

        var label: String {
            switch self {
            case .full:        return "Full download (no extra permission)"
            case .incremental: return "Incremental (needs Accessibility)"
            }
        }
    }

    /// How to apply an update for a self-updating "vendor" app — the official-
    /// website / self-baked-updater apps surfaced by `VendorProbeSource` (Office,
    /// Teams, OneDrive, Edge, Chrome, VS Code, Tailscale, …). These all ship their
    /// own updater (MAU, Keystone, a daemon, Sparkle), so we're only ever a
    /// fallback — and how aggressively we step in is a user choice:
    ///   • `.deferWhenRunning` — respect the app's own updater. If it isn't running
    ///     we download and install over it in place (no live process to disturb);
    ///     if it IS running we don't swap the bundle under it — we open its own
    ///     update path instead (a deep link like Chrome's `chrome://settings/help`
    ///     when the recipe has one, otherwise just bring the app forward so its
    ///     built-in updater takes over).
    ///   • `.alwaysOverwrite` — always download and replace in place regardless of
    ///     whether it's running, then surface a Restart/Relaunch prompt.
    /// Default `.deferWhenRunning`: never fight a running app's own updater.
    enum VendorInstallPolicy: String, CaseIterable, Identifiable, Sendable {
        case deferWhenRunning
        case alwaysOverwrite

        var id: String { rawValue }

        var label: String {
            switch self {
            case .deferWhenRunning: return "Defer to the app’s own updater while it’s running"
            case .alwaysOverwrite:  return "Always download & replace, then restart"
            }
        }
    }

    private enum Key {
        static let githubToken = "GitHubToken"   // pre-existing key; keep it
        static let githubTokenAccount = "GitHubTokenAccount"   // login the token verified as
        static let checkFrequency = "CheckFrequency"
        static let launchAtLogin = "LaunchAtLogin"
        static let maxConcurrency = "MaxConcurrency"
        static let keepBackups = "KeepBackups"
        static let notifyOnUpdates = "NotifyOnUpdates"
        static let appStoreUpdateStrategy = "AppStoreUpdateStrategy"
        static let vendorInstallPolicy = "VendorInstallPolicy"
        static let ignoredKeys = "IgnoredApps"
        static let skippedVersions = "SkippedVersions"
        static let lastCheckDate = "LastCheckDate"
        static let notifiedVersions = "NotifiedVersions"
        static let notificationBaselineSeeded = "NotificationBaselineSeeded"
    }

    private let defaults: UserDefaults

    // MARK: - Stored settings

    /// A GitHub API token the user pasted in. Empty means "fall back to env /
    /// `gh` CLI" — `GitHubToken.resolve` treats empty as no explicit value.
    var githubToken: String {
        didSet { defaults.set(githubToken, forKey: Key.githubToken) }
    }

    /// The GitHub login the saved token last verified as, for display in
    /// Settings. Empty when the token wasn't pasted-and-verified here (e.g. it
    /// came from env / `gh` CLI, or predates verification).
    var githubTokenAccount: String {
        didSet { defaults.set(githubTokenAccount, forKey: Key.githubTokenAccount) }
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

    /// Post a notification when a background check finds updates.
    var notifyOnUpdates: Bool {
        didSet { defaults.set(notifyOnUpdates, forKey: Key.notifyOnUpdates) }
    }

    /// Which route to use for Mac App Store updates. See `AppStoreUpdateStrategy`.
    var appStoreUpdateStrategy: AppStoreUpdateStrategy {
        didSet { defaults.set(appStoreUpdateStrategy.rawValue, forKey: Key.appStoreUpdateStrategy) }
    }

    /// How to apply self-updating vendor-app updates. See `VendorInstallPolicy`.
    var vendorInstallPolicy: VendorInstallPolicy {
        didSet { defaults.set(vendorInstallPolicy.rawValue, forKey: Key.vendorInstallPolicy) }
    }

    /// Apps the user has chosen to hide from update checks entirely, keyed by
    /// `key(for:)`.
    private(set) var ignoredKeys: Set<String> {
        didSet { defaults.set(Array(ignoredKeys), forKey: Key.ignoredKeys) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.githubToken = defaults.string(forKey: Key.githubToken) ?? ""
        self.githubTokenAccount = defaults.string(forKey: Key.githubTokenAccount) ?? ""
        self.checkFrequency = CheckFrequency(
            rawValue: defaults.string(forKey: Key.checkFrequency) ?? "") ?? .every6Hours
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let storedConcurrency = defaults.integer(forKey: Key.maxConcurrency)
        self.maxConcurrency = storedConcurrency == 0 ? 12 : min(32, max(1, storedConcurrency))
        // Default ON for these two — both are opt-out conveniences.
        self.keepBackups = defaults.object(forKey: Key.keepBackups) as? Bool ?? true
        self.notifyOnUpdates = defaults.object(forKey: Key.notifyOnUpdates) as? Bool ?? true
        self.appStoreUpdateStrategy = AppStoreUpdateStrategy(
            rawValue: defaults.string(forKey: Key.appStoreUpdateStrategy) ?? "") ?? .full
        self.vendorInstallPolicy = VendorInstallPolicy(
            rawValue: defaults.string(forKey: Key.vendorInstallPolicy) ?? "") ?? .deferWhenRunning
        self.ignoredKeys = Set(defaults.stringArray(forKey: Key.ignoredKeys) ?? [])
        self.skippedVersions = defaults.dictionary(forKey: Key.skippedVersions) as? [String: String] ?? [:]
        self.lastCheckDate = defaults.object(forKey: Key.lastCheckDate) as? Date
        self.notifiedVersions = defaults.dictionary(forKey: Key.notifiedVersions) as? [String: String] ?? [:]
        self.notificationBaselineSeeded = defaults.bool(forKey: Key.notificationBaselineSeeded)
    }

    // MARK: - Per-app keys

    /// A stable identity for an app's preferences. Delegates to `BackupStore.key`
    /// so an ignore/skip and a backup resolve to the *same* string for the same
    /// app — prefer the bundle id (survives the app moving on disk), fall back to
    /// the sanitised path when there's none.
    func key(for app: InstalledApp) -> String {
        BackupStore.key(bundleID: app.bundleID, path: app.path)
    }

    // MARK: - Ignore

    func isIgnored(_ app: InstalledApp) -> Bool {
        ignoredKeys.contains(key(for: app))
    }

    func setIgnored(_ ignored: Bool, _ app: InstalledApp) {
        let k = key(for: app)
        if ignored { ignoredKeys.insert(k) } else { ignoredKeys.remove(k) }
    }

    // MARK: - Skip version

    func isVersionSkipped(_ app: InstalledApp, version: String?) -> Bool {
        guard let version, let skipped = skippedVersions[key(for: app)] else { return false }
        return skipped == version
    }

    func skipVersion(_ version: String, _ app: InstalledApp) {
        skippedVersions[key(for: app)] = version
    }

    func clearSkip(_ app: InstalledApp) {
        skippedVersions[key(for: app)] = nil
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
