import SwiftUI
import DuoUpdaterCore

/// One thing the Settings sidebar's search found below the page level: a setting,
/// found by the words on its control, or an app, found by its name wherever a page
/// lists it. Picking one opens the page scrolled to that card or row
/// (`SettingsAnchor`), the way System Settings lands on "Notifications →
/// Application Notifications" for an app's name.
struct SettingsSearchHit: Identifiable, Hashable {
    enum Icon: Hashable {
        /// The page's own tile, as the page row above it shows.
        case section(SettingsSection)
        /// An app's bundle path; nil when no scanned app has that key any more
        /// (an ignore outlives the app it was set on).
        case app(String?)
    }

    let anchor: SettingsAnchor
    let title: String
    /// Where it lives, "Page → Card", under the title.
    let location: String
    let icon: Icon

    var id: SettingsAnchor { anchor }
}

/// The searchable catalog, and the matching over it.
///
/// Titles are spelled exactly as the control on the page spells them, so each one
/// resolves through the same catalog key and a translated window searches — and
/// shows — the translated words. A title that drifts from its control is a result
/// that finds the old wording; keep them in step when a label changes.
@MainActor
enum SettingsSearch {
    private struct Setting {
        let anchor: SettingsAnchor
        let title: String
        /// The card's header, when it has one; nil for a card without.
        let card: String?
    }

    /// In page order, then in order down the page — the order results are listed.
    private static func catalog(prefs: Preferences) -> [Setting] {
        let routing = String(localized: "Install routing")
        let notify = String(localized: "Notify me about updates to")
        let rollback = String(localized: "Rollback points")
        let permissions = String(localized: "Permissions")
        let signIn = String(localized: "Apple Developer sign-in")
        return [
            Setting(anchor: .launchAtLogin, title: String(localized: "Launch at login"), card: nil),
            Setting(anchor: .checkFrequency, title: String(localized: "Check for updates"), card: nil),
            Setting(anchor: .hideDockIcon, title: String(localized: "Hide the Dock icon"), card: nil),
            Setting(anchor: .appRuntimeTags, title: String(localized: "Show what each app is built with"), card: nil),
            Setting(anchor: .cliRuntimeTags, title: String(localized: "Show what each command-line tool is built with"), card: nil),
            Setting(anchor: .autoRelaunch, title: String(localized: "Relaunch updated apps automatically"), card: String(localized: "After an update")),
            Setting(anchor: .concurrency, title: String(localized: "Check up to \(prefs.maxConcurrency) apps at once"), card: nil),
            Setting(anchor: .appStoreUpdates, title: String(localized: "App Store updates"), card: routing),
            Setting(anchor: .selfUpdatingApps, title: String(localized: "Self-updating apps"), card: routing),
            Setting(anchor: .digestOnlyInstalls, title: String(localized: "Allow one-click updates for apps without a developer signature"), card: nil),
            Setting(anchor: .testFlightDetection, title: String(localized: "TestFlight betas"), card: nil),

            Setting(anchor: .notifyApps, title: String(localized: "Apps"), card: notify),
            Setting(anchor: .notifyCLITools, title: String(localized: "Command-line tools"), card: notify),
            Setting(anchor: .notifyHomebrew, title: String(localized: "Homebrew packages"), card: notify),

            Setting(anchor: .keepBackups, title: String(localized: "Keep a backup so updates can be restored"), card: rollback),
            Setting(anchor: .pruneOrphanBackups, title: String(localized: "Delete a backup once its app is uninstalled"), card: rollback),
            Setting(anchor: .backupLocation, title: String(localized: "Where backups are kept"), card: nil),

            Setting(anchor: .storageCaches, title: String(localized: "Clear Caches"), card: String(localized: "Caches")),
            Setting(anchor: .storageAppData, title: String(localized: "App data"), card: nil),
            Setting(anchor: .storageSystem, title: String(localized: "Kept by macOS for DuoUpdater"), card: nil),

            Setting(anchor: .scanFolders, title: String(localized: "Folders to scan"), card: nil),
            Setting(anchor: .builtInFolders, title: String(localized: "Always scanned"), card: nil),

            Setting(anchor: .selfUpdateCheck, title: String(localized: "Check for Updates…"), card: nil),
            Setting(anchor: .silentSelfUpdate, title: String(localized: "Install DuoUpdater's own updates silently"), card: nil),

            Setting(anchor: .githubCLI, title: String(localized: "Use the GitHub CLI’s sign-in"), card: String(localized: "GitHub CLI integration")),
            Setting(anchor: .githubToken, title: String(localized: "GitHub token", comment: "A Settings search result: the GitHub page's personal access token field"), card: nil),
            Setting(anchor: .alcoveLicense, title: String(localized: "Alcove license key"), card: nil),
            Setting(anchor: .appleDeveloperSignIn, title: signIn, card: nil),
            Setting(anchor: .renewAppleSession, title: String(localized: "Renew the session in the background"), card: signIn),
            Setting(anchor: .downloadXcode, title: String(localized: "Download Xcode"), card: nil),

            Setting(anchor: .ignoredApps, title: String(localized: "Ignored apps"), card: nil),
            Setting(anchor: .skippedVersions, title: String(localized: "Skipped versions"), card: nil),

            Setting(anchor: .appManagement, title: String(localized: "App Management"), card: permissions),
            Setting(anchor: .fullDiskAccess, title: String(localized: "Full Disk Access"), card: permissions),
            Setting(anchor: .appStoreHelper, title: String(localized: "App Store helper"), card: permissions),
            Setting(anchor: .lastChecked, title: String(localized: "Last checked"), card: nil),
            Setting(anchor: .recentFailures, title: String(localized: "Recent failures"), card: nil),
            Setting(anchor: .recipes, title: String(localized: "Detection recipes"), card: nil),
        ]
    }

    /// Settings whose label, or whose card's header, contains the query. Nothing
    /// for an empty query: with no search the sidebar lists pages only.
    static func settings(matching query: String, prefs: Preferences) -> [SettingsSearchHit] {
        guard !isEmpty(query) else { return [] }
        return catalog(prefs: prefs).compactMap { setting in
            guard SearchMatch.matches(query, in: [setting.title, setting.card])
            else { return nil }
            return SettingsSearchHit(
                anchor: setting.anchor,
                title: setting.title,
                location: location(setting.anchor.section, setting.card),
                icon: .section(setting.anchor.section))
        }
    }

    /// Apps named on a settings page — ignored, with a skipped version, or with a
    /// detection recipe on Diagnostics — whose name contains the query. One
    /// result per place, so an app both ignored and skipped is listed twice, each
    /// leading to its own row. Sorted by name, then page order.
    static func apps(
        matching query: String,
        prefs: Preferences,
        results: [UpdateResult],
        recipes: [RecipeHealth.Entry]
    ) -> [SettingsSearchHit] {
        guard !isEmpty(query) else { return [] }

        // Key → app, under both keys an ignore or skip may be stored under (the
        // same pair `IgnoredSettingsPage` resolves names with).
        var byKey: [String: InstalledApp] = [:]
        var byBundleID: [String: InstalledApp] = [:]
        for result in results {
            byKey[prefs.key(for: result.app)] = result.app
            byKey[prefs.legacyKey(for: result.app)] = result.app
            if let id = result.app.bundleID { byBundleID[id] = result.app }
        }

        var hits: [SettingsSearchHit] = []
        let ignoredCard = String(localized: "Ignored apps")
        for key in prefs.ignoredKeys {
            let app = byKey[key]
            let name = app?.name ?? key
            guard SearchMatch.matches(query, in: name) else { continue }
            hits.append(SettingsSearchHit(
                anchor: .ignoredApp(key), title: name,
                location: location(.ignored, ignoredCard), icon: .app(app?.path.path)))
        }
        let skippedCard = String(localized: "Skipped versions")
        for (key, version) in prefs.skippedVersions {
            let app = byKey[key]
            let name = app?.name ?? key
            guard SearchMatch.matches(query, in: name) else { continue }
            hits.append(SettingsSearchHit(
                anchor: .skippedVersion(key), title: "\(name) \(version)",
                location: location(.ignored, skippedCard), icon: .app(app?.path.path)))
        }
        let recipesCard = String(localized: "Detection recipes")
        let names = byBundleID.mapValues(\.name)
        let installed = Set(byBundleID.keys)
        for entry in recipes {
            let name = entry.displayName(resolving: names)
            guard SearchMatch.matches(query, in: name) else { continue }
            // The same lookup as the row on the Diagnostics page: the id or one of
            // its parts, or for a GitHub rule the rule's own bundle id.
            let app = entry.bundleID(among: installed).flatMap { byBundleID[$0] }
            hits.append(SettingsSearchHit(
                anchor: .recipe(entry.key), title: name,
                location: location(.diagnostics, recipesCard), icon: .app(app?.path.path)))
        }

        let order = SettingsSection.allCases
        return hits.sorted {
            let byName = $0.title.localizedStandardCompare($1.title)
            if byName != .orderedSame { return byName == .orderedAscending }
            return order.firstIndex(of: $0.anchor.section)! < order.firstIndex(of: $1.anchor.section)!
        }
    }

    private static func isEmpty(_ query: String) -> Bool {
        SearchMatch.trimmed(query).isEmpty
    }

    /// "Page → Card", as System Settings writes it; the page alone for a card
    /// without a header.
    private static func location(_ section: SettingsSection, _ card: String?) -> String {
        [section.label, card].compactMap { $0 }.joined(separator: " → ")
    }
}
