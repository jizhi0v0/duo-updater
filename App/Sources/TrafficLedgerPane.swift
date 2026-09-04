import SwiftUI
import AppKit
import DuoUpdaterCore

/// The download ledger: how much bandwidth keeping this machine up to date has
/// actually cost, which apps spent it, and on which version transitions.
///
/// Its own window, alongside the Release Log and What's New, because the data is
/// aggregate — a cross-app, cross-time account. It previously lived as a per-app
/// "lens" inside the workbench detail pane, which meant you had to pick an app
/// before you could see anything, and then only saw that app's raw byte counts.
/// The questions people actually ask ("what did updates cost me", "which app is
/// the hog", "more or less than last month") all need the whole set at once.
struct TrafficWindowView: View {
    static let windowID = "traffic"

    @Bindable var model: AppListModel

    /// How the ranked list is ordered. Size first: "which app is the hog" is the
    /// question the window exists to answer.
    private enum Sort: String, CaseIterable, Identifiable {
        case size, downloads, recent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .size:      return String(localized: "Size")
            case .downloads: return String(localized: "Downloads")
            case .recent:    return String(localized: "Recent")
            }
        }
    }
    @State private var sort: Sort = .size
    /// App ids whose event history is expanded. A set rather than a single
    /// selection so several apps can be compared side by side.
    @State private var expanded: Set<String> = []
    @State private var showRemoved = false

    var body: some View {
        VStack(spacing: 0) {
            if model.trafficSummary.downloadCount == 0 {
                emptyState
            } else {
                header
                Divider()
                toolbar
                Divider()
                ledger
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        // An app deleted or renamed since the last recorded download moves between
        // the present and removed groups. Nothing else re-reads the log, so without
        // this the split would only refresh after the next install.
        .task { await model.reloadTrafficStats() }
    }

    // MARK: - Header

    private var summary: TrafficSummary { model.trafficSummary }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            statStrip
            sourceBar
            caveat
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Grand total and the trailing months, laid out as equal columns. Equal widths
    /// rather than a headline-left/months-right split: with only a short total on
    /// the left, pushing the months to the far edge leaves a hole down the middle
    /// that grows with the window.
    private var statStrip: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ByteFormat.string(summary.totalBytes))
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The store counts to the byte; the rounded headline would
                    // otherwise be the only figure anywhere and quietly drop that.
                    .help("\(summary.totalBytes) bytes")
                Text(totalCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 175, maxWidth: .infinity, alignment: .leading)

            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                // Safe positionally only because `calendarMonths` guarantees the
                // window is gap-free and ends on the current month.
                monthCell(month, previous: index > 0 ? months[index - 1] : nil,
                          isCurrent: index == months.count - 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Real calendar months, zero-filled — not `summary.months`, which skips
    /// quiet months and would put "This month" on an older column.
    private var months: [TrafficMonth] { summary.calendarMonths(3) }

    private var totalCaption: String {
        let downloads = String(localized: "\(summary.downloadCount) downloads")
        let apps = String(localized: "\(summary.appCount) apps")
        guard let first = summary.firstDownload else { return "\(downloads) · \(apps)" }
        let since = String(localized: "since \(Self.monthYear.string(from: first))")
        return "\(downloads) · \(apps) · \(since)"
    }

    @ViewBuilder
    private func monthCell(_ month: TrafficMonth, previous: TrafficMonth?, isCurrent: Bool)
        -> some View
    {
        HStack(spacing: 0) {
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrent
                     ? String(localized: "This month")
                     : Self.monthName.string(from: month.start).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    // ByteCountFormatter renders 0 as "Zero KB", which reads as a
                    // unit error rather than as "nothing yet"; the count below says
                    // the same thing properly.
                    Text(month.bytes > 0 ? ByteFormat.string(month.bytes) : "—")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if let previous, previous.bytes > 0 {
                        delta(from: previous.bytes, to: month.bytes)
                    }
                }
                Text(String(localized: "\(month.count) downloads"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.leading, 12)
        }
    }

    private func delta(from old: Int64, to new: Int64) -> some View {
        let percent = Int((Double(new - old) / Double(old) * 100).rounded())
        let down = percent < 0
        return Text("\(down ? "▼" : "▲")\(abs(percent))%")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(down ? Color.secondary : Color.orange)
    }

    /// One stacked bar plus its legend. Reads as a whole-to-part split, which is
    /// what "where did the bytes come from" is.
    private var sourceBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(summary.sources) { source in
                        Rectangle()
                            .fill(Self.color(forSource: source.sourceName))
                            .frame(width: max(1, geo.size.width * fraction(source.bytes)))
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            // Wraps to a second line on a narrow window rather than truncating a
            // source away — every source has to stay visible for the split to add up.
            FlowLayout(spacing: 16) {
                ForEach(summary.sources) { source in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Self.color(forSource: source.sourceName))
                            .frame(width: 7, height: 7)
                        Text(source.sourceName).font(.caption)
                        Text(ByteFormat.string(source.bytes))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                        Text("\(source.count)×")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private func fraction(_ bytes: Int64) -> Double {
        summary.totalBytes > 0 ? Double(bytes) / Double(summary.totalBytes) : 0
    }

    /// Permanent, not just an empty-state note. Homebrew, the App Store, and apps
    /// that update through their own updater fetch their own bytes, so this total
    /// is a lower bound — and the moment it most misleads is exactly when there IS
    /// a big number above it.
    private var caveat: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Counts only what Duo Updater downloaded itself. Homebrew, the App Store, and apps with their own built-in updater fetch their own bytes, so this total is a lower bound.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("Sort", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text("\(model.trafficPresent.count) apps · \(ByteFormat.string(presentBytes))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }

    private var presentBytes: Int64 {
        model.trafficPresent.reduce(0) { $0 + $1.totalBytes }
    }

    // MARK: - Ledger

    private var ledger: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let present = sorted(model.trafficPresent)
                ForEach(Array(present.enumerated()), id: \.element.id) { index, stat in
                    TrafficRow(stat: stat, maxBytes: maxBytes,
                               isExpanded: expanded.contains(stat.id),
                               isRemoved: false,
                               toggle: { toggle(stat.id) })
                    // Between rows only — a trailing rule would dangle under the
                    // last row whenever there is no removed group beneath it.
                    if index < present.count - 1 { Divider() }
                }
                if !model.trafficRemoved.isEmpty {
                    // The group header carries only a background tint, so the rule
                    // that separates it from the list has to be drawn here.
                    Divider()
                    removedGroup
                }
            }
        }
    }

    /// Scale the proportion bars against the heaviest app in the *whole* log, not
    /// the heaviest in the current group — otherwise the removed group's bars
    /// would re-normalise and read as if those apps were the biggest spenders.
    private var maxBytes: Int64 {
        max(model.trafficStats.map(\.totalBytes).max() ?? 0, 1)
    }

    private func sorted(_ stats: [AppTrafficStat]) -> [AppTrafficStat] {
        switch sort {
        case .size:
            return stats.sorted { $0.totalBytes > $1.totalBytes }
        case .downloads:
            return stats.sorted {
                $0.updateCount != $1.updateCount
                    ? $0.updateCount > $1.updateCount
                    : $0.totalBytes > $1.totalBytes
            }
        case .recent:
            return stats.sorted {
                ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast)
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Entries recorded against a path that no longer resolves. Kept — they are
    /// real measured traffic and still count toward the total — but grouped away,
    /// because next to the app's current entry they read as a duplicate rather
    /// than as history.
    @ViewBuilder
    private var removedGroup: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showRemoved.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showRemoved ? 90 : 0))
                Text("Removed").font(.caption.weight(.semibold))
                Text("\(model.trafficRemoved.count) entries whose app is no longer at that path — history kept")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(ByteFormat.string(removedBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))

        if showRemoved {
            ForEach(sorted(model.trafficRemoved)) { stat in
                Divider()
                TrafficRow(stat: stat, maxBytes: maxBytes,
                           isExpanded: expanded.contains(stat.id),
                           isRemoved: true,
                           toggle: { toggle(stat.id) })
            }
        }
    }

    private var removedBytes: Int64 {
        model.trafficRemoved.reduce(0) { $0 + $1.totalBytes }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No downloads measured", systemImage: "chart.bar")
        } description: {
            Text("Traffic appears here after an update we download ourselves (Sparkle, a vendor site, GitHub, or a pkg). Homebrew, the App Store, and apps that update through their own built-in updater aren’t measured.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared formatting

    static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMy")
        return f
    }()

    /// Source colours, keyed by name so a source keeps its colour as the ranking
    /// shifts. An unrecognised source falls back to grey rather than borrowing a
    /// known source's colour.
    static func color(forSource name: String) -> Color {
        switch name {
        case "Vendor":  return .teal
        case "GitHub":  return .purple
        case "Sparkle": return .orange
        case "pkg":     return .indigo
        default:        return .secondary
        }
    }
}

// MARK: - One app's row

private struct TrafficRow: View {
    let stat: AppTrafficStat
    let maxBytes: Int64
    let isExpanded: Bool
    let isRemoved: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 9)
                    Image(nsImage: AppIconCache.icon(for: stat.appID))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(stat.appName).font(.system(size: 13)).lineLimit(1)
                            if isRemoved {
                                Text(stat.appID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        proportionBar
                    }
                    Text(ByteFormat.string(stat.totalBytes))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                        .help("\(stat.totalBytes) bytes")
                    Text("\(stat.updateCount)×")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                    Text(lastUpdatedText)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isRemoved ? 0.62 : 1)

            if isExpanded { events }
        }
    }

    private var proportionBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .separatorColor).opacity(0.5))
                Capsule()
                    .fill(isRemoved ? Color.secondary : Color.accentColor)
                    .frame(width: max(2, geo.size.width
                        * Double(stat.totalBytes) / Double(max(maxBytes, 1))))
            }
        }
        .frame(height: 3)
    }

    private var lastUpdatedText: String {
        guard let date = stat.lastUpdated else { return "—" }
        return Self.dayMonth.string(from: date)
    }

    /// Newest first — the same order the old per-app pane used, and the order you
    /// read a ledger in.
    private var events: some View {
        // Enumerated rather than keyed on the event itself: two downloads of the
        // same size for the same version transition are equal values, and would
        // collide as ForEach ids.
        let ordered = Array(stat.events.sorted { $0.date > $1.date }.enumerated())
        return VStack(spacing: 0) {
            ForEach(ordered, id: \.offset) { index, event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(versionTransition(event))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Real bytes for no change. Only ever shown when both builds
                    // were recorded, so it never guesses at an older event.
                    if event.changedNothing {
                        Text("no change")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let source = event.sourceName {
                        Text(source)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TrafficWindowView.color(forSource: source))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(TrafficWindowView.color(forSource: source).opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let evidence = stat.deltaEvidence(for: event) {
                        Text("Delta")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .help(deltaHelp(evidence))
                    }
                    Text(Self.eventStamp.string(from: event.date))
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 108, alignment: .trailing)
                    Text(ByteFormat.string(event.bytes))
                        .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                        .help("\(event.bytes) bytes")
                }
                .padding(.leading, 63)
                .padding(.trailing, 20)
                .padding(.vertical, 3)
                // Between events only. A rule after the last one lands right above
                // the next app's full-width divider and reads as a double line.
                if index < ordered.count - 1 {
                    Divider().padding(.leading, 63)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func versionTransition(_ event: TrafficEvent) -> String {
        // versionSides folds the build numbers in when the marketing versions are
        // identical, which is the only case where they carry the change.
        switch event.versionSides {
        case let (from?, to?): return String(localized: "\(from) → \(to)")
        case let (nil, to?):   return to
        case let (from?, nil): return from
        case (nil, nil):       return String(localized: "Update")
        }
    }

    private func deltaHelp(_ evidence: AppTrafficStat.DeltaEvidence) -> String {
        switch evidence {
        case .recorded:
            return String(localized: "This update used a Sparkle delta patch.")
        case .inferred:
            return String(localized: "Likely a delta update based on its much smaller download. This event predates delta-route tracking.")
        }
    }

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    private static let eventStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Legend layout

/// A row that wraps. Used for the source legend so a narrow window pushes the last
/// source onto a second line instead of clipping it away — the split has to stay
/// fully visible to be checkable against the total.
///
/// Shared with the workbench's Network Activity panel, whose purpose legend has
/// the same requirement for the same reason; hence not `private`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
