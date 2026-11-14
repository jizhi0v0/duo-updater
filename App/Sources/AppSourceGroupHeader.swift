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
    /// A search holds it open and disables toggling.
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
    /// A search holds the section open and disables toggling.
    let toggleDisabled: Bool
    let toggle: () -> Void

    @Environment(\.sidebarScrollToHeader) private var scrollToHeader
    @State private var pinned = false

    static func scrollID(_ group: UpdateSourceGroup) -> String { "app-source:\(group.rawValue)" }

    var body: some View {
        Button {
            if pinned { scrollToHeader(Self.scrollID(group)) }
            toggle()
        } label: {
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
        .sidebarGroupHeaderFrame()
        .onGeometryChange(for: Bool.self) {
            $0.frame(in: .named(SidebarSectionMetrics.coordinateSpace)).minY
                <= SidebarSectionMetrics.verticalPadding + 0.5
        } action: { pinned = $0 }
    }
}

/// A source heading, dividing rule and count in the popover's grouped list.
/// The stronger title and extra space above it distinguish each group.
/// Not a control: the popover's sections stay open.
struct PopoverSourceGroupHeader: View {
    let group: UpdateSourceGroup
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: group.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
            Text(verbatim: "\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
