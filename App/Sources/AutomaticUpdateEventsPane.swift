import SwiftUI
import DuoUpdaterCore

struct AutomaticUpdateEventsPane: View {
    @State private var events: [DuoEvent] = []
    @State private var confirmsClear = false
    @State private var report: String?
    @State private var exportError: String?
    /// Rows whose diagnostics are open. Kept here, not in the row: a lazy stack
    /// drops rows scrolled out of view, and their state with them.
    @State private var expanded: Set<String> = []
    /// The outcome picked in the summary bar; nil shows every row.
    @State private var filter: AttemptStatus?

    var body: some View {
        let allRows = AutomaticUpdateActivity.rows(from: events)
        // A filter whose outcome is no longer listed (cleared, or aged out)
        // shows everything rather than an empty list.
        let active = filter.flatMap { f in allRows.contains { AttemptStatus($0.status) == f } ? f : nil }
        let rows = active.map { f in allRows.filter { AttemptStatus($0.status) == f } } ?? allRows
        let days = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.last) }
            .sorted { $0.key > $1.key }
        // A stack, not a List: the table under a List kept a row's old height
        // when its diagnostics opened or closed — squeezing the row, then
        // leaving a blank gap — until the next scroll re-measured it.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(days, id: \.key) { day, rows in
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().padding(.leading, 44) }
                            ActivityRow(row: row, expanded: Binding(
                                get: { expanded.contains(row.id) },
                                set: { if $0 { expanded.insert(row.id) } else { expanded.remove(row.id) } }))
                        }
                    } header: {
                        Text(DayLabel.string(for: day))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12).padding(.bottom, 4)
                            .background(.background)
                    }
                }
            }
            .padding(.horizontal, NetworkPaneMetrics.gutter)
            .padding(.bottom, 12)
        }
        .background(.background)
        .overlay {
            if allRows.isEmpty {
                ContentUnavailableView("No automatic update activity yet.", systemImage: "clock.arrow.circlepath")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !allRows.isEmpty { SummaryBar(rows: allRows, filter: active) { filter = $0 } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("Activity is kept for 90 days, up to 10,000 records. Showing the latest 200.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Review sanitized report…") {
                    report = AutomaticUpdateDiagnostics.sanitizedReport(events)
                }
                Button("Clear activity…") { confirmsClear = true }
            }
            .padding(.horizontal, NetworkPaneMetrics.gutter)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review sanitized report").font(.headline)
                Text("Contains aggregate outcomes and process probe results from the displayed records. App names, paths, process IDs and activity times are omitted. Nothing is sent automatically.")
                ScrollView { Text(report ?? "").font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if let exportError { Text(exportError).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { report = nil }
                    Button("Save report…") { saveReport() }
                }
            }.padding().frame(width: 650, height: 480)
        }
        .confirmationDialog("Clear automatic update activity?", isPresented: $confirmsClear) {
            Button("Clear activity", role: .destructive) {
                Task {
                    await EventStore.shared.resetAutomaticUpdates()
                    events = await EventStore.shared.events(.init(kind: "automaticUpdate", limit: 200))
                }
            }
        } message: {
            Text("Request logs and permanent install history will be kept.")
        }
        .task {
            while !Task.isCancelled {
                events = await EventStore.shared.events(.init(kind: "automaticUpdate", limit: 200))
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private func saveReport() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "automatic-update-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
            self.report = nil
        } catch { exportError = error.localizedDescription }
    }
}

/// "Today", "Yesterday", then the date, in the reader's language.
private enum DayLabel {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func string(for day: Date) -> String { formatter.string(from: day) }
}

/// One tile per outcome, counting attempts rather than rows.
private struct SummaryBar: View {
    let rows: [AutomaticUpdateActivity]
    /// The outcome the list is narrowed to, if any.
    let filter: AttemptStatus?
    let select: (AttemptStatus?) -> Void

    var body: some View {
        let counts = Dictionary(grouping: rows) { AttemptStatus($0.status) }
            .mapValues { $0.reduce(0) { $0 + $1.count } }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(AttemptStatus.allCases, id: \.self) { status in
                    let count = counts[status] ?? 0
                    if count > 0 || status != .started {
                        tile(status, count: count)
                    }
                }
                Spacer(minLength: 0)
            }
            if counts[.deferred, default: 0] > 0 {
                Label("Deferral is temporary. Eligible updates are reconsidered on a later scheduled pass; other work or network restrictions may delay it.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, NetworkPaneMetrics.gutter)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// A tile is a toggle: click to show only that outcome, again to show all.
    private func tile(_ status: AttemptStatus, count: Int) -> some View {
        let selected = filter == status
        let dimmed = filter != nil && !selected
        return Button {
            select(selected ? nil : status)
        } label: {
            tileLabel(status, count: count, selected: selected)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(dimmed ? 0.55 : 1)
        .help(selected ? String(localized: "Show all") : status.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tileLabel(_ status: AttemptStatus, count: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbol)
                .font(.title2)
                .foregroundStyle(count > 0 ? status.tint : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(count, format: .number)
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text(status.shortLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 120, alignment: .leading)
        .background((count > 0 ? status.tint : Color.secondary).opacity(selected ? 0.22 : 0.1),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(status.tint, lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One attempt, or an unbroken run of identical ones.
private struct ActivityRow: View {
    let row: AutomaticUpdateActivity
    @Binding var expanded: Bool

    private var fields: [String: String] { row.fields }
    private var status: AttemptStatus { AttemptStatus(row.status) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIcon(path: fields["appID"])
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: status.badgeSymbol)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(status.tint, in: Circle())
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
                // On the icon only: on the row, every child inherited it, so
                // hovering the diagnostics button showed a box of IDs.
                .help(details)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fields["appName"] ?? "").font(.body.weight(.semibold))
                    versions
                    Spacer(minLength: 12)
                    if row.count > 1 {
                        Text(verbatim: "×\(row.count)")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(status.tint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(status.tint.opacity(0.15), in: Capsule())
                    }
                    time.foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(status.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(status.tint.opacity(0.15), in: Capsule())
                        .help(status.label)
                    if let reason = fields["reason"], !reason.isEmpty {
                        Text(AutomaticUpdateReasonText.display(reason))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if fields["recoveredFrom"]?.isEmpty == false {
                    Label("A later attempt recovered and installed the update.", systemImage: "arrow.uturn.forward")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !row.diagnostics.isEmpty || row.undecodedDiagnostics != nil {
                    DiagnosticsDisclosure(row: row, expanded: $expanded)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy attempt details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(details, forType: .string)
            }
            .disabled(details.isEmpty)
        }
    }

    @ViewBuilder private var versions: some View {
        let from = fields["fromVersion"] ?? "", to = fields["toVersion"] ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !from.isEmpty {
                Text(from).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(to).fontWeight(.medium)
        }
        .monospacedDigit().lineLimit(1)
    }

    @ViewBuilder private var time: some View {
        if row.count > 1, row.first < row.last {
            Text((row.first..<row.last).formatted(.interval.hour().minute()))
        } else {
            Text(row.last, format: .dateTime.hour().minute())
        }
    }

    /// Correlation IDs: useful when reading a report, noise in the list.
    private var details: String {
        var lines: [String] = []
        if let pass = fields["passID"] { lines.append(String(localized: "Pass: \(pass)")) }
        if let id = fields["attemptID"] { lines.append(String(localized: "Attempt: \(id)")) }
        if let retry = fields["retryOf"], !retry.isEmpty { lines.append(String(localized: "Previous attempt: \(retry)")) }
        if let ids = fields["diagnosticIDs"], !ids.isEmpty { lines.append(String(localized: "Diagnostics: \(ids)")) }
        return lines.joined(separator: "\n")
    }
}

/// The blockers the latest attempt recorded, one readable entry each.
///
/// A plain button rather than a DisclosureGroup: inside a list row the group's
/// label lost its clicks, so it looked expandable and never opened.
private struct DiagnosticsDisclosure: View {
    let row: AutomaticUpdateActivity
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                // No animation: the stack resizes the row in one step.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    // Swapped, not rotated: an animated rotation also animated the
                    // chevron's position while the row resized, so it jumped onto
                    // the line above and slid back.
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text("Local process diagnostics (\(row.diagnostics.count))")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)

            if expanded {
                let running = row.diagnostics.filter { $0.diagnostic.kind == .targetRunning }
                VStack(alignment: .leading, spacing: 8) {
                    if !running.isEmpty { RunningProcessList(entries: running) }
                    ForEach(row.diagnostics.filter { $0.diagnostic.kind != .targetRunning }, id: \.id) { entry($0) }
                    if let raw = row.undecodedDiagnostics {
                        Text(raw).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textSelection(.enabled)
            }
        }
    }

    private func entry(_ entry: AutomaticUpdateDiagnostics.Entry) -> some View {
        let d = entry.diagnostic
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gearshape").foregroundStyle(.tertiary)
                if let name = d.processName, !name.isEmpty {
                    Text(name).fontWeight(.medium)
                    Text(Self.label(d.kind)).foregroundStyle(.secondary)
                } else {
                    Text(Self.label(d.kind)).fontWeight(.medium)
                }
                if entry.occurrences > 1 {
                    Text(verbatim: "×\(entry.occurrences)").foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Group {
                    if entry.first < entry.last {
                        Text((entry.first..<entry.last).formatted(.interval.hour().minute().second()))
                    } else {
                        Text(entry.first, format: .dateTime.hour().minute().second())
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            Group {
                let ids = [d.pid.map { "PID \($0)" }, d.parentPID.map { "PPID \($0)" },
                           d.lifecycleState.map { "pbi_status \($0)" }].compactMap { $0 }
                if !ids.isEmpty { Text(verbatim: ids.joined(separator: " · ")) }
                ForEach(Array(d.probes.enumerated()), id: \.offset) { _, probe in
                    Text(verbatim: Self.describe(probe))
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.leading, 22)
        }
    }

    /// `pidPath = 0, errno 2 (No such file or directory)`: the probe as the
    /// kernel answered it, which is what a bug report needs.
    static func describe(_ probe: AutomaticProcessDiagnostic.Probe) -> String {
        var text = "\(probe.name.rawValue) = \(probe.result)"
        if probe.error != 0 {
            text += ", errno \(probe.error) (\(String(cString: strerror(probe.error))))"
        }
        return text
    }

    static func label(_ kind: AutomaticProcessDiagnostic.Kind) -> String {
        switch kind {
        case .targetRunning: String(localized: "App process running")
        case .zombie: String(localized: "Zombie process")
        case .exited: String(localized: "Process exited")
        case .permissionDenied: String(localized: "Permission denied")
        case .executablePathUnavailable: String(localized: "Executable path unavailable")
        case .unresolvedIdentity: String(localized: "Unidentified process")
        case .enumerationFailed: String(localized: "Process list unavailable")
        case .enumerationTruncated: String(localized: "Process list incomplete")
        }
    }
}

/// The app's processes that were running, one line per executable: what it
/// is, how many copies, since when. Path and parent are in the tooltip.
private struct RunningProcessList: View {
    let entries: [AutomaticUpdateDiagnostics.Entry]

    private struct Executable: Identifiable {
        let id: String
        let name: String?
        let path: String?
        var processes: [AutomaticProcessDiagnostic]
        var started: Date? { processes.compactMap(\.startedAt).min() }
    }

    /// Same executable, one group; the earliest-started first, which puts the
    /// main process ahead of the helpers it launched.
    private var groups: [Executable] {
        var groups: [Executable] = []
        for d in entries.map(\.diagnostic) {
            let key = (d.processName ?? "") + "\u{0}" + (d.bundlePath ?? "")
            if let i = groups.firstIndex(where: { $0.id == key }) {
                groups[i].processes.append(d)
            } else {
                groups.append(Executable(id: key, name: d.processName, path: d.bundlePath, processes: [d]))
            }
        }
        return groups.enumerated().sorted { a, b in
            switch (a.element.started, b.element.started) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }

    var body: some View {
        let first = entries.map(\.first).min() ?? Date()
        let last = entries.map(\.last).max() ?? first
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gearshape").foregroundStyle(.tertiary)
                Text("App process running").fontWeight(.medium)
                Spacer(minLength: 8)
                Group {
                    if first < last {
                        Text((first..<last).formatted(.interval.hour().minute().second()))
                    } else {
                        Text(first, format: .dateTime.hour().minute().second())
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(groups) { group in
                    GridRow {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(group.name ?? String(localized: "Name not recorded"))
                                .foregroundStyle(group.name == nil ? .secondary : .primary)
                                .lineLimit(1).truncationMode(.middle)
                            if group.processes.count > 1 {
                                Text(verbatim: "×\(group.processes.count)")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Never empty: an empty Text has no baseline, and the
                        // row, aligned on baselines, rode up over the header.
                        Text(verbatim: group.started.map { since($0, detected: last) } ?? "–")
                            .foregroundStyle(group.started == nil ? .tertiary : .secondary)
                        Text(verbatim: "PID " + group.processes.compactMap(\.pid).map(String.init).joined(separator: ", "))
                            .font(.caption.monospaced()).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.tail)
                            .gridColumnAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    .help(details(group))
                }
            }
            .padding(.leading, 22)
        }
    }

    /// "since 2:44 pm"; the date too when it started on another day.
    private func since(_ start: Date, detected: Date) -> String {
        let text = Calendar.current.isDate(start, inSameDayAs: detected)
            ? start.formatted(date: .omitted, time: .shortened)
            : start.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "since \(text)")
    }

    private func details(_ group: Executable) -> String {
        var lines: [String] = []
        if let path = group.path, !path.isEmpty { lines.append(path) }
        for d in group.processes {
            var parts = [d.pid.map { "PID \($0)" }]
            // The PID as text: interpolated as a number it gets a grouping separator.
            parts.append(d.parentPID.map { pid in
                d.parentName.map { String(localized: "parent \($0) (\(String(pid)))") } ?? "PPID \(pid)"
            })
            parts.append(d.startedAt.map {
                String(localized: "Running since \($0.formatted(date: .abbreviated, time: .shortened))")
            })
            lines.append(parts.compactMap { $0 }.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }
}

/// The installed copy's Finder icon; a generic app icon once it is gone.
private struct AppIcon: View {
    let path: String?
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high).frame(width: 32, height: 32)
    }

    private var image: NSImage {
        guard let path, path.hasPrefix("/") else { return NSWorkspace.shared.icon(for: .application) }
        if let cached = Self.cache.object(forKey: path as NSString) { return cached }
        let icon = FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path) : NSWorkspace.shared.icon(for: .application)
        Self.cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

private enum AttemptStatus: CaseIterable {
    case installed, deferred, failed, started

    init(_ raw: String?) {
        switch raw {
        case "installed": self = .installed
        case "started": self = .started
        case "deferred": self = .deferred
        default: self = .failed
        }
    }

    var label: String {
        switch self {
        case .started: String(localized: "Automatic update started")
        case .installed: String(localized: "Automatically updated")
        case .deferred: String(localized: "Automatic update deferred")
        case .failed: String(localized: "Automatic update did not complete")
        }
    }

    var shortLabel: String {
        switch self {
        case .started: String(localized: "Installing")
        case .installed: String(localized: "Updated")
        case .deferred: String(localized: "Deferred")
        case .failed: String(localized: "Did not complete")
        }
    }

    var symbol: String {
        switch self {
        case .installed: "checkmark.circle.fill"
        case .started: "arrow.down.circle.fill"
        case .deferred: "clock.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .installed: "checkmark"
        case .started: "arrow.down"
        case .deferred: "clock"
        case .failed: "exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .installed: .green
        case .started: .blue
        case .deferred: .orange
        case .failed: .red
        }
    }
}
