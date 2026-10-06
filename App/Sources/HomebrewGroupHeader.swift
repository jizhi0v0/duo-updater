import SwiftUI

// The top of the CLI tab's Homebrew group, which is all of the group while it is
// closed (`HomebrewGroupState`). So it carries what the closed group would
// otherwise hide: how many packages there are and how many are outdated, a mark
// for packages Homebrew would not read (unchecked — no count can call them
// outdated or not), a mark for a Homebrew release waiting, and Upgrade All.
//
// Two lines, not one: the section header and a summary row under it. A sidebar
// section header is drawn at a fixed single-line height — a second line inside it
// was cut off top and bottom (rendered at 260 and 340 pt) — and the name, "212
// packages · 3 outdated", the two marks and Upgrade All did not fit on one line
// even at the sidebar's 340 pt maximum (rendered, English). The header keeps the
// name and Upgrade All, whose translations run to "Formeln aktualisieren"; the
// counts and the marks share the row beneath.
//
// Plain values in, not the model, so both can be drawn from fixtures.

/// The Homebrew group's section header: open/close, and Upgrade All. The
/// "Other tools" level above the tool groups wears the same one, with its own
/// title and Update All.
struct HomebrewGroupHeader<Trailing: View>: View {
    var title = "Homebrew"
    let expanded: Bool
    let toggleDisabled: Bool
    let toggle: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                    Text(verbatim: title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(toggleDisabled)
            .help(expanded ? String(localized: "Hide packages") : String(localized: "Show packages"))
            Spacer(minLength: 4)
            trailing()
        }
    }
}

/// The row under the Homebrew header: how many packages and how many outdated,
/// then the marks. A click on it opens or closes the group, like the header's name.
struct HomebrewGroupSummary: View {
    let packages: Int
    let outdated: Int
    let unchecked: Int
    /// The Homebrew release on offer (`HomebrewSelfUpdate.latest`), or nil.
    let homebrewUpdate: String?
    let toggleDisabled: Bool
    let toggle: () -> Void

    private var counts: String {
        let packages = String(localized: "\(packages) packages")
        guard outdated > 0 else { return packages }
        // " · ", the separator every row caption already uses, rather than a comma
        // that is wrong in Chinese and Japanese.
        return "\(packages) · \(String(localized: "\(outdated) outdated"))"
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(verbatim: counts)
                    .foregroundStyle(outdated > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // The marks are what a closed group hides that the counts do not say,
                // so they keep their room and the counts give way.
                marks.fixedSize()
                Spacer(minLength: 0)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(toggleDisabled)
    }

    private var marks: some View {
        HStack(spacing: 6) {
            if unchecked > 0 {
                let help = String(localized: "\(unchecked) packages not checked")
                Label {
                    Text(verbatim: "\(unchecked)")
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
                .help(help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(help)
            }
            if let homebrewUpdate {
                // The glyph alone, the version on hover: with it spelled out, the
                // Spanish counts beside it were cut at the 260 pt minimum (rendered).
                let help = String(localized: "Homebrew \(homebrewUpdate) is available")
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.tint)
                    .help(help)
                    .accessibilityLabel(help)
            }
        }
    }
}
