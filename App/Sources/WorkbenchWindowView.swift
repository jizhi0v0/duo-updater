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
    /// Collapsed/expanded state for the sidebar trees. All open by default.
    @State private var appsExpanded = true
    @State private var brewExpanded = true
    /// The Rollback section (apps with a restorable backup) — its own collapse state.
    /// Collapsed by default: it's a recovery surface that can list many apps, so the
    /// always-visible header (with its count pill) is the discovery cue, and expanding
    /// it is opt-in rather than permanently crowding the Apps tree above.
    @State private var rollbackExpanded = false

    /// Negative top padding that cancels the top inset VSplitView adds to each pane's
    /// sidebar list (see `splitRegion`). Measured at 10pt; kept as one constant so the
    /// two panes stay in sync and it's a single knob to retune.
    private static let splitPaneListInset: CGFloat = -10
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
    ///
    /// Brew-managed casks are excluded here: they live under the Brew tree instead
    /// (the "cask 只在此面板" rule), so they never appear in both places.
    private var apps: [UpdateResult] {
        model.results
            .filter { $0.remote?.sourceName != "Homebrew" }
            .sorted { lhs, rhs in
                if lhs.hasUpdate != rhs.hasUpdate { return lhs.hasUpdate }
                return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
            }
    }

    /// Brew-managed casks, updates first then alphabetical — the cask half of the
    /// Brew tree. (The formula half is `model.brewFormulae` — all top-level leaves.)
    private var brewCasks: [UpdateResult] {
        model.brewCaskResults.sorted { lhs, rhs in
            if lhs.hasUpdate != rhs.hasUpdate { return lhs.hasUpdate }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }

    /// Apps that have a restorable backup on disk — the ones the user can roll back
    /// to a prior version. Drawn from `model.backupVersions` (the on-disk backup index)
    /// rather than the install pipeline, so a just-updated app shows up here even
    /// though it no longer has a *pending* update. A no-op rollback is filtered out:
    /// once the on-disk version already matches the backup (e.g. right after a
    /// rollback), there's nothing left to undo, so the row drops away on its own.
    private var rollbackableApps: [UpdateResult] {
        model.results
            .filter { result in
                guard let backup = model.backupVersion(result.id) else { return false }
                return result.app.shortVersion != backup
            }
            .sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
    }

    /// Whether to show the Rollback section at all — hidden when nothing is restorable.
    private var hasRollback: Bool { !rollbackableApps.isEmpty }

    /// Content-fitting height for the (bottom-pinned) Rollback list, capped so a long
    /// list scrolls internally instead of crowding out the Apps tree above it.
    private var rollbackListHeight: CGFloat {
        min(CGFloat(rollbackableApps.count) * 34 + 12, 240)
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

    /// The Brew-tree formula selected, when the selection is a formula row (tagged
    /// `brew:formula:<name>`) rather than an app. Drives the formula detail pane.
    private var selectedFormula: BrewInstalledFormula? {
        let prefix = "brew:formula:"
        guard let id = detailSelection, id.hasPrefix(prefix) else { return nil }
        let name = String(id.dropFirst(prefix.count))
        return model.brewFormulae.first { $0.name == name }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
        } detail: {
            if let selected {
                detail(for: selected)
                    .id(selected.id)
            } else if let formula = selectedFormula {
                FormulaDetailPane(formula: formula, model: model)
                    .id("brew:formula:\(formula.name)")
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
            // Traffic lens hidden for now — the metering wasn't pulling its weight, so
            // the Release Notes/Traffic switcher is gone and the detail is always
            // Release Notes. (Underlying TrafficStore still records; only the UI is
            // hidden, so this is reversible.)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: SettingsView.windowID)
                    model.surfaceWindow(sceneID: SettingsView.windowID)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .task {
            // A "Changelog" deep-link from the menu row lands instantly, before the
            // (possibly networked) refresh below — the row already exists in
            // `model.results`, so the detail can render right away.
            let hadRequest = model.requestedWorkbenchAppID != nil
            if hadRequest { applyRequestedApp() }
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
            if !hadRequest && selection == nil {
                selection = apps.first?.id
                detailSelection = selection   // first show is immediate, no debounce
            }
        }
        // Brew tree data (formulae + the cask set derives from results above).
        .task { await model.refreshBrewFormulae() }
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
        // Keep lifecycle bookkeeping in the model so focus/badge refresh behavior
        // matches the other top-level windows.
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
        // A "Changelog" deep-link arriving while the window is already open — the
        // `.task` above only fires on a fresh open, so catch the in-flight case here.
        .onChange(of: model.requestedWorkbenchAppID) { applyRequestedApp() }
    }

    /// Honor a pending "Changelog" deep-link to a specific app, then clear it so the
    /// selection isn't forced again on the next open. Bypasses the arrow-key debounce
    /// (sets `detailSelection` directly) — a deliberate jump should land instantly —
    /// and forces the Release Notes lens so it opens on the changelog, not Traffic.
    private func applyRequestedApp() {
        guard let id = model.requestedWorkbenchAppID else { return }
        model.requestedWorkbenchAppID = nil
        mode = .releaseNotes
        selection = id
        detailSelection = id
    }

    // MARK: - Sidebar

    /// A prominent, full-width-clickable group header that lives OUTSIDE the
    /// scrolling lists (so both Apps and Brew titles are always on screen at once —
    /// you never have to scroll the app list to discover Brew). The whole row
    /// toggles the section; the rotating chevron shows collapsed/expanded and the
    /// trailing pill shows the item count.
    @ViewBuilder
    private func sectionHeader<Accessory: View>(
        _ title: String, systemImage: String, count: Int, expanded: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    Image(systemName: systemImage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Optional trailing control (e.g. Brew's bulk Upgrade) — a sibling of the
            // collapse button, so tapping it never toggles the section.
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Whether there's anything brew-managed to show a Brew tree for. Non-brew users
    /// see only the Apps tree (no empty Brew header).
    private var hasBrew: Bool {
        !brewCasks.isEmpty || !model.brewFormulae.isEmpty
    }

    /// Total brew items, for the Brew header's count pill and its list height.
    private var brewItemCount: Int {
        brewCasks.count + model.brewFormulae.count
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            AppSearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            // Fill the middle and top-align: without this, when both trees are
            // collapsed (no list filling the space) the outer VStack would center the
            // headers vertically, floating them in the middle with empty space above.
            splitRegion
                .frame(maxHeight: .infinity, alignment: .top)

            // Rollback pinned to the bottom, below the Apps/Brew split (so it never
            // disturbs that draggable divider). Only shown when something is
            // restorable; the always-visible header is the discovery surface for
            // apps that have already updated and dropped out of the lists above.
            if hasRollback {
                Divider()
                rollbackHeader
                if rollbackExpanded { rollbackListView }
            }
        }
    }

    private var appsHeader: some View {
        sectionHeader("Apps", systemImage: "square.grid.2x2.fill",
                      count: filteredApps.count, expanded: $appsExpanded)
    }

    private var brewHeader: some View {
        sectionHeader("Brew", systemImage: "mug.fill",
                      count: brewItemCount, expanded: $brewExpanded) {
            brewBulkUpgrade
        }
    }

    private var rollbackHeader: some View {
        sectionHeader("Rollback", systemImage: "arrow.uturn.backward",
                      count: rollbackableApps.count, expanded: $rollbackExpanded)
    }

    /// The Rollback list: every app with a backup we can restore, each with an inline
    /// "Roll back to vX" action. Reuses `$selection`, so clicking a row also opens that
    /// app's changelog in the detail pane — useful context before undoing an update.
    private var rollbackListView: some View {
        List(selection: $selection) {
            ForEach(rollbackableApps) { result in
                WorkbenchRollbackRow(
                    result: result,
                    target: model.backupVersion(result.id) ?? "previous",
                    model: model)
                    .tag(result.id)
            }
        }
        .listStyle(.sidebar)
        .frame(height: rollbackListHeight)
    }

    /// Bulk "Upgrade All" for the Brew tree — runs `brew upgrade --formula` (all
    /// outdated CLI formulae at once). Only shown when there are formulae to upgrade;
    /// casks stay per-row (their own distribution channel). A spinner replaces it
    /// while the bulk run is in flight.
    @ViewBuilder
    private var brewBulkUpgrade: some View {
        if !model.brewOutdatedFormulae.isEmpty {
            if model.brewUpgrading {
                HStack(spacing: 6) {
                    if let progress = model.brewBulkProgressText {
                        Text(progress)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView().controlSize(.small)
                }
            } else {
                Button("Upgrade All") { Task { await model.upgradeBrewFormulae() } }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    // A per-row upgrade is already holding brew's lock — a bulk run
                    // would just fail, so disable it until that row finishes.
                    .disabled(!model.upgradingFormulae.isEmpty)
                    .help("Runs `brew upgrade --formula` — upgrades every outdated CLI formula at once. Casks are managed per-row above.")
            }
        }
    }

    /// The two trees. Only when BOTH are open does it use a native VSplitView
    /// (NSSplitView) — that's the case that needs a draggable divider, and the
    /// system splitter resizes the NSScrollView-backed lists without the ghosting a
    /// hand-rolled per-frame resize causes. The moment either tree is collapsed there's
    /// nothing to resize, so it drops to a plain stack with a thin Divider — avoiding
    /// NSSplitView's heavy splitter bar rendering as a black line against a 34pt
    /// collapsed pane.
    @ViewBuilder
    private var splitRegion: some View {
        if hasBrew && appsExpanded && brewExpanded {
            VSplitView {
                // VSplitView gives each pane's sidebar list a ~10pt top inset that the
                // collapsed (plain-VStack) layout doesn't, so the list sat 10pt lower
                // under its header only while the split was engaged (measured: the rows
                // shifted down exactly 20px @2x). Pull each list back up by that inset so
                // both layouts hug the header identically.
                VStack(spacing: 0) { appsHeader; appsListView.padding(.top, Self.splitPaneListInset) }
                    .frame(minHeight: 120)
                VStack(spacing: 0) { brewHeader; brewListView.padding(.top, Self.splitPaneListInset) }
                    .frame(minHeight: 100)
            }
            // Persist the divider position across launches. VSplitView exposes no
            // position binding, so we reach the backing NSSplitView and give it an
            // autosaveName — AppKit then saves/restores the split to UserDefaults.
            .background(SplitViewAutosave(name: "duo.workbench.sidebarSplit"))
        } else {
            VStack(spacing: 0) {
                appsHeader
                if appsExpanded { appsListView.frame(maxHeight: .infinity) }
                if hasBrew {
                    Divider()
                    brewHeader
                    if brewExpanded { brewListView.frame(maxHeight: .infinity) }
                }
            }
        }
    }

    /// The Apps tree's scrolling list (extracted so the split layout above stays
    /// readable).
    private var appsListView: some View {
        List(selection: $selection) {
            ForEach(filteredApps) { result in
                WorkbenchSidebarRow(
                    result: result,
                    mode: mode,
                    bytes: bytes(for: result),
                    isSelected: result.id == selection,
                    isRunning: model.isRunning(result),
                    needsRestart: model.needsRestart.contains(result.id),
                    runningVersion: model.restartFromVersion(result.id))
                    .tag(result.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if filteredApps.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    /// The Brew tree's scrolling list: brew-managed casks (reusing the app row + its
    /// existing install path) above outdated CLI formulae (their own inline action).
    private var brewListView: some View {
        List(selection: $selection) {
            ForEach(brewCasks) { result in
                WorkbenchSidebarRow(
                    result: result,
                    mode: mode,
                    bytes: bytes(for: result),
                    isSelected: result.id == selection,
                    isRunning: model.isRunning(result),
                    needsRestart: model.needsRestart.contains(result.id),
                    runningVersion: model.restartFromVersion(result.id))
                    .tag(result.id)
            }
            ForEach(model.brewFormulae) { formula in
                BrewFormulaSidebarRow(formula: formula, model: model)
                    .tag("brew:formula:\(formula.name)")
            }
        }
        .listStyle(.sidebar)
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
        case .queued: return "Queued"
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

// MARK: - Split-view autosave

/// Gives the `VSplitView`'s backing `NSSplitView` an `autosaveName` so AppKit
/// persists its divider position across launches (SwiftUI's `VSplitView` exposes
/// no position binding of its own). Introspects the window's view tree for the
/// FIRST horizontal-divider split view — `isVertical == false` skips the
/// `NavigationSplitView`'s own (vertical-divider) sidebar split, which we don't
/// want to bind to.
private struct SplitViewAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async { [weak probe] in
            guard let root = probe?.window?.contentView,
                  let split = Self.firstHorizontalSplit(in: root) else { return }
            // Setting the same autosaveName on every appearance is idempotent; AppKit
            // restores the saved position when the name is assigned.
            if split.autosaveName != name { split.autosaveName = name }
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Depth-first search for a split view whose dividers are horizontal (panes
    /// stacked vertically — what VSplitView produces).
    private static func firstHorizontalSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, !split.isVertical { return split }
        for sub in view.subviews {
            if let found = firstHorizontalSplit(in: sub) { return found }
        }
        return nil
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
    /// Self-updated on disk, waiting for a relaunch to take effect (the "Restart"
    /// state). When set, the subtitle shows running → installed instead of a bare
    /// version, so the row says what the restart will land.
    let needsRestart: Bool
    /// The "from" side of a restart line, pre-formatted by `restartFromVersion`: the
    /// running build, or "marketing (build)" when the pre-update marketing version is
    /// recoverable from the rollback backup. nil when not lagging an on-disk build.
    let runningVersion: String?

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
        } else if needsRestart, let from = runningVersion {
            // Self-updated on disk: show running version → installed marketing version
            // (build) so "Restart" reads as a real change. `from` is pre-formatted by
            // `restartFromVersion` — the running build, or "marketing (build)" when the
            // pre-update marketing version is recoverable from the rollback backup; the
            // on-disk `to` side carries the marketing version, e.g. "1.7.3 (194)".
            let to = result.restartTargetVersion
            Text("\(from) → \(to)")
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            Text("v\(result.app.shortVersion ?? "?")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - Rollback row

/// One row in the Rollback section: an app with a restorable backup, plus an inline
/// "Roll back" action. Rollback reuses the install pipeline's per-row state, so the
/// in-flight spinner and inline error read off `installing`/`installErrors` exactly
/// like an install does (and the model's own guard stops a rollback from racing one).
private struct WorkbenchRollbackRow: View {
    let result: UpdateResult
    /// The version the backup restores to; "previous" when its marketing version
    /// wasn't recorded.
    let target: String
    @Bindable var model: AppListModel

    private var inFlight: Bool { model.installing[result.id] != nil }
    private var error: String? { model.installErrors[result.id] }
    private var targetLabel: String { target == "previous" ? "previous version" : "v\(target)" }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.app.name).font(.body).lineLimit(1)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text("v\(result.app.shortVersion ?? "?") → \(targetLabel)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if inFlight {
                ProgressView().controlSize(.small)
            } else {
                Button("Roll back") { Task { await model.rollback(result) } }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help("Restore \(result.app.name) \(targetLabel) from the backup taken before its last update")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Brew formula row

/// A CLI-formula row under the Brew tree. Unlike a cask (which reuses
/// `WorkbenchSidebarRow` + the app install path), a formula isn't an app — no
/// icon, channel, or changelog — so it gets this compact row with its own inline
/// `brew upgrade --formula <name>` action.
private struct BrewFormulaSidebarRow: View {
    let formula: BrewInstalledFormula
    @Bindable var model: AppListModel

    // A bulk "Upgrade All" run upgrades every *outdated* formula at once, so each
    // outdated row is part of it — show the same in-flight state and (crucially) hide
    // its Update button so it can't fire a conflicting `brew upgrade` on top of the
    // bulk run. Up-to-date leaves aren't touched by the bulk run, so they stay quiet.
    private var upgrading: Bool {
        model.upgradingFormulae.contains(formula.name) || (model.brewUpgrading && formula.hasUpdate)
    }
    private var error: String? { model.formulaUpgradeErrors[formula.name] }
    private var progressNote: String? { model.formulaUpgradeNotes[formula.name] }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(formula.name).font(.body).lineLimit(1)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if upgrading, let progressNote {
                    // Live brew output ("Downloading…", "Pouring…") so the upgrade
                    // visibly progresses instead of sitting on a bare spinner.
                    Text(progressNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } else if let available = formula.availableVersion {
                    Text("\(formula.installedVersion) → \(available)")
                        .font(.caption).foregroundStyle(.tint).lineLimit(1)
                } else {
                    // Up-to-date leaf: just its version, like an up-to-date app row.
                    Text(formula.installedVersion)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if upgrading {
                ProgressView().controlSize(.small)
            } else if formula.hasUpdate {
                Button("Update") { Task { await model.upgradeBrewFormula(named: formula.name) } }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Formula detail pane

/// The detail pane for a selected Brew formula. A formula isn't an app, so it has
/// no Sparkle/recipe changelog — instead we lazily fetch its GitHub release notes
/// (`BrewFormulaReleaseService`) and render them with the same `ChangelogEntriesView`
/// the app rows use; non-GitHub formulae fall back to a web view of their page.
private struct FormulaDetailPane: View {
    let formula: BrewInstalledFormula
    @Bindable var model: AppListModel

    private var upgrading: Bool { model.upgradingFormulae.contains(formula.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            notes
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Load notes for the upgrade target when there is one, else the installed
        // version (so an up-to-date formula still shows its current release notes).
        .task {
            model.ensureFormulaReleaseLoading(
                name: formula.name,
                version: formula.availableVersion ?? formula.installedVersion)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(formula.name).font(.title2).fontWeight(.semibold)
                if let available = formula.availableVersion {
                    Text("\(formula.installedVersion) → \(available)")
                        .font(.callout).foregroundStyle(.tint)
                } else {
                    Text(formula.installedVersion)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if upgrading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(model.formulaUpgradeNotes[formula.name] ?? "Updating…")
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            } else if formula.hasUpdate {
                Button("Update") { Task { await model.upgradeBrewFormula(named: formula.name) } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var notes: some View {
        switch model.formulaReleaseState(name: formula.name) {
        case .loaded(let release):
            if let changelog = release.changelog {
                ChangelogEntriesView(changelog: changelog)
            } else if let url = release.pageURL {
                CachedWebView(url: url)
            } else {
                noNotes
            }
        default:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noNotes: some View {
        ContentUnavailableView {
            Label("No release notes", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Homebrew doesn’t publish notes for \(formula.name), and it isn’t a GitHub release we can read.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    /// Cached rail width. The measurement below runs AppKit text sizing over every
    /// entry plus a sort — pure function of the immutable `changelog`, so it's
    /// computed once (`.onAppear` / on changelog change) rather than every render.
    @State private var cachedRailWidth: CGFloat = 200

    /// Content-driven rail width. For each row take the wider of its two lines — the
    /// title/version (callout) and the date subtitle (caption2) — since a short
    /// version like "3.6.8" can still carry a longer date ("4 July, 2023"). Sort
    /// those, then take a HIGH percentile, not the median: a title-based changelog
    /// (Codex) has many long titles and the median would clip the upper half. The
    /// 85th percentile fits the great majority; the upper clamp caps a lone runaway
    /// title (and the lower clamp keeps a terse changelog from getting cramped).
    /// Measured with AppKit since the labels are known up front — no GeometryReader.
    private static func railWidth(for changelog: Changelog) -> CGFloat {
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
            // New changelog (app switch) → select the newest entry again, and
            // re-measure the rail (its width depends only on the changelog).
            .onChange(of: changelog) {
                selection = 0
                cachedRailWidth = Self.railWidth(for: changelog)
            }
            .onAppear { cachedRailWidth = Self.railWidth(for: changelog) }
        }
    }

    /// Master/detail: a content-sized version rail + the selected version's notes.
    private var columnsBody: some View {
        // Clamp: the same view can be reused when the user switches apps, so a stale
        // selection from a longer changelog must not index past a shorter one.
        let index = min(max(selection, 0), changelog.entries.count - 1)
        return HStack(spacing: 0) {
            ChangelogVersionList(entries: changelog.entries, selection: $selection)
                .frame(width: cachedRailWidth)
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
            // Rich entries (notes interleaved with images, e.g. WeChat) walk `content`
            // so a screenshot lands between the change lines exactly as on the vendor's
            // page. Text-only entries (the common case) just bullet `items`.
            if entry.content.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        noteRow(item)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entry.content.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case let .note(text): noteRow(text)
                        case let .image(url): noteImage(url)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func noteRow(_ item: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(item).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A vendor-embedded release illustration. Served from the changelog image cache
    /// (prewarmed alongside the notes, so it paints instantly); a load failure shows
    /// a quiet placeholder rather than a broken-image box.
    @ViewBuilder
    private func noteImage(_ url: URL) -> some View {
        CachedImage(url: url)
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.vertical, 2)
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

    // Parse once per `text` (via `.task(id:)`), not on every body pass: the .html
    // path runs NSAttributedString's WebKit-backed parser, and re-running it each
    // render was a UI-freeze source. Seeded with the plain text so the view never
    // renders blank before the parse lands.
    @State private var rendered: AttributedString

    init(text: String, format: Format) {
        self.text = text
        self.format = format
        _rendered = State(initialValue: AttributedString(text))
    }

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
            .tint(.accentColor)
            .task(id: text) { rendered = Self.parse(text, format: format) }
    }

    /// NSAttributedString's HTML parser is documented main-thread-only, so this
    /// stays on the MainActor — the fix is that it now runs once per `text` change
    /// instead of on every render, which is the actual cost.
    @MainActor
    private static func parse(_ text: String, format: Format) -> AttributedString {
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
