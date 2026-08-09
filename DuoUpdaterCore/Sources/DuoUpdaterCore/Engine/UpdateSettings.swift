import Foundation

/// How Mac App Store updates are applied.
///
/// Both routes drive the store's own `storedownloadd`, so neither mixes
/// channels — they differ in dependency and bandwidth:
///   • `.full` — the `mas` CLI replays the store purchase and redownloads the
///     whole app. No extra permission, but needs `mas` (brew) and more traffic.
///   • `.incremental` — drives App Store.app's own Update button via the
///     Accessibility API, so the store fetches a delta. No `mas` needed and less
///     traffic, but requires an Accessibility grant (guided via PermissionFlow).
/// Default is `.full`: it asks for no sensitive permission up front.
public enum AppStoreUpdateStrategy: String, CaseIterable, Identifiable, Sendable {
    case full
    case incremental

    public var id: String { rawValue }

    /// Release builds currently expose only the more predictable full-download
    /// path. Keep the incremental case in the model so older defaults still
    /// decode cleanly and the implementation can return later without a
    /// migration.
    public static let availableCases: [Self] = [.full]

    public var label: String {
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
public enum VendorInstallPolicy: String, CaseIterable, Identifiable, Sendable {
    case deferWhenRunning
    case alwaysOverwrite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .deferWhenRunning: return "Defer to the app’s own updater while it’s running"
        case .alwaysOverwrite:  return "Always download & replace, then restart"
        }
    }
}

/// The user preference values `UpdatePolicy` consults when deciding how an
/// update may be installed. A plain value so the policy stays pure — the
/// `@MainActor` app reads these out of its settings object and hands them in;
/// a CLI reads the same UserDefaults keys and builds the same value, so both
/// share one set of rules.
public struct UpdateSettings: Sendable {
    /// Which route to use for Mac App Store updates. See `AppStoreUpdateStrategy`.
    public var appStoreUpdateStrategy: AppStoreUpdateStrategy
    /// How to apply self-updating vendor-app updates. See `VendorInstallPolicy`.
    public var vendorInstallPolicy: VendorInstallPolicy

    /// The UserDefaults key the app persists `appStoreUpdateStrategy` under.
    /// Shared here (not in the app) so a CLI reading the same suite can never
    /// drift onto a differently-named key.
    public static let appStoreUpdateStrategyKey = "AppStoreUpdateStrategy"
    /// The UserDefaults key the app persists `vendorInstallPolicy` under.
    public static let vendorInstallPolicyKey = "VendorInstallPolicy"

    public init(
        appStoreUpdateStrategy: AppStoreUpdateStrategy,
        vendorInstallPolicy: VendorInstallPolicy
    ) {
        self.appStoreUpdateStrategy = appStoreUpdateStrategy
        self.vendorInstallPolicy = vendorInstallPolicy
    }
}

/// The stable per-install identity for an app's preferences (ignore, skip,
/// notification baseline). Keys on the on-disk path — exactly like
/// `InstalledApp.id`, and deliberately NOT the bundle id: several installed
/// apps can legitimately share one (the JetBrains-Toolbox Android Studio
/// channels, Thunderbird stable/esr, …), and a bundle-id key collapses them
/// so ignoring/skipping one applied to every copy. Kept separate from
/// `BackupStore.key`: rollback storage has its own compatibility and
/// collision-avoidance rules, while preferences must preserve old ignore/skip
/// identities exactly.
///
/// Not named `PreferenceKey`: SwiftUI exports a protocol under that name and
/// this module is imported by the views, so the bare name would shadow it in
/// unqualified lookup in every file that imports both.
public enum InstallPreferenceKey {
    public static func key(for app: InstalledApp) -> String {
        preferenceKey(app.path.path)
    }

    /// The previous bundle-id-preferred identity. Entries written before the
    /// switch to per-path keys live under this; we still honour them on read so
    /// an existing ignore/skip never silently resurfaces, and migrate them to the
    /// new key the next time the app is toggled.
    public static func legacyKey(for app: InstalledApp) -> String {
        preferenceKey(app.bundleID ?? app.path.path)
    }

    /// Sanitise an install identity down to characters that are safe as a
    /// UserDefaults key: letters, digits, `.`, `-`, `_`; everything else
    /// (slashes, spaces, colons) becomes `_`. A key that is empty or only dots
    /// — a path like `/.` — would otherwise collide with the "unset" sentinel,
    /// so it falls back to the literal `"app"`.
    public static func preferenceKey(_ raw: String) -> String {
        let safe = raw.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == "_" { return c }
            return "_"
        }
        let joined = String(safe)
        return joined.isEmpty || joined.allSatisfy { $0 == "." } ? "app" : joined
    }
}

/// Whether the user has told us to stop showing an update. Shared because the
/// legacy-key fallbacks are not symmetric between the two rules, and a
/// re-derived copy gets them subtly wrong: skip falls back to the legacy key
/// only when the per-path key is **absent**, so an app skipped at 2.0 and then
/// skipped again at 3.0 must not stay hidden via a stale legacy entry — while
/// ignore matches either key, so un-ignoring has to clear both.
public enum VisibilityRules {

    public static func isIgnored(_ app: InstalledApp, ignoredKeys: Set<String>) -> Bool {
        ignoredKeys.contains(InstallPreferenceKey.key(for: app))
            || ignoredKeys.contains(InstallPreferenceKey.legacyKey(for: app))
    }

    public static func isVersionSkipped(
        _ app: InstalledApp, version: String?, skippedVersions: [String: String]
    ) -> Bool {
        guard let version else { return false }
        let skipped = skippedVersions[InstallPreferenceKey.key(for: app)]
            ?? skippedVersions[InstallPreferenceKey.legacyKey(for: app)]
        return skipped == version
    }
}
