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
///
/// As tall as its button whether or not the button is there: the button goes
/// once nothing is left on offer, and the header shrank to its title, moving
/// every row below 6 pt up as the last update ended (the user's recording of a
/// workbench Helm update, 2026-10-20: "Other tools" y 28 → 21 px, its first
/// row 142 → 130 px at 2x).
struct HomebrewGroupHeader<Trailing: View>: View {
    var title = "Homebrew"
    let scrollID: String
    let isFixed: Bool
    let expanded: Bool
    let toggleDisabled: Bool
    let toggle: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.sidebarScrollToHeader) private var scrollToHeader
    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isFixed { scrollToHeader(scrollID) }
                toggle()
            } label: {
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

/// The row under the Homebrew header: counts and their supporting details.
struct HomebrewGroupSummary: View {
    let packages: Int
    let outdated: Int
    let batchUpdates: Int
    let unlistedUpdates: Int
    let uncheckedDetails: [String]
    /// Why the last Upgrade All failed (`AppListModel.brewUpgradeError`), or nil.
    let upgradeError: String?
    /// The Homebrew release on offer (`HomebrewSelfUpdate.latest`), or nil.
    let homebrewUpdate: String?
    var readError: String? = nil
    var retry: () -> Void = {}

    private var counts: String {
        let packages = String(localized: "\(packages) packages")
        guard outdated > 0 else { return packages }
        // " · ", the separator every row caption already uses, rather than a comma
        // that is wrong in Chinese and Japanese.
        return "\(packages) · \(String(localized: "\(outdated) outdated"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            countsRow
            if let readError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SummaryDetailButton(details: readError) {
                        Label(String(localized: "Check failed — showing last results"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button("Retry", action: retry)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .help(String(localized: "Retry Homebrew check"))
                }
                .font(.caption)
            }
        }
    }

    private var countsRow: some View {
        HStack(spacing: 8) {
            if let upgradeError {
                SummaryDetailButton(details: upgradeError) {
                    Text(verbatim: upgradeError).foregroundStyle(.red).lineLimit(1)
                }
            } else if unlistedUpdates > 0 || batchUpdates != outdated {
                SummaryDetailButton(details: batchDetails) {
                    HStack(spacing: 4) {
                        countsLabel
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                }
            } else {
                countsLabel
            }
            marks.fixedSize()
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private var countsLabel: some View {
        Text(verbatim: counts)
            .foregroundStyle(outdated > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    static func batchUpdateLines(updates: Int, unlisted: Int) -> [String] {
        let summary = String(localized: "Upgrade All") + " · " + String(localized: "\(updates) updates")
        return unlisted > 0 ? [summary, String(localized: "\(unlisted) unlisted updates")] : [summary]
    }

    private var batchDetails: String {
        var lines = Self.batchUpdateLines(updates: batchUpdates, unlisted: unlistedUpdates)
        if unlistedUpdates > 0 {
            lines.append(String(localized: "Homebrew can also upgrade packages such as dependencies that have no row in this list."))
        }
        if outdated > batchUpdates - unlistedUpdates {
            lines.append(String(localized: "Some listed updates aren’t eligible for Upgrade All."))
        }
        return lines.joined(separator: "\n")
    }

    private var marks: some View {
        HStack(spacing: 6) {
            if !uncheckedDetails.isEmpty {
                let count = uncheckedDetails.count
                SummaryDetailButton(details: uncheckedDetails.joined(separator: "\n\n")) {
                    Label {
                        Text(verbatim: "\(count)")
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                }
                .accessibilityLabel(String(localized: "\(count) packages not checked"))
            }
            if let homebrewUpdate {
                // The glyph alone, the version on hover: with it spelled out, the
                // Spanish counts beside it were cut at the 260 pt minimum (rendered).
                let help = String(localized: "Homebrew \(homebrewUpdate) is available")
                SummaryDetailButton(details: help) {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tint)
                }
                .accessibilityLabel(help)
            }
        }
    }
}
