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

    /// Deliberately terse. These labels sit in a popup button whose slot is the
    /// settings row, and the sentence-length versions they replaced ("Full
    /// download (no extra permission)") could not be shown whole at the window's
    /// own minimum width in ANY language we ship — the popup truncated its own
    /// current selection, so the setting could not be read without opening the
    /// menu. Everything the parenthetical carried is in the card's footer, which
    /// has room for it.
    ///
    /// `.incremental` keeps its longer label: it is not in `availableCases`, so
    /// nothing renders it, and re-translating a string no one can see would be
    /// churn for its own sake.
    public var label: String {
        switch self {
        case .full:        return String(localized: "Full download")
        case .incremental: return String(localized: "Incremental (needs Accessibility)")
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
///
/// Default `.alwaysOverwrite`, changed from `.deferWhenRunning`. Deferring reads
/// as the cautious choice, but the apps it applies to — Chrome, VS Code, Cursor,
/// the Electron ones — are the apps that are *always* running, so deferring meant
/// the common case never installed anything: the row offered "Open" forever and
/// the tool only ever reported. The reasons it is safe to overwrite instead:
///   • anything with sibling components to install (daemons, launch items) ships
///     a `.pkg` — Tailscale, all of Office — and a pkg goes to the system
///     installer, which places those components properly. Bundle replacement
///     only ever happens for dmg/zip apps, where the bundle *is* the product.
///   • the artifact is the vendor's own official installer, so this does what a
///     user doing it by hand would do.
///   • the quit is graceful — `terminate()`, never a force-kill, so save prompts
///     still run — and auto-restart is on by default, so in the normal case the
///     window where a live process runs beside a replaced bundle is short.
///     Be precise about the failure case though: the restart happens *after* the
///     swap, so an app that refuses to quit is left running old code beside a new
///     bundle until the user relaunches it. Nothing is lost and the row keeps a
///     Restart button, but the install is not rolled back and never was — there
///     is no pre-install quit to abort.
/// `.deferWhenRunning` remains for anyone who would rather we never touch a
/// running app.
public enum VendorInstallPolicy: String, CaseIterable, Identifiable, Sendable {
    case deferWhenRunning
    case alwaysOverwrite

    public var id: String { rawValue }

    /// Terse for the same reason as `AppStoreUpdateStrategy.label`, and worded to
    /// match the footer exactly: it already names these two by their short names
    /// ("Always replace" — the default … switch to "Defer while running"), so the
    /// popup and the prose explaining it now say the same thing.
    public var label: String {
        switch self {
        case .deferWhenRunning: return String(localized: "Defer while running")
        case .alwaysOverwrite:  return String(localized: "Always replace")
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
    /// Installs whose administrator prompt the user dismissed, keyed by
    /// `InstallPreferenceKey.key(for:)` — an install PATH, never a bundle id.
    /// See `ElevationRules` for why this is remembered at all.
    public var declinedElevationKeys: Set<String>

    /// The UserDefaults key the app persists `appStoreUpdateStrategy` under.
    /// Shared here (not in the app) so a CLI reading the same suite can never
    /// drift onto a differently-named key.
    public static let appStoreUpdateStrategyKey = "AppStoreUpdateStrategy"
    /// The UserDefaults key the app persists `vendorInstallPolicy` under.
    public static let vendorInstallPolicyKey = "VendorInstallPolicy"

    /// What `vendorInstallPolicy` resolves to when the key is absent.
    ///
    /// Shared for the same reason the key names are: the app and the CLI each
    /// resolve this independently, and a default that drifted between them would
    /// mean `duo install` and the menu bar routing the same app differently — a
    /// difference nothing would report, since both answers are individually valid.
    public static let vendorInstallPolicyDefault: VendorInstallPolicy = .alwaysOverwrite

    /// Where the ignore list and the per-app skipped version live. Shared
    /// because `duo ignore` and `duo skip` **write** these: a name that drifted
    /// would not read as empty, it would silently create a second, invisible
    /// ignore list while the app kept using the first.
    public static let ignoredKeysKey = "IgnoredApps"
    public static let skippedVersionsKey = "SkippedVersions"
    /// Where the declined administrator prompts live. Shared for the same reason
    /// as the two above: the CLI resolves this independently, and a drifted name
    /// would not read as empty — it would silently keep offering a one-click the
    /// user already refused in the menu bar.
    public static let declinedElevationKeysKey = "DeclinedElevatedInstalls"

    public init(
        appStoreUpdateStrategy: AppStoreUpdateStrategy,
        vendorInstallPolicy: VendorInstallPolicy,
        declinedElevationKeys: Set<String> = []
    ) {
        self.appStoreUpdateStrategy = appStoreUpdateStrategy
        self.vendorInstallPolicy = vendorInstallPolicy
        self.declinedElevationKeys = declinedElevationKeys
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

    /// Whether this app is worth spending a network check on.
    ///
    /// Ignoring an app means "stop telling me about this one" — nothing will be
    /// said about the answer however it comes back, so the request is pure cost.
    /// On an unauthenticated GitHub budget (60 requests an hour) it is cost that
    /// pushes apps the user *does* watch out of the hour.
    ///
    /// A **skipped version** is deliberately not covered here and must keep being
    /// checked: whether the version being offered is still the one the user
    /// skipped is knowable only by asking. Skipping 3.3 hides 3.3, not 3.4.
    public static func deservesCheck(_ app: InstalledApp, ignoredKeys: Set<String>) -> Bool {
        !isIgnored(app, ignoredKeys: ignoredKeys)
    }

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

/// Whether the user has refused to let us install into a location we cannot
/// write, and so should stop being offered a one-click Update for it.
///
/// This is remembered rather than re-asked because the alternative is worse in
/// both directions: an app in `/Library/Input Methods` or an admin-owned
/// `/Applications` needs a password on *every* install, so a row that keeps its
/// Update button turns one refusal into a password panel on every future
/// release — while pre-emptively demoting such a row to "Open" would deny the
/// user a working one-click they never said no to. Hence a tri-state: never
/// asked keeps Update, declined falls back to Open, and the user can retire the
/// refusal from the row's context menu.
///
/// Keyed exactly like ignore, and matched against **either** key form for the
/// same reason: several installed apps legitimately share a bundle id (the
/// Toolbox-managed Android Studio channels, Thunderbird stable/esr), so a
/// bundle-id key would silence a channel the user never declined. Clearing must
/// therefore drop both forms — see `Preferences.setElevationDeclined`.
public enum ElevationRules {

    public static func isDeclined(_ app: InstalledApp, declinedKeys: Set<String>) -> Bool {
        declinedKeys.contains(InstallPreferenceKey.key(for: app))
            || declinedKeys.contains(InstallPreferenceKey.legacyKey(for: app))
    }
}
