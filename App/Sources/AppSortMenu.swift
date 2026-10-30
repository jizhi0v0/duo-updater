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

    var body: some View {
        Menu {
            Picker("Sort", selection: selection) {
                ForEach(RowOrder.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // A clear label, not the image. A borderless `Menu`'s label is drawn
            // by AppKit as a fixed-size menu image: `.font`, `.imageScale` and even
            // `.foregroundStyle` on an `Image` inside it are ignored, so the arrows
            // stood taller and brighter than the `.caption` text and icons around
            // them. Drawing the symbol ourselves as an overlay is the only way to
            // give it the footer's type size and secondary colour.
            Color.clear
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
        }
        .menuStyle(.borderlessButton)
        // No disclosure chevron. Both places it lives are rows of plain icon
        // buttons (the popover's footer, the workbench's toolbar), where a lone
        // chevron beside the arrows read as a second, unrelated control.
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay {
            Image(systemName: "arrow.up.arrow.down")
                // Measured against the footer: `.caption` text is 13 pt tall, and
                // this symbol at 10.5 pt draws 16 × 12 pt — the same band as the
                // clock/network/window icons beside it (12–13 pt). At the menu's
                // default size it drew 15 pt and stood above them.
                .font(.system(size: compact ? 10.5 : 13, weight: .regular))
                .foregroundStyle(.secondary)
                // The Menu owns the click; the icon must not sit in front of it.
                .allowsHitTesting(false)
        }
        .help("Sort")
        .accessibilityLabel(Text("Sort"))
        .accessibilityValue(Text(prefs.appSortOrder.title))
    }
}
