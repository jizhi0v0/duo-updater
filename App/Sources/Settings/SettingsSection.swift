import SwiftUI

/// One page of the Settings window. Promoted out of `SettingsView` so the model
/// can deep-link to a page (`AppListModel.requestedSettingsSection`) without
/// depending on the view that renders it.
///
/// `group` drives the sidebar's section headers; `tint` colors the icon tile the
/// way System Settings does. `keywords` widen the sidebar search beyond the
/// visible label, so "token" finds GitHub and "rollback" finds General.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, folders, updates
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
        case .general, .folders, .updates: return .app
        case .github, .alcove:             return .accounts
        case .ignored, .diagnostics:       return .library
        }
    }

    var label: String {
        switch self {
        case .general:     return String(localized: "General")
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
        case .folders:     return String(localized: "Where Duo Updater looks for installed apps.")
        case .updates:     return String(localized: "Duo Updater's own version.")
        case .github:      return String(localized: "Lift GitHub's anonymous rate limit for apps tracked through Releases.")
        case .alcove:      return String(localized: "Alcove keeps release notes and installable builds behind its license.")
        case .ignored:     return String(localized: "Apps and versions you've told Duo Updater to leave alone.")
        case .diagnostics: return String(localized: "Permissions, last check, and the health of each detection recipe.")
        }
    }

    /// Extra search terms, beyond `label`, that should match this page.
    private var keywords: [String] {
        switch self {
        case .general:     return ["launch", "login", "frequency", "notify", "restart", "backup", "rollback", "concurrency", "app store", "mas", "self-updating", "vendor"]
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
        return ([label, subtitle] + keywords).contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
