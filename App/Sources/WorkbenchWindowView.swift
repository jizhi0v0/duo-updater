import SwiftUI
import AppKit
import WebKit
import DuoUpdaterCore

/// The unified workbench window — one roomy home for everything the menu-bar
/// popover can't hold. App-centric: the left column lists every scanned app; the
/// right pane shows the selected app through one of two lenses, toggled in the
/// toolbar:
///   • Release Notes — its changelog (recipe → structured → inline HTML → web page).
///   • Traffic       — the exact bytes we've downloaded for it, event by event.
/// A toolbar gear opens Settings as a sheet, so all three former windows
/// (Changelog, Traffic, Settings) now live in this single window.
struct WorkbenchWindowView: View {
    static let windowID = "workbench"

    /// Which lens the detail pane shows. Shared across the selection, so flipping
    /// the toggle keeps you on the same app and just re-frames it.
    enum DetailMode: String, CaseIterable, Identifiable {
        case releaseNotes
        case traffic
        var id: String { rawValue }
        var label: String {
            switch self {
            case .releaseNotes: return "Release Notes"
            case .traffic:      return "Traffic"
            }
        }
    }

    @Bindable var model: AppListModel
    /// The sidebar selection — updated instantly on every arrow-key press so the
    /// highlight tracks the cursor with zero lag.
    @State private var selection: String?
    /// The selection the *detail pane* renders, lagged behind `selection` by a short
    /// debounce. Building the detail (laying out a long changelog, attaching a
    /// WKWebView, the `.id`-forced teardown/rebuild) is the expensive part; doing it
    /// for every intermediate row while the user holds ↑/↓ is what froze the window.
    /// Debouncing means we render the detail once, after the selection settles.
    @State private var detailSelection: String?
    /// The pending debounce, cancelled and restarted on each selection change.
    @State private var detailSettleTask: Task<Void, Never>?
    @State private var mode: DetailMode = .releaseNotes
    /// Sidebar filter text. Empty shows every app; otherwise the list narrows to
    /// apps whose name (or bundle id) contains the query, case/diacritic-insensitively.
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    /// While the window stays open, re-read on-disk versions every 15s so an app
    /// that self-updates in the background surfaces even if you never close/refocus
    /// the window. `refreshLocal()` is network-free and `!isChecking`-guarded.
    private let refreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    /// The sidebar app list. One stable order regardless of the active lens —
    /// pending updates float to the top, everything else alphabetical — so
    /// flipping between Release Notes and Traffic never reshuffles the list under
    /// the user. The lens only changes each row's trailing detail, not its place.
    private var apps: [UpdateResult] {
        model.results.sorted { lhs, rhs in
            if lhs.hasUpdate != rhs.hasUpdate { return lhs.hasUpdate }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }

    /// `apps` narrowed by the search field. A blank query passes everything through;
    /// otherwise we match the query against the app name and bundle id (so
    /// "com.google" finds Chrome too), ignoring case and diacritics.
    private var filteredApps: [UpdateResult] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { result in
            if result.app.name.localizedCaseInsensitiveContains(query) { return true }
            if let bundleID = result.app.bundleID,
               bundleID.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    private func bytes(for result: UpdateResult) -> Int64 {
        model.trafficStats.first { $0.appID == result.app.id }?.totalBytes ?? 0
    }

    /// The app the detail pane shows — keyed off the debounced `detailSelection`,
    /// not the live `selection`, so fast arrow-key scrubbing doesn't rebuild it.
    private var selected: UpdateResult? {
        model.results.first { $0.id == detailSelection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
        } detail: {
            if let selected {
                detail(for: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView(
                    "Select an app",
                    systemImage: "sidebar.left",
                    description: Text(mode == .releaseNotes
                        ? "Pick an app to read its changelog."
                        : "Pick an app to see its download history."))
            }
        }
        .navigationTitle("Duo Updater")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModeSwitcher(mode: $mode)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: SettingsView.windowID) } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .task {
            // First open with no data: full (networked) check. Otherwise, if no
            // user-present check has read TestFlight yet this launch, run one full
            // refresh (the natural moment to surface the TCC prompt); past that a
            // cheap, network-free rescan that catches background self-updates.
            if model.results.isEmpty {
                await model.refresh()
            } else if !model.testFlightReadThisSession {
                await model.refresh()
            } else {
                await model.refreshLocal()
            }
            if selection == nil {
                selection = apps.first?.id
                detailSelection = selection   // first show is immediate, no debounce
            }
        }
        // Refocus → re-read on-disk versions. App-scoped notification, cheap, idempotent.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refreshLocal() }
        }
        // Stationary stay (never lose focus) → the 15s timer keeps versions fresh.
        // Skip ticks while hidden/minimized: refreshing for a window no one sees is
        // wasted work and battery.
        .onReceive(refreshTimer) { _ in
            guard scenePhase != .background else { return }
            Task { await model.refreshLocal() }
        }
        // Menu-bar (.accessory) app: promote to .regular while any window is open
        // — Dock icon, app menu, ⌘-Tab — then drop back when the last one closes.
        // The model ref-counts open windows so the workbench and the Settings
        // window don't fight over the policy.
        .onAppear { model.windowAppeared() }
        .onDisappear { model.windowDisappeared() }
        // Debounce the detail pane: the sidebar highlight (`selection`) follows the
        // arrow keys instantly, but `detailSelection` — what the heavy detail renders
        // — only catches up once the selection holds still for ~160ms. Scrubbing
        // through 40 apps then fires one detail build instead of 40.
        .onChange(of: selection) { _, newValue in
            let name = model.results.first { $0.id == newValue }?.app.name
            Log.changelog.info("perf selection → \(name ?? newValue ?? "nil", privacy: .public) [mode=\(mode.rawValue, privacy: .public)]")
            detailSettleTask?.cancel()
            detailSettleTask = Task {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                detailSelection = newValue
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            AppSearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            List(filteredApps, selection: $selection) { result in
                WorkbenchSidebarRow(
                    result: result,
                    mode: mode,
                    bytes: bytes(for: result),
                    isSelected: result.id == selection,
                    isRunning: model.isRunning(result))
                    .tag(result.id)
            }
            .overlay {
                // No match for the current filter — say so rather than show a blank list.
                if filteredApps.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            Divider()
            totalFooter
        }
    }

    /// Grand-total downloaded, carried over from the old Traffic window's header so
    /// the byte count isn't lost in the app-centric layout.
    private var totalFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Total downloaded")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(ByteFormat.string(model.trafficTotalBytes))
                    .font(.callout.weight(.semibold)).monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for result: UpdateResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(result: result, mode: mode, model: model)
            Divider()
            switch mode {
            case .releaseNotes: ReleaseNotesPane(result: result, model: model)
            case .traffic:      TrafficPane(result: result, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Workbench action

/// The selected app's primary action, surfaced in the workbench detail header so a
/// user reading an update's release notes can act on it right there — instead of
/// having to reopen the menu-bar popover. A deliberately focused mirror of the
/// popover's `trailing`: it covers the common, safe one-click states (install
/// progress, Update, Restart, Relaunch) and otherwise stays out of the way, leaving
/// the gated cases (major upgrades, region locks) to the popover's richer affordances.
private struct WorkbenchActionView: View {
    let result: UpdateResult
    @Bindable var model: AppListModel

    private var stage: InstallStage? { model.installing[result.id] }

    var body: some View {
        if let stage {
            installProgress(stage)
        } else if model.relaunching.contains(result.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Relaunching…").font(.callout).foregroundStyle(.secondary)
            }
        } else if model.awaitingQuitConfirm[result.id] != nil {
            Button("Relaunch") { model.confirmQuit(result.id, proceed: true) }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Quit the app to finish installing the update, then reopen it")
        } else if let staged = model.actionableStaged(result) {
            Button("Relaunch") { Task { await model.relaunchStagedUpdate(result) } }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("\(result.app.name) already downloaded \(staged.version) — relaunch to apply it")
        } else if model.needsRestart.contains(result.id) && !result.hasUpdate {
            Button("Restart") { Task { await model.restart(result) } }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Running an older build — restart to apply the installed update")
        } else if model.isActionableUpdate(result) {
            updateAction
        }
    }

    /// The install action for an actionable update, mirroring the popover's routing
    /// for the one-click-safe cases. Major upgrades and region/compat-gated App Store
    /// apps are intentionally NOT one-click here — they keep their explanatory
    /// popover affordances in the menu bar — so we show a hint that points there.
    @ViewBuilder
    private var updateAction: some View {
        if model.vendorDefersToSelfUpdater(result) {
            // Running self-updating vendor app + "defer while running" policy: open
            // its own update path rather than swapping the bundle under it.
            Button("Open") { model.openSelfUpdater(result) }
                .buttonStyle(.bordered)
                .help("\(result.app.name) is running — open it so its own updater applies the update. Quit it, or pick “Always replace” in Settings, to install directly.")
        } else if result.isMajorUpgrade {
            // License-boundary warning lives in the popover; don't one-click it here.
            Label("Major update", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
                .help("Major version upgrade — review and install it from the menu-bar popover")
        } else if model.canAutoInstall(result) {
            Button("Update \(result.remote?.displayVersion ?? "")") { Task { await model.install(result) } }
                .buttonStyle(.borderedProminent)
                .help("Download and install \(result.app.name) \(result.remote?.displayVersion ?? "")")
        } else if model.requiresInstaller(result) {
            Button("Update") { Task { await model.install(result) } }
                .buttonStyle(.bordered)
                .help("Downloads the official installer and opens it (asks for admin)")
        } else if let info = result.remote?.appStore, !info.isRegionMismatch, !info.isLatestMacIncompatible {
            Button("Get") { if let url = info.deepLink ?? result.remote?.downloadURL { NSWorkspace.shared.open(url) } }
                .buttonStyle(.bordered)
                .help("Open in the App Store")
        } else if let url = result.remote?.downloadURL {
            Button("Open page") { NSWorkspace.shared.open(url) }
                .buttonStyle(.bordered)
                .help("Open the official download page")
        }
    }

    @ViewBuilder
    private func installProgress(_ stage: InstallStage) -> some View {
        HStack(spacing: 8) {
            if case .downloading(let f) = stage {
                ProgressView(value: f).frame(width: 80).controlSize(.small)
                Text("\(Int(f * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            } else {
                ProgressView().controlSize(.small)
                Text(stageLabel(stage)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func stageLabel(_ stage: InstallStage) -> String {
        switch stage {
        case .checking: return "Checking"
        case .downloading(let f): return "\(Int(f * 100))%"
        case .verifyingSignature, .verifyingCodeSignature: return "Verifying"
        case .extracting: return "Extracting"
        case .installing: return "Installing"
        case .runningCommand: return "Installing"
        case .done: return "Done"
        }
    }
}

// MARK: - Mode switcher

/// The detail-lens switcher, wrapping a native `NSSegmentedControl`. SwiftUI's
/// `.segmented` Picker sizes each segment to its label (so "Release Notes" and
/// "Traffic" came out lopsided); `NSSegmentedControl.segmentDistribution =
/// .fillEqually` makes both segments equal width, and the native control keeps the
/// system's standard material/selection look rather than a hand-painted fill.
private struct ModeSwitcher: NSViewRepresentable {
    @Binding var mode: WorkbenchWindowView.DetailMode

    private var modes: [WorkbenchWindowView.DetailMode] { WorkbenchWindowView.DetailMode.allCases }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: modes.map(\.label),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onChange = { mode = modes[$0] }
        control.selectedSegment = modes.firstIndex(of: mode) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onChange: ((Int) -> Void)?
        @objc func changed(_ sender: NSSegmentedControl) { onChange?(sender.selectedSegment) }
    }
}

// MARK: - Sidebar row

private struct WorkbenchSidebarRow: View {
    let result: UpdateResult
    let mode: WorkbenchWindowView.DetailMode
    let bytes: Int64
    /// Whether this row is the selected one. The selection highlight is blue, and so
    /// is the update tint — so a selected update row was blue-on-blue (unreadable).
    /// When selected we render the version line in the emphasized foreground (white
    /// over the highlight) instead of the tint; the arrow still conveys "update".
    let isSelected: Bool
    /// Whether the app currently has a running process — shows the green live dot.
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(result.app.name).font(.body).lineLimit(1)
                    if isRunning { RunningIndicator(size: 5) }
                    ChannelTag(channel: result.app.releaseChannel)
                }
                subtitle
            }
            Spacer()
            if mode == .traffic, bytes > 0 {
                Text(ByteFormat.string(bytes))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var subtitle: some View {
        if case .updateAvailable(let latest) = result.status {
            // Same-marketing build bump (JetBrains EAP, Surge): show the builds so it
            // doesn't read as a no-op "2026.2 → 2026.2".
            let bump = result.buildBump(latest: latest)
            let from = bump.map { "\(result.app.shortVersion ?? "?") (\($0.installed))" }
                ?? (result.app.shortVersion ?? "?")
            let to = bump.map { "\(latest) (\($0.remote))" } ?? latest
            Text("\(from) → \(to)")
                .font(.caption)
                // White over the blue highlight when selected; blue tint otherwise.
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .lineLimit(1)
        } else {
            Text("v\(result.app.shortVersion ?? "?")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - Detail header

private struct DetailHeader: View {
    let result: UpdateResult
    let mode: WorkbenchWindowView.DetailMode
    @Bindable var model: AppListModel

    /// The vendor page to link out to in Release Notes mode.
    private var changelogURL: URL? {
        result.remote?.changelogURL ?? ChangelogCatalog.url(forBundleID: result.app.bundleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(result.app.name).font(.title2).bold()
                        if model.isRunning(result) { RunningIndicator(size: 7) }
                        ChannelTag(channel: result.app.releaseChannel)
                    }
                    versionLine
                }
                Spacer()
                // The contextual primary action (Update / Restart / Relaunch / Get),
                // so an update can be acted on right here while its notes are open —
                // no trip back to the menu-bar popover.
                WorkbenchActionView(result: result, model: model)
                if mode == .releaseNotes, let url = changelogURL {
                    Link(destination: url) {
                        Label("Open page", systemImage: "safari")
                    }
                    .font(.callout)
                }
            }
            // Surface an install error inline, same as the popover row does.
            if let error = model.installErrors[result.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note = model.installNotes[result.id] {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var versionLine: some View {
        if case .updateAvailable(let latest) = result.status {
            let bump = result.buildBump(latest: latest)
            let from = bump.map { "\(result.app.shortVersion ?? "?") (\($0.installed))" }
                ?? (result.app.shortVersion ?? "?")
            let to = bump.map { "\(latest) (\($0.remote))" } ?? latest
            Text("\(from)  →  \(to)")
                .font(.callout).foregroundStyle(.tint)
        } else {
            Text("v\(result.app.shortVersion ?? "?") · up to date")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Release notes pane

/// The Release Notes lens. Source priority: a hand-authored recipe (full history,
/// loaded through the model's session cache so re-opening an app is instant and
/// spinner-free) → a GitHub release body parsed into entries → inline Sparkle/App
/// Store HTML → the vendor's page embedded in a (cached) web view → "nothing to
/// show".
private struct ReleaseNotesPane: View {
    let result: UpdateResult
    @Bindable var model: AppListModel

    private var changelogURL: URL? {
        result.remote?.changelogURL ?? ChangelogCatalog.url(forBundleID: result.app.bundleID)
    }

    var body: some View {
        // `changelogState(for:)` is non-nil only for recipe-backed apps. The load
        // itself is owned by the model (not this view), so switching apps never
        // cancels an in-flight fetch — the spinner shows once, then the cached
        // result renders instantly on every later visit.
        if let state = model.changelogState(for: result) {
            switch state {
            case .loaded(let changelog):
                ChangelogEntriesView(changelog: changelog)
                    .onAppear { Log.changelog.info("perf pane=recipe \(result.app.name, privacy: .public) (\(changelog.entries.count, privacy: .public) entries)") }
            case .failed:
                fallback
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { model.ensureChangelogLoading(for: result) }
            }
        } else if let changelog = result.remote?.structuredChangelog {
            ChangelogEntriesView(changelog: changelog)
                .onAppear { Log.changelog.info("perf pane=structured \(result.app.name, privacy: .public)") }
        } else if let html = result.remote?.releaseNotesHTML {
            ScrollView {
                ReleaseNotesText(text: html, format: .forSource(result.remote?.sourceName))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onAppear { Log.changelog.info("perf pane=inline-html \(result.app.name, privacy: .public) (\(html.count, privacy: .public) chars, src=\(result.remote?.sourceName ?? "?", privacy: .public))") }
        } else if let url = changelogURL {
            CachedWebView(url: url)
                .onAppear { Log.changelog.info("perf pane=webview \(result.app.name, privacy: .public) \(url.host ?? "?", privacy: .public)") }
        } else {
            emptyNotes
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let url = changelogURL {
            CachedWebView(url: url)
        } else if let html = result.remote?.releaseNotesHTML {
            ScrollView {
                ReleaseNotesText(text: html, format: .forSource(result.remote?.sourceName))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            emptyNotes
        }
    }

    private var emptyNotes: some View {
        ContentUnavailableView {
            Label("No release notes", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("\(result.remote?.sourceName ?? "This source") doesn’t publish a changelog we can read.")
        } actions: {
            if let dl = result.remote?.downloadURL {
                Link("Open download page", destination: dl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Which way to lay out a multi-version changelog. Persisted so the choice sticks
/// across apps and launches.
private enum ChangelogLayout: String, CaseIterable {
    case columns  // master/detail: version list on the left, selected notes right
    case list     // one long top-down scroll of every version

    var symbol: String {
        switch self {
        case .columns: return "sidebar.squares.left"
        case .list:    return "list.bullet"
        }
    }
}

/// Lays out a parsed `Changelog`. Shared by the recipe and GitHub-release paths.
/// A single-entry changelog (VS Code, VLC) renders full width. A multi-version one
/// (HBuilderX, Slack, …) offers two layouts the user toggles between (remembered):
/// `columns` — a master/detail with a version list on the left and the selected
/// version's notes on the right, best for content-heavy changelogs; or `list` — one
/// long top-down scroll, better when each version is only a line or two.
private struct ChangelogEntriesView: View {
    let changelog: Changelog
    @AppStorage("changelogLayout") private var layout: ChangelogLayout = .columns
    @State private var selection = 0

    /// Content-driven rail width. For each row take the wider of its two lines — the
    /// title/version (callout) and the date subtitle (caption2) — since a short
    /// version like "3.6.8" can still carry a longer date ("4 July, 2023"). Sort
    /// those, then take a HIGH percentile, not the median: a title-based changelog
    /// (Codex) has many long titles and the median would clip the upper half. The
    /// 85th percentile fits the great majority; the upper clamp caps a lone runaway
    /// title (and the lower clamp keeps a terse changelog from getting cramped).
    /// Measured with AppKit since the labels are known up front — no GeometryReader.
    private var railWidth: CGFloat {
        let labelFont = NSFont.preferredFont(forTextStyle: .callout)
        let dateFont = NSFont.preferredFont(forTextStyle: .caption2)
        let rowWidths = changelog.entries
            .map { entry -> CGFloat in
                let labelW = (ChangelogVersionList.label(for: entry) as NSString)
                    .size(withAttributes: [.font: labelFont]).width
                let dateW = (entry.date?.isEmpty == false)
                    ? (entry.date! as NSString).size(withAttributes: [.font: dateFont]).width
                    : 0
                return max(labelW, dateW)
            }
            .sorted()
        guard !rowWidths.isEmpty else { return 200 }
        let pick = rowWidths[Int((Double(rowWidths.count - 1) * 0.85).rounded())]
        // Row chrome: line .horizontal(10)×2 + rail .padding(8)×2.
        let chrome: CGFloat = 20 + 16
        return min(max(pick + chrome, 140), 360)
    }

    var body: some View {
        if changelog.entries.count <= 1 {
            // Nothing to navigate — render the single entry full width, no toggle.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                        ChangelogEntryView(entry: entry)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 0) {
                // Slim header carrying the layout toggle, right-aligned.
                HStack(spacing: 0) {
                    Spacer()
                    Picker("Layout", selection: $layout) {
                        ForEach(ChangelogLayout.allCases, id: \.self) { option in
                            Image(systemName: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Switch between side-by-side and long-scroll layouts")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                switch layout {
                case .columns: columnsBody
                case .list:    listBody
                }
            }
            // New changelog (app switch) → select the newest entry again.
            .onChange(of: changelog) { selection = 0 }
        }
    }

    /// Master/detail: a content-sized version rail + the selected version's notes.
    private var columnsBody: some View {
        // Clamp: the same view can be reused when the user switches apps, so a stale
        // selection from a longer changelog must not index past a shorter one.
        let index = min(max(selection, 0), changelog.entries.count - 1)
        return HStack(spacing: 0) {
            ChangelogVersionList(entries: changelog.entries, selection: $selection)
                .frame(width: railWidth)
            Divider()
            ScrollView {
                ChangelogEntryView(entry: changelog.entries[index])
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Re-id on switch so the right pane scrolls back to the top instead of
            // keeping the previous version's scroll offset.
            .id(index)
        }
    }

    /// One long top-down scroll of every version. LazyVStack so a long changelog
    /// doesn't lay out every selectable, `fixedSize` bullet synchronously on appear.
    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                    ChangelogEntryView(entry: entry)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The left rail of the master/detail changelog: one selectable row per version,
/// newest first. The selected row is tinted; clicking it drives the detail pane.
private struct ChangelogVersionList: View {
    let entries: [Changelog.Entry]
    @Binding var selection: Int

    var body: some View {
        let selected = min(max(selection, 0), entries.count - 1)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Button { selection = index } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.label(for: entry))
                                .font(.callout)
                                .fontWeight(index == selected ? .semibold : .regular)
                                .lineLimit(1)
                            if let date = entry.date, !date.isEmpty {
                                Text(date).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            index == selected ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    /// Prefer the human title (post-style entries), else the version string.
    /// Static so the parent can measure label widths to size the rail.
    static func label(for entry: Changelog.Entry) -> String {
        if let title = entry.title, !title.isEmpty { return title }
        return entry.version.isEmpty ? "—" : entry.version
    }
}

// MARK: - Traffic pane

/// The Traffic lens: one app's per-update download history, newest first. When the
/// app has never recorded a measured download we say so plainly — and why (brew,
/// App Store, and "open the app's own updater" downloads aren't measured here).
private struct TrafficPane: View {
    let result: UpdateResult
    @Bindable var model: AppListModel

    private var stat: AppTrafficStat? {
        model.trafficStats.first { $0.appID == result.app.id }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if let stat, !stat.events.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(ByteFormat.string(stat.totalBytes)) · \(stat.totalBytes) bytes")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Divider()
                    ForEach(events(stat), id: \.self) { event in
                        eventRow(event)
                        Divider()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView {
                Label("No downloads measured", systemImage: "chart.bar")
            } description: {
                Text("Traffic appears here after an update we download ourselves (Sparkle, a vendor site, GitHub, or a pkg). Homebrew, the App Store, and apps that update through their own built-in updater aren’t measured.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func events(_ stat: AppTrafficStat) -> [TrafficEvent] {
        stat.events.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func eventRow(_ event: TrafficEvent) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(versionTransition(event)).font(.callout)
                HStack(spacing: 6) {
                    if let source = event.sourceName { Text(source) }
                    Text(Self.dateFormatter.string(from: event.date))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(event.bytes) bytes")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func versionTransition(_ event: TrafficEvent) -> String {
        switch (event.fromVersion, event.toVersion) {
        case let (from?, to?): return "\(from) → \(to)"
        case let (nil, to?): return to
        case let (from?, nil): return from
        case (nil, nil): return "Update"
        }
    }
}

// MARK: - One changelog entry

/// One changelog block: either a classic version heading, or a post-style title
/// with date/build metadata underneath.
private struct ChangelogEntryView: View {
    let entry: Changelog.Entry

    private var displayDate: String? {
        guard let date = entry.date else { return nil }
        return Self.displayDate(for: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = entry.title {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title).font(.title3).bold()
                        if !entry.version.isEmpty {
                            Text(entry.version).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let date = displayDate {
                        Text(date).font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.version).font(.title3).bold()
                    if let date = displayDate {
                        Text(date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private static func displayDate(for raw: String) -> String {
        if let parsed = iso8601Fractional.date(from: raw) ?? iso8601.date(from: raw) {
            return ymd.string(from: parsed)
        }
        return raw
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Inline release notes

/// Renders inline notes. The wire format differs by source: GitHub bodies are
/// GitHub-flavored markdown, Sparkle `<description>` blocks are HTML, and the App
/// Store's `releaseNotes` is plain text whose newlines carry the layout.
private struct ReleaseNotesText: View {
    enum Format {
        case markdown   // GitHub release body
        case html       // Sparkle <description>
        case plainText  // App Store releaseNotes — newline-delimited, no markup

        static func forSource(_ name: String?) -> Format {
            switch name {
            case "GitHub": return .markdown
            case "App Store": return .plainText
            default: return .html
            }
        }
    }

    let text: String
    let format: Format

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .tint(.accentColor)
    }

    private var attributed: AttributedString {
        let start = Date()
        defer {
            let ms = Date().timeIntervalSince(start) * 1000
            // The .html path uses NSAttributedString's WebKit-backed parser, which
            // runs synchronously on the main actor and is a classic UI-freeze
            // source. Log when any conversion runs long.
            if ms > 5 {
                Log.changelog.info("perf release-notes \(String(describing: format), privacy: .public) parse: \(ms, format: .fixed(precision: 1), privacy: .public)ms (\(text.count, privacy: .public) chars)")
            }
        }
        switch format {
        case .markdown:
            if let a = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) { return a }
        case .html:
            if let data = text.data(using: .utf8),
               let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil),
               let a = try? AttributedString(ns, including: \.appKit) {
                return a
            }
        case .plainText:
            break
        }
        return AttributedString(text)
    }
}

// MARK: - Cached web view

/// A `WKWebView` wrapper that reuses one loaded instance per URL, so switching
/// back to a vendor changelog page you've already opened shows it instantly
/// instead of reloading (and re-spinning) every time. Capped at a handful of
/// instances, evicted oldest-first.
///
/// Each live instance holds its own WebContent process (~70–130MB), so the cap
/// is the memory ceiling: limit × per-page. Kept low on purpose — 5 covers
/// typical back-and-forth between a few apps without pinning N processes.
@MainActor
private enum WebViewCache {
    private static var byURL: [String: WKWebView] = [:]
    private static var guardians: [String: WebGuardian] = [:]
    private static var order: [String] = []
    private static let limit = 5

    static func view(for url: URL) -> WKWebView {
        let key = url.absoluteString
        if let cached = byURL[key] {
            // Touch: most-recently-used moves to the back of the eviction queue.
            order.removeAll { $0 == key }
            order.append(key)
            Log.changelog.info("perf webview cache HIT: \(url.host ?? key, privacy: .public)")
            return cached
        }
        // Miss: `WKWebView()` spins up a web-content process synchronously on the
        // main actor — a prime suspect for the freeze when switching to a
        // web-backed changelog app. Time it.
        let start = Date()
        let view = WKWebView()
        // Set the delegate before loading so the guardian sees the very first
        // navigation start and arms its watchdog on it.
        let guardian = WebGuardian()
        view.navigationDelegate = guardian
        view.load(URLRequest(url: url))
        let ms = Date().timeIntervalSince(start) * 1000
        Log.changelog.info("perf webview cache MISS: created in \(ms, format: .fixed(precision: 1), privacy: .public)ms for \(url.host ?? key, privacy: .public)")
        byURL[key] = view
        guardians[key] = guardian
        order.append(key)
        if order.count > limit {
            let evict = order.removeFirst()
            guardians[evict]?.cancel()
            guardians[evict] = nil
            byURL[evict] = nil
        }
        return view
    }
}

/// Per-WebView watchdog. WKWebView won't surface two failure modes on its own,
/// so we recover them here:
///   • the WebContent process crashing or being killed → blank page, no retry;
///   • a load that wedges and never calls back → spinner forever.
/// Both recover the same way — reload in place, which respawns the process. The
/// recovery has to land on the mounted instance, so we reload it rather than
/// swap in a new one. Bounded by `maxAutoReloads` so a persistently-broken page
/// doesn't reload-loop; a healthy `didFinish` resets the budget.
@MainActor
private final class WebGuardian: NSObject, WKNavigationDelegate {
    private var watchdog: Task<Void, Never>?
    private var autoReloads = 0
    private let maxAutoReloads = 2
    private let timeout: Duration = .seconds(20)

    func cancel() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func armWatchdog(_ webView: WKWebView) {
        watchdog?.cancel()
        let timeout = self.timeout
        watchdog = Task { [weak self, weak webView] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, let webView else { return }
            self.recover(webView, reason: "load timed out")
        }
    }

    private func recover(_ webView: WKWebView, reason: String) {
        guard autoReloads < maxAutoReloads else {
            Log.changelog.error("perf webview giving up after \(self.maxAutoReloads) reloads: \(webView.url?.host ?? "?", privacy: .public)")
            return
        }
        autoReloads += 1
        Log.changelog.error("perf webview recover (\(reason, privacy: .public)) reload #\(self.autoReloads): \(webView.url?.host ?? "?", privacy: .public)")
        webView.stopLoading()
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        armWatchdog(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        cancel()
        autoReloads = 0   // a clean load earns back the reload budget
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cancel()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        cancel()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        cancel()
        recover(webView, reason: "process terminated")
    }
}

private struct CachedWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WebViewCache.view(for: url)
    }

    // The cached view already holds the loaded page; nothing to do on update.
    func updateNSView(_ view: WKWebView, context: Context) {}
}
