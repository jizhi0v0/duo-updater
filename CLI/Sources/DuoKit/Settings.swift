import Foundation
import DuoUpdaterCore

/// A read-only view of the settings the menu-bar app persists, so `duo` reaches
/// the same verdict for the same app.
///
/// Deliberately read-only. `Preferences` in the app keeps an in-memory copy and
/// writes it back on `didSet`, so a value the CLI writes is overwritten the next
/// time the app touches anything — a CLI that appeared to work and silently
/// didn't. Writes (`duo ignore`, `duo skip`) need a change-notification
/// handshake with the app and are deliberately not here yet.
///
/// Key *names* are duplicated from `Preferences.Key` for everything except the
/// two the policy consults, which are shared through `UpdateSettings`. That is
/// the drift risk worth accepting: a wrong name here shows up as a setting the
/// CLI appears to ignore, whereas a wrong policy key would silently change what
/// gets installed.
public struct Settings: Sendable {

    /// The suite the app writes. Passed explicitly because a CLI's own
    /// `UserDefaults.standard` is keyed to its bundle id (or nothing at all when
    /// it has no bundle), and would read an empty universe without complaint.
    public static let suiteName = "com.duoupdater.app"

    public var updateSettings: UpdateSettings
    public var ignoredKeys: Set<String>
    /// App preference key → the version the user chose to skip.
    public var skippedVersions: [String: String]
    public var customScanPaths: [String]
    public var maxConcurrency: Int
    /// Whether to store a rollback point before replacing a bundle. Defaults to
    /// true when unset, matching the app — a CLI that defaulted the other way
    /// would silently install without the safety net the user believes they have.
    public var keepBackups: Bool
    public var githubToken: String?
    public var alcove: AlcoveUpdateSource.Credentials?

    public static func load() -> Settings {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        let strategy = defaults.string(forKey: UpdateSettings.appStoreUpdateStrategyKey)
            .flatMap(AppStoreUpdateStrategy.init(rawValue:)) ?? .full
        let vendorPolicy = defaults.string(forKey: UpdateSettings.vendorInstallPolicyKey)
            .flatMap(VendorInstallPolicy.init(rawValue:)) ?? UpdateSettings.vendorInstallPolicyDefault

        let licenseKey = Keychain.string(account: "alcove-license-key") ?? ""
        let instanceID = Keychain.string(account: "alcove-instance-id") ?? ""

        return Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: strategy, vendorInstallPolicy: vendorPolicy),
            ignoredKeys: Set(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey) ?? []),
            skippedVersions: defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey)
                as? [String: String] ?? [:],
            customScanPaths: defaults.stringArray(forKey: "CustomScanPaths") ?? [],
            // 0 means "never set"; the app's own default is 12.
            maxConcurrency: max(1, defaults.integer(forKey: "MaxConcurrency") == 0
                ? 12 : defaults.integer(forKey: "MaxConcurrency")),
            keepBackups: defaults.object(forKey: "KeepBackups") as? Bool ?? true,
            // Same ladder as the app: the token the user entered, else the
            // environment, else whatever `gh` is logged in as.
            githubToken: GitHubToken.resolve(
                explicit: Keychain.string(account: "github-token")),
            alcove: licenseKey.isEmpty || instanceID.isEmpty
                ? nil
                : AlcoveUpdateSource.Credentials(
                    licenseKey: licenseKey, instanceID: instanceID))
    }

    /// Whether the user has hidden this app: ignored outright, or told to skip
    /// exactly the version being offered. The same two predicates the app's
    /// `isActionableUpdate` runs, so a row counted here is a row counted there.
    public func isHidden(_ result: UpdateResult) -> Bool {
        VisibilityRules.isIgnored(result.app, ignoredKeys: ignoredKeys)
            || VisibilityRules.isVersionSkipped(
                result.app, version: result.remote?.displayVersion,
                skippedVersions: skippedVersions)
    }
}
