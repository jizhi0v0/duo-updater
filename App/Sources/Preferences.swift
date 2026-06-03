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

    private enum Key {
        static let githubToken = "GitHubToken"   // pre-existing key; keep it
        static let githubTokenAccount = "GitHubTokenAccount"   // login the token verified as
        static let checkFrequency = "CheckFrequency"
        static let launchAtLogin = "LaunchAtLogin"
        static let maxConcurrency = "MaxConcurrency"
        static let keepBackups = "KeepBackups"
        static let notifyOnUpdates = "NotifyOnUpdates"
        static let ignoredKeys = "IgnoredApps"
        static let skippedVersions = "SkippedVersions"
        static let lastCheckDate = "LastCheckDate"
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
        self.ignoredKeys = Set(defaults.stringArray(forKey: Key.ignoredKeys) ?? [])
        self.skippedVersions = defaults.dictionary(forKey: Key.skippedVersions) as? [String: String] ?? [:]
        self.lastCheckDate = defaults.object(forKey: Key.lastCheckDate) as? Date
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
