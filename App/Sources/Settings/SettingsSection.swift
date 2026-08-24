import SwiftUI

/// One page of the Settings window. Promoted out of `SettingsView` so the model
/// can deep-link to a page (`AppListModel.requestedSettingsSection`) without
/// depending on the view that renders it.
///
/// `group` drives the sidebar's section headers; `tint` colors the icon tile the
/// way System Settings does. `localizedKeywords` and `englishAliases` widen the
/// sidebar search beyond the visible label, so "token" finds GitHub and
/// "rollback" finds General.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, backups, folders, updates
    case github, alcove
    case ignored, diagnostics

    var id: String { rawValue }

    /// Sidebar grouping. Pages are ordered by group, then by declaration order.
    enum Group: String, CaseIterable, Identifiable {
        case app = "App"
        case accounts = "Accounts"
        case library = "Library"
        var id: String { rawValue }

        /// Localized sidebar group header. `rawValue` stays a plain internal
        /// identifier — this is the only form actually shown to the user.
        var displayName: String {
            switch self {
            case .app:      return String(localized: "App")
            case .accounts: return String(localized: "Accounts")
            case .library:  return String(localized: "Library")
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .backups, .folders, .updates: return .app
        case .github, .alcove:             return .accounts
        case .ignored, .diagnostics:       return .library
        }
    }

    var label: String {
        switch self {
        case .general:     return String(localized: "General")
        case .backups:     return String(localized: "Backups")
        case .folders:     return String(localized: "Folders")
        case .updates:     return String(localized: "Updates")
        case .github:      return String(localized: "GitHub")
        case .alcove:      return String(localized: "Alcove")
        case .ignored:     return String(localized: "Ignored")
        case .diagnostics: return String(localized: "Diagnostics")
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .backups:     return "clock.arrow.circlepath"
        case .folders:     return "folder.fill"
        case .updates:     return "arrow.triangle.2.circlepath"
        case .github:      return "key.fill"
        case .alcove:      return "sparkles"
        case .ignored:     return "eye.slash.fill"
        case .diagnostics: return "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .general:     return .gray
        case .backups:     return .indigo
        case .folders:     return .blue
        case .updates:     return .green
        case .github:      return .purple
        case .alcove:      return .pink
        case .ignored:     return .orange
        case .diagnostics: return .teal
        }
    }

    /// Short line under the page title.
    var subtitle: String {
        switch self {
        case .general:     return String(localized: "How often Duo Updater checks, and what it does when it finds something.")
        case .backups:     return String(localized: "Keep a copy of the previous version so an update can be undone — here or on another disk.")
        case .folders:     return String(localized: "Where Duo Updater looks for installed apps.")
        case .updates:     return String(localized: "Duo Updater's own version.")
        case .github:      return String(localized: "Lift GitHub's anonymous rate limit for apps tracked through Releases.")
        case .alcove:      return String(localized: "Alcove keeps release notes and installable builds behind its license.")
        case .ignored:     return String(localized: "Apps and versions you've told Duo Updater to leave alone.")
        case .diagnostics: return String(localized: "Permissions, last check, and the health of each detection recipe.")
        }
    }

    /// Extra search terms, in the reader's language, beyond what `label` and
    /// `subtitle` already say.
    ///
    /// One comma-separated string per page rather than an array, so a translator
    /// can add, drop or merge terms freely — the useful search words in German are
    /// not a one-for-one mapping of the English ones, and a fixed-length array
    /// would pretend they are.
    ///
    /// This half was English-only until now, which mostly worked by accident: the
    /// subtitles are prose-rich, so a German user typing `Berechtigungen` reached
    /// Diagnostics through the subtitle. What did not work was anything that
    /// exists *only* as a keyword — `Zurücksetzen` found nothing where English
    /// `rollback` reached General.
    private var localizedKeywords: [String] {
        let list: String
        switch self {
        case .general:     list = String(localized: "launch, login, frequency, notify, restart, concurrency, app store, self-updating, vendor", comment: "Comma-separated extra search terms for the General settings page")
        case .backups:     list = String(localized: "backup, rollback, roll back, undo, restore, previous version, external disk, drive, nas, archive, storage, space", comment: "Comma-separated extra search terms for the Backups settings page")
        case .folders:     list = String(localized: "scan, locations, applications, path, directory", comment: "Comma-separated extra search terms for the Folders settings page")
        case .updates:     list = String(localized: "version, about, self", comment: "Comma-separated extra search terms for the Updates settings page")
        case .github:      list = String(localized: "token, personal access token, rate limit", comment: "Comma-separated extra search terms for the GitHub settings page")
        case .alcove:      list = String(localized: "license, key, instance, activation", comment: "Comma-separated extra search terms for the Alcove settings page")
        case .ignored:     list = String(localized: "hidden, skip, skipped, versions, unignore", comment: "Comma-separated extra search terms for the Ignored settings page")
        case .diagnostics: list = String(localized: "permissions, app management, helper, recipe, health, relaunch, setup", comment: "Comma-separated extra search terms for the Diagnostics settings page")
        }
        // Full-width separators too. A CJK translator reaching for a comma types
        // "，" or "、", and splitting on ASCII alone would quietly turn the whole
        // line into one unmatchable keyword — a failure with no symptom except a
        // search that finds nothing.
        return list.split(whereSeparator: { ",，、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The original English terms, kept searchable in every language.
    ///
    /// Not a leftover. Two different readers type into this field: one searching
    /// in their own language, who `localizedKeywords` is for, and one who has read
    /// the README, an issue thread or a `duo` man page — all of which are English
    /// — and types `rollback` or `app management` whatever the UI is set to. Some
    /// of these are not words at all but names (`pat`, `gh`, `cli`, `mas`,
    /// `sparkle`), which no language translates.
    ///
    /// Searching both lists is strictly additive: every query that found a page
    /// before still finds it, and the localized terms are new ground.
    private var englishAliases: [String] {
        switch self {
        case .general:     return ["launch", "login", "frequency", "notify", "restart", "concurrency", "app store", "mas", "self-updating", "vendor"]
        case .backups:     return ["backup", "rollback", "roll back", "undo", "restore", "previous version", "external disk", "drive", "nas", "archive", "storage", "space"]
        case .folders:     return ["scan", "locations", "applications", "path", "directory"]
        case .updates:     return ["version", "sparkle", "about", "self"]
        case .github:      return ["token", "personal access token", "pat", "gh", "cli", "rate limit"]
        case .alcove:      return ["license", "key", "instance", "activation"]
        case .ignored:     return ["hidden", "skip", "skipped", "versions", "unignore"]
        case .diagnostics: return ["permissions", "app management", "helper", "recipe", "health", "relaunch", "setup"]
        }
    }

    /// Case- and diacritic-insensitive match over the label, subtitle, and keywords.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return ([label, subtitle] + localizedKeywords + englishAliases).contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
