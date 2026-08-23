import SwiftUI
import DuoUpdaterCore

/// The Release Log: a global, chronological feed of every release we've seen the
/// apps we track announce — built up over time from each update check. Grouped by
/// the day the vendor *published*, newest first, with the exact time of day on
/// every row (the seed for "what time do these apps like to ship?").
///
/// Only releases carrying a trustworthy vendor timestamp appear here (Sparkle,
/// GitHub, Alcove); see `ReleaseTimelineStore`. Apps that update through their own
/// built-in updater, the App Store, or Homebrew can't supply an honest release
/// date, so they're absent rather than plotted against our own polling clock.
struct ReleaseLogView: View {
    static let windowID = "release-log"

    @Bindable var model: AppListModel

    /// The two ways to read the log: a chronological feed, or the aggregate
    /// "when do they ship?" pattern view.
    private enum Mode: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case patterns = "Patterns"
        var id: String { rawValue }

        /// User-facing label. Kept separate from `rawValue` (which stays a stable,
        /// English identifier) so the segmented control can be translated.
        var displayName: String {
            switch self {
            case .timeline: return String(localized: "Timeline")
            case .patterns: return String(localized: "Patterns")
            }
        }
    }
    @State private var mode: Mode = .timeline

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if events.isEmpty {
                emptyState
            } else {
                switch mode {
                case .timeline: feed
                case .patterns: ReleasePatternsView(events: events)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Release Log").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !events.isEmpty {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summary: String {
        let releases = events.count
        let apps = Set(events.map(\.appID)).count
        guard releases > 0 else { return String(localized: "Releases appear here as the apps you track ship them") }
        return String(localized: "\(releases) releases across \(apps) apps")
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.events) { row in
                            ReleaseRow(event: row)
                            if row.id != group.events.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    } header: {
                        dayHeader(group.day)
                    }
                }
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack {
            Text(day.formatted(.dateTime.weekday(.wide).month().day().year()))
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("No releases logged yet").font(.headline)
            Text("As the apps you track publish updates, each release is recorded here. Sparkle, GitHub and Alcove come with an exact publish time; other apps get an estimated “≈” window from when we spot the change. The Patterns view uses only the exact ones.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Data

    /// One flattened release, carrying the app identity alongside the event so the
    /// global feed can render an icon and name per row.
    struct Row: Identifiable {
        let appID: String
        let appName: String
        let event: ReleaseEvent
        var id: String { appID + "|" + event.version }
    }

    private struct DayGroup {
        let day: Date
        let events: [Row]
    }

    /// Every recorded release across all apps, newest first (by best-known time).
    private var events: [Row] {
        model.releaseTimelines
            .flatMap { tl in tl.events.map { Row(appID: tl.appID, appName: tl.appName, event: $0) } }
            .sorted { $0.event.timestamp > $1.event.timestamp }
    }

    /// The feed grouped into day buckets (by the user's calendar), newest day first.
    private var groups: [DayGroup] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: events) { cal.startOfDay(for: $0.event.timestamp) }
        return buckets.keys.sorted(by: >).map { day in
            DayGroup(day: day, events: buckets[day] ?? [])
        }
    }
}

/// One release in the feed: app icon + name, the version, the source, and the
/// timing — an exact publish time, or an "≈" estimated window for detection-only
/// apps (which is shown muted so it never reads as a precise claim).
private struct ReleaseRow: View {
    let event: ReleaseLogView.Row

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.icon(for: event.appID))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.appName).font(.body)
                    Text(event.event.version)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(event.event.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            timing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var timing: some View {
        if let published = event.event.publishedAt {
            Text(published.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help("Published \(published.formatted(date: .abbreviated, time: .standard))")
        } else if let range = event.event.estimatedRange {
            Text(ReleaseTiming.approxLabel(range))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                .help(ReleaseTiming.approxHelp(range))
        }
    }
}

/// Compact formatting for an estimated release window, shared by the feed and the
/// per-app version list.
enum ReleaseTiming {
    /// "≈ 2:00–6:00 PM" for a tight (≤36h) window, else "≈ within 3d".
    static func approxLabel(_ range: DateInterval) -> String {
        if range.duration <= 36 * 3600 {
            let from = range.start.formatted(date: .omitted, time: .shortened)
            let to = range.end.formatted(date: .omitted, time: .shortened)
            return String(localized: "≈ \(from)–\(to)")
        }
        let days = max(1, Int((range.duration / 86_400).rounded()))
        return String(localized: "≈ within \(days)d")
    }

    static func approxHelp(_ range: DateInterval) -> String {
        let from = range.start.formatted(date: .abbreviated, time: .shortened)
        let to = range.end.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Released sometime between \(from) and \(to) — estimated from when we detected the change, not a vendor date.")
    }
}

// MARK: - Patterns (heatmap)

/// The aggregate "when do these apps like to ship?" view: a weekday × hour
/// heatmap over every recorded release, plus the headline peak. All buckets use
/// the local clock (`Calendar.current`), so a row at "3 PM" means 3 PM here.
private struct ReleasePatternsView: View {
    let rows: [ReleaseLogView.Row]

    init(events: [ReleaseLogView.Row]) { self.rows = events }

    /// nil = all apps combined; otherwise an appID to focus a single app's pattern.
    @State private var selectedAppID: String? = nil

    /// The rows feeding the heatmap — every app, or just the selected one.
    private var scoped: [ReleaseLogView.Row] {
        guard let id = selectedAppID else { return rows }
        return rows.filter { $0.appID == id }
    }

    private var stats: ReleaseStats {
        ReleaseStats(events: scoped.map(\.event), calendar: .current)
    }

    /// Apps that have recorded releases, most-active first — so a fast-moving app
    /// (lots of releases) surfaces at the top of the picker.
    private var apps: [(id: String, name: String, count: Int)] {
        var byID: [String: (name: String, count: Int)] = [:]
        for row in rows {
            let cur = byID[row.appID]
            byID[row.appID] = (row.appName, (cur?.count ?? 0) + 1)
        }
        return byID.map { (id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Weekday indices (0 = Sunday) in the user's preferred display order, so a
    /// Monday-first locale reads Mon→Sun.
    private var weekdayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1   // 0-based
        return (0..<7).map { (first + $0) % 7 }
    }

    private let hours = Array(0..<24)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appPicker
                if stats.total > 0 {
                    insight
                    heatmap
                    legend
                } else {
                    noExactDatesNote
                }
                if selectedAppID != nil { versionList }
            }
            .padding(16)
        }
    }

    /// Shown when the current scope has no exact-dated releases to plot — e.g. a
    /// detection-only app selected. The version list (estimated windows) still
    /// renders below, so the view isn't empty; it just can't draw a habit heatmap.
    private var noExactDatesNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark").foregroundStyle(.secondary)
            Text(selectedAppID == nil
                 ? String(localized: "No exact release times recorded yet — the heatmap fills in as Sparkle/GitHub apps ship.")
                 : String(localized: "This app reports versions but no exact release time, so there's no habit heatmap — only the estimated windows below."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: App picker

    private var appPicker: some View {
        Picker("App", selection: $selectedAppID) {
            Text("All apps").tag(String?.none)
            Divider()
            ForEach(apps, id: \.id) { app in
                Text("\(app.name)  ·  \(app.count)").tag(String?.some(app.id))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    // MARK: Insight headline

    @ViewBuilder
    private var insight: some View {
        if let peak = stats.peakCell {
            VStack(alignment: .leading, spacing: 3) {
                Text(peakSentence(peak)).font(.title3).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        // A single-app pattern only means something with a handful of releases; say
        // so plainly rather than over-reading one or two points. Each branch is a
        // full sentence (rather than a concatenation) so it translates cleanly.
        if selectedAppID != nil && stats.total < 5 {
            return String(localized: "Across \(stats.total) recorded releases. Times in your local zone. The pattern sharpens as this app ships more.")
        }
        return String(localized: "Across \(stats.total) recorded releases. Times in your local zone.")
    }

    /// "Peak: Friday, around 6 PM".
    ///
    /// A label rather than a sentence, and that is the fix rather than the style.
    /// The day comes from `standaloneWeekdaySymbols`, which is nominative by
    /// definition — that is what "standalone" means — and the catalog only ever
    /// sees `%@`. So no translation of "Most often ships %@, around %@." could
    /// inflect it: Russian needs `по пятницам` or `в пятницу` where it was getting
    /// `пятница`, and every other case-marking language had the same problem.
    /// After a colon the nominative is the right form in all of them.
    ///
    /// It also folds the all-apps and single-app variants into one string. The
    /// distinction they drew ("most often" vs "usually") is already carried, more
    /// honestly, by the subtitle underneath, which names how many releases the
    /// pattern is drawn from.
    private func peakSentence(_ peak: (weekday: Int, hour: Int, count: Int)) -> String {
        let day = Calendar.current.standaloneWeekdaySymbols[peak.weekday]
        let time = hourLabel(peak.hour, long: true)
        return String(localized: "Peak: \(day), around \(time)")
    }

    // MARK: Per-app version list

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Versions")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ForEach(Array(scoped.sorted { $0.event.timestamp > $1.event.timestamp }.enumerated()), id: \.element.id) { idx, row in
                HStack {
                    Text(row.event.version)
                        .font(.callout).monospacedDigit()
                    Spacer()
                    if let published = row.event.publishedAt {
                        Text(published.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else if let range = row.event.estimatedRange {
                        Text(range.end.formatted(date: .abbreviated, time: .omitted) + " " + ReleaseTiming.approxLabel(range))
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                            .help(ReleaseTiming.approxHelp(range))
                    }
                }
                .padding(.vertical, 5)
                if idx != scoped.count - 1 { Divider() }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Heatmap grid

    private var heatmap: some View {
        let maxCount = max(stats.maxCellCount, 1)
        return VStack(alignment: .leading, spacing: 3) {
            // Hour axis labels (sparse: every 6 hours) aligned over the columns.
            HStack(spacing: cellSpacing) {
                Color.clear.frame(width: labelWidth)
                ForEach(hours, id: \.self) { h in
                    Text(h % 6 == 0 ? hourLabel(h, long: false) : "")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                        .frame(width: cellSize)
                        .fixedSize()
                }
            }
            ForEach(weekdayOrder, id: \.self) { wd in
                HStack(spacing: cellSpacing) {
                    Text(Calendar.current.shortWeekdaySymbols[wd])
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .trailing)
                    ForEach(hours, id: \.self) { h in
                        cell(count: stats.grid[wd][h], maxCount: maxCount)
                    }
                }
            }
        }
    }

    private func cell(count: Int, maxCount: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(cellColor(count: count, maxCount: maxCount))
            .frame(width: cellSize, height: cellSize)
            .help(count > 0 ? String(localized: "\(count) releases") : "")
    }

    private func cellColor(count: Int, maxCount: Int) -> Color {
        guard count > 0 else { return Color.secondary.opacity(0.10) }
        // Scale opacity by intensity, with a visible floor so a single release
        // still reads clearly against the empty cells.
        let intensity = Double(count) / Double(maxCount)
        return Color.accentColor.opacity(0.28 + 0.62 * intensity)
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Fewer").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.10, 0.34, 0.58, 0.82, 0.90], id: \.self) { op in
                RoundedRectangle(cornerRadius: 2)
                    .fill(op <= 0.10 ? Color.secondary.opacity(0.10) : Color.accentColor.opacity(op))
                    .frame(width: 12, height: 12)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Metrics

    private let cellSize: CGFloat = 15
    private let cellSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 30

    /// "3 PM" / "3p" where the locale writes clock times that way, "15:00" / "15"
    /// where it doesn't.
    ///
    /// Asked of the locale rather than hard-coded: this used to render 12-hour
    /// everywhere for compactness, which put "около 6 PM" in front of a Russian
    /// reader who writes 18:00 — a foreign notation, not a shorter one. The
    /// 24-hour forms are no wider than the ones they replace ("18" against "6p"),
    /// so the axis keeps its `labelWidth`.
    private func hourLabel(_ hour: Int, long: Bool) -> String {
        if uses24HourClock {
            return long ? String(format: "%02d:00", hour) : "\(hour)"
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        if long {
            let meridiem = hour < 12 ? String(localized: "AM") : String(localized: "PM")
            return "\(h12) \(meridiem)"
        }
        let ampm = hour < 12 ? String(localized: "a") : String(localized: "p")
        return "\(h12)\(ampm)"
    }

    /// Whether this locale writes clock times on a 24-hour dial. The "j" template
    /// is the documented way to ask: it resolves to the locale's own hour field,
    /// and only the 12-hour ones carry a day-period ("a") beside it.
    ///
    /// Asked on every call rather than cached in a `static let`. macOS's 24-Hour
    /// Time is a switch a user flips, and a value read once per process would
    /// leave the chart on the old dial until the app was relaunched. A view render
    /// asks for it five times (four axis ticks and the headline).
    private var uses24HourClock: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h"
        return !format.contains("a")
    }
}
