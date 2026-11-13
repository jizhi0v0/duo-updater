import SwiftUI
import DuoUpdaterCore

extension RowOrder.SortOrder {
    /// The menu item's label. Kept out of Core: `RowOrder` decides the order and
    /// has no business knowing what this locale calls it.
    var title: String {
        switch self {
        case .name: return String(localized: "Name")
        case .recent: return String(localized: "Recent")
        }
    }
}

extension RowOrder.Grouping {
    var title: String {
        switch self {
        case .none: return String(localized: "None", comment: "Group by: the apps list as one list")
        case .source: return String(localized: "Update Source", comment: "Group by: one section per update source (Sparkle, App Store, Homebrew…)")
        }
    }
}

extension UpdateSourceGroup {
    /// A section's name in the grouped apps list. Product names stay as they
    /// are; the two that describe a kind of source are translated.
    var title: String {
        switch self {
        case .sparkle: return "Sparkle"
        case .gitHub: return "GitHub Releases"
        case .appFeed: return String(localized: "App Update Feed", comment: "Apps-list section: updates from the feed the app itself reads (Electron and similar)")
        case .vendor: return String(localized: "Developer’s Site", comment: "Apps-list section: updates read from the developer’s own website")
        case .homebrew: return "Homebrew"
        case .appStore: return "App Store"
        case .setapp: return "Setapp"
        case .testFlight: return "TestFlight"
        case .toolbox: return "JetBrains Toolbox"
        case .xcodeReleases: return "Xcode Releases"
        case .other: return String(localized: "Other", comment: "Apps-list section: apps with no update source that can be named")
        }
    }
}

/// The apps list's order control, shared by the popover's footer and the
/// workbench's toolbar so the two surfaces cannot offer different choices.
///
/// Icon-only because both places are already dense; the tooltip and the
/// accessibility label carry the word "Sort". The menu holds the *choice*, never
/// a status: status tiers (Relaunch, Update, up to date) stay in the list itself.
struct AppSortMenu: View {
    let prefs: Preferences
    /// The popover's footer is a row of `.caption`-sized icon buttons, and the
    /// arrows' glyph is taller than the round symbols beside it at any size. The
    /// toolbar draws the system's own control size instead. Without this split the
    /// popover's sort icon stood a head above the window icons.
    var compact = false

    private var selection: Binding<RowOrder.SortOrder> {
        Binding(
            get: { prefs.appSortOrder },
            set: { prefs.appSortOrder = $0 })
    }

    private var grouping: Binding<RowOrder.Grouping> {
        Binding(
            get: { prefs.appGrouping },
            set: { prefs.appGrouping = $0 })
    }

    var body: some View {
        // Two styles, because the two places need different drawings, not just
        // different sizes.
        //
        // `.borderlessButton` (the footer) draws its label as one fixed-size menu
        // image: `.font` on the label is ignored and the control looks like a bare
        // icon, which is what the row of icons beside it is.
        //
        // `.button` (the toolbar) draws the label the way a toolbar button draws
        // its symbol, so the size below is the size on screen — and it wraps the
        // control in a capsule of its own, which beside plain icons in the footer
        // read as a second, unrelated control.
        //
        // Neither can be reached through a ternary: `MenuStyle` is a protocol and
        // the two styles are different types, so the whole menu is built twice
        // through this generic helper. It is two dozen points of view either way;
        // `AnyView` here costs nothing measurable and keeps one copy of the
        // picker, the label and the accessibility wiring.
        if compact {
            AnyView(styled(.borderlessButton))
        } else {
            AnyView(styled(.button))
        }
    }

    /// The menu with one place's style and both places' wiring.
    private func styled<S: MenuStyle>(_ style: S) -> some View {
        Menu {
            Picker("Sort", selection: selection) {
                ForEach(RowOrder.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
            // A second choice in the same menu: grouping does not change the
            // order inside a section, so it is not another sort.
            Picker("Group By", selection: grouping) {
                ForEach(RowOrder.Grouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.inline)
        } label: {
            if compact {
                // The footer keeps a clear label with the symbol drawn over the
                // control: beside `.caption` text and 12–13 pt icons, AppKit's own
                // menu image stands a head above them. Layered on the control the
                // size below is the size on screen, which is how this row has
                // always been drawn.
                Color.clear.frame(width: 16, height: 16)
            } else {
                // The toolbar draws the label itself, the way it draws the
                // `gearshape` beside it. Measured there: this glyph's ink is
                // 16.9 × 13.8 pt to the gear's 15.5 × 15.5, and it drew 1 pt low
                // before this lift.
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .regular))
                    .offset(y: -0.5)
            }
        }
        .overlay {
            if compact {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    // The Menu owns the click; the icon must not sit in front of it.
                    .allowsHitTesting(false)
            }
        }
        .menuStyle(style)
        // No disclosure chevron. Both places it lives are rows of plain icon
        // buttons (the popover's footer, the workbench's toolbar), where a lone
        // chevron beside the arrows read as a second, unrelated control.
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort")
        .accessibilityLabel(Text("Sort"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        prefs.appGrouping == .none ? prefs.appSortOrder.title
            : "\(prefs.appSortOrder.title), \(prefs.appGrouping.title)"
    }
}
