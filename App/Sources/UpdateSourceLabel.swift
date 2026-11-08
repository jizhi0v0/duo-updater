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
    /// "via Sparkle", "via the developer’s site".
    let phrase: String
    /// What Update does for this source, for the phrase's help.
    let detail: String
    /// The sidebar row's name for the source, or nil when Update just downloads
    /// and replaces the app, which is most apps and needs no mention there.
    let sidebarName: String?

    init?(_ result: UpdateResult, usesInstaller: Bool = false) {
        guard let source = result.remote?.sourceName,
              let label = Self.label(for: source, usesInstaller: usesInstaller)
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
            self.init(
                phrase: String(localized: "no Homebrew update", comment: "Before “· via Sparkle”: Homebrew installed the app but has no newer version") + " · " + label.phrase,
                detail: String(localized: "Homebrew installed this app but has no newer version, so Update uses this source. Homebrew’s record of the app stays at the old version.") + " " + label.detail,
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

    private static func label(for source: String, usesInstaller: Bool) -> UpdateSourceLabel? {
        let phrase: String, detail: String, sidebarName: String?
        // What the download-and-replace sources do. A `.pkg` goes to macOS's
        // installer instead (`AppListModel.requiresInstaller`).
        let replaces = usesInstaller
            ? String(localized: "Update downloads an installer package and runs it with macOS’s installer, which may ask for your password.")
            : String(localized: "Update downloads the new version, verifies it and replaces the app.")
        switch source {
        case "Sparkle":
            phrase = Self.via("Sparkle")
            detail = String(localized: "Updates come from the app’s own Sparkle feed.") + " " + replaces
            sidebarName = nil
        case "GitHub":
            phrase = Self.via("GitHub Releases")
            detail = String(localized: "Updates come from the project’s GitHub Releases.") + " " + replaces
            sidebarName = nil
        case "Electron", MyGoUpdateSource.sourceName:
            phrase = String(localized: "via the app’s update feed")
            detail = String(localized: "Updates come from the update feed the app itself reads.") + " " + replaces
            sidebarName = nil
        case "Vendor":
            phrase = String(localized: "via the developer’s site")
            detail = String(localized: "Updates come from the developer’s own site.") + " " + replaces
            sidebarName = nil
        case "Homebrew":
            phrase = Self.via("Homebrew")
            detail = String(localized: "Updates come from a Homebrew cask. Update runs brew for this app only.")
            sidebarName = "Homebrew"
        case "App Store":
            phrase = Self.via("App Store")
            detail = String(localized: "Updates come from the App Store, which installs them.")
            sidebarName = "App Store"
        case "Setapp":
            phrase = Self.via("Setapp")
            detail = String(localized: "Updates come from Setapp. Update opens Setapp, which installs them and may also update your other Setapp apps.")
            sidebarName = "Setapp"
        case "TestFlight":
            phrase = Self.via("TestFlight")
            detail = String(localized: "TestFlight installs this app’s betas.")
            sidebarName = nil
        case "Toolbox":
            phrase = Self.via("JetBrains Toolbox")
            detail = String(localized: "JetBrains Toolbox installs this app’s updates.")
            sidebarName = nil
        case "Xcode Releases":
            phrase = Self.via("Xcode Releases")
            detail = String(localized: "New Xcode versions are found through Xcode Releases. Update downloads and installs the new Xcode.")
            sidebarName = nil
        default:
            return nil
        }
        return UpdateSourceLabel(phrase: phrase, detail: detail, sidebarName: sidebarName)
    }

    private static func via(_ name: String) -> String {
        String(localized: "via \(name)", comment: "Where an app's updates come from, e.g. “via Sparkle”, “via Homebrew”")
    }
}
