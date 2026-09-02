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
    /// When the sidebar selection last moved, so the settle below can tell a
    /// deliberate step from a held arrow key.
    @State private var lastSelectionChange = Date.distantPast
    /// The pending debounce, cancelled and restarted on each selection change.
    @State private var detailSettleTask: Task<Void, Never>?
    /// Whether the Apps list holds the keyboard, so ↑/↓ scrub the selection without
    /// having to click a row first.
    ///
    /// It has to be claimed explicitly. Measured on the shipping window: it opened
    /// with `AXFocusedUIElement` on the search field (the sidebar's first AppKit
    /// view, which AppKit auto-focuses) or on nothing at all — either way the arrow
    /// keys had no destination. `defaultFocus` alone did not move it; setting this
    /// once the first results land does.
    @FocusState private var appsListFocused: Bool
    /// Sidebar filter text. Empty shows every app; otherwise the list narrows to
    /// apps whose name (or bundle id) contains the query, case/diacritic-insensitively.
    @State private var searchText = ""
    /// Collapsed/expanded state for the sidebar trees.
    @State private var appsExpanded = true
    /// The Brew tree starts collapsed and then remembers whatever you last left it
    /// as — `@AppStorage`, not `@State`, so the choice survives closing the window.
    /// Collapsed is only the first-run default: brew casks and formulae are a
    /// secondary channel, and having them expanded pushed the Apps tree up every
    /// time the window opened.
    @AppStorage("workbenchBrewExpanded") private var brewExpanded = false
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

    /// While the window stays open, re-read on-disk versions periodically so an app
    /// that self-updates in the background surfaces even if you never close/refocus
    /// the window. `refreshLocal()` is network-free and `!isChecking`-guarded.
    ///
    /// Deliberately slow. "Network-free" is not "cheap": each tick runs a full
    /// `AppScanner.scan()` (~45ms for 73 apps, growing with the library), spawns an
    /// `lsappinfo` subprocess for the restart probe (~57ms), stats every
    /// self-updater's staging area, walks the backup directory, and then replaces
    /// the whole `results` array — which invalidates the entire `@Observable` graph
    /// and re-renders the window. At 15s that ran ~240 times an hour to discover
    /// nothing, because the model ALREADY covers this ground: an FSEvents watcher on
    /// the same directories (whose whole job is catching background self-updates), a
    /// 180s backstop, and `NSWorkspace` launch/terminate observers for the
    /// process-only case. This timer is just a belt-and-braces for a missed event, so
    /// match the model's own backstop cadence rather than out-polling it 12×.
    private let refreshTimer = Timer.publish(every: 180, on: .main, in: .common).autoconnect()

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
                guard model.backupVersion(result.id) != nil else { return false }
                // Pairs, in Core: comparing the backup's marketing LABEL against
                // the installed marketing string hid this row for every app that
                // keeps one marketing version across builds.
                return model.rollbackIsDistinct(result)
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
                    description: Text("Pick an app to read its changelog."))
            }
        }
        .navigationTitle("Duo Updater")
        .toolbar {
            // Download traffic has its own window now (TrafficWindowView), so the
            // detail pane is always Release Notes and needs no lens switcher.
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
            // Claim the keyboard only now: before the rows exist there is no list to
            // focus, and the search field has already taken it by default.
            appsListFocused = true
        }
        // Brew tree data (formulae + the cask set derives from results above).
        .task { await model.refreshBrewFormulae() }
        // Refocus → re-read on-disk versions. Scoped to THIS window: the
        // notification carries whichever window became key, and with `object: nil`
        // we heard every one of them — so merely opening Settings, the Release Log,
        // or the popover kicked off a full disk rescan that had nothing to do with
        // the workbench.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard Self.isWorkbenchWindow(note.object) else { return }
            // Re-claim the keyboard. Focusing the list once on open isn't enough:
            // becoming key again hands the first responder back to whatever AppKit
            // picks by default — the search field, being the sidebar's first key
            // view — so ↑/↓ went dead again after any trip away from the window
            // (measured: AXFocusedUIElement back on the search text field).
            // Skipped mid-search, where the caret is where the user wants it.
            if searchText.isEmpty { appsListFocused = true }
            Task { await model.refreshLocal() }
        }
        // Stationary stay (never lose focus) → the backstop timer keeps versions
        // fresh. Skip ticks while hidden/minimized: refreshing for a window no one
        // sees is wasted work and battery.
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
            // A selection change means the user is working in the list — by arrow
            // key (already focused) or by clicking a row after the detail pane took
            // the keyboard, which is the case that left arrows dead until now.
            //
            // Only claim the keyboard when we do not already hold it. Re-asserting it
            // on a selection we caused by arrow key pushes focus down to AppKit again
            // mid-keystroke, and the outline drops the `scrollRowToVisible` that
            // normally follows an arrow-key selection — the highlight walks off the
            // bottom of the viewport and never comes back, even after the keys stop.
            if !appsListFocused { appsListFocused = true }
            let name = model.results.first { $0.id == newValue }?.app.name
            Log.changelog.info("perf selection → \(name ?? newValue ?? "nil", privacy: .public)")
            // Adaptive settle. A fixed 160 ms was shorter than a key REPEAT (~240 ms
            // measured from the perf log while scrubbing), so every press still paid
            // a full detail build — the debounce only ever helped for bursts faster
            // than itself. When the previous change was recent we are being
            // scrubbed through, so wait long enough to outlast the repeat; a
            // deliberate single step still lands promptly.
            let now = Date()
            let scrubbing = now.timeIntervalSince(lastSelectionChange) < 0.5
            lastSelectionChange = now
            detailSettleTask?.cancel()
            detailSettleTask = Task {
                try? await Task.sleep(for: .milliseconds(scrubbing ? 400 : 120))
                guard !Task.isCancelled else { return }
                detailSelection = newValue
            }
        }
        // A "Changelog" deep-link arriving while the window is already open — the
        // `.task` above only fires on a fresh open, so catch the in-flight case here.
        .onChange(of: model.requestedWorkbenchAppID) { applyRequestedApp() }
    }

    /// Whether a `didBecomeKey` notification's object is this workbench's own
    /// window. SwiftUI stamps a scene's window `identifier` with the scene id
    /// (e.g. "workbench-AppWindow-1") — the same match `AppListModel.surfaceWindow`
    /// uses to find a scene's window.
    private static func isWorkbenchWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return window.identifier?.rawValue.contains(Self.windowID) ?? false
    }

    /// Honor a pending "Changelog" deep-link to a specific app, then clear it so the
    /// selection isn't forced again on the next open. Bypasses the arrow-key debounce
    /// (sets `detailSelection` directly) — a deliberate jump should land instantly.
    private func applyRequestedApp() {
        guard let id = model.requestedWorkbenchAppID else { return }
        model.requestedWorkbenchAppID = nil
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
                    // Holds its size instead of compressing: the accessory beside it
                    // is a translated button, and "Обновить формулы" is wide enough
                    // to squeeze this to nothing — at which point a four-letter
                    // section name wraps to "Bre / w". The button truncates instead.
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        // Same reason as the title: with the title pinned, the
                        // squeeze lands here next, and "52" came out stacked as
                        // "5 / 2" inside the capsule.
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
        sectionHeader(String(localized: "Apps"), systemImage: "square.grid.2x2.fill",
                      count: filteredApps.count, expanded: $appsExpanded)
    }

    private var brewHeader: some View {
        sectionHeader(String(localized: "Brew"), systemImage: "mug.fill",
                      count: brewItemCount, expanded: $brewExpanded) {
            brewBulkUpgrade
        }
    }

    private var rollbackHeader: some View {
        sectionHeader(String(localized: "Rollback"), systemImage: "arrow.uturn.backward",
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
                    checkAgain: { Task { await model.retry(result) } },
                    isChecking: model.installing[result.id] != nil,
                    isSelected: result.id == selection,
                    isRunning: model.isRunning(result),
                    needsRestart: model.needsRestart.contains(result.id),
                    runningVersion: model.restartFromSide(result.id),
                    showsRuntime: model.prefs.showRuntimeTags)
                    .tag(result.id)
            }
        }
        .listStyle(.sidebar)
        .focused($appsListFocused)
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
                    checkAgain: { Task { await model.retry(result) } },
                    isChecking: model.installing[result.id] != nil,
                    isSelected: result.id == selection,
                    isRunning: model.isRunning(result),
                    needsRestart: model.needsRestart.contains(result.id),
                    runningVersion: model.restartFromSide(result.id),
                    showsRuntime: model.prefs.showRuntimeTags)
                    .tag(result.id)
            }
            ForEach(model.brewFormulae) { formula in
                BrewFormulaSidebarRow(formula: formula, model: model)
                    .tag("brew:formula:\(formula.name)")
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for result: UpdateResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(result: result, model: model)
            Divider()
            ReleaseNotesPane(result: result, model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - Sidebar row

private struct WorkbenchSidebarRow: View {
    let result: UpdateResult
    /// Re-check just this app, and whether it is busy already. Passed in as a
    /// closure and a flag rather than the model itself: this row is deliberately
    /// value-typed — every one of ~145 of them re-renders on any model change if
    /// it observes one — and these are the only two things the menu needs.
    let checkAgain: () -> Void
    let isChecking: Bool
    /// Whether this row is the selected one. The selection highlight is blue, and so
    /// is the update tint — so a selected update row was blue-on-blue (unreadable).
    /// When selected we render the version line in the emphasized foreground (white
    /// over the highlight) instead of the tint; the arrow still conveys "update".
    let isSelected: Bool
    /// Whether the app currently has a running process — shows the green live dot.
    let isRunning: Bool
    /// Self-updated on disk, waiting for a relaunch to take effect (the "Relaunch"
    /// state). When set, the subtitle shows running → installed instead of a bare
    /// version, so the row says what the restart will land.
    let needsRestart: Bool
    /// The running side of a relaunch line, still in parts so it can be formatted
    /// against the on-disk side rather than in isolation. nil when not lagging an
    /// on-disk build.
    let runningVersion: UpdateResult.VersionSide?
    /// Whether to show the runtime chip (Electron / Tauri / native / …).
    let showsRuntime: Bool

    /// Whether the sidebar row has room for the runtime symbol.
    ///
    /// Measured against the sidebar's **narrowest** setting (260pt, the minimum
    /// `navigationSplitViewColumnWidth` allows) rather than its current one. The
    /// column is user-resizable and the name already truncates at one line, so a
    /// symbol sized to a wide sidebar would silently start eating names the moment
    /// someone dragged the divider left — a fixed floor cannot. `ViewThatFits`
    /// is no help here for the same reason: a truncating `Text` reports a tiny
    /// minimum width, so every candidate "fits".
    private var runtimeTag: AppRuntime? {
        guard showsRuntime, let runtime = result.app.runtime else { return nil }
        var used = NSAttributedString(
            string: result.app.name,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).size().width
        if isRunning { used += 5 + 6 }
        let channel = ChannelTag.measuredWidth(for: result.app.releaseChannel)
        if channel > 0 { used += channel + 6 }
        return used + RuntimeTag.width() + 6 <= Self.narrowestNameColumn ? runtime : nil
    }

    /// 260pt minimum column, less the list's own insets (8 + 8), the 22pt icon and
    /// the 8pt gap after it.
    private static let narrowestNameColumn: CGFloat = 260 - 16 - 22 - 8

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(result.app.name).font(.body).lineLimit(1)
                    if isRunning {
                        RunningIndicator(size: 5).offset(y: RunningIndicator.opticalNudge)
                    }
                    ChannelTag(channel: result.app.releaseChannel)
                    if let runtimeTag {
                        RuntimeTag(runtime: runtimeTag, frameworks: result.app.linkedFrameworks,
                                   overHighlight: isSelected, interactive: false)
                    }
                }
                subtitle
            }
            Spacer()
        }
        .padding(.vertical, 2)
        // The row is name + version with a Spacer holding the rest open; without a
        // content shape the right-click only lands on the drawn parts, so the empty
        // stretch beside a short name would come up with no menu.
        .contentShape(Rectangle())
        .contextMenu {
            // The same "Open" the popover row offers, and it goes through
            // `AppRestarter.launchApp` rather than `NSWorkspace.open` for the same
            // reason: the latter blocks the main thread until the app has finished
            // launching.
            Button("Open") { Task { await AppRestarter.launchApp(result.app.path) } }
            // Ask about this one app, through the same entry point as the retry on
            // a failed row in the popover. Besides re-asking the source it re-reads
            // the app from disk, which is what corrects a stale running dot — some
            // apps never post one of the NSWorkspace notifications that set is
            // built from (issue #247).
            Button("Check Again", action: checkAgain).disabled(isChecking)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if case .updateAvailable(let latest) = result.status {
            // Same-marketing build bump (JetBrains EAP, Surge): show the builds so it
            // doesn't read as a no-op "2026.2 → 2026.2".
            let bump = result.buildBump(latest: latest)
            let from = bump.map { "\(result.installedDisplay ?? "?") (\($0.installed))" }
                ?? (result.installedDisplay ?? "?")
            let to = bump.map { "\(latest) (\($0.remote))" } ?? latest
            Text("\(from) → \(to)")
                .font(.caption)
                // White over the blue highlight when selected; blue tint otherwise.
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .lineLimit(1)
        } else if needsRestart, let running = runningVersion {
            // Self-updated on disk: show running version → the version on disk, so
            // "Relaunch" reads as a real change. Formatted as a pair by
            // `relaunchLine`, which keeps the build numbers only when the marketing
            // versions cannot tell the two apart — the same rule the update subtitle
            // above gets from `buildBump`.
            let line = UpdateResult.relaunchLine(from: running, to: result.relaunchTargetSide)
            Text("\(line.from) → \(line.to)")
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            Text("v\(result.installedDisplay ?? "?")")
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
    private var targetLabel: String { target == "previous" ? String(localized: "previous version") : String(localized: "v\(target)") }

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
        // Keyed on that version, not a bare `.task`: the pane's identity upstream is
        // `brew:formula:<name>`, so a refresh that reveals a NEWER available version
        // for the formula on screen moves this version string WITHOUT rebuilding the
        // view — and a bare `.task` would never re-fire, leaving the pane on the
        // notes for a version it is no longer displaying. See `FormulaReleaseStore`
        // for which refreshes actually move it (a plain `brew upgrade` does not).
        .task(id: notesVersion) {
            model.ensureFormulaReleaseLoading(name: formula.name, version: notesVersion)
        }
    }

    /// The version whose notes the pane shows: the upgrade target when there is one,
    /// else what's installed.
    private var notesVersion: String {
        formula.availableVersion ?? formula.installedVersion
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
                    Text(model.formulaUpgradeNotes[formula.name] ?? String(localized: "Updating…"))
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
        switch model.formulaReleaseState(name: formula.name, version: notesVersion) {
        case .loaded(let release):
            if let changelog = release.changelog {
                ChangelogEntriesView(changelog: changelog)
            } else if let url = ChangelogURLPolicy.displayable(release.pageURL) {
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
    @Bindable var model: AppListModel

    /// The vendor page to link out to.
    private var changelogURL: URL? {
        ChangelogURLPolicy.displayable(
            result.remote?.changelogURL ?? ChangelogCatalog.url(forBundleID: result.app.bundleID))
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
                        // Sized up to sit beside a `.title2` name rather than a
                        // list row's body text — the marks are drawn in a unit box,
                        // so they scale without losing their stroke ratio.
                        if model.prefs.showRuntimeTags, let runtime = result.app.runtime {
                            RuntimeTag(runtime: runtime, bundle: result.app.path,
                                       frameworks: result.app.linkedFrameworks, size: 18)
                        }
                    }
                    versionLine
                }
                Spacer()
                // The contextual primary action (Update / Relaunch / Get),
                // so an update can be acted on right here while its notes are open —
                // no trip back to the menu-bar popover.
                WorkbenchRowAction(
                    state: model.rowState(for: result),
                    result: result,
                    actions: RowActions(
                        install: { Task { await model.install(result) } },
                        openStagedPackage: { Task { await model.openStagedPackage(result) } },
                        retry: { Task { await model.retry(result) } },
                        restart: { Task { await model.restart(result) } },
                        relaunchStaged: { Task { await model.relaunchStagedUpdate(result) } },
                        confirmQuit: { model.confirmQuit(result.id, proceed: true) },
                        openSelfUpdater: { model.openSelfUpdater(result) },
                        openToolbox: { model.openToolbox() }),
                    helperEnabled: model.helperEnabled)
                if let url = changelogURL {
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
                if model.showsAppStoreUpdatesFallback(result.id) {
                    Button("Open App Store") { model.openAppStoreUpdatesPage() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
                if model.showsHelperApprovalFallback(result.id) {
                    Button("Turn On Helper…") { model.enableAppStoreHelper() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
                if model.showsHelperRestartFallback(result.id) {
                    Button(model.restartingHelper ? String(localized: "Restarting…") : String(localized: "Restart Helper…")) {
                        Task { await model.restartAppStoreHelper(result.id) }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(model.restartingHelper)
                }
            } else if let note = model.installNotes[result.id] ?? model.stagedPackageNote(for: result) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // No context menu on this row, so the way out of a package the user
            // has decided against is a plain link — same action the popover row
            // offers on right-click. See `AppListModel.discardStagedPackage`.
            if model.canDiscardStagedPackage(result) {
                Button("Discard Downloaded Installer") {
                    Task { await model.discardStagedPackage(result) }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var versionLine: some View {
        if case .updateAvailable(let latest) = result.status {
            let bump = result.buildBump(latest: latest)
            let from = bump.map { "\(result.installedDisplay ?? "?") (\($0.installed))" }
                ?? (result.installedDisplay ?? "?")
            let to = bump.map { "\(latest) (\($0.remote))" } ?? latest
            Text("\(from)  →  \(to)")
                .font(.callout).foregroundStyle(.tint)
        } else {
            Text("v\(result.installedDisplay ?? "?") · up to date")
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
        ChangelogURLPolicy.displayable(
            result.remote?.changelogURL ?? ChangelogCatalog.url(forBundleID: result.app.bundleID))
    }

    /// Which link of the fallback chain produced `changelogURL`, for the log.
    ///
    /// Exists because "the changelog pane showed the wrong page" is otherwise
    /// unanswerable after the fact: both candidates can share a host, the window
    /// in which the web view is reached at all is timing-dependent, and by the
    /// time anyone looks the check has usually completed and the pane renders
    /// natively instead. Recording the origin next to the URL turns the next
    /// sighting into evidence instead of another guess.
    ///
    /// `-rejected` means the chain picked a URL and `ChangelogURLPolicy` refused
    /// it — indistinguishable from "no URL at all" at the call site, and worth
    /// telling apart: since `??` takes the first non-nil, a `remote` URL that
    /// fails the policy shadows a usable catalog entry rather than falling
    /// through to it.
    private var changelogURLOrigin: String {
        let remote = result.remote?.changelogURL
        let chosen = remote ?? ChangelogCatalog.url(forBundleID: result.app.bundleID)
        guard let chosen else { return "none" }
        let link = remote != nil ? "remote" : "catalog"
        return ChangelogURLPolicy.displayable(chosen) == nil ? "\(link)-rejected" : link
    }

    /// One line describing what the web view was handed. `Redactor.url` keeps the
    /// host, path and harmless query while stripping credential-ish parameters,
    /// so the full address is safe to log at `.public` — and the path is exactly
    /// the part `url.host` alone was losing.
    ///
    /// `.notice`, NOT `.info` like the neighbouring `perf pane=` lines — please
    /// do not "tidy" it to match them. Those are live-streaming perf traces; this
    /// one exists to be read days after a sighting, and per `man 5 os_log` Info
    /// level goes to a memory buffer and is never persisted for a third-party
    /// subsystem, so at `.info` it would be gone by the time anyone looked. The
    /// storage layer folds `.notice` into the persisted Default level. Retention
    /// is still finite (measured at roughly 4.5 days on this hardware), so a
    /// report is only recoverable for a few days.
    private func logWebViewPane(_ url: URL, via route: String) {
        Log.changelog.notice(
            "perf pane=webview route=\(route, privacy: .public) \(result.app.name, privacy: .public) origin=\(changelogURLOrigin, privacy: .public) src=\(result.remote?.sourceName ?? "?", privacy: .public) url=\(Redactor.url(url), privacy: .public)")
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
            .onAppear { Log.changelog.info("perf pane=inline-html \(result.app.name, privacy: .public) (\(html.count, privacy: .public) chars, \(ReleaseNotesText.split(html).count, privacy: .public) chunks, src=\(result.remote?.sourceName ?? "?", privacy: .public))") }
        } else if let url = changelogURL {
            CachedWebView(url: url)
                .onAppear { logWebViewPane(url, via: "direct") }
        } else {
            emptyNotes
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let url = changelogURL {
            CachedWebView(url: url)
                // The recipe-backed path landed here because its changelog load
                // FAILED, which is the case most worth having on record: the pane
                // is now showing a vendor page chosen by fallback rather than the
                // notes the recipe was supposed to render.
                .onAppear { logWebViewPane(url, via: "recipe-failed") }
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
            Text("\(result.remote?.sourceName ?? String(localized: "This source")) doesn’t publish a changelog we can read.")
        } actions: {
            if let dl = result.remote?.pageURL {
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
/// Internal, not private: the self-changelog window renders Duo Updater's own
/// release notes through the very same view, so they look like every other app's
/// rather than a second, drifting layout.
struct ChangelogEntriesView: View {
    /// How an entry's items should read.
    ///
    /// A vendor changelog is a list of short lines, and a bullet in front of each
    /// is exactly right. Duo Updater's own notes are not that shape: they are
    /// prose paragraphs opening with a bold lead sentence, and a `•` in front of
    /// ten lines of prose reads as a list item that forgot to end. Same data, same
    /// view, different typesetting — this stays a presentation choice rather than
    /// a field on `Changelog`, which is `Codable` and lands on disk.
    enum ItemStyle {
        case bulleted
        case paragraphs
    }

    let changelog: Changelog
    var itemStyle: ItemStyle = .bulleted
    /// The version the reader is on, marked in the rail. Nil for a vendor
    /// changelog, where the row itself is already about the app they have.
    var runningVersion: String?
    /// Duo Updater's own history uses compact version + date rows. Vendor
    /// changelogs retain the two-line treatment because their titles can be long.
    var showsDatesInline: Bool = false
    /// Whether to offer the side-by-side / long-scroll switch.
    ///
    /// Off for our own notes: with 53 versions the rail is the only sane way to
    /// read them, so the picker sat alone in an empty strip offering a layout
    /// nobody would pick — cost in vertical space and visual noise, no benefit.
    /// A vendor changelog is often a handful of entries where the long scroll is a
    /// reasonable choice, so it keeps the switch.
    var showsLayoutPicker: Bool = true
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
    private static func railWidth(for changelog: Changelog, showsDatesInline: Bool) -> CGFloat {
        let labelFont = NSFont.preferredFont(forTextStyle: .callout)
        let dateFont = NSFont.preferredFont(forTextStyle: .caption2)
        let rowWidths = changelog.entries
            .map { entry -> CGFloat in
                let labelW = (ChangelogVersionList.label(for: entry) as NSString)
                    .size(withAttributes: [.font: labelFont]).width
                let dateW = (entry.date?.isEmpty == false)
                    ? (entry.date! as NSString).size(withAttributes: [.font: dateFont]).width
                    : 0
                return showsDatesInline && dateW > 0
                    ? labelW + 6 + dateW
                    : max(labelW, dateW)
            }
            .sorted()
        guard !rowWidths.isEmpty else { return 200 }
        let pick = rowWidths[Int((Double(rowWidths.count - 1) * 0.85).rounded())]
        // Row chrome: line .horizontal(10)×2 + rail .padding(8)×2. Inline dates
        // also reserve the current-version dot and its gap; without that small
        // accessory budget only the running row truncates its otherwise identical
        // date, which makes the rail look inconsistently sized.
        let chrome: CGFloat = 20 + 16
        let inlineAccessory: CGFloat = showsDatesInline ? 16 : 0
        let minimum: CGFloat = showsDatesInline ? 156 : 140
        return min(max(pick + chrome + inlineAccessory, minimum), 360)
    }

    var body: some View {
        if changelog.entries.count <= 1 {
            // Nothing to navigate — render the single entry full width, no toggle.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                        ChangelogEntryView(entry: entry, itemStyle: itemStyle, syntax: changelog.itemSyntax)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 0) {
                if showsLayoutPicker {
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
                }

                if showsLayoutPicker {
                    switch layout {
                    case .columns: columnsBody
                    case .list:    listBody
                    }
                } else {
                    columnsBody
                }
            }
            // New changelog (app switch) → select the newest entry again, and
            // re-measure the rail (its width depends only on the changelog).
            .onChange(of: changelog) {
                selection = 0
                cachedRailWidth = Self.railWidth(for: changelog, showsDatesInline: showsDatesInline)
            }
            .onAppear {
                cachedRailWidth = Self.railWidth(for: changelog, showsDatesInline: showsDatesInline)
            }
        }
    }

    /// Stable anchor for the detail pane's scroll-to-top. Constant on purpose —
    /// the whole point is that switching versions must NOT change view identity.
    private static let scrollTopAnchor = "changelog-entry-top"

    /// Master/detail: a content-sized version rail + the selected version's notes.
    private var columnsBody: some View {
        // Clamp: the same view can be reused when the user switches apps, so a stale
        // selection from a longer changelog must not index past a shorter one.
        let index = min(max(selection, 0), changelog.entries.count - 1)
        return HStack(spacing: 0) {
            ChangelogVersionList(
                entries: changelog.entries, selection: $selection,
                runningVersion: runningVersion,
                showsDatesInline: showsDatesInline)
                .frame(width: cachedRailWidth)
            Divider()
            // Scroll back to the top on switch WITHOUT changing identity. This used
            // to be `.id(index)`, which reset the offset by destroying and rebuilding
            // the whole ScrollView — measured at a ~18ms floor on every rail click
            // (a dropped frame at 60Hz) regardless of how short the entry was, which
            // is what made the rail feel detached from the pointer. Keeping one
            // ScrollView and moving it instead lets SwiftUI update the notes in place.
            ScrollViewReader { proxy in
                ScrollView {
                    ChangelogEntryView(entry: changelog.entries[index], itemStyle: itemStyle, syntax: changelog.itemSyntax)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(Self.scrollTopAnchor)
                }
                // BOTH triggers. `index` alone misses the most common switch there
                // is: picking a different app resets `selection` to 0, so a user who
                // was on entry 0 (the default) and had scrolled halfway down a long
                // release's notes keeps that offset while the pane now shows a
                // different app — `index` never changed, so the callback never ran.
                // `.id(index)` had the identical hole; the commit that replaced it
                // claimed a fix that only held for switching versions within one app.
                .onChange(of: index) {
                    proxy.scrollTo(Self.scrollTopAnchor, anchor: .top)
                }
                .onChange(of: changelog) {
                    proxy.scrollTo(Self.scrollTopAnchor, anchor: .top)
                }
            }
        }
    }

    /// One long top-down scroll of every version. LazyVStack so a long changelog
    /// doesn't lay out every selectable, `fixedSize` bullet synchronously on appear.
    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                    ChangelogEntryView(entry: entry, itemStyle: itemStyle, syntax: changelog.itemSyntax)
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
    /// The version the user is actually on, marked in the rail so a long history
    /// says where they stand in it. Nil for a vendor changelog, where "the version
    /// you have" is already the row's own subject and the rail is just navigation.
    var runningVersion: String?
    var showsDatesInline = false

    var body: some View {
        let selected = min(max(selection, 0), entries.count - 1)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Button { selection = index } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(Self.label(for: entry))
                                    .font(.callout)
                                    .fontWeight(index == selected ? .semibold : .regular)
                                    .lineLimit(1)
                                if showsDatesInline, let date = entry.date, !date.isEmpty {
                                    Text(date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if isRunning(entry) {
                                    // A filled dot, not the word "current": the rail
                                    // is narrow and sized from its labels, so a word
                                    // would widen every row to fit one of them.
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .help("The version you're running")
                                }
                            }
                            if !showsDatesInline, let date = entry.date, !date.isEmpty {
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

    private func isRunning(_ entry: Changelog.Entry) -> Bool {
        guard let runningVersion, !runningVersion.isEmpty else { return false }
        return entry.version == runningVersion
    }

    /// Prefer the human title (post-style entries), else the version string.
    /// Static so the parent can measure label widths to size the rail.
    static func label(for entry: Changelog.Entry) -> String {
        if let title = entry.title, !title.isEmpty { return title }
        return entry.version.isEmpty ? "—" : entry.version
    }
}

// MARK: - Traffic pane

// MARK: - One changelog entry

/// One changelog block: either a classic version heading, or a post-style title
/// with date/build metadata underneath.
private struct ChangelogEntryView: View {
    let entry: Changelog.Entry
    var itemStyle: ChangelogEntriesView.ItemStyle = .bulleted
    /// Carried down from the `Changelog` so a bullet knows whether its text is
    /// Markdown; see `rendered(_:syntax:)`.
    var syntax: Changelog.ItemSyntax = .plain

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
            // LAZY, not a plain VStack. An entry used to be a couple of dozen lines
            // at most, because every changelog came from a recipe. A Sparkle feed's
            // inline notes are not capped that way — TablePro's 0.67.0 carries 205
            // change lines — and an eager stack built every one of them on each
            // version switch. (The HTML fallback this path replaced was already
            // lazy; going native must not lose that.)
            if entry.content.isEmpty {
                LazyVStack(alignment: .leading, spacing: itemStyle == .paragraphs ? 14 : 6) {
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        noteRow(item)
                    }
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
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
        switch itemStyle {
        case .bulleted:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.rendered(item, syntax: syntax))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraphs:
            Text(Self.rendered(item, syntax: syntax))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `Text(someString)` does NOT parse Markdown — SwiftUI only does that for
    /// string *literals* — so a GitHub release body rendered this way showed the
    /// user raw `**bold**` and `[text](url)`. Parse it explicitly when the
    /// changelog says its items are Markdown, and only then: a page-scraped item
    /// is plain prose where a stray `*` or `_` is a character the vendor typed,
    /// not emphasis.
    ///
    /// `.inlineOnlyPreservingWhitespace` keeps this to inline spans — a change
    /// line is one bullet, and full-document parsing would swallow a leading `#`
    /// or `-` into block structure the bullet already provides. A malformed line
    /// falls back to itself rather than disappearing.
    static func rendered(_ item: String, syntax: Changelog.ItemSyntax) -> AttributedString {
        guard syntax == .markdown else { return AttributedString(item) }
        return (try? AttributedString(
            markdown: item,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(item)
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
    //
    // Held as CHUNKS, not one string, because parsing was only half the cost. A
    // long body (Headlamp's GitHub notes: 54,584 chars) laid out as a single
    // `Text` stalled the main thread for ~2 s even with the parse cached —
    // visible in the perf log as a two-second gap right after
    // `pane=inline-html Headlamp`. Chunks in a `LazyVStack` mean SwiftUI only
    // lays out what is on screen. Short notes stay one chunk and behave exactly
    // as before.
    @State private var chunks: [AttributedString]

    init(text: String, format: Format) {
        self.text = text
        self.format = format
        _chunks = State(initialValue: [AttributedString(text)])
    }

    var body: some View {
        Group {
            if chunks.count == 1 {
                Text(chunks[0])
            } else {
                // Selection is per-chunk here rather than across the whole
                // document — the cost of not blocking the main thread on a body
                // this size.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                        Text(chunk).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .tint(.accentColor)
        .task(id: text) { chunks = Self.parsedChunks(text, format: format) }
    }

    /// Notes short enough to lay out in one pass stay a single chunk; anything
    /// longer is split at paragraph boundaries so the `LazyVStack` above can skip
    /// what is off screen.
    private static let singleChunkLimit = 4_000
    private static let targetChunkSize = 1_500

    /// Parsed notes, memoized ACROSS view instances.
    ///
    /// `.task(id: text)` already avoided re-parsing on every render pass, but a
    /// new selection builds a NEW `ReleaseNotesText`, so arrow-keying between two
    /// apps re-parsed both bodies on every keystroke — visible in the log as
    /// `perf release-notes markdown parse: 8.3ms (54584 chars)` repeating once per
    /// press. Notes are immutable for a given text, so the result is cacheable;
    /// `NSCache` evicts under pressure rather than growing with the library.
    private static let parseCache: NSCache<NSString, ParsedNotes> = {
        let cache = NSCache<NSString, ParsedNotes>()
        cache.countLimit = 64
        return cache
    }()

    private final class ParsedNotes {
        let value: [AttributedString]
        init(_ value: [AttributedString]) { self.value = value }
    }

    @MainActor
    private static func parsedChunks(_ text: String, format: Format) -> [AttributedString] {
        // Length + hash, not the body itself: a 54 KB key would be copied into the
        // cache on every lookup.
        let key = "\(format)-\(text.count)-\(text.hashValue)" as NSString
        if let hit = parseCache.object(forKey: key) { return hit.value }
        let value = split(text).map { parse($0, format: format) }
        parseCache.setObject(ParsedNotes(value), forKey: key)
        return value
    }

    /// Split a long body at BLANK LINES, accumulating until a chunk is big enough
    /// to be worth its own `Text`. Breaking only on blank lines keeps a bullet
    /// list — or a fenced block — inside one chunk, so nothing is re-flowed into
    /// a different shape than the vendor wrote.
    static func split(_ text: String) -> [String] {
        guard text.count > singleChunkLimit else { return [text] }
        // NORMALIZE FIRST. GitHub release bodies come over the API with CRLF —
        // Headlamp's v0.44.0 body has 535 `\r\n` and ZERO bare `\n\n`, so
        // splitting on the blank line straight away found nothing and returned the
        // whole 54 KB as one chunk. The log said `1 chunks` and the stall stayed
        // exactly as it was; that is what made this visible rather than silent.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var chunks: [String] = []
        var current = ""
        for paragraph in normalized.components(separatedBy: "\n\n") {
            // A paragraph that is itself enormous (a table, or notes written with
            // no blank lines at all) still has to be broken up, or one chunk is
            // the whole document again — the bug above, one level down.
            if paragraph.count > targetChunkSize * 3 {
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(contentsOf: splitOnLines(paragraph))
                continue
            }
            current += current.isEmpty ? paragraph : "\n\n" + paragraph
            if current.count >= targetChunkSize {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }

    /// Last-resort break for a single paragraph with no blank lines in it.
    private static func splitOnLines(_ paragraph: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in paragraph.components(separatedBy: "\n") {
            current += current.isEmpty ? line : "\n" + line
            if current.count >= targetChunkSize {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
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
        // Ephemeral data store: these panes render third-party release-notes pages
        // purely to be read, so there is no reason for a vendor's cookies,
        // localStorage or embedded analytics to survive into the next launch inside
        // our container. The default store would persist all of it.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        // Set the delegate before loading so the guardian sees the very first
        // navigation start and arms its watchdog on it.
        let guardian = WebGuardian(origin: url)
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

    /// The host this pane was opened on. Navigation that leaves it is handed to the
    /// browser instead of being followed in-pane — the pane is a changelog reader,
    /// not a browser, and a vendor page that redirects itself (or a link the user
    /// taps) should not be able to point it anywhere it likes.
    private let originHost: String?

    init(origin: URL) {
        self.originHost = origin.host
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only a link the *user* clicked in the *main* frame is redirected. Everything
        // else is left alone on purpose:
        //   • sub-frames — `decidePolicyFor` fires for iframes too, and a changelog
        //     page that embeds a video or a third-party widget would otherwise have
        //     every frame cancelled and thrown at the browser, one window each;
        //   • server-side redirects and SPA routing — a vendor moving
        //     docs.x.com → x.com/docs is normal, and cancelling it just blanks the
        //     pane. The URL we start from comes from our own recipe registry, not
        //     from the page, so this is a usability boundary, not a trust boundary.
        // One thing here IS a trust boundary: the scheme. `ChangelogURLPolicy` only
        // vets the URL we start from, and a vendor page that redirects itself to
        // `http://` would land cleartext content in this in-process web view
        // anyway — which is the whole thing that policy exists to stop. Cross-host
        // https redirects stay allowed; only the downgrade is refused.
        if let url = navigationAction.request.url,
           url.scheme?.lowercased() == "http" {
            decisionHandler(.cancel); return
        }

        guard navigationAction.navigationType == .linkActivated,
              navigationAction.targetFrame?.isMainFrame ?? true,
              let url = navigationAction.request.url,
              url.host != originHost,
              url.scheme == "https" || url.scheme == "http"
        else {
            decisionHandler(.allow); return
        }
        // An outbound link the user chose: give it a real browser, with history,
        // tabs and their own extensions, instead of trapping it in a chrome-less
        // reader pane.
        decisionHandler(.cancel)
        NSWorkspace.shared.open(url)
    }

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
