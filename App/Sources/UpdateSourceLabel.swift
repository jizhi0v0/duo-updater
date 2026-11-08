import DuoUpdaterCore
import Foundation

/// Where an app's updates come from, as the workbench words it: "via Sparkle" at
/// the end of the detail header's version line, with what Update will do in its
/// help, and the source's short name on the sidebar row when Update hands the work
/// to another tool.
///
/// Keyed by `RemoteVersion.sourceName`. A source not listed here gets no label
/// rather than a made-up one.
struct UpdateSourceLabel: Equatable {
    /// What Update does for this row, which the source alone does not say: a
    /// Homebrew cask whose package needs macOS's installer goes there, not to brew,
    /// and a detection-only or gated row has no install at all.
    enum Action: Equatable {
        /// The source's own one-click route: download and replace, brew, Xcode.
        case install
        /// A package handed to macOS's installer (`AppListModel.requiresInstaller`).
        case installer
        /// No install from here: detection only, withheld by a gate, or a running
        /// app whose own updater applies it (`defersToSelfUpdater`).
        case none
    }

    /// "via Sparkle", "via the developer’s site".
    let phrase: String
    /// Where updates come from, and what Update does when it does something.
    let detail: String
    /// The sidebar row's name for the source, or nil when Update just downloads
    /// and replaces the app, which is most apps and needs no mention there.
    let sidebarName: String?

    init?(_ result: UpdateResult, action: Action = .none) {
        guard let source = result.remote?.sourceName,
              let label = Self.label(for: source, action: action)
        else { return nil }
        // A brew copy reaches another source only after Homebrew said it has
        // nothing newer (`UpdateChecker`, which then sets
        // `homebrewSourceIdentifier`). Naming that source on a copy it gave
        // nothing new to reads as if brew were not involved: the up-to-date
        // answer is Homebrew's, and an update from elsewhere says brew had none.
        guard source != "Homebrew", result.homebrewSourceIdentifier != nil else {
            self = label
            return
        }
        switch result.status {
        case .upToDate:
            self.init(
                phrase: Self.via("Homebrew"),
                detail: String(localized: "Homebrew installed this app and has no newer version, and neither does the app’s other update source."),
                sidebarName: "Homebrew")
        case .updateAvailable:
            var detail = String(localized: "Homebrew installed this app but has no newer version.") + " " + label.detail
            if action != .none {
                detail += " " + String(localized: "After this update, Homebrew’s record of the app stays at the old version.")
            }
            self.init(
                phrase: String(localized: "no Homebrew update", comment: "Before “· via Sparkle”: Homebrew installed the app but has no newer version") + " · " + label.phrase,
                detail: detail,
                sidebarName: label.sidebarName)
        default:
            self = label
        }
    }

    private init(phrase: String, detail: String, sidebarName: String?) {
        self.phrase = phrase
        self.detail = detail
        self.sidebarName = sidebarName
    }

    private static func label(for source: String, action: Action) -> UpdateSourceLabel? {
        let phrase: String, origin: String, sidebarName: String?
        // What this source's own route does; nil for a source whose sentence
        // already names the tool that installs.
        var installs: String?
        let replaces = String(localized: "Update downloads the new version, verifies it and replaces the app.")
        switch source {
        case "Sparkle":
            phrase = via("Sparkle")
            origin = String(localized: "Updates come from the app’s own Sparkle feed.")
            installs = replaces
            sidebarName = nil
        case "GitHub":
            phrase = via("GitHub Releases")
            origin = String(localized: "Updates come from the project’s GitHub Releases.")
            installs = replaces
            sidebarName = nil
        case "Electron", MyGoUpdateSource.sourceName:
            phrase = String(localized: "via the app’s update feed")
            origin = String(localized: "Updates come from the update feed the app itself reads.")
            installs = replaces
            sidebarName = nil
        case "Vendor":
            phrase = String(localized: "via the developer’s site")
            origin = String(localized: "Updates come from the developer’s own site.")
            installs = replaces
            sidebarName = nil
        case "Homebrew":
            phrase = via("Homebrew")
            origin = String(localized: "Updates come from a Homebrew cask.")
            installs = String(localized: "Update runs brew for this app only.")
            sidebarName = "Homebrew"
        case "App Store":
            phrase = via("App Store")
            origin = String(localized: "Updates come from the App Store, which installs them.")
            sidebarName = "App Store"
        case "Setapp":
            phrase = via("Setapp")
            origin = String(localized: "Updates come from Setapp, which installs them and may also update your other Setapp apps.")
            sidebarName = "Setapp"
        case "TestFlight":
            phrase = via("TestFlight")
            origin = String(localized: "TestFlight installs this app’s betas.")
            sidebarName = nil
        case "Toolbox":
            phrase = via("JetBrains Toolbox")
            origin = String(localized: "JetBrains Toolbox installs this app’s updates.")
            sidebarName = nil
        case "Xcode Releases":
            phrase = via("Xcode Releases")
            origin = String(localized: "New Xcode versions are found through Xcode Releases.")
            installs = String(localized: "Update downloads and installs the new Xcode.")
            sidebarName = nil
        default:
            return nil
        }
        var detail = origin
        switch action {
        case .install:
            if let installs { detail += " " + installs }
        case .installer:
            if installs != nil {
                detail += " " + String(localized: "Update downloads an installer package and runs it with macOS’s installer, which may ask for your password.")
            }
        case .none:
            break
        }
        return UpdateSourceLabel(phrase: phrase, detail: detail, sidebarName: sidebarName)
    }

    private static func via(_ name: String) -> String {
        String(localized: "via \(name)", comment: "Where an app's updates come from, e.g. “via Sparkle”, “via Homebrew”")
    }
}
