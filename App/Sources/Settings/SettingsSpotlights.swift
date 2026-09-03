import SwiftUI
import DuoUpdaterCore

/// Every setting that has ever earned a "new" dot, and the page it lives on.
///
/// The catalog is append-only and the ids are permanent: an id that changes is an
/// id an existing install has never acknowledged, so the dot would come back from
/// the dead. Old entries stay listed after everyone has seen them — they cost
/// nothing (`SettingsSpotlightLedger` only ever announces what is newer than the
/// version a user last ran) and removing one would re-announce it to anyone
/// upgrading across a long gap.
enum SettingsSpotlights {

    /// "Show what each app is built with" — the runtime chip beside every app name.
    static let appRuntimeTags = SettingsSpotlight(id: "app-runtime-tags", introducedIn: "0.3.77")

    static let all: [SettingsSpotlight] = [appRuntimeTags]

    /// Which page to send someone looking for the dot. Anything unrecognized —
    /// an id acknowledged by a newer build and read back by an older one — maps
    /// to nothing rather than to a wrong page.
    static func section(for id: String) -> SettingsSection? {
        switch id {
        case appRuntimeTags.id: return .general
        default: return nil
        }
    }
}

// MARK: - The dot itself

/// The blue dot that says "this is new". Six points, no label — the same
/// vocabulary macOS uses in System Settings for an item awaiting attention.
///
/// It appears in three places at once, and they are a chain rather than three
/// independent decisions: the menu bar's gear says "there is something in
/// Settings", the sidebar row says which page, and the row itself says which
/// control. Losing any link leaves a dot that leads nowhere.
struct SpotlightDot: View {
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: size, height: size)
            .accessibilityLabel(String(localized: "New", comment: "Accessibility label for the dot marking a newly added setting"))
    }
}
