import SwiftUI
import AppKit
import DuoUpdaterCore

/// Every request Duo Updater made, as a log you can interrogate.
///
/// The log **is** the view: no summary page in front of it and no drill-down
/// behind it. What sits on top is not a lifetime total but the answer to
/// whatever the field is currently asking — filter to one host and every figure
/// up there recomputes. A fixed total above a filtered list is two unrelated
/// numbers with the subtraction left to the reader.
///
/// Nothing is decided in this file. Every figure comes off ``RequestLogSummary``,
/// every filter is a ``RequestQuery``, and even the field's colouring comes from
/// ``RequestQuery/highlights(_:)`` — all in Core, because `App/project.yml` has
/// no test target, so a rule written into a `body` is a rule nothing executes.
///
/// The filter chips are not a second filtering path: each one is literally a
/// token appended to the field, so a question asked by clicking and the same
/// question asked by typing cannot answer differently, and `duo events` takes
/// the same syntax.
/// Everything the Requests tab is currently asking, kept by the window.
///
/// In the window rather than in the pane because switching to Downloads and back
/// destroys the pane — and with it, a filter somebody had just typed. The tabs
/// are two views of one window; a question survives looking away from it.
struct RequestLogFilter: Equatable {
    /// The pinned filters — `host:apple.com` and friends — as one string.
    var text = ""
    /// What is being typed and is not a `key:value`: a plain word, matched
    /// against host and path as you type. Kept apart from ``text`` so a search
    /// word does not freeze into a capsule you have to aim at to remove.
    var draft = ""
    var range: RequestLogPane.Range = .all
    var sort: RequestQuery.Sort = .time
    var ascending = false
    /// The row being read, if any. Live refresh pauses while it is set.
    var selection: UUID?
}

struct RequestLogPane: View {
    @Binding var filter: RequestLogFilter
    /// Whether the log has been read yet. Before that there is nothing to say —
    /// least of all "nothing recorded".
    var hasLoaded = true
    let summary: RequestLogSummary
    let events: [DuoEvent]
    let retainedEvents: Int
    let storeBytes: Int64
    /// Re-runs the query. Async so the caller can flush the store first.
    var onQuery: (RequestQuery) async -> Void = { _ in }
    var onReset: (RequestQuery) -> Void = { _ in }
    var onExport: (RequestQuery) -> Void = { _ in }
    /// Cheap "has anything changed" probe, polled while the window is open.
    var onChangeToken: () async -> String = { "" }
    /// Loads the transactions of one fetch, for a row being expanded.
    /// Forces the field to a value. Only an offline renderer passes it — read
    /// alongside the `@State` rather than seeding it, because `.task` does not
    /// run when a renderer draws this on its own.
    var initialText = ""

    @State private var hovered: UUID?
    /// The store changed while a row was selected. Refreshing under the reader
    /// would move the row they are reading out from under the pointer, so the
    /// list is held still and this offers the update instead.
    @State private var heldBack = false
    @State private var lastToken = ""
    /// Bumped to force a reload that the query itself did not change.
    @State private var refresh = UUID()
    /// Whether this window is the one being looked at. A log nobody is reading
    /// does not need re-reading every two seconds.
    @Environment(\.controlActiveState) private var activeState
    @State private var confirmingReset = false
    @State private var explainingCounts = false
    @State private var explainingScope = false

    /// Coarse date ranges, as a menu rather than tokens. Two reasons: a date is
    /// the one filter nobody wants to type, and it is the one that decides how
    /// much of the table has to be read, so it stays visible rather than buried
    /// in a string.
    enum Range: String, CaseIterable, Identifiable {
        case all, day, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:   return String(localized: "All time")
            case .day:   return String(localized: "Last 24 hours")
            case .week:  return String(localized: "Last 7 days")
            case .month: return String(localized: "Last 30 days")
            }
        }
        var since: Date? {
            switch self {
            case .all:   return nil
            case .day:   return Date(timeIntervalSinceNow: -86_400)
            case .week:  return Date(timeIntervalSinceNow: -7 * 86_400)
            case .month: return Date(timeIntervalSinceNow: -30 * 86_400)
            }
        }
    }

    /// The four or five filters worth one click. Each is a real token; clicking
    /// one types it for you.
    private static let chips: [(token: String, label: LocalizedStringKey)] = [
        ("status:problems", "Problems"),
        ("purpose:download", "App downloads"),
        ("purpose:check", "Update checks"),
        ("purpose:notes", "Release notes"),
        ("purpose:self", "Duo Updater itself"),
        ("took>5s", "Slower than 5 s"),
    ]

    /// Everything the query is: the pinned capsules plus whatever is being
    /// typed. One string, so the chips, the field and `duo events --filter` all
    /// stay the same grammar.
    private var text: String {
        let combined = [filter.text, filter.draft]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? initialText : combined
    }
    private var range: Range { filter.range }
    private var selection: UUID? { filter.selection }

    private var query: RequestQuery {
        var query = RequestQuery.window(text)
        query.since = range.since
        query.sort = filter.sort
        query.ascending = filter.ascending
        return query
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statStrip
            Divider()
            queryBar
            chipRow
            Divider()
            if events.isEmpty {
                // Blank, not "nothing recorded": that sentence is an answer, and
                // before the first read there is no answer yet.
                if hasLoaded { emptyState } else { Color.clear }
            } else {
                columnHeader
                Divider()
                log
            }
            if let request = selectedRequest {
                Divider()
                detail(request)
            }
            Divider()
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Coming back to the window catches up in one read rather than waiting
        // out the next tick.
        .onChange(of: activeState) { _, state in
            if state != .inactive { refresh = UUID() }
        }
        // Keyed on the query so every edit re-runs it, and debounced inside so a
        // held-down key does not run one full-table scan per character.
        .task(id: queryKey) {
            try? await Task.sleep(for: .milliseconds(text.isEmpty ? 0 : 180))
            guard !Task.isCancelled else { return }
            await onQuery(query)
            lastToken = await onChangeToken()
        }
        // Live updates. SQLite has no cross-process push — `PRAGMA data_version`
        // is the documented pull primitive, and it deliberately ignores this
        // process's own commits, so ``EventStore/changeToken()`` folds our own
        // write count in. Two seconds is a pragma read and an integer compare,
        // not a query.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                // Behind another window, or on the Downloads tab (which destroys
                // this pane), nobody is watching the log — so nothing polls it.
                // The catch-up happens when the window comes forward again.
                guard activeState != .inactive else { continue }
                let token = await onChangeToken()
                guard token != lastToken else { continue }
                lastToken = token
                // Never under a reader's cursor: refreshing while a row is
                // selected slides that row out from under the pointer, because
                // new events land at the top of a newest-first list.
                if selection == nil {
                    await onQuery(query)
                } else {
                    heldBack = true
                }
            }
        }
    }

    /// What a change of question looks like. The range and the ordering are in
    /// here because both change *which* rows the capped page contains, not only
    /// how they are arranged.
    private var queryKey: String {
        "\(text)\u{0}\(filter.range.rawValue)\u{0}\(filter.sort.rawValue)\u{0}\(filter.ascending)\u{0}\(refresh)"
    }

    // MARK: - The answer

    /// A fixed height, whatever the query matched.
    ///
    /// The bar and its legend collapse to nothing on an empty result, and a
    /// strip that changes height as you type moves the whole table under the
    /// pointer between keystrokes. The figures inside it change; the shape does
    /// not — which is also what keeps this tab from jumping when you switch to
    /// it from the ledger.
    private static let stripHeight: CGFloat = 122

    private var statStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ByteFormat.stringOrDash(summary.bytesReceived))
                        // The ledger's headline, to the point: the two tabs are
                        // one window, and a headline that changed size between
                        // them reads as two different apps.
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .help(String(localized: "\(summary.bytesReceived) bytes received, \(summary.bytesSent) sent"))
                    caption
                }
                .frame(minWidth: 220, alignment: .leading)
                Spacer(minLength: 8)
                counts
            }
            purposeBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(height: Self.stripHeight, alignment: .topLeading)
    }

    /// Says which question the number above answers. It has to name the filter:
    /// the same headline means two different things filtered and unfiltered, and
    /// nothing else on screen distinguishes them.
    @ViewBuilder
    private var caption: some View {
        let requests = String(localized: "\(summary.requests) requests")
        let hosts = String(localized: "\(summary.hostCount) hosts")
        Group {
            if isFiltered {
                Text("matching \(requests) · \(hosts)")
            } else if let since = summary.oldest {
                Text("\(requests) · \(hosts) · since \(Self.monthYear.string(from: since))")
            } else {
                Text("\(requests) · \(hosts)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var isFiltered: Bool { !text.isEmpty || range != .all }

    /// The same anatomy as the ledger's month cells — rule, small caps label,
    /// figure — because these sit in the same place in the same window and a
    /// second layout for the same job reads as a different screen.
    private var counts: some View {
        HStack(alignment: .top, spacing: 0) {
            countCell(String(localized: "Revalidated"), summary.notModified)
            countCell(String(localized: "From cache"), summary.cached)
            countCell(String(localized: "Problems"), summary.problems,
                      tint: summary.problems > 0 ? .orange : nil,
                      token: "status:problems")
            explainer
        }
        .fixedSize()
    }

    private func countCell(
        _ title: String, _ value: Int, tint: Color? = nil, token: String? = nil
    ) -> some View {
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
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint ?? (value > 0 ? .primary : .secondary))
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            // The count is the fastest route to the rows behind it, and without
            // this the only way to reach them is to know the token.
            .contentShape(Rectangle())
            .onTapGesture { if let token, value > 0 { toggle(token) } }
        }
    }

    /// Three words nobody outside this codebase has to know.
    ///
    /// A tooltip was the first answer and it is not one: nobody hovers a number
    /// they do not already suspect is interesting, so the explanation was only
    /// reachable by people who did not need it.
    private var explainer: some View {
        Button { explainingCounts.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .popover(isPresented: $explainingCounts, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                explain(String(localized: "Revalidated"),
                        String(localized: "We asked whether anything changed and the server answered “no”, sending headers only. Nearly free, and what most update checks are."))
                explain(String(localized: "From cache"),
                        String(localized: "Answered from this Mac. Nothing crossed the network at all."))
                explain(String(localized: "Problems"),
                        String(localized: "No answer at all, or an answer of 400 and up — a timeout, or a refusal such as a rate-limited “403”. These are the ones that leave an app showing a stale version."))
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private func explain(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var purposeBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            // The empty track is always drawn. Without it the bar and its legend
            // vanish on a query that matched nothing and the strip loses 22pt.
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .separatorColor).opacity(0.5))
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(summary.byPurpose) { slice in
                            Rectangle()
                                .fill(Self.color(for: slice.purpose))
                                .frame(width: max(1, geo.size.width * summary.share(slice)))
                        }
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            // Wraps rather than truncating a purpose away: every one has to stay
            // visible for the split to add up to the headline.
            FlowLayout(spacing: 16) {
                ForEach(summary.byPurpose) { slice in
                    Button { toggle("purpose:\(Self.token(for: slice.purpose))") } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Self.color(for: slice.purpose))
                                .frame(width: 7, height: 7)
                            Text(Self.label(for: slice.purpose)).font(.caption)
                            Text(ByteFormat.stringOrDash(slice.bytesReceived))
                                .font(.caption.weight(.semibold)).monospacedDigit()
                            Text("\(slice.requests)×")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 15, alignment: .topLeading)
            .clipped()
        }
    }

    // MARK: - The question

    private var queryBar: some View {
        HStack(spacing: 9) {
            QueryTokenField(
                text: $filter.text,
                draft: $filter.draft,
                ignored: Set(query.ignoredKeys),
                placeholder: "host:  app:  purpose:  status:  size>10MB")

            Picker("Range", selection: $filter.range) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(Self.chips, id: \.token) { chip in
                    Button { toggle(chip.token) } label: {
                        Text(chip.label)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(isActive(chip.token)
                                    ? Color.accentColor.opacity(0.22)
                                    : Color(nsColor: .textBackgroundColor).opacity(0.5)))
                            .overlay(Capsule().strokeBorder(
                                isActive(chip.token)
                                    ? Color.accentColor.opacity(0.55)
                                    : Color(nsColor: .separatorColor),
                                lineWidth: 1))
                            .foregroundStyle(isActive(chip.token) ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Two chips of the same kind widen the result rather than narrowing
            // it, which is the only way chips can work — under AND, a second
            // purpose would always match nothing — but it is invisible, and the
            // surprise is watching the list grow as you add a filter.
            if let either = eitherHint {
                Text("Repeated filters match either — \(either)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // A key that looks like a filter and is not would otherwise widen the
            // result set while looking like it narrowed it. The field underlines
            // it too; this says what it is.
            if !query.ignoredKeys.isEmpty {
                Text("Ignored: \(query.ignoredKeys.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    /// Names the groups that are ORed together, or nil when nothing repeats.
    private var eitherHint: String? {
        var groups: [String] = []
        if query.purposes.count > 1 {
            groups.append(String(localized: "purpose: \(list(query.purposes.map(Self.label(for:))))"))
        }
        if query.hosts.count > 1 {
            groups.append(String(localized: "host: \(list(query.hosts))"))
        }
        if query.apps.count > 1 {
            groups.append(String(localized: "app: \(list(query.apps))"))
        }
        if query.statuses.count > 1 {
            // Listed rather than counted: "status: 2 values" needs a plural rule
            // in every language to say nothing the list does not already say.
            groups.append(String(localized: "status: \(list(query.statuses.map(Self.name(for:))))"))
        }
        return groups.isEmpty ? nil : groups.joined(separator: " · ")
    }

    /// The token that names one status term — the same word that selects it.
    static func name(for status: RequestQuery.StatusTerm) -> String {
        switch status {
        case let .code(code):     return String(code)
        case let .family(family): return "\(family)xx"
        case .failed:             return "fail"
        case .cache:              return "cache"
        case .problem:            return "problems"
        }
    }

    private func list(_ items: [String]) -> String {
        items.formatted(.list(type: .or))
    }

    private func isActive(_ token: String) -> Bool {
        RequestQuery.tokenize(filter.text).contains(token)
    }

    /// Chips edit the field rather than a parallel filter state, so what a chip
    /// selects is always exactly what the text says.
    private func toggle(_ token: String) {
        var tokens = RequestQuery.tokenize(filter.text)
        if let index = tokens.firstIndex(of: token) {
            tokens.remove(at: index)
        } else {
            tokens.append(token)
        }
        filter.text = tokens.joined(separator: " ")
    }

    // MARK: - The log

    private enum Column {
        static let time: CGFloat = 116
        static let status: CGFloat = 48
        static let app: CGFloat = 118
        static let size: CGFloat = 76
        static let duration: CGFloat = 58
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 7, height: 1)
            sortHeader("TIME", .time, width: Column.time, alignment: .leading)
            Text("STATUS").frame(width: Column.status, alignment: .leading)
            Text("APP").frame(width: Column.app, alignment: .leading)
            Text("HOST AND PATH").frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("SIZE", .size, width: Column.size, alignment: .trailing)
            sortHeader("MS", .duration, width: Column.duration, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    private func sortHeader(
        _ title: LocalizedStringKey, _ column: RequestQuery.Sort,
        width: CGFloat, alignment: Alignment
    ) -> some View {
        Button {
            // Same column toggles direction; a new column starts at the order
            // that answers the question people are asking of it — biggest and
            // slowest first, newest first.
            if filter.sort == column {
                filter.ascending.toggle()
            } else {
                filter.sort = column
                filter.ascending = false
            }
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                Image(systemName: filter.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(filter.sort == column ? 1 : 0)
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .foregroundStyle(filter.sort == column ? Color.primary : Color.secondary)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var log: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events) { event in
                    if let request = event.request {
                        row(event.id, request, at: event.date)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var selectedRequest: RequestEvent? {
        events.first { $0.id == selection }?.request
    }

    private func row(_ id: UUID, _ request: RequestEvent, at date: Date) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Self.color(for: request.purpose))
                .frame(width: 7, height: 7)
            Text(Self.stamp.string(from: date))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Column.time, alignment: .leading)
            // Three states, not two: an HTTP status, a cache hit that never
            // asked, and a transfer that got no answer at all.
            Text(statusText(request))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(statusColor(request))
                .frame(width: Column.status, alignment: .leading)
            // The column the context menu's "Filter to this app" was offering to
            // filter on while nothing on screen showed it.
            Text(request.appName ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(request.appName == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Column.app, alignment: .leading)
                // The dash has two causes and they are not the same thing: a
                // fetch that belongs to no single app, and a row written before
                // this column existed. Without saying so it reads as data loss.
                .help(request.appName ?? String(localized: "Not recorded against one app — either a shared fetch (the Homebrew catalog, our own update) or a request logged before per-app attribution shipped."))
            HStack(spacing: 5) {
                Text(request.host + request.path)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if request.hadQuery == true {
                    // A badge, not a trailing "?…". The first version wrote the
                    // marker into the text, where it was indistinguishable from
                    // the middle-truncation ellipsis the column already draws —
                    // one glyph meaning two unrelated things on the same row.
                    Text(verbatim: "?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                        .help(String(localized: "This request carried a query string. It is never recorded — query strings carry credentials — so the URL here, and the one Copy URL gives you, are both without it."))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteFormat.stringOrDash(request.bytesReceived))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: Column.size, alignment: .trailing)
            Text(request.duration.map { "\(Self.millis($0))" } ?? "—")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: Column.duration, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(rowBackground(id))
        .contentShape(Rectangle())
        .onTapGesture { select(selection == id ? nil : id) }
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        .contextMenu {
            // Selecting on right-click as well as on left: a menu that acts on a
            // row you cannot see selected is a menu you have to guess about.
            Button("Filter to this host") { select(id); toggle("host:\(request.host)") }
            if let appName = request.appName {
                Button("Filter to this app") { select(id); toggle("app:\(appName)") }
            }
            Button(request.hadQuery == true ? "Copy URL (query omitted)" : "Copy URL") {
                select(id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(request.url, forType: .string)
            }
        }
    }

    /// Selecting pauses the live refresh; deselecting takes whatever it held.
    private func select(_ id: UUID?) {
        filter.selection = id
        if id == nil, heldBack { heldBack = false; refresh = UUID() }
    }

    private func rowBackground(_ id: UUID) -> Color {
        if selection == id { return Color.accentColor.opacity(0.20) }
        if hovered == id { return Color.primary.opacity(0.06) }
        return .clear
    }

    /// What used to be a multi-line tooltip.
    ///
    /// A tooltip was the wrong shape for it twice over: it is the reason the
    /// events are kept at all, and it was rendered as a stack of unlabelled
    /// lines in a yellow box you had to hold still to read. As a strip under the
    /// selected row it is legible, copyable, and stays put.
    private func detail(_ request: RequestEvent) -> some View {
        HStack(alignment: .top, spacing: 22) {
            fact(String(localized: "Purpose"), Self.label(for: request.purpose))
            if let appName = request.appName {
                fact(String(localized: "For"), appName)
            }
            if let address = request.remoteAddress {
                // With a proxy in front, this is the proxy's address, not the
                // server's — the metrics report what was actually connected to.
                // Labelling it "Address" presents 127.0.0.1 as the host that
                // served the file.
                fact(request.proxyConnection
                     ? String(localized: "Via proxy")
                     : String(localized: "Address"),
                     "\(address):\(request.remotePort ?? 0)")
            }
            if let ttfb = request.timeToFirstByte {
                fact(String(localized: "First byte"), "\(Self.millis(ttfb)) ms")
            }
            if let proto = request.networkProtocol {
                fact(String(localized: "Protocol"),
                     proto + (request.reusedConnection
                              ? " · " + String(localized: "reused") : ""))
            }
            if let tls = request.tlsVersionName {
                fact(String(localized: "TLS"), tls)
            }
            if request.hadQuery == true {
                fact(String(localized: "Query"), String(localized: "not recorded"))
            }
            if let domain = request.errorDomain, let code = request.errorCode {
                fact(String(localized: "Error"), "\(domain) \(code)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private func statusText(_ request: RequestEvent) -> String {
        if request.fromCache { return String(localized: "cache") }
        if let status = request.status { return String(status) }
        return String(localized: "fail")
    }

    private func statusColor(_ request: RequestEvent) -> Color {
        if request.fromCache { return .secondary }
        guard let status = request.status else { return .orange }
        return (200..<400).contains(status) ? .secondary : .orange
    }

    // MARK: - Footer

    private var statusBar: some View {
        HStack(spacing: 10) {
            // Says when the list is a window onto the matches rather than all of
            // them — without it a capped list reads as the whole answer.
            // Says when the list is a window onto the matches rather than all of
            // them — without it a capped list reads as the whole answer.
            if events.count < summary.requests {
                Text("Showing the most recent \(events.count) of \(summary.requests) matching requests")
            } else {
                Text("\(summary.requests) requests")
            }
            scopeNote
            if heldBack {
                Button {
                    heldBack = false
                    refresh = UUID()
                } label: {
                    Label("New requests — refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .help("Paused while a row is selected, so the list does not move under you")
            }
            Spacer()
            Text("\(retainedEvents) events · \(ByteFormat.string(storeBytes)) on disk")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Button("Export JSON") { onExport(query) }
                .buttonStyle(.link)
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Discard every recorded event and total")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .confirmationDialog(
            "Discard the recorded network history?",
            isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { onReset(query) }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The download ledger survives it: it is not diagnostics, it is the
            // answer to what keeping this machine updated has cost.
            Text("Every request and every running total goes. The Downloads tab is not affected.")
        }
    }

    /// Says what the log is a log *of*, and — the part that needs saying — what
    /// it is not.
    ///
    /// Every figure in this window is scoped to the requests this app issues
    /// through its own session. That is nearly all of its own traffic, but it is
    /// not everything this Mac sends on an app's behalf: a release-notes page is
    /// rendered in a web view that fetches its own images and fonts, and App
    /// Store and Homebrew updates are carried out by separate tools that do
    /// their own networking. None of that is recorded here and none of it can
    /// be — so a window that says "13 hosts" without qualification is inviting
    /// the reading that those are the only thirteen.
    ///
    /// `duo requests` has said this since it shipped, in its one-line summary
    /// ("what DuoUpdater *itself* put on the network"). This window had no
    /// equivalent, and it is the one most people will see.
    ///
    /// Always visible rather than a tooltip on the count, for the reason the
    /// counts explainer next to it is a button and not a tooltip: nobody hovers
    /// a figure they do not already suspect of being interesting, and the whole
    /// point here is to reach the reader who suspects nothing.
    private var scopeNote: some View {
        Button(String(localized: "What this covers")) { explainingScope.toggle() }
            .buttonStyle(.link)
            .popover(isPresented: $explainingScope, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    explain(
                        String(localized: "Recorded here"),
                        String(localized: "Every fetch Duo Updater makes itself: update checks, release notes, and the downloads it installs for you."))
                    explain(
                        String(localized: "Not recorded here"),
                        String(localized: "A release-notes page loads in a web view that fetches its own images and fonts, and App Store and Homebrew updates are carried out by separate tools. Those requests are not Duo Updater's to record, so this is not a log of everything your Mac sends."))
                }
                .padding(14)
                .frame(width: 340)
            }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            isFiltered ? "No requests match" : "Nothing recorded yet",
            systemImage: isFiltered ? "line.3.horizontal.decrease.circle" : "network.slash",
            description: Text(isFiltered
                ? "No request in this range matches that filter."
                : "Duo Updater logs the requests it makes on your behalf here — update checks, release notes, and its own downloads."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The token that selects one purpose. Never localized — it is typed into the
    /// field and read by `duo events`, so it has to be the same string in every
    /// language.
    static func token(for purpose: RequestPurpose) -> String {
        switch purpose {
        case .install:        return "download"
        case .selfUpdate:     return "self"
        case .catalog:        return "catalog"
        case .versionCheck:   return "check"
        case .changelog:      return "notes"
        case .changelogImage: return "images"
        case .other:          return "other"
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

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        // Both fields padded. The unpadded template renders "09/4, 02:19:02",
        // which puts the colons of a fixed-width column in three places.
        formatter.setLocalizedDateFormatFromTemplate("MMddHHmmss")
        return formatter
    }()
}
