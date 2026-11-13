import SwiftUI
import DuoUpdaterCore

/// One section of the apps list when it is grouped by update source
/// (`RowOrder.Grouping.source`). `group` is nil for the rows drawn above every
/// section without a header: the apps an interrupted install left gone, which
/// are the most urgent rows and have no source to be grouped by.
struct AppListSection: Equatable, Identifiable {
    let group: UpdateSourceGroup?
    let rows: [UpdateResult]
    /// Drawn open. Always true in the popover, which does not close sections.
    var expanded = true
    /// A search, or a selected row inside, holds it open.
    var toggleDisabled = false

    var id: String { group?.rawValue ?? "interrupted" }
    var updateCount: Int { rows.filter(\.hasUpdate).count }

    /// `rows` as the list draws them: the stand-ins first, without a header,
    /// then one section per update source when the list is grouped, or all of
    /// them as one headerless section when it is not.
    static func sections(
        _ rows: [UpdateResult], standIns: Set<String>, grouping: RowOrder.Grouping,
        group: (UpdateResult) -> UpdateSourceGroup
    ) -> [AppListSection] {
        guard grouping == .source else { return [AppListSection(group: nil, rows: rows)] }
        let interrupted = rows.filter { standIns.contains($0.id) }
        let rest = rows.filter { !standIns.contains($0.id) }
        let grouped = UpdateSourceGroup.sections(rest, group: group)
            .map { AppListSection(group: $0.group, rows: $0.rows) }
        return interrupted.isEmpty ? grouped : [AppListSection(group: nil, rows: interrupted)] + grouped
    }
}

/// The header of a section in the workbench's grouped apps list: open/close,
/// the source's name, how many apps and how many have an update.
struct AppSourceGroupHeader: View {
    let group: UpdateSourceGroup
    let count: Int
    let updates: Int
    let expanded: Bool
    /// A search, or a selected row inside, holds the section open.
    let toggleDisabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
                Text(verbatim: group.title)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if updates > 0 {
                    Text(String(localized: "\(updates) updates"))
                        .fontWeight(.regular)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                Text(verbatim: "\(count)")
                    .fontWeight(.regular)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(toggleDisabled)
        .help(expanded ? String(localized: "Hide apps") : String(localized: "Show apps"))
    }
}

/// The header of a section in the popover's grouped list: the source's name on
/// a hairline, and how many apps are under it. Not a control: the popover's
/// list is short and its sections stay open.
struct PopoverSourceGroupHeader: View {
    let group: UpdateSourceGroup
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: group.title)
                .fontWeight(.semibold)
                .lineLimit(1)
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
            Text(verbatim: "\(count)")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
