import SwiftUI
import DuoUpdaterCore

/// What Duo Updater itself put on the network: which hosts, what for, and what
/// it cost.
///
/// The other half of the accounting the Traffic window shows. That one counts
/// the installer bytes you asked for; this one counts what the updater spends on
/// its own — version checks against every watched app on a timer, changelog
/// fetches, the Homebrew catalog, its own self-update. A background updater is a
/// plausible candidate for the heaviest network consumer on a machine, so it
/// owes the person running it an answer.
///
/// Every figure here comes off ``NetworkActivitySummary``. Nothing is decided in
/// this file: `App/Sources` has no test target, so a rule written into a `body`
/// is a rule nothing executes.
/// Takes the summary as a value and its two actions as closures rather than
/// taking `AppListModel`. Not tidiness: `AppListModel.init` registers for
/// notification authorisation, starts timers and installs a filesystem watcher,
/// so a harness that wanted to render this could not construct one cheaply — and
/// a pane nothing can render offline is a pane nobody looks at until it ships.
/// Same reason `PopoverRowAction` takes `RowActions` closures.
struct NetworkActivityPane: View {
    /// The sidebar tag that selects this pane. A reserved id rather than an app's,
    /// matching how the Brew formula rows address their own detail pane.
    static let selectionID = "network:activity"

    let summary: NetworkActivitySummary
    /// Forces the request list open. Only the offline renderer passes it — read
    /// alongside the `@State` rather than seeding it, because `.task` does not run
    /// when the renderer draws ``sections`` on its own, and a flag applied there
    /// produced an "expanded" image byte-identical to the collapsed one.
    var showRecent = false

    private var isShowingRecent: Bool { showingRecent || showRecent }
    var onAppear: (() async -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil

    @State private var showingRecent = false
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if summary.isEmpty {
                emptyState
            } else {
                ScrollView { sections }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await onAppear?() }
    }

    /// Everything below the header, as one stack.
    ///
    /// Split out of `body` rather than inlined so an offline renderer can draw it:
    /// `ImageRenderer` lays out nothing inside a `ScrollView`, and a pane that can
    /// only be looked at by shipping it is a pane nobody looks at. Internal, not
    /// private, for the same reason.
    var sections: some View {
        VStack(alignment: .leading, spacing: 18) {
            statStrip
            purposeBar
            hostTable
            recentSection
            footprint
        }
        .padding(20)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Network Activity")
                    .font(.headline)
                Text("What Duo Updater fetched for itself")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            Button {
                onRefresh?()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Re-read the event store")
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Image(systemName: "trash")
            }
            .help("Discard every recorded event and total")
            .disabled(summary.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .confirmationDialog(
            "Discard the recorded network history?",
            isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { onReset?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The running totals go too, so the figures start again from zero.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing recorded yet",
            systemImage: "network.slash",
            description: Text("Duo Updater logs the requests it makes on your behalf here — update checks, release notes, and its own downloads."))
    }

    // MARK: - Headline figures

    private var statStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ByteFormat.string(summary.bytesReceived))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The store counts to the byte; the rounded headline would
                    // otherwise be the only figure anywhere and quietly drop that.
                    .help(String(localized: "\(summary.bytesReceived) bytes received, \(summary.bytesSent) sent"))
                Text(totalCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Takes what it needs before the three cells divide the rest: as an
            // equal fourth share it got ~190pt and broke its caption between
            // "since" and the month.
            .frame(minWidth: 230, alignment: .leading)
            .layoutPriority(1)

            // The three ways a request costs much less than it looks. Spelled out
            // rather than folded into the request count, because a total that
            // hides them makes revalidating look as expensive as re-downloading.
            cheapCell(String(localized: "Revalidated"), summary.notModified,
                      help: String(localized: "Answered 304 — asked, and only headers came back."))
            cheapCell(String(localized: "From cache"), summary.cached,
                      help: String(localized: "Answered locally. Nothing crossed the network."))
            cheapCell(String(localized: "Failed"), summary.failures,
                      help: String(localized: "No answer at all — a transport error or a cancellation."))
        }
    }

    /// Three clauses, not four. A fourth ("1.1 MB sent") pushed the line to two
    /// rows and broke it between the number and its unit; the sent figure is a
    /// footnote to the headline and lives in its tooltip instead.
    private var totalCaption: String {
        let requests = String(localized: "\(summary.requests) requests")
        let hosts = String(localized: "\(summary.hostCount) hosts")
        guard let since = summary.since else { return "\(requests) · \(hosts)" }
        return "\(requests) · \(hosts) · "
            + String(localized: "since \(Self.monthYear.string(from: since))")
    }

    private func cheapCell(_ title: String, _ value: Int, help: String) -> some View {
        HStack(spacing: 0) {
            Divider().frame(height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(value)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(value > 0 ? .primary : .secondary)
            }
            .padding(.leading, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
    }

    // MARK: - Purpose split

    private var purposeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "What for"))
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(summary.byPurpose) { row in
                        Rectangle()
                            .fill(Self.color(for: row.purpose))
                            .frame(width: max(1, geo.size.width * summary.share(row)))
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            // Wraps rather than truncating a purpose away: every one has to stay
            // visible for the split to add up.
            FlowLayout(spacing: 16) {
                ForEach(summary.byPurpose) { row in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Self.color(for: row.purpose))
                            .frame(width: 7, height: 7)
                        Text(Self.label(for: row.purpose)).font(.caption)
                        Text(ByteFormat.string(row.bytesReceived))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                        Text("\(row.requests)×")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Hosts

    private var hostTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(String(localized: "Which hosts"))
            ForEach(summary.topHosts) { row in
                HStack(spacing: 10) {
                    Text(row.host)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Spelled out rather than "940 × 304": beside the request
                    // count's trailing "×" that reads as a multiplication, and the
                    // two numbers on this row would then use one symbol for two
                    // different things.
                    if row.notModified > 0 {
                        Text("\(row.notModified) revalidated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Text("\(row.requests)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                    Text(ByteFormat.string(row.bytesReceived))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
            if summary.remainingHosts > 0 {
                Text("… and \(summary.remainingHosts) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Raw events

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingRecent.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isShowingRecent ? 90 : 0))
                    sectionTitle(String(localized: "Recent requests"))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingRecent {
                ForEach(Array(summary.recent.reversed().enumerated()), id: \.offset) { _, event in
                    recentRow(event)
                }
            }
        }
    }

    private func recentRow(_ event: RequestEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Ties each row back to the legend above. Without it the list answers
            // "what did it fetch" but not "what for", which is the question this
            // whole panel exists for.
            Circle()
                .fill(Self.color(for: event.purpose))
                .frame(width: 6, height: 6)
                .help(Self.label(for: event.purpose))
            Text(event.responseEnd.map { Self.time.string(from: $0) } ?? "—")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            // Three states, not two: an HTTP status, a cache hit that never asked,
            // and a transfer that got no answer at all.
            Text(statusText(event))
                .font(.caption.monospaced())
                .foregroundStyle(statusColor(event))
                .frame(width: 46, alignment: .leading)
            Text(event.host + event.path)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteFormat.string(event.bytesReceived))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
        // The detail that does not fit on the row, and the reason the events are
        // kept at all: the phase timings, the address actually connected to, and
        // whether the connection was reused.
        .help(rowDetail(event))
    }

    private func statusText(_ event: RequestEvent) -> String {
        if event.fromCache { return String(localized: "cache") }
        if let status = event.status { return String(status) }
        return String(localized: "fail")
    }

    private func statusColor(_ event: RequestEvent) -> Color {
        if event.fromCache { return .secondary }
        guard let status = event.status else { return .orange }
        return (200..<400).contains(status) ? .secondary : .orange
    }

    private func rowDetail(_ event: RequestEvent) -> String {
        var lines = [Self.label(for: event.purpose) + " · " + event.method]
        if let address = event.remoteAddress {
            lines.append("\(address):\(event.remotePort ?? 0)")
        }
        if let duration = event.duration {
            lines.append(String(localized: "\(Self.millis(duration)) ms total"))
        }
        if let ttfb = event.timeToFirstByte {
            lines.append(String(localized: "\(Self.millis(ttfb)) ms to first byte"))
        }
        if event.reusedConnection { lines.append(String(localized: "connection reused")) }
        if event.proxyConnection { lines.append(String(localized: "through a proxy")) }
        if let proto = event.networkProtocol { lines.append(proto) }
        if let tls = event.tlsVersionName { lines.append(tls) }
        if let domain = event.errorDomain, let code = event.errorCode {
            lines.append("\(domain) \(code)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Footprint

    private var footprint: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summary.showsRetentionCaveat, let oldest = summary.oldestEvent {
                note(String(localized: "The totals above run from the start. Individual requests are only kept back to \(Self.monthDay.string(from: oldest)); older ones are pruned, but their bytes are still counted."))
            }
            note(String(localized: "Homebrew and the App Store fetch their own bytes, so this is a lower bound. Query strings are never recorded."))
            Text("\(summary.retainedEvents) events · \(ByteFormat.string(summary.storeBytes)) on disk")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Presentation tables

    /// One colour per purpose, fixed rather than derived from position, so a
    /// purpose keeps its colour when a quiet one drops out of the bar.
    static func color(for purpose: RequestPurpose) -> Color {
        switch purpose {
        case .install:        return .blue
        case .selfUpdate:     return .purple
        case .catalog:        return .orange
        case .versionCheck:   return .green
        case .changelog:      return .teal
        case .changelogImage: return .mint
        case .other:          return .gray
        }
    }

    static func label(for purpose: RequestPurpose) -> String {
        switch purpose {
        case .install:        return String(localized: "App downloads")
        case .selfUpdate:     return String(localized: "Duo Updater itself")
        case .catalog:        return String(localized: "Homebrew catalog")
        case .versionCheck:   return String(localized: "Update checks")
        case .changelog:      return String(localized: "Release notes")
        case .changelogImage: return String(localized: "Release-note images")
        case .other:          return String(localized: "Other")
        }
    }

    private static func millis(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }

    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HHmmss")
        return formatter
    }()
}
