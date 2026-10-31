import SwiftUI
import AppKit
import WebKit
import DuoUpdaterCore

/// The unified workbench window — one roomy home for everything the menu-bar
/// popover can't hold. App-centric: the left column lists every scanned app; the
/// right pane shows the selected app's changelog (recipe → structured → inline
/// HTML → web page).
///
/// There is no *traffic* lens any more: download traffic has its own window
/// (`NetworkWindowView`). The app-row pane is Release Notes, or the Bundle Diff
/// when the selected app has a backup; a selected formula or unchecked package has
/// its own pane instead. The toolbar gear opens Settings in its own window too
/// (`openWindow`), not as a sheet.
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
    /// Whether the visible sidebar list holds the keyboard, so ↑/↓ scrub the
    /// selection without having to click a row first.
    ///
    /// It has to be claimed explicitly. Measured on the shipping window: it opened
    /// with `AXFocusedUIElement` on the search field (the sidebar's first AppKit
    /// view, which AppKit auto-focuses) or on nothing at all — either way the arrow
    /// keys had no destination. `defaultFocus` alone did not move it; setting this
    /// once the first results land does.
    ///
    /// Which list rather than whether: a tab's list is kept once built
    /// (`builtTabs`), so the hidden ones are alive beside the one on screen.
    @FocusState private var listFocus: SidebarTab?
    /// Sidebar filter text, applied to the list the current tab shows. Empty shows
    /// everything; otherwise rows whose name (or bundle id) contains the query,
    /// case/diacritic-insensitively.
    @State private var searchText = ""
    /// Which list the sidebar shows. Not persisted: the window always opens on Apps.
    @State private var sidebarTab: SidebarTab = .apps
    /// The tabs whose list has been on screen this visit. The Apps and Rollback
    /// lists are kept, hidden, once the reader moves on, rather than torn down:
    /// with 229 apps, rebuilding the Apps list held the main thread for 175–208 ms
    /// on every switch back to it (SwiftUI-template hitches, 2026-10-10), the old
    /// `List` alike. Built on the first visit, not up front, so opening the window
    /// costs what it did. The CLI list is not kept; see `sidebar`.
    @State private var builtTabs: Set<SidebarTab> = []
    /// Lets the selected tab's highlight slide between tabs instead of blinking.
    @Namespace private var tabHighlight
    /// The tab under the pointer while the highlight is being dragged along the
    /// track; nil when no drag is in progress. The drag only commits on release.
    /// `@GestureState`, not `@State`: it is reset when the drag is cancelled as well
    /// as when it ends, and `onEnded` does not run for a cancelled drag, so a plain
    /// state reset there would leave the highlight on a tab that is not shown.
    @GestureState private var draggedTab: SidebarTab?
    /// Each drawn tab's frame in the track, so a drag position maps to a tab.
    @State private var tabFrames: [SidebarTab: CGRect] = [:]
    /// Release notes, or the bundle diff against the app's backup. Only offered for
    /// an app that has a backup. Set by the tab — the Rollback tab opens on the diff,
    /// Apps and CLI on the notes — and kept across selections within it, so
    /// comparing several apps in a row does not mean switching back each time.
    @State private var detailMode: DetailMode = .releaseNotes
    /// Bumped by each "Show in Window" request from the popover's unchecked-brew
    /// tip; the CLI list scrolls to those rows when it sees a value it hasn't
    /// handled. A counter, not a flag, so the list can mark it handled without
    /// changing its own `.task(id:)` and cancelling the highlight it just started —
    /// and so leaving the CLI tab and coming back later doesn't replay it.
    @State private var uncheckedRevealRequest = 0
    @State private var uncheckedRevealHandled = 0
    /// Briefly true after a reveal, so the rows it scrolled to stand out.
    @State private var highlightUnchecked = false
    /// Bumped by each "Show in Window" from the popover's Homebrew or "Other
    /// tools" row: the CLI list scrolls that level's header (`cliRevealTarget`)
    /// to its top, `uncheckedRevealRequest`'s way. Opening the level alone left
    /// "Other tools" below a long Homebrew group, out of view (2026-10-20: the
    /// list stayed at its top, 62 packages above it) — and, once that scrolled,
    /// Homebrew above the list's top.
    @State private var cliRevealRequest = 0
    @State private var cliRevealHandled = 0
    /// The header the latest request scrolls to.
    @State private var cliRevealTarget = Self.homebrewHeaderID
    /// Where that target lands: a header at the list's top, a tool's row in its
    /// middle, with its group's header above it.
    @State private var cliRevealAnchor: UnitPoint = .top
    /// Whether the user keeps the CLI tab's Homebrew group open. Remembered across
    /// launches, like the changelog layout; closed until they open it. What else
    /// opens the group, and why that never writes here: `HomebrewGroupState`.
    @AppStorage("workbenchHomebrewExpanded") private var homebrewExpandedPreference = false
    /// A deep link opened the Homebrew group (`HomebrewGroupState.revealing`).
    @State private var homebrewRevealing = false
    /// Whether the user keeps the CLI tab's "Other tools" level open. Open by
    /// default: until 2026-10 its groups had no level above them and were always
    /// shown.
    @AppStorage("workbenchOtherToolsExpanded") private var otherToolsExpandedPreference = true
    /// The popover's command-line rows opened the level for this visit, without
    /// rewriting what the user keeps — `homebrewRevealing`'s rule.
    @State private var otherToolsRevealing = false
    /// The managers' levels (`managerLevels`) the user closed in this window;
    /// every one is open otherwise.
    @State private var collapsedManagerLevels: Set<String> = []
    /// The CLI tab's order — formula and tool rows' tags — as it stood when updates
    /// started running; nil while none runs. `CLIToolPresentation.holding`.
    @State private var heldCLIOrder: [String]?

    @Environment(\.scenePhase) private var scenePhase
    @State private var isWindowOpen = false
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

    /// The sidebar app list. `AppListModel` already holds `results` in display
    /// order (pending updates first, then the user's chosen intra-tier order), so
    /// this is only the Brew split — re-sorting here would be a second comparator
    /// that could drift from the popover's.
    ///
    /// Brew-managed casks are excluded here: they live under the Brew tree instead
    /// (the "cask 只在此面板" rule), so they never appear in both places.
    ///
    /// The apps an interrupted install left gone come first: the scan has no
    /// row for them (`AppListModel.interruptedStandIns`).
    private var apps: [UpdateResult] {
        let standIns = model.interruptedStandIns
        return standIns.isEmpty ? sortedResults().apps : standIns + sortedResults().apps
    }

    /// Brew-managed casks, in the same display order — the cask half of the Brew
    /// tree. (The formula half is `model.brewFormulae` — all top-level leaves.)
    private var brewCasks: [UpdateResult] { sortedResults().brewCasks }

    /// `apps` and `brewCasks`, split once per write to `model.results` rather than
    /// on every pass of this body: a tab switch, a selection, a download tick each
    /// re-read all 229 apps on the developer's Mac. Handing the Apps list the same
    /// array again also makes its comparison (`WorkbenchAppsList`) a check of one
    /// buffer instead of every app.
    private final class SortedResults {
        var generation = -1
        var apps: [UpdateResult] = []
        var brewCasks: [UpdateResult] = []
    }
    @State private var sortedResultsCache = SortedResults()

    private func sortedResults() -> SortedResults {
        // Read whether or not the cache holds: it is what makes a new list re-run
        // this body.
        let results = model.results
        let cache = sortedResultsCache
        guard cache.generation != model.resultsGeneration else { return cache }
        cache.apps = results.filter { $0.remote?.sourceName != "Homebrew" }
        cache.brewCasks = model.brewCaskResults
        cache.generation = model.resultsGeneration
        return cache
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

    /// `apps` narrowed by the search field. A blank query passes everything through;
    /// otherwise we match the query against the app name and bundle id (so
    /// "com.google" finds Chrome too), by the rule every search field shares
    /// (`SearchMatch`: case, diacritics and width folded).
    private var searchQuery: String { SearchMatch.trimmed(searchText) }

    private func matchesSearch(_ result: UpdateResult) -> Bool {
        SearchMatch.matches(searchQuery, in: [result.app.name, result.app.bundleID])
    }

    private func matchesSearch(_ name: String) -> Bool {
        SearchMatch.matches(searchQuery, in: name)
    }

    /// A command-line tool's row matches by the tool's name, so "claude" finds every
    /// copy of Claude Code, by the install's own name ("rustup", an npm package),
    /// and by the title and the path it stands for.
    private func matchesSearch(_ status: CLIToolStatus) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return matchesSearch(status.kind.displayName)
            || status.name.map(matchesSearch) == true
            || matchesSearch(CLIToolPresentation.title(of: status, home: home))
            || matchesSearch(status.path)
    }

    /// The derived lists the sidebar draws, built ONCE per body pass and handed down.
    ///
    /// They used to be computed properties read from the view builders that need
    /// them — `filteredApps` from three (the section header, the list, its empty
    /// overlay), `rollbackableApps` from four, `brewCasks` from three — so one
    /// pass re-ran every `filter` and every `sort(localizedCaseInsensitiveCompare)`
    /// three or four times over. And the pass is not rare: the body reads
    /// `model.installing`, so every download tick re-runs all of it.
    ///
    /// Each list is already narrowed by the search, so a tab's count pill and its
    /// rows always agree. `hasCLI` is not: a search that matches no CLI row must
    /// not make the CLI tab disappear from under the reader.
    struct SidebarLists {
        let filteredApps: [UpdateResult]
        /// The CLI tab's tool groups after Homebrew's, every tool's installs in
        /// `CLIToolKind.allCases` order and npm's by prefix — the order the groups
        /// are drawn in (`CLIToolPresentation.groups`).
        let cliTools: [CLIToolStatus]
        let brewCasks: [UpdateResult]
        let brewFormulae: [BrewInstalledFormula]
        let brewUnchecked: [BrewUncheckedPackage]
        /// App-less casks Homebrew deprecated or disabled (`BrewCaskLifecycle`).
        let brewLifecycleCasks: [BrewCaskLifecycle]
        /// The "Homebrew x is available" row, searched by the name it shows, so a
        /// query that matches nothing empties the Homebrew group like the other two.
        let homebrewSelfUpdate: HomebrewSelfUpdate?
        let rollbackable: [UpdateResult]
        /// The CLI tab has anything to show: Homebrew, or an install of another tool.
        let hasCLI: Bool
        /// Each tab's count before the search, which the count's slot is sized to so
        /// the icon and title hold still while typing narrows the count.
        let appsTotal: Int
        let cliTotal: Int
        let rollbackTotal: Int
    }

    private var sidebarLists: SidebarLists {
        let allApps = apps
        let allCasks = brewCasks
        let allRollbackable = rollbackableApps
        let brewTotal = allCasks.count + model.brewFormulae.count + model.brewUnchecked.count
            + model.brewAppLessCaskLifecycles.count + (model.homebrewSelfUpdate == nil ? 0 : 1)
        let cliTools = CLIToolPresentation.holding(
            CLIToolPresentation.updatesFirst(model.cliTools.statuses), to: heldCLIOrder, id: \.toolID.tag)
        let formulae = CLIToolPresentation.holding(
            CLIToolPresentation.outdatedFirst(model.brewFormulae, \.hasUpdate), to: heldCLIOrder, id: Self.formulaTag)
        return SidebarLists(
            // Unfiltered, the same array as the last pass (`sortedResults`).
            filteredApps: searchQuery.isEmpty ? allApps : allApps.filter(matchesSearch),
            cliTools: CLIToolPresentation.groups(cliTools.filter(matchesSearch)).flatMap(\.statuses),
            brewCasks: allCasks.filter(matchesSearch),
            brewFormulae: formulae.filter { matchesSearch($0.name) },
            brewUnchecked: model.brewUnchecked.filter { matchesSearch($0.fullName) },
            brewLifecycleCasks: model.brewAppLessCaskLifecycles.filter { matchesSearch($0.token) },
            homebrewSelfUpdate: matchesSearch("Homebrew") ? model.homebrewSelfUpdate : nil,
            rollbackable: allRollbackable.filter(matchesSearch),
            hasCLI: brewTotal > 0 || !cliTools.isEmpty,
            appsTotal: allApps.count,
            cliTotal: brewTotal + cliTools.count,
            rollbackTotal: allRollbackable.count)
    }

    /// A formula row's tag, as `heldCLIOrder` names it.
    private static func formulaTag(_ formula: BrewInstalledFormula) -> String { "brew:formula:\(formula.key)" }

    /// Anything in the CLI tab is updating — Homebrew's Upgrade All or a formula's
    /// own, Update All or a tool's own — or still saying "Updated to X". The tab's
    /// order holds meanwhile and re-sorts once after: the Apps list's frozen row
    /// order (`AppListModel.pinRowOrder`), whose release also waits for the
    /// confirmations.
    private var cliUpdatesRunning: Bool {
        model.brewUpgrading || !model.upgradingFormulae.isEmpty
            || model.cliTools.updatingAll || !model.cliTools.updating.isEmpty
            || !model.cliTools.justUpdated.isEmpty
    }

    /// The app the detail pane shows — keyed off the debounced `detailSelection`,
    /// not the live `selection`, so fast arrow-key scrubbing doesn't rebuild it.
    private var selected: UpdateResult? {
        model.results.first { $0.id == detailSelection }
            ?? model.interruptedStandIns.first { $0.id == detailSelection }
    }

    /// The Brew-tree formula selected, when the selection is a formula row (tagged
    /// `brew:formula:<name>`) rather than an app. Drives the formula detail pane.
    private var selectedFormula: BrewInstalledFormula? {
        let prefix = "brew:formula:"
        guard let id = detailSelection, id.hasPrefix(prefix) else { return nil }
        let key = String(id.dropFirst(prefix.count))
        return model.brewFormulae.first { $0.key == key }
    }

    /// The unchecked Brew package selected, when the selection is one of those rows
    /// (tagged `brew:unchecked:<package id>`).
    private var selectedUnchecked: BrewUncheckedPackage? {
        let prefix = "brew:unchecked:"
        guard let id = detailSelection, id.hasPrefix(prefix) else { return nil }
        let packageID = String(id.dropFirst(prefix.count))
        return model.brewUnchecked.first { $0.id == packageID }
    }

    /// The app-less deprecated cask selected, when the selection is one of those
    /// rows (tagged `brew:cask:<token>`).
    private var selectedLifecycleCask: BrewCaskLifecycle? {
        let prefix = "brew:cask:"
        guard let id = detailSelection, id.hasPrefix(prefix) else { return nil }
        let token = String(id.dropFirst(prefix.count))
        return model.brewAppLessCaskLifecycles.first { $0.token == token }
    }

    /// The Homebrew self-update row's selection tag. Under `brew:`, so it counts
    /// as one of the Homebrew group's rows (`isHomebrewRow`).
    static let homebrewSelfUpdateTag = "brew:self-update"

    /// The "Other tools" header's scroll id (`cliRevealRequest`): not a
    /// selection tag, since the header is not a row.
    static let otherToolsHeaderID = "cli:other-tools-header"
    /// The Homebrew header's, likewise.
    static let homebrewHeaderID = "cli:homebrew-header"

    /// The Homebrew update on offer, when its row is the selection.
    private var selectedHomebrewSelfUpdate: HomebrewSelfUpdate? {
        detailSelection == Self.homebrewSelfUpdateTag ? model.homebrewSelfUpdate : nil
    }

    /// The command-line tool install selected, when the selection is one of those
    /// rows (tagged `<kind>:<install path>`, `CLIToolID.tag`).
    private var selectedCLITool: CLIToolStatus? {
        guard let id = detailSelection else { return nil }
        return model.cliTools.statuses.first { $0.toolID.tag == id }
    }

    var body: some View {
        let lists = sidebarLists
        return NavigationSplitView {
            sidebar(lists)
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
        } detail: {
            if let selected {
                detail(for: selected)
                    .id(selected.id)
            } else if let formula = selectedFormula {
                FormulaDetailPane(formula: formula, model: model)
                    .id("brew:formula:\(formula.name)")
            } else if let package = selectedUnchecked {
                BrewUncheckedDetailPane(package: package)
                    .id("brew:unchecked:\(package.id)")
            } else if let cask = selectedLifecycleCask {
                BrewLifecycleCaskDetailPane(cask: cask)
                    .id("brew:cask:\(cask.token)")
            } else if let update = selectedHomebrewSelfUpdate {
                HomebrewSelfUpdateDetailPane(update: update, model: model)
                    .id(Self.homebrewSelfUpdateTag)
            } else if let status = selectedCLITool {
                Group {
                    if case .claudeCode(let claudeCode) = status.detail {
                        ClaudeCodeDetailPane(status: claudeCode, cli: model.cliTools,
                                             showsRuntime: model.prefs.showCLIRuntimeTags)
                    } else {
                        CLIToolDetailPane(status: status, cli: model.cliTools,
                                          showsRuntime: model.prefs.showCLIRuntimeTags)
                    }
                }
                .id(status.toolID.tag)
            } else {
                ContentUnavailableView(
                    "Select an app",
                    systemImage: "sidebar.left",
                    description: Text("Pick an app to read its changelog."))
            }
        }
        .navigationTitle("DuoUpdater")
        .toolbar {
            // One item holding both controls, not two. Left as two, macOS 26/27
            // draws them inside a single capsule anyway but pads each item
            // itself, which put more space between the arrows and the gear than
            // at either end of the capsule. Grouped here the spacing is this
            // `HStack`'s, and it is also what lets `AppSortMenu` draw its symbol
            // in the toolbar at all: a `.borderlessButton` menu laid out by the
            // toolbar alone is sized to its own menu image, so a label drawn at
            // a chosen size was clipped by that slot — the arrows came out as a
            // down arrow and a sliver of the up one.
            ToolbarItem(placement: .primaryAction) {
                // Zero, not a negative that would close the gap further: the
                // ~6 pt each control keeps inside the capsule is its hover
                // highlight, so overlapping the two frames (measured: −8 put the
                // gap at 7.9 pt, level with the capsule's own 6.3/7.5) made one
                // control's highlight sit under the other's. Adjacent is the
                // tightest that stays honest; the space that remains between the
                // glyphs is the two hover zones touching.
                HStack(spacing: 0) {
                    // The order only means something for the Apps list; the CLI
                    // and Rollback tabs keep their own fixed presentation.
                    if sidebarTab == .apps {
                        AppSortMenu(prefs: model.prefs)
                    }
                    // Download traffic has its own window now
                    // (NetworkWindowView), so no traffic lens is needed here;
                    // the app-row pane is Release Notes or the Bundle Diff,
                    // which the detail column switches on its own.
                    Button {
                        openWindow(id: SettingsView.windowID)
                        model.surfaceWindow(sceneID: SettingsView.windowID)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
        // The sort is a reading preference, not a scan result: apply it now rather
        // than waiting for the next check. The popover has the same control and the
        // same hook, so whichever one is used the model updates once and both
        // windows redraw from the same `results`.
        .onChange(of: model.prefs.appSortOrder) { _, _ in
            model.appSortOrderChanged()
        }
        .task {
            // A "Changelog" deep-link from the menu row lands instantly, before the
            // (possibly networked) refresh below — the row already exists in
            // `model.results`, so the detail can render right away.
            let hadRequest = model.requestedWorkbenchAppID != nil
            if hadRequest { applyRequestedApp() }
            applyRequestedBrewUnchecked()
            applyRequestedCLITools()
            applyRequestedHomebrew()
            applyRequestedCLITool()
            // Every lane decides what an open calls for (`AppListModel.refreshes`):
            // the apps a full check with no data or while TestFlight is still
            // owed a read, otherwise a network-free rescan (`AppsRefreshPolicy`);
            // the CLI tab's brew tree, Homebrew's own offer and the other tools
            // beside them. Waits for the apps only, so the first row is picked
            // without waiting on brew's read.
            await model.refreshes.handle(.workbenchOpen, waitingFor: model.appsLane)
            if !hadRequest && selection == nil {
                selection = apps.first?.id
                detailSelection = selection   // first show is immediate, no debounce
            }
            // Claim the keyboard only now: before the rows exist there is no list to
            // focus, and the search field has already taken it by default.
            listFocus = shownTab(sidebarLists)
        }
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
            if searchText.isEmpty { listFocus = shownTab(sidebarLists) }
            // The lock and the TestFlight tip offer "Grant…" from a mirror of the
            // permission that only the menu's open and the Welcome/Settings polling
            // refresh. Coming back from System Settings is exactly this moment.
            model.refreshPermissionStatus()
            // A disk re-read of the apps, and brew and the CLI tab's tools too: a
            // `brew trust` run in a terminal, or a Helm installed there, stayed
            // invisible until the window was reopened. What a focus calls for is
            // each lane's to say (`AppsRefreshPolicy`, `BrewRefreshPolicy`,
            // `CLIToolsModel.onFocus`).
            Task { await model.refreshes.handle(.workbenchFocus) }
        }
        // Stationary stay (never lose focus) → the backstop timer keeps versions
        // fresh. Skip ticks while hidden/minimized: refreshing for a window no one
        // sees is wasted work and battery.
        .onReceive(refreshTimer) { _ in
            guard scenePhase != .background else { return }
            // Unattended: this fires on a 180s clock, not because the user did
            // anything.
            Task { await model.appsLane.handle(.backstopTick) }
        }
        // Keep lifecycle bookkeeping in the model so focus/badge refresh behavior
        // matches the other top-level windows.
        .onAppear {
            isWindowOpen = true
            model.windowAppeared()
        }
        .onDisappear {
            isWindowOpen = false
            model.windowDisappeared()
            // A cached changelog page pins a WebContent process (323–463 MB
            // measured on 2026-09-28) for as long as the app runs; nobody reads
            // it with the window closed.
            WebViewCache.removeAll()
        }
        .environment(\.workbenchWindowOpen, isWindowOpen)
        // Debounce the detail pane: the sidebar highlight (`selection`) follows the
        // arrow keys instantly, but `detailSelection` — what the heavy detail renders
        // — only catches up once the selection holds still: 400 ms while scrubbing,
        // 120 ms for a deliberate single step. Scrubbing through 40 apps then fires
        // one detail build instead of 40.
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
            if listFocus == nil { listFocus = shownTab(sidebarLists) }
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
        .onChange(of: model.requestedWorkbenchBrewUnchecked) { applyRequestedBrewUnchecked() }
        .onChange(of: model.requestedWorkbenchCLITools) { applyRequestedCLITools() }
        .onChange(of: model.requestedWorkbenchHomebrew) { applyRequestedHomebrew() }
        .onChange(of: model.requestedWorkbenchCLITool) { applyRequestedCLITool() }
        // `initial`: the window can open on a run already going — Update All from
        // the popover, then the workbench — and the order it first shows must hold
        // too (review, #1013). Otherwise the snapshot is taken as the run starts:
        // a status moves only when a re-check lands, after its update has run.
        .onChange(of: cliUpdatesRunning, initial: true) { _, running in
            heldCLIOrder = running
                ? CLIToolPresentation.outdatedFirst(model.brewFormulae, \.hasUpdate).map(Self.formulaTag)
                    + CLIToolPresentation.updatesFirst(model.cliTools.statuses).map(\.toolID.tag)
                : nil
        }
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
        // A search that hides the row would leave it out of the list: `tabChanged`
        // would then move the selection to the tab's first row and open a different
        // app, or, with the tab unchanged, the detail would show a row the list
        // does not.
        if let result = model.results.first(where: { $0.id == id }), !matchesSearch(result) {
            searchText = ""
        }
        // The row may be a Homebrew cask, which lives on the CLI tab. The tab is
        // set first; `tabChanged` then finds the selection already in its list and
        // leaves it alone.
        let isCask = brewCasks.contains { $0.id == id }
        sidebarTab = isCask ? .cli : .apps
        // A cask row is inside the Homebrew group, which may be closed.
        if isCask { homebrewRevealing = true }
        selection = id
        detailSelection = id
    }

    /// Honor a pending "Show in Window" from the popover's unchecked-brew tip:
    /// switch to the CLI tab and ask its list to reveal those rows. Clears the
    /// request like `applyRequestedApp`.
    private func applyRequestedBrewUnchecked() {
        guard model.requestedWorkbenchBrewUnchecked else { return }
        model.requestedWorkbenchBrewUnchecked = false
        guard !model.brewUnchecked.isEmpty else { return }
        // A search would hide the very rows being revealed.
        searchText = ""
        sidebarTab = .cli
        // Open the group first: a closed one has no rows to scroll to.
        homebrewRevealing = true
        uncheckedRevealRequest += 1
    }

    /// Honor a pending "Show in Window" from the popover's command-line tools row:
    /// switch to the CLI tab. Clears the request like `applyRequestedApp`.
    private func applyRequestedCLITools() {
        guard model.requestedWorkbenchCLITools else { return }
        model.requestedWorkbenchCLITools = false
        // A search could hide the rows the click was about.
        searchText = ""
        sidebarTab = .cli
        otherToolsRevealing = true
        cliRevealTarget = Self.otherToolsHeaderID
        cliRevealAnchor = .top
        cliRevealRequest += 1
    }

    /// Honor a pending "Show in Window" from the popover's Homebrew row: the CLI
    /// tab with the Homebrew group open for this visit, without rewriting what
    /// the user keeps (`HomebrewGroupState.revealing`).
    private func applyRequestedHomebrew() {
        guard model.requestedWorkbenchHomebrew else { return }
        model.requestedWorkbenchHomebrew = false
        // A search could hide the rows the click was about.
        searchText = ""
        homebrewRevealing = true
        sidebarTab = .cli
        cliRevealTarget = Self.homebrewHeaderID
        cliRevealAnchor = .top
        cliRevealRequest += 1
    }

    /// Honor a pending click on a row of the popover's tool groups' page: the
    /// CLI tab with that copy selected — its level opens for a selected row
    /// (`otherToolsExpanded`, `managerLevelExpanded`) — and scrolled to. The tab
    /// is set first, as in `applyRequestedApp`.
    private func applyRequestedCLITool() {
        guard let tag = model.requestedWorkbenchCLITool else { return }
        model.requestedWorkbenchCLITool = nil
        guard let status = model.cliTools.statuses.first(where: { $0.toolID.tag == tag }) else { return }
        // A search could hide the row.
        searchText = ""
        sidebarTab = .cli
        // A level the user closed in this window opens for it.
        collapsedManagerLevels.remove(CLIToolPresentation.Group.key(
            kind: status.kind, prefix: nil, manager: status.managedItem?.manager, root: status.managedItem?.root))
        selection = tag
        detailSelection = tag
        cliRevealTarget = tag
        cliRevealAnchor = .center
        cliRevealRequest += 1
    }

    // MARK: - Sidebar

    /// Which list the sidebar shows — one at a time, each at full height.
    ///
    /// These used to be collapsible trees stacked in one column: Apps and Brew
    /// sharing a split, and Rollback pinned beneath them, collapsed by default and
    /// capped at 240 pt. The Rollback list, where a backup's Bundle Diff lives, was
    /// the hardest part of the window to find and the one with the least room.
    ///
    /// `cli` was the Brew tab. It holds command-line tools by group now — Homebrew,
    /// then one per `CLIToolKind` — and a later tool adds a group rather than a tab.
    enum SidebarTab: Hashable {
        case apps, cli, rollback
    }

    /// Homebrew has anything for the CLI tab to show, before the search.
    private var homebrewHasAnything: Bool {
        !model.brewCaskResults.isEmpty || !model.brewFormulae.isEmpty || !model.brewUnchecked.isEmpty
            || !model.brewAppLessCaskLifecycles.isEmpty || model.homebrewSelfUpdate != nil
    }

    /// Rows the Homebrew group shows after the search.
    private func brewItemCount(_ lists: SidebarLists) -> Int {
        lists.brewCasks.count + lists.brewFormulae.count + lists.brewUnchecked.count
            + lists.brewLifecycleCasks.count + (lists.homebrewSelfUpdate == nil ? 0 : 1)
    }

    /// Rows the CLI tab shows after the search, for the tab's count.
    private func cliItemCount(_ lists: SidebarLists) -> Int {
        brewItemCount(lists) + lists.cliTools.count
    }

    /// The tab actually drawn: a remembered CLI tab falls back to Apps once there
    /// is no command-line tool left to show.
    private func shownTab(_ lists: SidebarLists) -> SidebarTab {
        sidebarTab == .cli && !lists.hasCLI ? .apps : sidebarTab
    }

    @ViewBuilder
    private func sidebar(_ lists: SidebarLists) -> some View {
        let tab = shownTab(lists)
        VStack(spacing: 0) {
            // The whole row picks one layout: one line per tab while every tab fits,
            // two lines for all of them otherwise. Deciding per tab would stack
            // "Rollback" under its icon while "Apps" sits beside its own.
            ViewThatFits(in: .horizontal) {
                tabRow(lists, shown: draggedTab ?? tab, stacked: false)
                tabRow(lists, shown: draggedTab ?? tab, stacked: true)
            }
            .coordinateSpace(.named(Self.tabTrackSpace))
            // Dragging along the track moves the highlight and switches on release,
            // like the system segmented control. Simultaneous, so a plain click still
            // reaches the tab's button. Only on release: entering a tab moves the
            // selection and the detail pane, and a drag from Apps to Rollback should
            // not open CLI's first row on the way.
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.tabTrackSpace))
                    .updating($draggedTab) { value, dragged, _ in
                        dragged = tabAt(x: value.location.x, hasCLI: lists.hasCLI) ?? dragged
                    }
                    .onEnded { value in
                        if let target = tabAt(x: value.location.x, hasCLI: lists.hasCLI) {
                            sidebarTab = target
                        }
                    })
            .padding(3)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .animation(.snappy(duration: 0.22), value: draggedTab ?? tab)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            AppSearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            // Every list built so far, the one on screen above the others
            // (`builtTabs`). Each is its own branch, so showing one leaves the
            // others' identity, rows and scroll position alone.
            ZStack {
                if tab == .apps || builtTabs.contains(.apps) {
                    appsListView(lists, isShown: tab == .apps)
                        .keptLayer(isShown: tab == .apps)
                }
                // Not kept: its list is drawn in this body, so a hidden copy was rebuilt
                // with every pass of it and made each switch between the other two
                // 25–30 ms slower (Time Profiler, 2026-10-10).
                if lists.hasCLI, tab == .cli {
                    cliListView(lists)
                }
                if tab == .rollback || builtTabs.contains(.rollback) {
                    VStack(spacing: 0) {
                        // Shown even with nothing restorable locally: that is precisely
                        // the case where the list would otherwise look empty rather than
                        // partial.
                        if let disk = model.offlineBackupDisk {
                            offlineBackupNotice(disk, hasRollback: !lists.rollbackable.isEmpty)
                        }
                        rollbackListView(lists, isShown: tab == .rollback)
                    }
                    .keptLayer(isShown: tab == .rollback)
                }
            }
            .onChange(of: tab, initial: true) { _, shown in builtTabs.insert(shown) }
        }
        .onChange(of: sidebarTab) { _, newTab in tabChanged(to: newTab) }
    }

    private static let tabTrackSpace = "sidebarTabTrack"

    /// The tab at a horizontal position in the track, clamped to the first and last
    /// tab so dragging past either end keeps the end tab. A CLI frame outlives the
    /// CLI tab once no command-line tool is left, so it is skipped then.
    private func tabAt(x: CGFloat, hasCLI: Bool) -> SidebarTab? {
        let ordered = tabFrames
            .filter { hasCLI || $0.key != .cli }
            .sorted { $0.value.minX < $1.value.minX }
        guard let first = ordered.first, let last = ordered.last else { return nil }
        if x < first.value.minX { return first.key }
        if x >= last.value.maxX { return last.key }
        // Gaps between tabs belong to the tab on their left.
        return ordered.last { $0.value.minX <= x }?.key
    }

    private func tabRow(_ lists: SidebarLists, shown: SidebarTab, stacked: Bool) -> some View {
        HStack(spacing: 4) {
            tabButton(.apps, title: String(localized: "Apps"), systemImage: "square.grid.2x2.fill",
                      count: lists.filteredApps.count, reservedCount: lists.appsTotal,
                      shown: shown, stacked: stacked)
            if lists.hasCLI {
                // A terminal, not Homebrew's mug: the tab is every command-line tool
                // now. Filled, like the Apps tab's glyph beside it.
                tabButton(.cli, title: String(localized: "CLI"), systemImage: "terminal.fill",
                          count: cliItemCount(lists), reservedCount: lists.cliTotal,
                          shown: shown, stacked: stacked)
            }
            tabButton(.rollback, title: String(localized: "Restore"), systemImage: "arrow.uturn.backward",
                      count: lists.rollbackable.count, reservedCount: lists.rollbackTotal,
                      shown: shown, stacked: stacked)
        }
    }

    /// One tab: icon, title and count on one line when the row has room, otherwise
    /// icon and count on top with the title beneath. At the sidebar's 260 pt minimum
    /// a tab is ~75 pt wide inside the track. The widest title measured at caption
    /// semibold is the German "Wiederherstellen", 86 pt; the stacked layout's 0.8
    /// scale factor brings it to 69 pt, and covers whatever else is wider.
    private func tabButton(
        _ tab: SidebarTab, title: String, systemImage: String, count: Int, reservedCount: Int,
        shown: SidebarTab, stacked: Bool
    ) -> some View {
        let selected = tab == shown
        let icon = Image(systemName: systemImage).font(.body)
        // The tab is centred as a whole, so a count that loses a digit to the search
        // would shift the icon and title with it. The slot keeps the width of the
        // count before the search (digits are monospaced, so width follows the digit
        // count) and the count sits at its leading edge.
        let countText = ZStack(alignment: .leading) {
            // Sizes the slot only. `hidden()` is documented as not drawn and not
            // interactive, but says nothing about VoiceOver, so it is taken out of
            // the accessibility tree explicitly rather than risk "175 3" being read.
            Text("\(max(count, reservedCount))").hidden().accessibilityHidden(true)
            Text("\(count)")
        }
            .font(.caption.weight(.semibold)).monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        return Button {
            sidebarTab = tab
        } label: {
            Group {
                if stacked {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            icon
                            countText
                        }
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    // No scale factor here: ViewThatFits measures the unscaled width,
                    // so a title that only fits shrunk must take the stacked layout.
                    // On the text baseline: the count is a size smaller than the
                    // title, and centred it rides visibly higher than the title.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        icon
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        countText.opacity(0.75)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.16))
                        .matchedGeometryEffect(id: "selectedTab", in: tabHighlight)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.tabTrackSpace)) } action: {
                tabFrames[tab] = $0
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }

    /// Says why this list is shorter than the store. Without it an unplugged disk
    /// and an empty store look the same on screen — and the second reading is the
    /// one that makes a user think their backups are gone.
    private func offlineBackupNotice(_ disk: String, hasRollback: Bool) -> some View {
        Label {
            // No `fixedSize(vertical:)`: the window's minimum size is measured with
            // this text far narrower than the column's 260 pt minimum, where it
            // stands about a character to a row. Measured, it held the Workbench at
            // 1,247 pt on a 1,083 pt screen, its bottom off-screen. Without it the
            // list below gives way first: the longest translation (French, at the
            // 260 pt column) still wraps in full in a window 300 pt tall.
            Text("Backups on “\(disk)” aren’t available right now — showing only what’s on this Mac.")
        } icon: {
            Image(systemName: "externaldrive.badge.xmark")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, hasRollback ? 2 : 8)
    }

    /// Entering a tab sets which pane the detail opens on, and moves the selection
    /// into the tab's own list when it is not already there — a detail pane showing
    /// an app the visible list does not contain reads as a bug.
    private func tabChanged(to tab: SidebarTab) {
        detailMode = tab == .rollback ? .bundleDiff : .releaseNotes
        // A reveal is for the visit it was made for.
        if tab != .cli { homebrewRevealing = false; otherToolsRevealing = false }
        let lists = sidebarLists
        // The list that held the keyboard stays alive, hidden and out of the key
        // loop, so the keyboard moves to the one now on screen.
        if listFocus != nil { listFocus = shownTab(lists) }
        let ids = selectableIDs(tab, lists)
        if let current = selection, ids.contains(current) { return }
        selection = ids.first
        detailSelection = selection
        listFocus = shownTab(lists)
    }

    /// A tab's selectable rows, in the order its list draws them: what the arrow
    /// keys walk, and where entering the tab puts the selection. A closed group's
    /// rows are not drawn, so they are not in it.
    private func selectableIDs(_ tab: SidebarTab, _ lists: SidebarLists) -> [String] {
        switch tab {
        case .apps:
            return lists.filteredApps.map(\.id)
        case .cli:
            let brew = (lists.homebrewSelfUpdate == nil ? [] : [Self.homebrewSelfUpdateTag])
                + lists.brewCasks.map(\.id)
                + lists.brewFormulae.map(Self.formulaTag)
                + lists.brewLifecycleCasks.map { "brew:cask:\($0.token)" }
                + lists.brewUnchecked.map { "brew:unchecked:\($0.id)" }
            return SidebarSelection.cliOrder(
                homebrewExpanded: homebrewExpanded(lists), homebrew: brew,
                otherToolsExpanded: otherToolsExpanded(lists),
                tools: lists.cliTools.filter { $0.managedItem == nil }.map(\.toolID.tag),
                managers: managerLevels(lists.cliTools).map {
                    (managerLevelExpanded($0, lists), $0.statuses.map(\.toolID.tag))
                })
        case .rollback:
            return lists.rollbackable.map(\.id)
        }
    }

    /// The Rollback tab: every app with a backup we can restore, each with an inline
    /// "Roll back" action. Selecting one opens its Bundle Diff, the change a rollback
    /// would undo.
    private func rollbackListView(_ lists: SidebarLists, isShown: Bool) -> some View {
        WorkbenchRollbackList(
            apps: lists.rollbackable, searchText: searchText, isShown: isShown,
            model: model, selection: $selection, focus: $listFocus)
            .equatable()
    }

    /// Bulk "Upgrade All" for the Homebrew group — runs `brew upgrade --formula` (all
    /// outdated CLI formulae at once). Only shown when there are formulae to upgrade;
    /// casks stay per-row (their own distribution channel). Its own view
    /// (`BrewUpgradeAllButton`), so its progress redraws it alone.
    private var brewBulkUpgrade: some View {
        BrewUpgradeAllButton(model: model)
    }

    // MARK: - Other tools

    /// Open while the user keeps it open, a deep link revealed it, a search
    /// matches inside it, or one of its rows is selected.
    private func otherToolsExpanded(_ lists: SidebarLists) -> Bool {
        otherToolsExpandedPreference || otherToolsRevealing || otherToolsSearchHits(lists)
            || isOtherToolsRow(selection)
    }

    /// A search is typed and matches a row of the tool groups.
    private func otherToolsSearchHits(_ lists: SidebarLists) -> Bool {
        !searchQuery.isEmpty && lists.cliTools.contains { $0.managedItem == nil }
    }

    private func isOtherToolsRow(_ id: String?) -> Bool {
        guard let id else { return false }
        return model.cliTools.statuses.contains { $0.managedItem == nil && $0.toolID.tag == id }
    }

    /// The copies under "Other tools": every tool but a manager's items, which
    /// have a level of their own (`managerLevels`).
    private var standaloneScope: Set<CLIToolID> {
        Set(model.cliTools.statuses.filter { $0.managedItem == nil }.map(\.toolID))
    }

    // MARK: - Managers' own levels

    /// Each manager's items ("mise tools") as a level of their own beside
    /// Homebrew and "Other tools": the same shape as Homebrew, one manager and
    /// its many packages, with its own counts and its own Update All. In the
    /// order the groups are drawn (`CLIToolPresentation.groups`), from `statuses`.
    private func managerLevels(_ statuses: [CLIToolStatus]) -> [CLIToolPresentation.Group] {
        CLIToolPresentation.managerGroups(CLIToolPresentation.groups(statuses))
    }

    /// The whole level's copies, not the search's: what its counts and its
    /// Update All cover.
    private func scope(of level: CLIToolPresentation.Group) -> Set<CLIToolID> {
        Set(model.cliTools.statuses.filter {
            CLIToolPresentation.Group.key(kind: $0.kind, prefix: nil, manager: $0.managedItem?.manager,
                                          root: $0.managedItem?.root) == level.id
        }.map(\.toolID))
    }

    /// Open unless the user closed it in this window — not remembered, like
    /// the popover's stack — or while a search matches inside it or one of its
    /// rows is selected.
    private func managerLevelExpanded(_ level: CLIToolPresentation.Group, _ lists: SidebarLists) -> Bool {
        !collapsedManagerLevels.contains(level.id) || managerLevelSearchHits(level, lists)
            || level.statuses.contains { $0.toolID.tag == selection }
    }

    private func managerLevelSearchHits(_ level: CLIToolPresentation.Group, _ lists: SidebarLists) -> Bool {
        !searchQuery.isEmpty && managerLevels(lists.cliTools).contains { $0.id == level.id }
    }

    /// A click on a manager level's header or summary. Closing it moves a
    /// selection that was one of its rows off it, since that row is going.
    private func toggleManagerLevel(_ level: CLIToolPresentation.Group, _ lists: SidebarLists) {
        if managerLevelExpanded(level, lists) {
            collapsedManagerLevels.insert(level.id)
            if level.statuses.contains(where: { $0.toolID.tag == selection }) {
                selection = nil
                detailSelection = nil
            }
        } else {
            collapsedManagerLevels.remove(level.id)
        }
    }

    /// Opens or closes a group in one frame, not animated. The sidebar list drew
    /// these changes in one frame anyway, except when the click also moved the
    /// selection — after a tab switch, which selects the first row — and then
    /// the closing rows slid up underneath the header and summary rows that
    /// stay, fading as they went (recorded at 60 fps on 2026-10-06).
    private func inOneFrame(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// A click on the "Other tools" header or its summary. Closing it moves a
    /// selection that was one of its rows off it, since that row is going.
    private func toggleOtherTools(_ lists: SidebarLists) {
        let closing = otherToolsExpanded(lists)
        otherToolsExpandedPreference = !closing
        otherToolsRevealing = false
        if closing, isOtherToolsRow(selection) {
            selection = nil
            detailSelection = nil
        }
    }

    /// The row under the "Other tools" header: how many updates the tool groups
    /// below have, and how many copies went unchecked — the whole set's, not the
    /// search's, like the Homebrew summary. A click on it opens or closes the
    /// level, like the Homebrew summary's.
    private func otherToolsSummary(_ lists: SidebarLists) -> some View {
        toolsSummary(scope: standaloneScope, trailing: nil, toggleDisabled: otherToolsSearchHits(lists)) {
            toggleOtherTools(lists)
        }
    }

    /// The same row under a manager's level: its items' counts, and on the
    /// right what its group header said — "mise 2026.10.15", with the root after
    /// it when the manager has more than one, which tells two roots of one
    /// manager apart.
    private func managerLevelSummary(_ level: CLIToolPresentation.Group, _ lists: SidebarLists) -> some View {
        toolsSummary(scope: scope(of: level), trailing: cliToolHeaderSummary(level),
                     info: managedHeaderInfo(level),
                     toggleDisabled: managerLevelSearchHits(level, lists)) {
            toggleManagerLevel(level, lists)
        }
    }

    /// A level's counts over the copies `scope` names.
    private func toolsSummary(
        scope: Set<CLIToolID>, trailing: String?, info: ManagedHeaderInfo? = nil, toggleDisabled: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        let tools = model.cliTools
        let inScope = { (status: CLIToolStatus) in scope.contains(status.toolID) }
        // What Update All updates; a held-back update is counted apart — counted
        // with them, "2 updates" sat above one Update button.
        let updates = tools.offered.filter(inScope).count
        let held = tools.heldBack.filter(inScope)
        let unchecked = tools.unchecked.filter(inScope).count
        let sudoCount = tools.adminOffered.filter(inScope).count
        return HStack(spacing: 8) {
            Button { inOneFrame(toggle) } label: {
                HStack(spacing: 8) {
                    if updates > 0 {
                        Text(String(localized: "\(updates) updates")).foregroundStyle(.tint).lineLimit(1)
                    } else if held.isEmpty && unchecked == 0 {
                        // Not while a copy went unanswered: that would be a claim
                        // about it too (`CLIToolsModel.unchecked`).
                        Text(String(localized: "Up to date")).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let sudo = CLIToolPresentation.needSudo(sudoCount) {
                        Text(sudo)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(CLIToolPresentation.sudoBadgeHelp)
                    }
                    if !held.isEmpty {
                        // Why each was held back, on hover: "openclaw 2026.9.8 needs …".
                        Text(String(localized: "\(held.count) held back"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(held.compactMap { status in
                                status.withheld.map { CLIToolsModel.reason($0, of: status) }
                            }.joined(separator: "\n"))
                    }
                    if unchecked > 0 {
                        let help = String(localized: "\(unchecked) not checked")
                        Label {
                            Text(verbatim: "\(unchecked)")
                        } icon: {
                            Image(systemName: "questionmark.circle")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .help(help)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(help)
                        .fixedSize()
                    }
                    Spacer(minLength: 0)
                    if let trailing {
                        Text(verbatim: trailing)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .help(trailing)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(toggleDisabled)
            if let info {
                ManagedPathsInfoButton(info: info)
            }
        }
    }

    /// The managed group's info affordance: hover shows the abbreviated paths,
    /// and a click opens the full paths with a copy button for each. It is
    /// deliberately outside the summary's toggle Button — inside it, a click
    /// folded the group instead of showing anything.
    private struct ManagedHeaderInfo {
        let tooltip: String
        let paths: [ManagerContext.Paths]
    }

    private struct ManagedPathsInfoButton: View {
        let info: ManagedHeaderInfo
        @State private var showing = false

        var body: some View {
            Button { showing.toggle() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help(info.tooltip)
            .accessibilityLabel(Text(verbatim: "Manager paths"))
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(info.paths.enumerated()), id: \.offset) { index, paths in
                        if index > 0 { Divider() }
                        if let binary = paths.binary {
                            ManagedPathRow(label: "Binary", path: binary)
                        }
                        ManagedPathRow(label: "Data", path: paths.data)
                    }
                }
                .padding(12)
                .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    /// One path in the info popover: selectable text, and a button right after
    /// it that puts the full path on the pasteboard. The button follows the
    /// path instead of being pushed to the popover's edge: a short `.nvm` path
    /// would otherwise leave a hand's width of empty space before it.
    private struct ManagedPathRow: View {
        let label: String
        let path: String

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(Text(verbatim: "Copy path"))
                    .accessibilityLabel(Text(verbatim: "Copy path"))
                }
            }
        }
    }

    /// Update All for the tool groups: what the popover's "Other tools" Update
    /// runs — every copy with a one-click update, each with its own tool's
    /// command, the independent ones at once (`CLIToolsModel.lane(of:)`), after
    /// one administrator panel per copy that needs sudo, at the click. Copies
    /// without one are left alone.
    ///
    /// Kept while any update is on offer, disabled while every one of them is
    /// already updating — Homebrew's Upgrade All rule — and covered by a spinner
    /// while it runs rather than replaced by one. The header's height is the
    /// button's: when it went away for a single row's update and came back when
    /// that failed, every row below moved 1 pt up and back (fx, 2026-10-06).
    /// Kept too while Update All waits or runs, whatever is on offer: a check
    /// landing mid-run can hold back every copy left ("npm is busy in this
    /// prefix", its own run's npm), and the header took its spinner and Cancel
    /// with it (2026-10-20, #1498 real-Mac check).
    private var otherToolsBulkUpdate: some View {
        OtherToolsUpdateAllButton(tools: model.cliTools, scope: standaloneScope)
    }

    // MARK: - Homebrew group

    private var homebrewGroup: HomebrewGroupState {
        HomebrewGroupState(preferenceExpanded: homebrewExpandedPreference, revealing: homebrewRevealing)
    }

    /// A search is typed and matches a row inside the Homebrew group.
    private func homebrewSearchHits(_ lists: SidebarLists) -> Bool {
        !searchQuery.isEmpty && brewItemCount(lists) > 0
    }

    /// Whether `id` is one of the Homebrew group's rows: a cask, a formula, or an
    /// unchecked package.
    private func isHomebrewRow(_ id: String?) -> Bool {
        guard let id else { return false }
        return id.hasPrefix("brew:") || model.brewCaskResults.contains { $0.id == id }
    }

    private func homebrewExpanded(_ lists: SidebarLists) -> Bool {
        homebrewGroup.isExpanded(searchHits: homebrewSearchHits(lists), holdsSelection: isHomebrewRow(selection))
    }

    /// A click on the Homebrew header. Closing it moves a selection that was one of
    /// its rows to the first row of the tool groups below it (or none), since that
    /// row is going.
    private func toggleHomebrewGroup() {
        var group = homebrewGroup
        let holdsSelection = isHomebrewRow(selection)
        group.toggle(holdsSelection: holdsSelection)
        homebrewExpandedPreference = group.preferenceExpanded
        homebrewRevealing = group.revealing
        if !group.preferenceExpanded, holdsSelection {
            // To the first tool row only while "Other tools" is open: moved into a
            // closed level, the selection opened it (a selected row holds its
            // level open), and the one click closed Homebrew and opened that.
            let lists = sidebarLists
            selection = otherToolsExpanded(lists) ? lists.cliTools.first?.toolID.tag : nil
            detailSelection = selection
        }
    }

    /// The Homebrew group's header (`HomebrewGroupHeader`), fed from the model.
    private func homebrewHeader(_ lists: SidebarLists, expanded: Bool) -> some View {
        HomebrewGroupHeader(
            expanded: expanded,
            // A search holds the group open while it matches rows inside; closing
            // it then would hide exactly what was searched for.
            toggleDisabled: homebrewSearchHits(lists),
            toggle: { inOneFrame { toggleHomebrewGroup() } }
        ) {
            brewBulkUpgrade
        }
        .padding(.trailing, Self.sectionHeaderTrailingInset)
    }

    /// What a sidebar section header needs at its trailing edge to end where its
    /// rows' content does. Without it a header runs 14 pt further, to 2 pt from
    /// the list's edge: measured 2026-10-06 in a 300 pt `.sidebar` List, header
    /// content to 298 against a row's 284 with overlay scroll bars, 281 against
    /// 267 with them always shown. There the overlay scroller covered the end of
    /// each header's summary ("auto-update o", "node 24.13.") and Upgrade All.
    private static let sectionHeaderTrailingInset: CGFloat = 14

    /// The counts-and-marks row under that header (`HomebrewGroupSummary`). The
    /// whole group's, not the search's: a search that matches inside opens the
    /// group, and its rows show what matched.
    private func homebrewSummary(_ lists: SidebarLists) -> some View {
        let casks = model.brewCaskResults
        return HomebrewGroupSummary(
            packages: casks.count + model.brewFormulae.count + model.brewUnchecked.count
                + model.brewAppLessCaskLifecycles.count,
            outdated: casks.filter(\.hasUpdate).count + model.brewFormulae.filter(\.hasUpdate).count,
            unchecked: model.brewUnchecked.count,
            // While Upgrade All is on offer, as the popover shows it.
            upgradeError: model.brewOutdatedFormulae.isEmpty ? nil : model.brewUpgradeError,
            homebrewUpdate: model.homebrewSelfUpdate?.latest,
            toggleDisabled: homebrewSearchHits(lists),
            toggle: { inOneFrame { toggleHomebrewGroup() } })
    }

    /// A tool group's header: the tool's name, and what decides its installs'
    /// verdicts tool-wide. Claude Code's channel and whether auto-update is on —
    /// which decides whether any of them can offer one-click at all; fx's channel;
    /// nothing for bub, which has neither.
    private func cliToolHeader(_ group: CLIToolPresentation.Group) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: group.title)
            Spacer()
            if let summary = cliToolHeaderSummary(group) {
                // Several languages say "auto-update off" in twice the English width;
                // shrunk a little, then cut in the middle, with the whole line on
                // hover. Middle, not tail: a managed group's root comes last, and
                // that is the part telling two roots of one manager apart.
                Text(verbatim: summary)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    .help(summary)
            }
            // Where the manager's binary and data root are: the header keeps
            // the name, version and (for a multi-root manager) the root, and the
            // full paths stay out of the way until asked for.
            if let info = managedHeaderInfo(group) {
                ManagedPathsInfoButton(info: info)
            }
            // The node an npm prefix runs has notices: one mark for the node,
            // on its group, not one on each package it runs. A click says them.
            if let prefix = group.prefix {
                let notices = CLIToolPresentation.nodeNotices(
                    ofPrefix: prefix, statuses: model.cliTools.statuses, in: model.runtimeSecurity)
                if let help = CLIToolPresentation.securityMarkHelp(notices) {
                    let statuses = model.cliTools.statuses, report = model.runtimeSecurity
                    RuntimeSecurityMarkButton(
                        help: help, title: cliToolHeaderSummary(group) ?? group.title, notices: notices,
                        upgrade: { CLIToolPresentation.upgradeCommand(ofPrefix: prefix, statuses: statuses, in: report) })
                        .font(.caption)
                }
            }
        }
        .padding(.trailing, Self.sectionHeaderTrailingInset)
    }

    private func cliToolHeaderSummary(_ group: CLIToolPresentation.Group) -> String? {
        let kind = group.kind
        if let prefix = group.prefix {
            // One npm prefix: which one, and its node. The whole prefix's packages,
            // not the search's, like the other summaries.
            let label = CLIToolPresentation.prefixLabel(prefix, home: FileManager.default.homeDirectoryForCurrentUser.path)
            let mine = model.cliTools.statuses.filter {
                guard case .npm(let package) = $0.detail else { return false }
                return $0.kind == .npm && package.install.prefix.path == prefix.path
            }
            let node = CLIToolPresentation.headerSummary(.npm, statuses: mine, context: model.cliTools.contexts[.npm])
            return [label, node].compactMap { $0 }.joined(separator: " · ")
        }
        switch kind {
        case .claudeCode:
            return ClaudeCodePresentation.settingsSummary(model.cliTools.claudeCodeSettings ?? ClaudeCodeSettings())
        case .fx:
            // What the installs were checked on, as their statuses say. The whole
            // group's, not the search's, like the Homebrew summary.
            return CLIToolPresentation.channels(of: model.cliTools.statuses.filter { $0.kind == .fx })
        case .bub:
            return nil
        case .uv, .junie, .rust, .npm, .boat, .codex, .bun, .pnpm, .yarn, .opencode, .cursorAgent, .amp, .vitePlus, .herdr, .luvus, .lorca, .zoxide, .nvm, .atuin, .ghcup, .flyctl, .helm, .starship, .deno, .mise, .obelus, .biome:
            return CLIToolPresentation.headerSummary(
                kind, statuses: model.cliTools.statuses, context: model.cliTools.contexts[kind])
        case .managed:
            // "uv 0.13.4", or "fnm 1.39.0 · ~/.local/share/fnm" when the manager
            // has more than one root (`ManagerContext.headerSummary`). The paths
            // are behind the group's info icon.
            guard let manager = group.manager else { return nil }
            return model.cliTools.managedContexts[manager]?.headerSummary(
                home: FileManager.default.homeDirectoryForCurrentUser.path, root: group.root)
        }
    }

    /// The info icon's data for a managed group: the abbreviated hover text and
    /// the real paths to copy, when there is a binary to name. Nil for every
    /// other kind and for a group whose manager was not found (its summary is
    /// the root alone).
    private func managedHeaderInfo(_ group: CLIToolPresentation.Group) -> ManagedHeaderInfo? {
        guard group.kind == .managed, let manager = group.manager,
              let context = model.cliTools.managedContexts[manager]
        else { return nil }
        let root = group.root.flatMap { path in context.roots.first { $0.path == path } }
            ?? (group.root == nil ? context.roots.first : nil)
        guard root?.binary != nil else { return nil }
        let paths = context.headerPaths(root: group.root)
        guard !paths.isEmpty, let tooltip = context.headerTooltip(
            home: FileManager.default.homeDirectoryForCurrentUser.path, root: group.root)
        else { return nil }
        return ManagedHeaderInfo(tooltip: tooltip, paths: paths)
    }

    /// The Apps tab's list.
    private func appsListView(_ lists: SidebarLists, isShown: Bool) -> some View {
        WorkbenchAppsList(
            apps: lists.filteredApps, searchText: searchText, isShown: isShown,
            model: model, selection: $selection, focus: $listFocus)
            .equatable()
    }

    /// The CLI tab's list, one group per tool: Homebrew, then each `CLIToolKind`
    /// with an install, in `allCases` order.
    ///
    /// The Homebrew group is what the Brew tab was — brew-managed casks (reusing
    /// the app row + its existing install path) above CLI formulae (their own inline
    /// action) — and opens and closes (`HomebrewGroupState`). Every other tool's is
    /// a handful of rows at most and is always open.
    private func cliListView(_ lists: SidebarLists) -> some View {
        let brewExpanded = homebrewExpanded(lists)
        // With nothing typed, the group is there whenever Homebrew has anything;
        // a search that matches nothing inside it hides it like any other row.
        let showsBrew = searchQuery.isEmpty ? homebrewHasAnything : brewItemCount(lists) > 0
        return ScrollViewReader { proxy in
            SidebarList(selection: $selection, order: selectableIDs(.cli, lists),
                        label: String(localized: "CLI"), focus: $listFocus, focusValue: .cli) {
                if showsBrew {
                    homebrewHeader(lists, expanded: brewExpanded)
                        .sidebarSectionHeader(first: true)
                        .id(Self.homebrewHeaderID)
                    homebrewSummary(lists)
                        .sidebarStaticRow()
                    if brewExpanded {
                        if let update = lists.homebrewSelfUpdate {
                            // Selecting it opens Homebrew's release notes
                            // (`HomebrewSelfUpdateDetailPane`).
                            HomebrewSelfUpdateSidebarRow(update: update, model: model)
                                .sidebarRow(Self.homebrewSelfUpdateTag, selection: $selection)
                        }
                        ForEach(lists.brewCasks) { result in
                            WorkbenchAppRow(result: result, model: model)
                                .equatable()
                                .sidebarRow(result.id, selection: $selection)
                        }
                        ForEach(lists.brewFormulae) { formula in
                            BrewFormulaSidebarRow(formula: formula, model: model)
                                .sidebarRow(Self.formulaTag(formula), selection: $selection)
                        }
                        ForEach(lists.brewLifecycleCasks) { cask in
                            BrewLifecycleCaskSidebarRow(cask: cask)
                                .sidebarRow("brew:cask:\(cask.token)", selection: $selection)
                        }
                        ForEach(lists.brewUnchecked) { package in
                            BrewUncheckedSidebarRow(package: package, highlighted: highlightUnchecked)
                                .sidebarRow("brew:unchecked:\(package.id)", selection: $selection)
                        }
                    }
                }
                // Each manager's items, a level of their own right under Homebrew,
                // which is one too — a manager and its many packages — and before
                // the single tools under "Other tools" (owner, 2026-10-24; D12
                // revised). Laid out as Homebrew's: header with its Update All,
                // the counts row, its rows.
                let levels = managerLevels(lists.cliTools)
                ForEach(levels) { level in
                    let expanded = managerLevelExpanded(level, lists)
                    // The 4 pt between sections, as "Other tools" draws it below.
                    if showsBrew || level.id != levels.first?.id {
                        Color.clear.frame(height: 4).accessibilityHidden(true)
                    }
                    HomebrewGroupHeader(
                        title: level.title,
                        expanded: expanded,
                        toggleDisabled: managerLevelSearchHits(level, lists),
                        toggle: { inOneFrame { toggleManagerLevel(level, lists) } }
                    ) {
                        OtherToolsUpdateAllButton(tools: model.cliTools, scope: scope(of: level))
                    }
                    .padding(.trailing, Self.sectionHeaderTrailingInset)
                    .sidebarSectionHeader(first: true)
                    managerLevelSummary(level, lists)
                        .sidebarStaticRow()
                    ForEach(expanded ? level.statuses : [], id: \.toolID) { status in
                        CLIToolSidebarRow(
                            status: status, cli: model.cliTools,
                            showsRuntime: model.prefs.showCLIRuntimeTags)
                            .sidebarRow(status.toolID.tag, selection: $selection)
                    }
                }
                // The popover's second row, "Other tools", as a level of its own,
                // after the managers': what the groups below come to, and Update
                // All for them.
                let othersExpanded = otherToolsExpanded(lists)
                let standalone = lists.cliTools.filter { $0.managedItem == nil }
                if searchQuery.isEmpty ? !standaloneScope.isEmpty : !standalone.isEmpty {
                    // A later section's header sits 16 pt under the row above, the
                    // first's 12 (`sidebarSectionHeader`). The 4 pt between is drawn
                    // apart from the header, which takes the first's padding: scrolled
                    // to the top (`cliRevealRequest`) it then lands where Homebrew's
                    // does, not 4 pt lower (2026-10-20, y 190 against 186).
                    if showsBrew || !levels.isEmpty {
                        Color.clear.frame(height: 4).accessibilityHidden(true)
                    }
                    // Homebrew's header, so the two levels open, close and line up
                    // alike.
                    HomebrewGroupHeader(
                        title: String(localized: "Other tools"),
                        expanded: othersExpanded,
                        toggleDisabled: otherToolsSearchHits(lists),
                        toggle: { inOneFrame { toggleOtherTools(lists) } }
                    ) {
                        // One spinner for a check, which reads every tool at once:
                        // drawn on each group's header, twelve of them turned while
                        // one update re-checked. Update All shows its own while it
                        // runs.
                        if model.cliTools.checking && !model.cliTools.updatingAll {
                            ProgressView().controlSize(.mini)
                        }
                        otherToolsBulkUpdate
                    }
                    .padding(.trailing, Self.sectionHeaderTrailingInset)
                    .sidebarSectionHeader(first: true)
                    .id(Self.otherToolsHeaderID)
                    otherToolsSummary(lists)
                        .sidebarStaticRow()
                }
                ForEach(othersExpanded ? CLIToolPresentation.groups(standalone) : []) { group in
                    cliToolHeader(group)
                        .sidebarSectionHeader(first: false)
                    ForEach(group.statuses, id: \.toolID) { status in
                        CLIToolSidebarRow(
                            status: status, cli: model.cliTools,
                            showsRuntime: model.prefs.showCLIRuntimeTags)
                            .sidebarRow(status.toolID.tag, selection: $selection)
                    }
                }
            }
            .overlay {
                if cliItemCount(lists) == 0, !searchQuery.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            // Runs on a new request, and also when this list is created by the tab
            // switch that request caused (on another tab there was no list to scroll).
            .task(id: uncheckedRevealRequest) {
                guard uncheckedRevealRequest != uncheckedRevealHandled else { return }
                // Let a list that tab switch just created lay out its rows before
                // scrolling it. Not measured whether the wait is strictly needed.
                try? await Task.sleep(for: .milliseconds(150))
                // Marked handled only by the task that actually scrolls. A freshly
                // opened window replaces this list once while settling (measured:
                // height 80 → 381, and this task woke cancelled); marking it before
                // the sleep let that dead list's task claim the request, so the
                // list on screen never scrolled.
                guard !Task.isCancelled, let last = lists.brewUnchecked.last else { return }
                uncheckedRevealHandled = uncheckedRevealRequest
                withAnimation(.easeIn(duration: 0.2)) { highlightUnchecked = true }
                // The unchecked rows are the tail of the Homebrew group; anchoring the
                // last one at the bottom brings the whole run into view.
                //
                // Twice, on purpose. In a freshly opened window one scroll stopped
                // several rows short, the same spot every time (measured: two runs,
                // ending on trivy with the unchecked rows below the fold), while the
                // same call in a window already open landed. A second scroll a
                // moment later reached the bottom (measured: two runs). Why the
                // first falls short isn't established. The last row's `onAppear` was
                // tried as a "did it land" signal and read true after the short
                // scroll too, so it can't decide whether to retry.
                //
                // Scrolled to by the row's selection id, which `sidebarRow` sets as
                // the row's `.id` (`SidebarRowModifier`) — the same `.id` the
                // keyboard's `scrollTo` in `SidebarList` resolves, so keep it on every
                // row. (Under the old `List` the rows carried a selection `.tag`
                // instead, and a separate `.id(package.id)` stopped the scroll
                // working; that no longer applies.)
                proxy.scrollTo("brew:unchecked:\(last.id)", anchor: .bottom)
                try? await Task.sleep(for: .milliseconds(250))
                proxy.scrollTo("brew:unchecked:\(last.id)", anchor: .bottom)
                try? await Task.sleep(for: .seconds(2))
                // Not guarded on cancellation: a highlight left on would never clear.
                withAnimation(.easeOut(duration: 0.6)) { highlightUnchecked = false }
            }
            // The popover's Homebrew and "Other tools" rows: that level's header
            // to the top of the list, at once — not after the unchecked reveal's
            // 150 ms wait, which in a freshly opened window showed the list's top
            // for ~100 ms before the jump (recorded at 60 fps, 2026-10-20) — and
            // once more a frame later, for a list laid out after the first. Marked
            // handled only by a task that was not cancelled, for the reason above.
            .task(id: cliRevealRequest) {
                guard cliRevealRequest != cliRevealHandled else { return }
                proxy.scrollTo(cliRevealTarget, anchor: cliRevealAnchor)
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                cliRevealHandled = cliRevealRequest
                proxy.scrollTo(cliRevealTarget, anchor: cliRevealAnchor)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for result: UpdateResult) -> some View {
        let hasBackup = model.backupVersion(result.id) != nil
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(result: result, model: model)
            if let sunset = ProductSunsetCatalog.sunset(forBundleID: result.app.bundleID) {
                ProductSunsetNotice(name: result.app.name, sunset: sunset)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            if let cask = model.brewCaskLifecycle(for: result) {
                BrewLifecycleNotice(name: cask.token, lifecycle: cask.lifecycle, isCask: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            if hasBackup {
                Picker(selection: $detailMode) {
                    Text("Release Notes").tag(DetailMode.releaseNotes)
                    Text("Bundle Diff").tag(DetailMode.bundleDiff)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            Divider()
            DetailLenses(result: result, model: model, lens: hasBackup ? detailMode : .releaseNotes)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// A view kept alive while another takes its place — a sidebar tab's list, a
    /// detail pane's lens — drawn, hit and read by VoiceOver only while shown.
    func keptLayer(isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            .zIndex(isShown ? 1 : 0)
    }
}

// MARK: - Sidebar lists

/// The Apps tab's list, its own view compared on what it shows.
///
/// As part of the window's body it was rebuilt on every pass of that body — a tab
/// switch, the detail pane's lens, a selection, a download tick — each one
/// diffing all 229 apps on the developer's Mac and placing the rows again, though
/// nothing in the list had changed. Equal now, the pass skips it. What a row reads
/// from the model it reads in its own body (`WorkbenchAppRow`), so a change there
/// still reaches the row without passing through here.
///
/// The selection is not compared: each row's `sidebarRow` reads the binding
/// itself, and a change to it updates those rows alone.
private struct WorkbenchAppsList: View, @MainActor Equatable {
    let apps: [UpdateResult]
    let searchText: String
    let isShown: Bool
    let model: AppListModel
    @Binding var selection: String?
    var focus: FocusState<WorkbenchWindowView.SidebarTab?>.Binding

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.apps == rhs.apps && lhs.searchText == rhs.searchText && lhs.isShown == rhs.isShown
            && lhs.model === rhs.model
    }

    var body: some View {
        SidebarList(selection: $selection, order: apps.map(\.id),
                    label: String(localized: "Apps"), focus: focus, focusValue: .apps,
                    isShown: isShown) {
            ForEach(apps) { result in
                WorkbenchAppRow(result: result, model: model)
                    .equatable()
                    .sidebarRow(result.id, selection: $selection)
            }
        }
        .overlay {
            if apps.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

/// An app's row in the Apps list or the CLI tab's Homebrew group: what
/// `WorkbenchSidebarRow` draws, read from the model here, in this row's own body,
/// so only the rows on screen read it and each re-reads only when what it read
/// changes.
private struct WorkbenchAppRow: View, @MainActor Equatable {
    let result: UpdateResult
    let model: AppListModel

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.result == rhs.result && lhs.model === rhs.model
    }

    var body: some View {
        WorkbenchSidebarRow(
            result: result,
            checkAgain: { Task { await model.retry(result) } },
            isChecking: model.installing[result.id] != nil,
            isRunning: model.isRunning(result),
            versionLineState: model.versionLineState(for: result),
            runningSide: model.restartFromSide(result.id),
            showsRuntime: model.prefs.showRuntimeTags,
            isIgnored: model.prefs.isIgnored(result.app),
            isVersionSkipped: model.prefs.isVersionSkipped(
                result.app, version: result.remote?.versionSide),
            toggleIgnore: { model.toggleIgnore(result) },
            skipVersion: { model.skipThisVersion(result) },
            clearSkip: { model.prefs.clearSkip(result.app) },
            fullDiskAccessNeeds: model.fullDiskAccessNeedsAffecting(result),
            grantFullDiskAccess: { model.presentFullDiskAccessPermissionFlow() },
            caskLifecycle: model.brewCaskLifecycle(for: result)?.lifecycle,
            sunsetPhase: ProductSunsetCatalog.sunset(forBundleID: result.app.bundleID)
                .map { ($0.endDate, $0.phase(today: ProductSunsetCatalog.today())) })
            .equatable()
    }
}

/// The Rollback tab's list, kept out of the window's body passes like
/// `WorkbenchAppsList`.
private struct WorkbenchRollbackList: View, @MainActor Equatable {
    let apps: [UpdateResult]
    let searchText: String
    let isShown: Bool
    let model: AppListModel
    @Binding var selection: String?
    var focus: FocusState<WorkbenchWindowView.SidebarTab?>.Binding
    @Environment(\.openWindow) private var openWindow

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.apps == rhs.apps && lhs.searchText == rhs.searchText && lhs.isShown == rhs.isShown
            && lhs.model === rhs.model
    }

    var body: some View {
        SidebarList(selection: $selection, order: apps.map(\.id),
                    label: String(localized: "Restore"), focus: focus, focusValue: .rollback,
                    isShown: isShown) {
            ForEach(apps) { result in
                WorkbenchRollbackRow(result: result, model: model)
                    .sidebarRow(result.id, selection: $selection)
            }
        }
        .overlay {
            if apps.isEmpty {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    emptyState
                }
            }
        }
    }

    /// Why the Rollback tab is empty, which is the question a reader has here: either
    /// backups are off, or no update has gone through DuoUpdater since they were
    /// turned on. An app that updates itself replaces its bundle without us, so it
    /// never gets a backup — said here because it is the case people will hit.
    @ViewBuilder
    private var emptyState: some View {
        if model.prefs.keepBackups {
            ContentUnavailableView {
                Label("Nothing to restore yet", systemImage: "arrow.uturn.backward")
            } description: {
                Text("A backup is kept each time DuoUpdater updates an app. Apps that update themselves are not backed up.")
            }
        } else {
            ContentUnavailableView {
                Label("Backups are off", systemImage: "arrow.uturn.backward")
            } description: {
                Text("Turn them on to restore the version from before an update and compare what it changed.")
            } actions: {
                Button("Open Settings") {
                    model.requestedSettingsAnchor = .backups
                    openWindow(id: SettingsView.windowID)
                    model.surfaceWindow(sceneID: SettingsView.windowID)
                }
            }
        }
    }
}

// MARK: - Sidebar row

private struct WorkbenchSidebarRow: View {
    let result: UpdateResult
    /// Re-check just this app, and whether it is busy already. Passed in as a
    /// closure and a flag rather than the model itself: this row is deliberately
    /// value-typed — every one of ~145 of them re-renders on any model change if
    /// it observes one — and these are the only two things the menu needs.
    let checkAgain: () -> Void
    let isChecking: Bool
    /// Whether the app currently has a running process — shows the green live dot.
    let isRunning: Bool
    /// The one version-line fact this row should explain, in the same priority
    /// order the popover reads (`AppListModel.versionLineState(for:)` /
    /// `RowVersionLine`): a staged self-update relaunch, a pending restart (either
    /// confirmed or still awaiting the batch's post-install sweep), a lagging-feed
    /// downgrade note, or the plain status line. Passed in rather than recomputed
    /// from `needsRestart`/`pendingBatchRestart` here so this row can't drift into
    /// its own ladder again (#289) — it stays exactly what the popover and the
    /// action button already agreed on.
    let versionLineState: RowVersionLineState
    /// The running version when an older process is still live behind the bundle
    /// on disk (`AppListModel.restartFromSide`), so the update subtitle names what
    /// is running rather than what has never run (`UpdateResult.runningUpdateLine`).
    let runningSide: UpdateResult.VersionSide?
    /// Whether to show the runtime chip (Electron / Tauri / native / …).
    let showsRuntime: Bool
    /// The user's two verdicts, and the ways back out of them. Passed in rather
    /// than read from a model for the same reason everything else here is: this row
    /// stays renderable without one.
    let isIgnored: Bool
    let isVersionSkipped: Bool
    let toggleIgnore: () -> Void
    let skipVersion: () -> Void
    let clearSkip: () -> Void
    /// The reads turned away for this app that could change its answer
    /// (`AppListModel.fullDiskAccessNeedsAffecting`), and the way to grant them.
    let fullDiskAccessNeeds: [FullDiskAccessNeed]
    let grantFullDiskAccess: () -> Void
    /// Set when the cask that installed this app is deprecated or disabled
    /// (`AppListModel.brewCaskLifecycle(for:)`); the detail pane says the rest.
    var caskLifecycle: BrewLifecycle? = nil
    /// Set when the developer has announced the app's end (`ProductSunset`): the
    /// end date and whether it has passed; the detail pane says the rest.
    var sunsetPhase: (endDate: String, phase: ProductSunset.Phase)? = nil

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
        let channel = ChannelTag.measuredWidth(for: result.effectiveReleaseChannel)
        if channel > 0 { used += channel + 6 }
        if !fullDiskAccessNeeds.isEmpty { used += FullDiskAccessMark.width() + 6 }
        if caskLifecycle != nil { used += BrewCaskLifecycleMark.width + 6 }
        if sunsetPhase != nil { used += ProductSunsetMark.width + 6 }
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
                    ChannelTag(channel: result.effectiveReleaseChannel)
                    FullDiskAccessMark(needs: fullDiskAccessNeeds, grant: grantFullDiskAccess)
                    if let sunsetPhase {
                        ProductSunsetMark(endDate: sunsetPhase.endDate, phase: sunsetPhase.phase)
                    }
                    if let caskLifecycle {
                        BrewCaskLifecycleMark(lifecycle: caskLifecycle)
                    }
                    if let runtimeTag {
                        RuntimeTag(runtime: runtimeTag, frameworks: result.app.linkedFrameworks,
                                   interactive: false)
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
            // Skip and Ignore are here because this window SAYS they are: a skipped
            // or ignored row draws "Skipped"/"Ignored" with the popover's own help
            // text, which tells the user to right-click to undo it. That menu did
            // not exist here, so the instruction was dead in all seven languages and
            // the only way out was to reopen the menu bar. Same actions, same
            // wording, same model calls as the popover's row menu.
            Divider()
            if result.hasUpdate {
                let offered = result.offeredDisplay ?? String(localized: "this version")
                if isVersionSkipped {
                    Button("Don’t skip \(offered)", action: clearSkip)
                } else {
                    Button("Skip \(offered)", action: skipVersion)
                }
            }
            Button(isIgnored
                   ? String(localized: "Stop ignoring \(result.app.name)")
                   : String(localized: "Ignore \(result.app.name)"),
                   action: toggleIgnore)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch versionLineState {
        case .interrupted(let oldVersion):
            // The version from before the cut-off update: the copy on disk may
            // be gone or broken, and Restore puts this one back.
            Text(interruptedVersionLine(oldVersion))
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .stagedRelaunch(let staged):
            // The app's own updater already has the latest downloaded; Relaunch
            // just swaps to it. `actionableStaged` (upstream of this state)
            // guarantees the staged build is current, so there's nothing newer to
            // note here — mirrors the popover's `stagedVersionLine`.
            let line = result.stagedRelaunchLine(staged)
            Text("\(line.from) → \(line.to)")
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .stagedRelaunchVersionUnknown:
            // Same fact as the popover's line: no readable target, so a "?". Hover
            // only here: a click on a sidebar row selects it, and the detail header
            // it opens carries the clickable `StagedVersionUnknownMark`.
            Text(verbatim: "\(result.installedDisplay ?? "?") → ?")
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .help(String(localized: "\(result.app.name) has already downloaded an update itself, but which version can't be read from here — usually because it installs with administrator rights. Relaunch to apply it."))
        case .restart(let from):
            // Self-updated on disk: show running version → the version on disk, so
            // "Relaunch" reads as a real change. Formatted as a pair by
            // `relaunchLine`, which keeps the build numbers only when the marketing
            // versions cannot tell the two apart — the same rule the update subtitle
            // below gets from `buildBump`. `from` covers both a confirmed restart
            // and a batch install still awaiting the post-install process sweep
            // (#289) — either way the Restart button below needs this line to
            // agree with it instead of falling back to a bare "v<version>".
            let line = UpdateResult.relaunchLine(from: from, to: result.relaunchTargetSide)
            Text("\(line.from) → \(line.to)")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .downgrade(let older):
            // Vendor's latest is *older* than what's installed — action-less, so
            // muted like the popover's `downgradeVersionLine`. No pending relaunch
            // outranks it here, or `versionLineState` would have returned one of
            // the cases above instead.
            let installed = result.app.shortVersion ?? "?"
            Text("\(installed) ↓ \(older)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .status:
            if case .updateAvailable(let latest) = result.status {
                // Same-marketing build bump (JetBrains EAP, Surge): show the builds so it
                // doesn't read as a no-op "2026.2 → 2026.2".
                // Names the running version when an older process is still live.
                let running = result.runningUpdateLine(latest: latest, running: runningSide)
                let bump = result.buildBump(latest: latest)
                let (installed, offered) = result.updateLineSides(latest: latest)
                let from = running?.from ?? bump.map { "\(installed) (\($0.installed))" } ?? installed
                let to = running?.to ?? bump.map { "\(offered) (\($0.remote))" } ?? offered
                Text("\(from) → \(to)")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    // Its `.stagedRelaunch` / `.restart` siblings scale; this one is
                    // the longest of the four (two versions, both possibly with a
                    // build in parentheses) and had only the line limit, so it
                    // truncated where they shrank.
                    .minimumScaleFactor(0.75)
            } else {
                Text("v\(result.installedDisplay ?? "?")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Compared on what it draws, leaving out the closures. A closure never compares
/// equal, so without this every visible row re-ran its body on each pass of the
/// window's — a tab switch, a download tick — whether or not anything in it had
/// changed. Leaving them out is sound because each one only calls the model, the
/// same one every pass, about `result`, which is compared.
extension WorkbenchSidebarRow: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.result == rhs.result && lhs.isChecking == rhs.isChecking && lhs.isRunning == rhs.isRunning
            && lhs.versionLineState == rhs.versionLineState && lhs.runningSide == rhs.runningSide
            && lhs.showsRuntime == rhs.showsRuntime
            && lhs.isIgnored == rhs.isIgnored && lhs.isVersionSkipped == rhs.isVersionSkipped
            && lhs.fullDiskAccessNeeds == rhs.fullDiskAccessNeeds && lhs.caskLifecycle == rhs.caskLifecycle
            && lhs.sunsetPhase?.endDate == rhs.sunsetPhase?.endDate && lhs.sunsetPhase?.phase == rhs.sunsetPhase?.phase
    }
}

// MARK: - Rollback row

/// One row in the Rollback section: an app with a restorable backup, plus an inline
/// "Roll back" action. Rollback reuses the install pipeline's per-row state, so the
/// in-flight spinner and inline error read off `installing`/`installErrors` exactly
/// like an install does (and the model's own guard stops a rollback from racing one).
private struct WorkbenchRollbackRow: View {
    let result: UpdateResult
    @Bindable var model: AppListModel

    /// The version the backup restores to; "previous" when its marketing version
    /// wasn't recorded. Read here rather than handed in: the list above is skipped
    /// while its rows are unchanged (`WorkbenchRollbackList`), and this row's own
    /// body is what hears a new backup.
    private var target: String { model.backupVersion(result.id) ?? "previous" }

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
                Button("Restore") { Task { await model.rollback(result) } }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    // `rollback` refuses while the row is busy (`canRollback`) —
                    // here, in practice, a Relaunch of this app (its backup copy,
                    // then the quit) — so don't offer it.
                    .disabled(!model.canRollback(result.id))
                    .help("Restore \(result.app.name) \(targetLabel) from the backup taken before its last update")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Brew formula row

/// A CLI-formula row under the Brew tree. Unlike a cask (which reuses
/// `WorkbenchSidebarRow` + the app install path), a formula isn't an app — no
/// bundle icon, channel, or changelog — so it gets this compact row with its own
/// inline `brew upgrade --formula <name>` action, and a `FormulaIcon`.
private struct BrewFormulaSidebarRow: View {
    let formula: BrewInstalledFormula
    @Bindable var model: AppListModel

    /// What the row draws (`BrewRowSnapshot.Formula.row`): its own
    /// formula's facts, so an idle row does not redraw with another's
    /// progress.
    private var row: BrewFormulaRow { model.brewFormulaRow(formula) }

    var body: some View {
        let row = row
        HStack(spacing: 8) {
            FormulaIcon(name: formula.name, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(formula.name).font(.body).lineLimit(1)
                    if formula.needsSudo { CLISudoBadge(help: CLIToolPresentation.brewSudoBadgeHelp) }
                }
                caption(row.caption)
            }
            Spacer()
            action(row.slot).swallowsClicksAfterSwap(of: row.slot.isRunning)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func caption(_ caption: BrewFormulaRow.Caption) -> some View {
        switch caption {
        case .error(let error):
            Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
        case .progress(let progress):
            // Live brew output ("Downloading…", "Pouring…") so the upgrade
            // visibly progresses instead of sitting on a bare spinner.
            Text(progress.text)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        case .status:
            HStack(spacing: 4) {
                statusCaption
                // A homebrew/core node or php with notices: the mark the CLI
                // rows give breaking changes, after the version. The detail
                // pane says it in words.
                if formula.kind == .formula, let help = CLIToolPresentation.securityMarkHelp(
                    model.runtimeSecurity.notices(forFormula: formula.name)) {
                    RuntimeSecurityMark(help: help).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        if let available = formula.availableVersion {
            Text("\(formula.installedVersion) → \(available)")
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
        } else if let head = formula.head {
            // Up to date by brew's measure, which doesn't look upstream:
            // say what is known about upstream instead.
            let status = model.headStatus(for: head)
            Text("\(formula.installedVersion) · \(status.text)")
                .font(.caption)
                .foregroundStyle(status.isBehind ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        } else if let lifecycle = formula.lifecycle {
            // Up to date, but Homebrew is phasing it out: say so in the one
            // line the row has. An update line above outranks it.
            Text("\(formula.installedVersion) · \(lifecycle.statusText)")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            // Up-to-date leaf: just its version, like an up-to-date app row.
            Text(formula.installedVersion)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Update and its Cancel take turns here: the rest of a double-click that
    /// swapped them is not a click on the other.
    @ViewBuilder
    private func action(_ slot: CLIRowState<String>) -> some View {
        switch slot {
        case .cancel, .spinnerOnly:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                BrewUpgradeCancelButton(slot: slot, jobID: AppListModel.formulaJobID(formula.key), model: model)
            }
        case .update:
            Button("Update") { Task { await model.upgradeBrewFormula(named: formula.key) } }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        case .none, .copy:
            EmptyView()
        }
    }
}

/// A brew run's Cancel beside its progress (`InstallCancelButton`): a
/// formula row's own upgrade (`AppListModel.formulaJobID`), Upgrade All
/// (`upgradeAllJobID`), or `brew update` while it waits its turn
/// (`homebrewUpdateJobID`), as `BrewRowSnapshot` decides it — a row that only
/// spins because Upgrade All covers it has none (`.spinnerOnly`). A row's is
/// gone once the cancel was accepted, its progress saying "Cancelling…" until
/// the run ends (`AppListModel.cancelBrewUpgrade`); Upgrade All's stays,
/// greyed, as the tool groups' Update All's does.
struct BrewUpgradeCancelButton: View {
    let slot: CLIRowState<String>
    let jobID: String
    let model: AppListModel

    init(slot: CLIRowState<String>, jobID: String, model: AppListModel) {
        self.slot = slot
        self.jobID = jobID
        self.model = model
    }

    init(cancel: BrewRowSnapshot.GroupCancel?, jobID: String, model: AppListModel) {
        self.init(slot: cancel.map(CLIRowState.cancel) ?? .spinnerOnly, jobID: jobID, model: model)
    }

    var body: some View {
        if case .cancel(let group) = slot {
            InstallCancelButton(state: group.state, pending: group.pending) {
                model.cancelBrewUpgrade(jobID)
            }
        }
    }
}

// MARK: - Homebrew self-update row

/// "Homebrew X is available" at the top of the Brew tree, with a one-click
/// `brew update`. Only exists when `AppListModel.homebrewSelfUpdate` is non-nil,
/// which already accounts for the user having turned auto-update off.
private struct HomebrewSelfUpdateSidebarRow: View {
    let update: HomebrewSelfUpdate
    @Bindable var model: AppListModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mug")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Homebrew \(update.latest) is available").font(.body).lineLimit(1)
                if let error = model.homebrewUpdateError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if model.homebrewUpdating, let note = model.homebrewUpdateNote {
                    Text(note)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text("You have \(update.installed)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            // Update and its Cancel take turns here: the rest of a double-click
            // that swapped them is not a click on the other.
            ZStack {
                if model.homebrewUpdating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        // Only while it waits its turn: `brew update` itself has none.
                        BrewUpgradeCancelButton(cancel: model.homebrewUpdateCancel,
                                                jobID: AppListModel.homebrewUpdateJobID, model: model)
                    }
                } else {
                    Button("Update") { Task { await model.updateHomebrew() } }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .help(String(localized: "Runs `brew update`, which updates Homebrew and refreshes its package lists using your own Homebrew settings."))
                }
            }
            .swallowsClicksAfterSwap(of: model.homebrewUpdating)
        }
        .padding(.vertical, 2)
    }
}

/// The self-update row's detail: Homebrew's release notes for the versions the
/// offered `brew update` brings (`HomebrewReleaseNotes`), drawn by the view every
/// other changelog uses. Loaded as `CLIToolReleaseNotesView` loads a tool's.
private struct HomebrewSelfUpdateDetailPane: View {
    let update: HomebrewSelfUpdate
    @Bindable var model: AppListModel

    private enum LoadState {
        case loading
        case loaded(Changelog?)
        case failed(String)
    }
    @State private var state: LoadState = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            notes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keyed on both versions: a check that finds a newer Homebrew, or an
        // update that moves the installed one, re-cuts the notes.
        .task(id: "\(update.installed)|\(update.latest)") { await load(force: false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "mug")
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Homebrew").font(.title2).fontWeight(.semibold)
                Text("\(update.installed) → \(update.latest)")
                    .font(.callout).foregroundStyle(.tint)
            }
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var notes: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded(let changelog?):
            ChangelogEntriesView(changelog: changelog)
        case .loaded(nil):
            ContentUnavailableView {
                Label("No release notes", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("\("Homebrew")’s release notes have no section for these versions yet.")
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Couldn't load the release notes")
                    .font(.callout)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("Try Again") { Task { await load(force: true) } }
                    .font(.callout)
            }
        }
    }

    private func load(force: Bool) async {
        if force { state = .loading }
        do {
            state = .loaded(try await model.homebrewReleaseNotes(for: update, force: force))
        } catch CLIToolReleaseNotesError.http(let status) {
            state = .failed(String(localized: "The server answered HTTP \(status)."))
        } catch CLIToolReleaseNotesError.rateLimited {
            state = .failed(String(localized: "Hitting GitHub’s rate limit"))
        } catch is GitHubRateLimitGate.Refused {
            state = .failed(String(localized: "Hitting GitHub’s rate limit"))
        } catch CLIToolReleaseNotesError.noSections {
            state = .failed(String(localized: "The file loaded but carried no release sections."))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// A Brew-tree row for an installed package brew wouldn't read from its tap
/// (`BrewUncheckedPackage`). Without it the package is simply missing from the
/// tree — brew's own listings drop it — which reads as "nothing to update". No
/// update action: we don't know the version, and trusting the tap is the user's
/// call, so the row offers the `brew trust` command to copy instead of running it
/// (for a formula moved to a cask, the commands that swap it — `fixCommand`).
private struct BrewUncheckedSidebarRow: View {
    let package: BrewUncheckedPackage
    /// Set briefly when the popover's tip sends the user here.
    var highlighted = false

    @State private var copied = false

    private var status: String { package.uncheckedStatus }
    private var explanation: String { package.uncheckedExplanation }

    var body: some View {
        HStack(spacing: 8) {
            FormulaIcon(name: package.name, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(package.name).font(.body).lineLimit(1)
                Text(status)
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            if let command = package.fixCommand {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Copy “\(command)”"))
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(highlighted ? 0.25 : 0))
                .padding(.horizontal, -6))
        .help(explanation)
    }
}

/// The copy the unchecked row and its detail pane share.
private extension BrewUncheckedPackage {
    var uncheckedStatus: String {
        switch reason {
        case .tapNotTrusted: String(localized: "Not checked · tap not trusted")
        case .unreadable: String(localized: "Not checked · Homebrew can’t read it")
        case .movedToCask: String(localized: "Not checked · moved to a cask")
        case .renamed(let newName): String(localized: "Not checked · renamed to \(newName)")
        case .removed: String(localized: "Not checked · removed from Homebrew")
        }
    }

    var uncheckedExplanation: String {
        switch reason {
        case .tapNotTrusted:
            String(localized: "Homebrew won’t read \(fullName) from its tap until you trust it, so updates can’t be checked. To trust it, run: \(trustCommand)")
        case .unreadable:
            String(localized: "Homebrew didn’t read \(fullName) from its tap, so updates can’t be checked.")
        case .movedToCask:
            String(localized: "Homebrew replaced the \(name) formula with a cask of the same name, so the installed formula gets no more updates. To switch to the cask, run: \(migrateCommand)")
        case .renamed(let newName):
            String(localized: "Homebrew renamed \(name) to \(newName), and the installed copy hasn’t been migrated. Until it is, Homebrew can’t check any formula for updates. To migrate it, run: \(fixCommand ?? "")")
        case .removed:
            String(localized: "Homebrew no longer has a \(name) formula, and no cask of that name replaces it, so the installed copy gets no more updates.")
        }
    }
}

// MARK: - Unchecked package detail pane

/// The detail pane for a selected unchecked Brew package. No release notes: brew
/// refuses to load the definition, so there is no version or homepage to fetch
/// them from. What it can say is why, and what to run.
private struct BrewUncheckedDetailPane: View {
    let package: BrewUncheckedPackage

    /// The narrowest a detail-pane block of wrapped, `fixedSize` text is laid out
    /// at — see the frame at the end of `body`.
    static let minTextWidth: CGFloat = 280

    private static let tapTrustDocs = URL(string: "https://docs.brew.sh/Tap-Trust")!

    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FormulaIcon(name: package.name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name).font(.title2).fontWeight(.semibold)
                    // The version is brew's install record, the only one it gives
                    // for a package it won't load.
                    Text("\(package.fullName) · \(package.installedVersion)")
                        .font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(package.uncheckedStatus)
                        .font(.callout).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(package.uncheckedExplanation)
                if let command = package.fixCommand {
                    HStack(spacing: 8) {
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            // Wraps rather than truncating: the cask migration is two
                            // commands, wider than the pane (`brew trust …` fit).
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            copied = true
                            copiedResetTask?.cancel()
                            // Back to the copy glyph, so a second copy confirms again.
                            copiedResetTask = Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                guard !Task.isCancelled else { return }
                                copied = false
                            }
                        } label: {
                            // One frame for both glyphs: the checkmark is shorter than
                            // doc.on.doc, and the box resized when they swapped.
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Copy “\(command)”"))
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                if package.reason == .tapNotTrusted {
                    // NSWorkspace rather than SwiftUI `openURL`, which errors -50 in
                    // this app's windows (see `AlcoveSettingsPage`).
                    Button {
                        NSWorkspace.shared.open(Self.tapTrustDocs)
                    } label: {
                        Text(String(localized: "Homebrew docs: Tap Trust")).underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(Self.tapTrustDocs.absoluteString)
                }
            }
            .padding(16)
            // Top, not `.leading` (vertically centered): this block can measure
            // taller than it draws, and centered it sat 7pt lower for
            // claude-code-notification than for musl-cross (measured in an
            // NSHostingView copy of this pane), so switching rows jumped.
            //
            // A floor under the width, for the command's `fixedSize`: measuring
            // the window's minimum size (`.contentMinSize`) proposes this column a
            // sliver of width, and a fixed-height wrapped command one character
            // wide pushed the window's minimum height to 1185pt — past the screen
            // (measured on the installed app, 2026-10-08). Same trap as the
            // offline-backup notice (2026-09-24).
            .frame(minWidth: Self.minTextWidth, maxWidth: 560, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let lifecycle = formula.lifecycle {
                BrewLifecycleNotice(name: formula.name, lifecycle: lifecycle, isCask: formula.kind == .cask)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            // Why an update it shows has no Update (`manualInstaller`).
            if formula.manualInstaller, formula.hasUpdate {
                BrewLifecycleNotice(text: AttributedString(String(localized: "Homebrew can’t upgrade \(formula.name) itself: its installer has to be run by hand.")))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            // A homebrew/core node or php's notices (`RuntimeSecurityReport`),
            // in the deprecation notice's place and look.
            let security = formula.kind == .formula ? model.runtimeSecurity.notices(forFormula: formula.name) : []
            if !security.isEmpty {
                BrewLifecycleNotice(text: CLIToolPresentation.securityNotice(security))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            if let head = formula.head {
                BrewHeadNotice(head: head, model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
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
            // A cask's notes aren't a formula's: none are looked up by its name.
            guard formula.kind == .formula else { return }
            model.ensureFormulaReleaseLoading(name: formula.name, version: notesVersion)
        }
    }

    /// The version whose notes the pane shows: the upgrade target when there is one,
    /// else what's installed.
    private var notesVersion: String {
        formula.availableVersion ?? formula.installedVersion
    }

    private var header: some View {
        HStack(spacing: 8) {
            FormulaIcon(name: formula.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formula.name).font(.title2).fontWeight(.semibold)
                    if formula.needsSudo { CLISudoBadge(help: CLIToolPresentation.brewSudoBadgeHelp) }
                }
                if let available = formula.availableVersion {
                    Text("\(formula.installedVersion) → \(available)")
                        .font(.callout).foregroundStyle(.tint)
                } else {
                    Text(formula.installedVersion)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // What it draws: `BrewRowSnapshot.Formula.row`, as its sidebar row.
            let row = model.brewFormulaRow(formula)
            headerAction(row).swallowsClicksAfterSwap(of: row.slot.isRunning)
        }
        .padding(16)
    }

    /// Update and its Cancel take turns here: the rest of a double-click that
    /// swapped them is not a click on the other.
    @ViewBuilder
    private func headerAction(_ row: BrewFormulaRow) -> some View {
        switch row.slot {
        case .cancel, .spinnerOnly:
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text((row.progress ?? .updating).text)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                BrewUpgradeCancelButton(slot: row.slot, jobID: AppListModel.formulaJobID(formula.key), model: model)
            }
        case .update:
            Button("Update") { Task { await model.upgradeBrewFormula(named: formula.key) } }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        case .none, .copy:
            EmptyView()
        }
    }

    @ViewBuilder
    private var notes: some View {
        if formula.kind == .cask {
            noNotes
        } else {
            formulaNotes
        }
    }

    @ViewBuilder
    private var formulaNotes: some View {
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

// MARK: - HEAD install notice

/// What can be said about a formula installed from HEAD (`BrewHeadInstall`):
/// that brew doesn't compare it with upstream, a way to ask upstream once, and
/// the command that rebuilds it.
private struct BrewHeadNotice: View {
    let head: BrewHeadInstall
    @Bindable var model: AppListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(head.commit.map { String(localized: "Installed from HEAD, built from commit \($0). Homebrew doesn’t compare it with upstream, so it reads as up to date until the formula’s next release.") }
                     ?? String(localized: "Installed from HEAD. Homebrew doesn’t compare it with upstream, so it reads as up to date until the formula’s next release."))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
            }
            if model.canCheckHeadUpstream(head) {
                HStack(spacing: 8) {
                    Button(String(localized: "Check Upstream")) {
                        Task { await model.checkHeadUpstream(head) }
                    }
                    .disabled(model.headCheck(for: head) == .checking)
                    if model.headCheck(for: head) == .checking {
                        ProgressView().controlSize(.small)
                    } else if let line = model.headStatus(for: head).answerLine {
                        Text(line)
                            .foregroundStyle(model.headStatus(for: head).isBehind ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if case .github = head.upstream, head.commit != nil {
                // The one case a setting changes: anonymous GitHub requests share
                // 60 an hour with every other check, so this waits for a token.
                Text(String(localized: "Add a GitHub token in Settings to check its upstream here."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(String(localized: "To rebuild it from upstream’s latest commit, run:"))
            CopyableCommandBox(command: head.upgradeCommand)
        }
        // See `BrewUncheckedDetailPane.minTextWidth`: its `fixedSize` texts
        // need a width floor when the window measures its minimum size.
        .frame(minWidth: BrewUncheckedDetailPane.minTextWidth, maxWidth: 560, alignment: .topLeading)
    }
}

/// A command shown for the user to run, with a copy button that confirms.
private struct CopyableCommandBox: View {
    let command: String
    /// False never breaks the command at its spaces, which reads as several
    /// commands: each `&&` step gets a line of its own, shrunk to fit rather
    /// than cut off. (A sideways scroll hid the end — "fnm default 24.22." on
    /// the real Mac — with nothing to say there was more.)
    var wraps = true

    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            if wraps {
                commandText.fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Self.steps(command).enumerated()), id: \.offset) { _, step in
                        Text(step)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .textSelection(.enabled)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                copiedResetTask?.cancel()
                copiedResetTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Copy “\(command)”"))
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var commandText: some View {
        Text(command)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }

    /// `a && b` as `a` and `&& b`, for display only; the copy is the command.
    static func steps(_ command: String) -> [String] {
        let parts = command.components(separatedBy: " && ")
        return [parts[0]] + parts.dropFirst().map { "&& " + $0 }
    }
}

extension AppListModel {
    /// A HEAD install's upstream state, in the words the row and the notice use.
    struct HeadStatus {
        let text: String
        let answerLine: String?
        let isBehind: Bool
    }

    func headStatus(for head: BrewHeadInstall) -> HeadStatus {
        switch headCheck(for: head) {
        case nil:
            return HeadStatus(text: String(localized: "not compared with upstream"), answerLine: nil, isBehind: false)
        case .checking:
            return HeadStatus(text: String(localized: "checking upstream…"), answerLine: nil, isBehind: false)
        case .answered(.upToDate, _, _):
            return HeadStatus(text: String(localized: "same as upstream"),
                              answerLine: String(localized: "Upstream is still at this commit."), isBehind: false)
        case .answered(.behind(let latest), _, _):
            return HeadStatus(text: String(localized: "upstream has newer commits"),
                              answerLine: String(localized: "Upstream has moved on to \(latest)."), isBehind: true)
        case .answered(.failed(let message), _, _):
            return HeadStatus(text: String(localized: "upstream check failed"), answerLine: message, isBehind: false)
        }
    }
}

// MARK: - Deprecation notice

/// What Homebrew says about a formula it has deprecated or disabled
/// (`BrewLifecycle`), above its release notes: what that means for updates, why,
/// when, and the replacement brew suggests, to copy — like `brew trust`, shown for
/// the user to run, never run here.
///
/// Also a node or php formula's security notices (`RuntimeSecurityNotice`), in
/// the same place and look: `init(text:)`, whose links open in the browser.
private struct BrewLifecycleNotice: View {
    let text: AttributedString
    let replacementCommand: String?
    let replacementName: String?

    /// A cask's notice speaks of the cask, not of the app's updates, which may
    /// come from another source (see `BrewCaskLifecycle`).
    init(name: String, lifecycle: BrewLifecycle, isCask: Bool = false) {
        text = AttributedString(lifecycle.sentences(for: name, isCask: isCask).joined(separator: " "))
        replacementCommand = lifecycle.replacementCommand
        replacementName = lifecycle.replacementName
    }

    init(text: AttributedString) {
        self.text = underliningLinks(text)
        replacementCommand = nil
        replacementName = nil
    }

    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                    // NSWorkspace rather than SwiftUI's own `openURL`, which
                    // errors -50 in this app's windows (see `AlcoveSettingsPage`).
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let command = replacementCommand, let replacement = replacementName {
                Text(String(localized: "Homebrew suggests \(replacement) instead:"))
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                        copiedResetTask?.cancel()
                        // Back to the copy glyph, so a second copy confirms again.
                        copiedResetTask = Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            guard !Task.isCancelled else { return }
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Copy “\(command)”"))
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        // See `BrewUncheckedDetailPane.minTextWidth`: its `fixedSize` texts
        // need a width floor when the window measures its minimum size.
        .frame(minWidth: BrewUncheckedDetailPane.minTextWidth, maxWidth: 560, alignment: .topLeading)
    }
}

extension BrewLifecycle {
    /// The row's one-word state.
    var statusText: String {
        switch stage {
        case .deprecated: String(localized: "Deprecated")
        case .disabled: String(localized: "Disabled")
        }
    }

    /// The notice's prose: what the stage means, why, and when — each its own
    /// sentence, so a translation never has to splice brew's reason into another.
    func sentences(for name: String, isCask: Bool = false, today: String = Self.today()) -> [String] {
        var out: [String] = []
        switch (stage, isCask) {
        case (.deprecated, false):
            out.append(String(localized: "Homebrew has deprecated \(name). It still installs and upgrades, with a warning."))
        case (.disabled, false):
            out.append(String(localized: "Homebrew has disabled \(name): it can no longer be installed or upgraded, so it gets no more updates."))
        case (.deprecated, true):
            out.append(String(localized: "Homebrew has deprecated the \(name) cask. It still installs and upgrades, with a warning."))
        case (.disabled, true):
            // Not "no more updates": the app may update itself, or be checked by
            // another source — only Homebrew's part has stopped.
            out.append(String(localized: "Homebrew has disabled the \(name) cask: Homebrew can no longer install or upgrade it."))
        }
        if let reason { out.append(Self.reasonSentence(reason)) }
        if let disableDate {
            // ISO dates compare as strings.
            out.append(disableDate < today
                ? String(localized: "It was disabled on \(disableDate).")
                : String(localized: "It will be disabled on \(disableDate)."))
        }
        return out
    }

    /// brew's reason symbols (`DeprecateDisable::FORMULA_DEPRECATE_DISABLE_REASONS`
    /// and `CASK_DEPRECATE_DISABLE_REASONS`; the two that both lists have,
    /// `unmaintained` and `unreachable`, read the same in each), translated; any
    /// other reason is the package's own English text, quoted.
    static func reasonSentence(_ reason: String) -> String {
        switch reason {
        case "does_not_build": String(localized: "It doesn’t build.")
        case "no_license": String(localized: "It has no license.")
        case "repo_archived": String(localized: "Its upstream repository is archived.")
        case "repo_removed": String(localized: "Its upstream repository was removed.")
        case "unmaintained": String(localized: "It isn’t maintained upstream.")
        case "unreachable": String(localized: "It’s no longer reliably reachable upstream.")
        case "unsupported": String(localized: "It isn’t supported upstream.")
        case "deprecated_upstream": String(localized: "It’s deprecated upstream.")
        case "versioned_formula": String(localized: "It’s a versioned formula.")
        case "checksum_mismatch": String(localized: "Its source file’s checksum changed after release, so its upstream repository may have been compromised.")
        case "discontinued": String(localized: "It’s discontinued upstream.")
        case "moved_to_mas": String(localized: "It’s now distributed only on the Mac App Store.")
        case "no_longer_available": String(localized: "It’s no longer available upstream.")
        case "no_longer_meets_criteria": String(localized: "It no longer meets Homebrew’s criteria for casks.")
        case "fails_gatekeeper_check": String(localized: "It doesn’t pass the macOS Gatekeeper check.")
        default: String(localized: "Homebrew’s reason: “\(reason)”.")
        }
    }

    /// Today as `yyyy-MM-dd` in the user's calendar day.
    static func today() -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// The ⚠ a sidebar row or npm group header carries when a node or php it stands
/// for has notices (`RuntimeSecurityNotice`): the CLI rows' breaking-changes
/// mark, its sentences on hover (`CLIToolPresentation.securityMarkHelp`).
private struct RuntimeSecurityMark: View {
    let help: String

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help(help)
            .accessibilityLabel(help)
    }
}

/// `text` with its links underlined as well as tinted, like the app's other
/// inline links: a version alone in the accent colour reads as emphasis.
private func underliningLinks(_ text: AttributedString) -> AttributedString {
    var underlined = text
    for run in underlined.runs where run.link != nil {
        underlined[run.range].underlineStyle = .single
    }
    return underlined
}

/// `RuntimeSecurityMark` as a button, for an npm prefix group's header: a
/// click opens the node's notices in a popover — `RuntimeTag`'s click-through,
/// in its layout and its way — with the release links, which open in the
/// browser. Its own Button, so the popover anchors to the mark, not to the
/// header row.
private struct RuntimeSecurityMarkButton: View {
    let help: String
    /// Which node: the header's "nvm · node 24.13.0".
    let title: String
    let notices: [RuntimeSecurityNotice]
    /// The command to copy for an nvm or fnm node (`NodeUpgradeCommand`). Asked
    /// only when the popover opens: it reads the manager's default alias.
    let upgrade: () -> NodeUpgradeCommand?

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            RuntimeSecurityMark(help: help)
                // A caption-sized glyph is a small target; padded like
                // `RuntimeTag`'s mark without moving the drawing.
                .padding(3)
                .contentShape(Rectangle())
                .padding(-3)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .popover(isPresented: $showing, arrowEdge: .bottom) { detail }
        // `RuntimeTag`'s reason: a popover hangs where it opened once the list
        // scrolls, so it closes when the mark moves.
        .background(
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global).minY) {
                    showing = false
                }
            }
        )
    }

    private var detail: some View {
        detail(upgrade: upgrade())
    }

    private func detail(upgrade: NodeUpgradeCommand?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).font(.headline)
                    Text(underliningLinks(CLIToolPresentation.securityNotice(notices)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // NSWorkspace rather than SwiftUI's own `openURL`, which
                        // errors -50 in this app's windows (see `AlcoveSettingsPage`).
                        .environment(\.openURL, OpenURLAction { url in
                            NSWorkspace.shared.open(url)
                            return .handled
                        })
                }
            }
            // Handed out, never run: installing beside the old version and
            // moving packages is the user's to decide. The whole popover's
            // width, not the text column's, and never broken mid-step: fnm's
            // `install … && fnm default …` broke into three at 300 pt.
            if let upgrade {
                Text("To update it yourself, run:")
                    .font(.callout)
                    .padding(.top, 4)
                CopyableCommandBox(command: upgrade.command, wraps: false)
                ForEach([CLIToolPresentation.packagesLeftBehind(upgrade),
                         CLIToolPresentation.replacedDefault(upgrade)].compactMap { $0 }, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: upgrade == nil ? 300 : 420, alignment: .leading)
    }
}

/// The mark an app row carries when the cask that installed it is deprecated or
/// disabled. Orange like the formula rows' status; the detail pane explains.
private struct BrewCaskLifecycleMark: View {
    let lifecycle: BrewLifecycle

    static let width: CGFloat = 13

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .frame(width: Self.width)
            .help(lifecycle.caskHelp)
            .accessibilityLabel(lifecycle.caskHelp)
    }
}

/// A Brew-tree row for a cask that installs no app (a CLI, a font) and that
/// Homebrew deprecated or disabled: without it nothing would say so, since such a
/// cask has a row only while it's outdated.
private struct BrewLifecycleCaskSidebarRow: View {
    let cask: BrewCaskLifecycle

    var body: some View {
        HStack(spacing: 8) {
            FormulaIcon(name: cask.token, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(cask.token).font(.body).lineLimit(1)
                Text("\(cask.installedVersion) · \(cask.lifecycle.statusText)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// The detail pane for an app-less deprecated cask: what Homebrew says about it.
private struct BrewLifecycleCaskDetailPane: View {
    let cask: BrewCaskLifecycle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FormulaIcon(name: cask.token, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cask.token).font(.title2).fontWeight(.semibold)
                    Text(cask.installedVersion)
                        .font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(16)
            BrewLifecycleNotice(name: cask.token, lifecycle: cask.lifecycle, isCask: true)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension BrewLifecycle {
    /// The app row mark's tooltip.
    var caskHelp: String {
        switch stage {
        case .deprecated: String(localized: "Homebrew has deprecated the cask this app was installed with")
        case .disabled: String(localized: "Homebrew has disabled the cask this app was installed with")
        }
    }
}

// MARK: - Product sunset

/// The mark an app row carries when its developer has announced the app's end
/// (`ProductSunset`): orange before the date, red from it on. A calendar, not
/// Homebrew's triangle: this is the app itself stopping, not a package manager.
private struct ProductSunsetMark: View {
    let endDate: String
    let phase: ProductSunset.Phase

    static let width: CGFloat = 13

    private var help: String {
        switch phase {
        case .upcoming: String(localized: "The developer has announced this app stops working on \(endDate)")
        case .ended: String(localized: "The developer has announced this app stopped working on \(endDate)")
        }
    }

    var body: some View {
        Image(systemName: "calendar.badge.exclamationmark")
            .font(.system(size: 10))
            .foregroundStyle(phase == .upcoming ? .orange : .red)
            .frame(width: Self.width)
            .help(help)
            .accessibilityLabel(help)
    }
}

/// What the developer announced about the app's end, above its release notes:
/// the date, worded by whether it has passed, and a link to the announcement.
private struct ProductSunsetNotice: View {
    let name: String
    let sunset: ProductSunset

    var body: some View {
        let phase = sunset.phase(today: ProductSunsetCatalog.today())
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(phase == .upcoming
                     ? String(localized: "The developer has announced that \(name) will stop working on \(sunset.endDate).")
                     : String(localized: "The developer has announced that \(name) stopped working on \(sunset.endDate)."))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(phase == .upcoming ? .orange : .red)
            }
            // NSWorkspace rather than SwiftUI's `Link`/`openURL`, which errors -50
            // in this app's windows (see `BrewLifecycleNotice`).
            // Looks like the header's "Open page" link.
            Button {
                NSWorkspace.shared.open(sunset.announcement)
            } label: {
                Label("Read the announcement", systemImage: "safari")
            }
            .buttonStyle(.link)
            .font(.callout)
            .help(sunset.announcement.absoluteString)
        }
        // See `BrewUncheckedDetailPane.minTextWidth`: its `fixedSize` texts
        // need a width floor when the window measures its minimum size.
        .frame(minWidth: BrewUncheckedDetailPane.minTextWidth, maxWidth: 560, alignment: .topLeading)
    }
}

// MARK: - Detail header

private struct DetailHeader: View {
    let result: UpdateResult
    @Bindable var model: AppListModel
    /// For the TestFlight tip's deep link into Settings — the same three lines the
    /// window's own gear button and the popover's rate-limit banner use.
    @Environment(\.openWindow) private var openWindow

    /// The vendor page to link out to.
    private var changelogURL: URL? {
        ChangelogURLPolicy.displayable(ChangelogRecipeSelection.fallbackPage(for: result).url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(result.app.name).font(.title2).bold()
                        if model.isRunning(result) { RunningIndicator(size: 7) }
                        ChannelTag(channel: result.effectiveReleaseChannel)
                        FullDiskAccessMark(
                            needs: model.fullDiskAccessNeedsAffecting(result),
                            grant: { model.presentFullDiskAccessPermissionFlow() },
                            size: 15)
                        // Sized up to sit beside a `.title2` name rather than a
                        // list row's body text — the marks are drawn in a unit box,
                        // so they scale without losing their stroke ratio.
                        if model.prefs.showRuntimeTags, let runtime = result.app.runtime {
                            RuntimeTag(runtime: runtime, bundle: result.app.path,
                                       frameworks: result.app.linkedFrameworks,
                                       buildSDK: result.app.buildSDK, size: 18)
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
                    actions: RowActions.live(
                        install: { Task { await model.install(result) } },
                        installBackingUpOnce: { Task { await model.install(result, backUpOnce: true) } },
                        openStagedPackage: { Task { await model.openStagedPackage(result) } },
                        retry: { Task { await model.retry(result) } },
                        restart: { Task { await model.restart(result) } },
                        relaunchStaged: { Task { await model.relaunchStagedUpdate(result) } },
                        confirmQuit: { model.confirmQuit(result.id, proceed: true) },
                        openSelfUpdater: { model.openSelfUpdater(result) },
                        openToolbox: { model.openToolbox() },
                        openTestFlight: { model.openTestFlight(for: result) },
                        grantFullDiskAccess: { model.presentFullDiskAccessPermissionFlow() },
                        openTestFlightSetting: {
                            model.requestedSettingsSection = .general
                            model.requestedSettingsAnchor = .testFlightDetection
                            openWindow(id: SettingsView.windowID)
                            model.surfaceWindow(sceneID: SettingsView.windowID)
                        },
                        openBackupSetting: {
                            model.requestedSettingsAnchor = .keepBackups
                            openWindow(id: SettingsView.windowID)
                            model.surfaceWindow(sceneID: SettingsView.windowID)
                        },
                        signInToAppleDeveloper: { model.signInToAppleDeveloper() },
                        cancelInstall: { model.cancelInstall(result) },
                        restoreInterrupted: { Task { await model.restoreInterrupted(result) } },
                        retryPausedUntil: model.gitHubPausedUntil),
                    helperEnabled: model.helperEnabled,
                    testFlightUnboundedReason: model.testFlightUnboundedReason,
                    installCancel: model.installRows.cancels[result.id],
                    installCancelPending: model.installRows.cancelPending.contains(result.id))
                if let url = changelogURL {
                    Link(destination: url) {
                        Label("Open page", systemImage: "safari")
                    }
                    .font(.callout)
                }
            }
            // Surface an install error inline, same as the popover row does.
            if let error = model.installErrorText(for: result) {
                // Kept wrapping rather than clamped like the popover's copy of this
                // note: this window is resizable and much wider than 370pt, so the
                // reason fits without costing a row its height. The tooltip is here
                // anyway so both windows answer a hover the same way.
                // The width floor is `BrewUncheckedDetailPane.minTextWidth`'s:
                // without it the window's minimum-size pass lays this out a few
                // points wide, and a failed restore's line held the Workbench at
                // 1,486 pt on a 1,083 pt screen (measured 2026-10-25).
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: BrewUncheckedDetailPane.minTextWidth, alignment: .leading)
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
                if let failure = model.reportableFailure(for: result) {
                    Button("Report this problem…") {
                        model.openFailureReport(failure)
                        openWindow(id: FailureReportView.windowID)
                        model.surfaceWindow(sceneID: FailureReportView.windowID)
                    }
                    .font(.caption)
                    .buttonStyle(.link)
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
            // An app with no developer signature: what its one-click rests on, or
            // why there is none — said beside the button rather than after a click.
            // No `fixedSize(vertical:)`, as in `offlineBackupNotice`: with it,
            // selecting Alacritty held the Workbench at 1,870 pt on a 1,083 pt
            // screen (measured 2026-10-02).
            if let note = model.digestOnlyNote(for: result) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.digestOnlyIsTurnedOff(for: result) {
                    Button("Open Settings") {
                        model.requestedSettingsSection = .general
                        openWindow(id: SettingsView.windowID)
                        model.surfaceWindow(sceneID: SettingsView.windowID)
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var versionLine: some View {
        // Same fact, same priority order as the popover and the sidebar row
        // (`AppListModel.versionLineState(for:)` / `RowVersionLine`) — this pane
        // used to run its own two-branch ladder with no downgrade note and no
        // pending-batch-restart branch, so it could show "up to date" on a row the
        // action button beside it already offered Restart for (#289).
        switch model.versionLineState(for: result) {
        case .interrupted(let oldVersion):
            Text(interruptedVersionLine(oldVersion))
                .font(.callout).foregroundStyle(.orange)
                .lineLimit(1).minimumScaleFactor(0.75)
        case .stagedRelaunch(let staged):
            let line = result.stagedRelaunchLine(staged)
            Text("\(line.from)  →  \(line.to)")
                .font(.callout).foregroundStyle(.tint)
                .lineLimit(1).minimumScaleFactor(0.75)
        case .stagedRelaunchVersionUnknown:
            HStack(spacing: 0) {
                Text(verbatim: "\(result.installedDisplay ?? "?")  →  ")
                StagedVersionUnknownMark(
                    appName: result.app.name, helperOff: !model.helperEnabled,
                    enableHelper: model.enableAppStoreHelper)
            }
            .font(.callout).foregroundStyle(.tint)
            .lineLimit(1).minimumScaleFactor(0.75)
        case .restart(let from):
            let line = UpdateResult.relaunchLine(from: from, to: result.relaunchTargetSide)
            Text("\(line.from)  →  \(line.to)")
                .font(.callout).foregroundStyle(.orange)
                .lineLimit(1).minimumScaleFactor(0.75)
        case .downgrade(let older):
            let installed = result.app.shortVersion ?? "?"
            Text("\(installed)  ↓  \(older)")
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        case .status:
            switch result.status {
            case .updateAvailable(let latest):
                // Names the running version when an older process is still live.
                let running = model.runningUpdateLine(result, latest: latest)
                let bump = result.buildBump(latest: latest)
                let (installed, offered) = result.updateLineSides(latest: latest)
                let from = running?.from ?? bump.map { "\(installed) (\($0.installed))" } ?? installed
                let to = running?.to ?? bump.map { "\(offered) (\($0.remote))" } ?? offered
                Text("\(from)  →  \(to)")
                    .font(.callout).foregroundStyle(.tint)
                    .lineLimit(1).minimumScaleFactor(0.75)
            case .upToDate where result.heldBySubscription != nil:
                // Current only within the subscription, and the action beside
                // this line says what it is not offering — so not "up to date".
                Text("v\(result.installedDisplay ?? "?")")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            case .upToDate:
                // The only status a check answers with "current". The popover
                // prints a bare "v<installed>" here too and puts the verdict in
                // its action column as a checkmark; this header's action is blank
                // for an up-to-date row, so the line says it.
                Text("v\(result.installedDisplay ?? "?") · up to date")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            default:
                // A failed check (`.error` — a rate limit, a timeout), no source
                // (`.unknown`), or a channel that owns the updates: none of them
                // established "up to date", and the action column beside this line
                // already says which it is (Failed / Rate-limited, a source hint, a
                // store tile). This used to append "· up to date" to all of
                // them, so a rate-limited row read "v3.3.0 · up to date" right next
                // to its orange "Rate-limited" badge. Same bare line the popover
                // and sidebar draw for these.
                Text("v\(result.installedDisplay ?? "?")")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
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
        ChangelogURLPolicy.displayable(ChangelogRecipeSelection.fallbackPage(for: result).url)
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
    /// telling apart: since the chain takes the first non-nil, a `remote` URL
    /// that fails the policy shadows a usable catalog entry rather than falling
    /// through to it. `catalog-withheld` is the third way to end up with no URL:
    /// a curated VENDOR page existed and this copy came from the store, so
    /// `ChangelogRecipeSelection` refused it on provenance (see its
    /// `fallbackPage`). Telling that apart from `none` is the whole point —
    /// "nobody publishes notes" and "we had notes and they were the wrong
    /// distribution's" look identical in the pane.
    ///
    /// ⚠️ Three of these five tokens are only reachable because `emptyNotes`
    /// logs. `logWebViewPane` is called from inside `if let url = changelogURL`
    /// at both of its call sites, so everything routed through it reports
    /// `remote` or `catalog` and nothing else — the first version of this
    /// property, and the `??` expression before it, could never emit `none` or
    /// either `-rejected` form at all. Adding a token without a call site that
    /// can reach it is how a diagnostic starts describing a distinction the log
    /// cannot actually make.
    private var changelogURLOrigin: String {
        let page = ChangelogRecipeSelection.fallbackPage(for: result)
        guard let chosen = page.url else { return page.logToken }
        return ChangelogURLPolicy.displayable(chosen) == nil
            ? "\(page.logToken)-rejected"
            : page.logToken
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
                    .onAppear {
                        Log.changelog.info("perf pane=recipe \(result.app.name, privacy: .public) (\(changelog.entries.count, privacy: .public) entries)")
                        // The other half of `AppListModel.changelogRevalidated`:
                        // notes painted from the cross-launch disk cache still owe
                        // one network read, and THIS is the only place that can ask
                        // for it. A prewarmed key arrives here already `.loaded`, so
                        // it never reaches the `.loading` branch below — which was
                        // the only caller, leaving the debt with nobody to collect
                        // it and a page the vendor published late frozen for good.
                        // `ensureChangelogLoading` returns at its first line once
                        // the key has been confirmed, so the steady state is one
                        // call per appearance and no request.
                        model.ensureChangelogLoading(for: result)
                    }
            case .failed:
                fallback
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { model.ensureChangelogLoading(for: result) }
            case .deferred:
                // A prewarm put this off (Low Data Mode, an expensive network); the
                // pane being open is the user asking, so load now. Its own branch,
                // not folded into `.loading`: a pane already on the `.loading`
                // spinner when the prewarm settles here must get a fresh `onAppear`.
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

    /// `.notice` for the same reason `logWebViewPane` is: this is read days after
    /// a sighting, and `.info` is never persisted for a third-party subsystem.
    /// Without this line the three no-URL outcomes are indistinguishable in a
    /// report AND in the pane — the user is told "no release notes" whether the
    /// vendor publishes none, the URL failed `ChangelogURLPolicy`, or we held a
    /// vendor page back from a store copy. ⚠️ The pane's own wording still says
    /// "doesn't publish a changelog we can read", which is untrue in the withheld
    /// case; correcting it means a new localized string and its translations, so
    /// it is deliberately left for its own change rather than done half-way here.
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
        .onAppear {
            Log.changelog.notice(
                "perf pane=empty \(result.app.name, privacy: .public) origin=\(changelogURLOrigin, privacy: .public) src=\(result.remote?.sourceName ?? "?", privacy: .public)")
        }
    }
}

private enum DetailMode: Hashable {
    case releaseNotes
    case bundleDiff
}

/// The app pane's two lenses, each kept once shown for this app (the pane is
/// rebuilt for another app, `.id(selected.id)`).
///
/// Switching between the Apps and Rollback tabs flips the lens (`tabChanged`), and
/// building it afresh was the larger part of each switch: flipping the lens alone,
/// with the picker, held the main thread for 53–77 ms a time on a 229-app Mac
/// (Time Profiler, 2026-10-10). Kept, flipping back is showing it again — and a
/// Bundle Diff still comparing carries on while Release Notes are shown, rather
/// than starting over; it still stops when the selection moves on.
private struct DetailLenses: View {
    let result: UpdateResult
    let model: AppListModel
    let lens: DetailMode
    @State private var built: Set<DetailMode> = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            if lens == .releaseNotes || built.contains(.releaseNotes) {
                ReleaseNotesPane(result: result, model: model)
                    .keptLayer(isShown: lens == .releaseNotes)
            }
            if lens == .bundleDiff || built.contains(.bundleDiff) {
                BundleDiffPane(result: result)
                    .keptLayer(isShown: lens == .bundleDiff)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: lens, initial: true) { _, shown in built.insert(shown) }
    }
}

/// `duo diff` in the workbench: the backup taken before this app's last update
/// against the bundle installed now, as the same raw report the command prints.
///
/// Deliberately not interpreted for the reader. The report's own notes say how
/// each kind of difference misleads (source paths follow logging, a missing
/// localization key proves nothing), and this surface is for investigating an
/// update, not for judging one.
///
/// Computed when the pane appears and not cached: `.task(id:)` cancels it when the
/// selection moves on, and `BundleDiff.report` stops walking at the next file, so
/// scrolling through the Rollback list never leaves bundles hashing behind it.
private struct BundleDiffPane: View {
    let result: UpdateResult

    /// The report split for display, with the width its widest line needs.
    private struct Report: Equatable {
        let text: String
        let lines: [String]
        let width: CGFloat

        init(_ text: String) {
            self.text = text
            lines = text.components(separatedBy: "\n")
                .map { $0.isEmpty ? " " : ($0.count > 1000 ? String($0.prefix(1000)) + "…" : $0) }
            // Measured, not estimated from a character count: the localization
            // section carries Chinese values, twice the width of the ASCII around them.
            let font = NSFont.monospacedSystemFont(
                ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
            width = lines.reduce(0) { widest, line in
                max(widest, ceil((line as NSString).size(withAttributes: [.font: font]).width))
            }
        }
    }

    private enum Phase: Equatable {
        case running
        case done(Report)
        case failed(String)
        case noBackup
    }

    @State private var phase: Phase = .running
    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    /// A new installed version is a new comparison.
    private var comparisonID: String {
        "\(result.id)|\(result.app.shortVersion ?? "")|\(result.app.buildVersion ?? "")"
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: comparisonID) { await compare() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .running:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Comparing with the backup…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            VStack(alignment: .leading, spacing: 0) {
                // Its own row, not an overlay: floated over the report it covered
                // the lines under it.
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.text, forType: .string)
                        // A click has to say it landed; the same confirm-and-revert as
                        // the Brew trust command's copy button.
                        copied = true
                        copiedResetTask?.cancel()
                        copiedResetTask = Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            guard !Task.isCancelled else { return }
                            copied = false
                        }
                    } label: {
                        // Both labels always laid out, one hidden, so the button keeps
                        // the wider one's size in every language instead of jumping.
                        ZStack {
                            Label("Copy Report", systemImage: "doc.on.doc").opacity(copied ? 0 : 1)
                            Label("Copied", systemImage: "checkmark").opacity(copied ? 1 : 0)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                // One Text per line, laid out lazily. As a single Text, Baidu Netdisk's
                // report (256 lines, one of them 2,563 characters) drew nothing at all
                // while its Copy Report button worked. Suspected, not confirmed: a view
                // that size is past what can be drawn in one piece. The long line is
                // split in Core now; the lazy stack keeps a long report from growing
                // one view without bound, and the cap covers any line Core does not
                // split. Copy Report still copies every character.
                //
                // A lazy stack only measures the rows it has built, so on its own it
                // is as wide as the window and the report cannot scroll sideways.
                // The widest line is measured up front and given to the stack.
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line)
                                .font(.system(.callout, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: true)
                        }
                    }
                    .frame(width: report.width + 8, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't compare with the backup", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noBackup:
            ContentUnavailableView {
                Label("No backup of this app was found.", systemImage: "externaldrive.badge.questionmark")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func compare() async {
        phase = .running
        let app = result.app
        // The same lookup a rollback makes: the key moved once, so older backups
        // live under a legacy candidate.
        let backup = await offCooperativePool {
            BackupStore.keyCandidates(bundleID: app.bundleID, path: app.path)
                .lazy.compactMap { BackupStore.backup(forKey: $0) }.first
        }
        guard !Task.isCancelled else { return }
        guard let backup else {
            phase = .noBackup
            return
        }
        let started = ContinuousClock.now
        let outcome = await BundleDiff.report(
            old: backup.bundlePath.path, new: app.path.path,
            oldLabel: "backup (\(backup.version ?? "?"))", newLabel: "installed",
            omittedFromOld: backup.omittedFiles,
            // What this backup holds was recorded when it was written, so on a
            // backup that has moved to a disk this is the difference between
            // reading one file and unpacking the whole bundle back over a cable.
            // Nil for a backup taken before that was recorded, which reads the
            // backup itself exactly as it always did.
            recordedOld: BackupFactsLibrary.Reference(backup))
        guard !Task.isCancelled else { return }
        switch outcome {
        case .success(let report):
            Log.changelog.info("perf pane=bundle-diff \(app.name, privacy: .public) \(String(describing: ContinuousClock.now - started), privacy: .public)")
            phase = .done(Report(report))
        case .failure(let failure):
            Log.changelog.error("bundle diff failed for \(app.name, privacy: .public): \(failure.description, privacy: .public)")
            phase = .failed(failure.description)
        }
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

/// A request to show one version's breaking changes in a `ChangelogEntriesView`:
/// a version in the CLI detail pane's Compatibility row, clicked. Each click is
/// a new request, so clicking the same version again scrolls back to it.
struct BreakingChangesJump: Equatable {
    let version: String
    private let click = UUID()

    init(version: String) { self.version = version }
}

/// Lays out a parsed `Changelog`. Shared by the recipe and GitHub-release paths.
/// A single-entry changelog (VS Code, VLC) renders full width. A multi-version one
/// (HBuilderX, Slack, …) offers two layouts the user toggles between (remembered):
/// `columns` — a master/detail with a version list on the left and the selected
/// version's notes on the right, best for content-heavy changelogs; or `list` — one
/// long top-down scroll, better when each version is only a line or two.
/// Internal, not private: the self-changelog window renders DuoUpdater's own
/// release notes through the very same view, so they look like every other app's
/// rather than a second, drifting layout.
struct ChangelogEntriesView: View {
    /// How an entry's items should read.
    ///
    /// A vendor changelog is a list of short lines, and a bullet in front of each
    /// is exactly right. DuoUpdater's own notes are not that shape: they are
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
    /// Versions whose notes mark breaking changes, flagged in the rail. Only a
    /// command-line tool's pane passes any (`CLIToolsModel.breaking`): the
    /// versions its update brings.
    var breakingVersions: [String] = []
    /// The latest click on a version in the pane's Compatibility row: shown
    /// like a click on that version's ⚠ in the rail (`showBreaking`).
    var breakingJump: BreakingChangesJump?
    /// DuoUpdater's own history uses compact version + date rows. Vendor
    /// changelogs retain the two-line treatment because their titles can be long.
    var showsDatesInline: Bool = false
    /// Whether to offer the side-by-side / long-scroll switch.
    ///
    /// Off for our own notes: with 101 versions the rail is the only sane way to
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
    /// The version whose breaking changes are tinted, and scrolled to when it
    /// was set: until the reader picks another version or another click lands.
    @State private var shownBreaking: BreakingChangesJump?
    /// The version a switch to the long scroll lands on: the one picked in
    /// the rail. Nil once landed, and dropped by new notes.
    @State private var landing: Int?

    /// What `scrollToBreaking` needs to know about the notes as they scroll,
    /// kept by the rows and the scroll views. Not observed: rows coming and
    /// going while the reader scrolls must not re-run this body.
    final class NotesScroll {
        /// The ids of the rows built right now (blocks of rows beside the
        /// rail). Kept per id, by each row's own `onAppear`/`onDisappear`,
        /// whether or not a scroll may go to it: tinting changes no id, so a
        /// row on screen when it is tinted must already be here.
        var built: Set<AnyHashable> = []
        /// The height of each of those rows, last measured.
        var heights: [AnyHashable: CGFloat] = [:]
        /// A version header's height (`ChangelogSectionsList`), last measured.
        var headerHeight: CGFloat = 0
        /// The measured version's header and first row in the window, last
        /// measured, by version: where `bandInset` is read
        /// (`ChangelogSectionsList.measured`). Each is nil while not built.
        /// The row's id too, so only the view that reported a frame clears it.
        var measuredHeader: (entry: Int, frame: CGRect)?
        var measuredFirstRow: (entry: Int, id: AnyHashable, frame: CGRect)?
        /// The long scroll's versions whose headers are built, by each header's
        /// `onAppear`/`onDisappear`. The first is the one floating at the top:
        /// the version the reader is in, carried to the side-by-side layout.
        var shownHeaders: Set<Int> = []
        /// The top of the long scroll's list in the window. The window's space,
        /// not one named on the list: that did not reach the list's headers,
        /// which got the window's anyway (2026-10-15).
        var listTop: CGFloat = 0
        /// What the list adds above and below a header's own view: the band
        /// floating over the notes is `headerHeight + 2 × bandInset`.
        var bandInset: CGFloat = 0
        /// The height the floating header covers.
        var band: CGFloat { headerHeight + 2 * bandInset }

        /// Reads `bandInset` off `entry`'s header where that is unambiguous
        /// (`HeaderBand.padding`), else keeps the value read before; whether
        /// it changed.
        func readBandInset(entry: Int) -> Bool {
            guard let header = measuredHeader, header.entry == entry,
                  let padding = HeaderBand.padding(
                      header: header.frame,
                      firstRow: measuredFirstRow?.entry == entry ? measuredFirstRow?.frame : nil,
                      listTop: listTop),
                  abs(padding - bandInset) > 0.5 else { return false }
            bandInset = padding
            return true
        }
        /// The scroll view's height.
        var viewportHeight: CGFloat = 0
    }
    @State private var notesScroll = NotesScroll()

    /// `shownBreaking` resolved to its entry and the rows that mark it breaking,
    /// once per render rather than once per row.
    private var tint: ChangelogRowsStack.Tint? {
        guard let shownBreaking, let index = entry(shownBreaking.version) else { return nil }
        return .init(entry: index, rows: ChangelogEntryView.breakingRows(of: changelog.entries[index]))
    }

    /// Content-driven rail width. For each row take the wider of its two lines — the
    /// title/version (callout) and the date subtitle (caption2) — since a short
    /// version like "3.6.8" can still carry a longer date ("4 July, 2023"). Sort
    /// those, then take a HIGH percentile, not the median: a title-based changelog
    /// (Codex) has many long titles and the median would clip the upper half. The
    /// 85th percentile fits the great majority; the upper clamp caps a lone runaway
    /// title (and the lower clamp keeps a terse changelog from getting cramped).
    /// Measured with AppKit since the labels are known up front — no GeometryReader.
    private static func railWidth(
        for changelog: Changelog, showsDatesInline: Bool, flagsBreaking: Bool = false
    ) -> CGFloat {
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
        // The ⚠ beside a flagged version, budgeted for the same reason: without
        // it only the flagged rows would truncate their labels.
        let breakingAccessory: CGFloat = flagsBreaking ? 18 : 0
        let minimum: CGFloat = showsDatesInline ? 156 : 140
        return min(max(pick + chrome + inlineAccessory + breakingAccessory, minimum), 360)
    }

    var body: some View {
        Group {
            if changelog.entries.count <= 1 {
                singleBody
            } else {
                multipleBody
            }
        }
        .releaseNoteLinks()
        // New changelog (app switch) → select the newest entry again, and
        // re-measure the rail (its width depends only on the changelog).
        .onChange(of: changelog) {
            selection = 0
            shownBreaking = nil
            landing = nil
            cachedRailWidth = measuredRailWidth
        }
        // The other layout opens on the version the reader was in: the one
        // floating at the top of the long scroll, or the one picked in the rail.
        .onChange(of: layout) { _, layout in
            switch layout {
            case .columns:
                if let top = notesScroll.shownHeaders.min() { selection = top }
            case .list:
                landing = selection
            }
        }
        // The flags can land after the notes: they come from the tool's check.
        .onChange(of: breakingVersions) {
            cachedRailWidth = measuredRailWidth
        }
        .onChange(of: breakingJump) {
            if let breakingJump { showBreaking(breakingJump) }
        }
        // Another version picked in the rail: its notes come untinted.
        .onChange(of: selection) {
            if let shownBreaking, entry(shownBreaking.version) != selection { self.shownBreaking = nil }
        }
        .onAppear {
            cachedRailWidth = measuredRailWidth
            // A click that landed while the notes were still loading.
            if let breakingJump { showBreaking(breakingJump) }
        }
    }

    /// Nothing to navigate — render the single entry full width, no toggle.
    private var singleBody: some View {
        sectionsBody
    }

    private var multipleBody: some View {
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
    }

    private var measuredRailWidth: CGFloat {
        let shown = Set(changelog.entries.map(\.version))
        return Self.railWidth(for: changelog, showsDatesInline: showsDatesInline,
                              flagsBreaking: breakingVersions.contains(where: shown.contains))
    }

    private func entry(_ version: String) -> Int? {
        changelog.entries.firstIndex { $0.version == version }
    }

    /// Select `jump`'s version and tint its breaking changes; the open layout's
    /// `scrollToBreaking` then brings them into view. A version these notes
    /// have no section for is left alone.
    private func showBreaking(_ jump: BreakingChangesJump) {
        guard let index = entry(jump.version) else { return }
        selection = index
        withAnimation(.easeOut(duration: 0.2)) { shownBreaking = jump }
    }

    /// Scroll to the tinted part of `shownBreaking`'s version: its first tinted
    /// row, or the top of its notes when nothing in them could be tinted but
    /// the version itself.
    ///
    /// One move, straight to the row. Every row has its id through its
    /// `ForEach`, and with that `scrollTo` reached the row from the top of
    /// openclaw's long scroll, unbuilt, in every run — on the lazy stack and
    /// again on the list (2026-10-14; Apple's docs say only that it scrolls to
    /// "a child view with identifier `id`").
    ///
    /// `belowHeader`: the version's header floats over the top of the notes
    /// (`ChangelogSectionsList`), so the row lands one band below the top
    /// (`NotesScroll.band`: the header and the list's padding around it).
    /// The anchor assumes `scrollTo` lines up the point at `anchor.y` of the
    /// target with the point at `anchor.y` of the scroll view, putting the
    /// target's top at `y × (viewport − target)`, solved for the band's
    /// height. Apple's docs don't spell that out. The row's height is measured
    /// once built; before that, a line. Beside the rail nothing floats (the
    /// rail says which version it is): the top of the pane.
    ///
    /// Under the band, a second move once the first has landed. A jump to an
    /// unbuilt row landed off by a row or more, which way depending on where
    /// the list started (openclaw, 2026-10-15); the rows it passes unbuilt
    /// being placed by guessed heights is a guess. And the band's padding can
    /// only be read with the version's header at the top. With both, the
    /// breaking row landed just under the band from the top, a fifth and four
    /// fifths of the way down, and again from on screen.
    ///
    /// Animated only when the row is already built (`notesScroll.built`), which
    /// means on screen or just off it: a short way, and the motion keeps where
    /// the reader was coming from. Otherwise a jump. The row is then typically
    /// far away, and an animated scroll that far builds every row it passes:
    /// 70–240 ms between frames, recorded on the lazy stack the long scroll
    /// used to be (2026-10-14); not re-measured on the list. Deferred a turn,
    /// to the update after the one that tints the row.
    ///
    /// Tinting keeps every row's id. It once gave the first tinted row an id
    /// of its own, set inside the tint's animation: a row on screen then left
    /// and came back as a new one, flying in under the version's first rows
    /// (recorded 2026-10-15).
    private func scrollToBreaking(_ proxy: ScrollViewProxy, belowHeader: Bool) {
        guard let shownBreaking, let index = entry(shownBreaking.version) else { return }
        let breaking = ChangelogEntryView.breakingRows(of: changelog.entries[index])
        let target: AnyHashable
        let built: AnyHashable
        if belowHeader {
            guard ChangelogEntryView.rowCount(of: changelog.entries[index]) > 0 else { return }
            target = ChangelogSectionsList.rowID(entry: index, row: breaking.first ?? 0)
            built = target
        } else {
            // One version shown: its top is the top of the pane, padding included.
            let opensEntry = (breaking.first ?? 0) == 0
            target = opensEntry ? AnyHashable(Self.scrollTopAnchor) : ChangelogRowsStack.rowID(breaking.first ?? 0)
            built = opensEntry ? ChangelogRowsStack.titleID : target
        }
        Task { @MainActor in
            _ = notesScroll.readBandInset(entry: index)
            if notesScroll.built.contains(built) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: anchor(for: target, belowHeader: belowHeader))
                }
                guard belowHeader else { return }
                // The band's padding may be readable only now, with the
                // version's header at the top.
                try? await Task.sleep(for: .milliseconds(350))
                if notesScroll.readBandInset(entry: index) {
                    proxy.scrollTo(target, anchor: anchor(for: target, belowHeader: belowHeader))
                }
            } else if belowHeader {
                await land(proxy, on: target, built: built, entry: index)
            } else {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    /// Jump to `target` under the band, and again once it is built: the move
    /// `scrollToBreaking` makes to a row far away.
    private func land(_ proxy: ScrollViewProxy, on target: AnyHashable, built: AnyHashable, entry: Int) async {
        proxy.scrollTo(target, anchor: anchor(for: target, belowHeader: true))
        for _ in 0..<10 where !notesScroll.built.contains(built) {
            try? await Task.sleep(for: .milliseconds(16))
        }
        _ = notesScroll.readBandInset(entry: entry)
        proxy.scrollTo(target, anchor: anchor(for: target, belowHeader: true))
        // The padding read only now, with the header at the top.
        try? await Task.sleep(for: .milliseconds(50))
        if notesScroll.readBandInset(entry: entry) {
            proxy.scrollTo(target, anchor: anchor(for: target, belowHeader: true))
        }
    }

    /// The long scroll just opened from the side-by-side layout: bring
    /// `landing`'s version to the top, its first row under its header.
    private func land(_ proxy: ScrollViewProxy) {
        guard let landing else { return }
        let index = min(max(landing, 0), changelog.entries.count - 1)
        guard ChangelogEntryView.rowCount(of: changelog.entries[index]) > 0 else {
            self.landing = nil
            return
        }
        let target = ChangelogSectionsList.rowID(entry: index, row: 0)
        Task { @MainActor in
            await land(proxy, on: target, built: target, entry: index)
            self.landing = nil
        }
    }

    /// Where `scrollToBreaking` puts `target`'s top: under the floating band
    /// (`NotesScroll.band`), or at the top of the pane when nothing floats.
    private func anchor(for target: AnyHashable, belowHeader: Bool) -> UnitPoint {
        let room = notesScroll.viewportHeight - (notesScroll.heights[target] ?? 20)
        return !belowHeader || room <= notesScroll.band
            ? .top
            : UnitPoint(x: 0, y: notesScroll.band / room)
    }

    /// Stable anchor for the detail pane's scroll-to-top. Constant on purpose —
    /// the whole point is that switching versions must NOT change view identity.
    fileprivate static let scrollTopAnchor = "changelog-entry-top"

    /// Master/detail: a content-sized version rail + the selected version's notes.
    private var columnsBody: some View {
        // Clamp: the same view can be reused when the user switches apps, so a stale
        // selection from a longer changelog must not index past a shorter one.
        let index = min(max(selection, 0), changelog.entries.count - 1)
        return HStack(spacing: 0) {
            ChangelogVersionList(
                entries: changelog.entries, selection: $selection,
                runningVersion: runningVersion,
                breakingVersions: Set(breakingVersions),
                showsDatesInline: showsDatesInline,
                showBreaking: { showBreaking(BreakingChangesJump(version: $0)) })
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
                    ChangelogRowsStack(changelog: changelog, entry: index, itemStyle: itemStyle,
                                       tint: tint, scroll: notesScroll)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(Self.scrollTopAnchor)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { notesScroll.viewportHeight = $0 }
                // The version's Copy, where the long scroll has it too: the top
                // right of the notes, wherever they are scrolled to.
                .overlay(alignment: .topTrailing) {
                    ChangelogEntryView.CopyNotesButton(entry: changelog.entries[index])
                        .padding(4)
                        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 10)
                        .padding(.trailing, 12)
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
                .onChange(of: shownBreaking) {
                    scrollToBreaking(proxy, belowHeader: false)
                }
            }
        }
    }

    /// One long top-down scroll of every version.
    private var listBody: some View {
        sectionsBody
    }

    /// Every version as a section of a native list, its header floating over
    /// the notes while they are read (`ChangelogSectionsList`).
    private var sectionsBody: some View {
        ScrollViewReader { proxy in
            ChangelogSectionsList(changelog: changelog, itemStyle: itemStyle, tint: tint,
                                  measured: tint?.entry ?? landing, scroll: notesScroll)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    notesScroll.viewportHeight = $0.height
                    notesScroll.listTop = $0.minY
                }
                .onChange(of: shownBreaking) {
                    scrollToBreaking(proxy, belowHeader: true)
                }
                .onAppear { land(proxy) }
        }
    }
}

/// The notes of the version picked in the rail, as one flat lazy stack of rows:
/// its title, then the rows under it (`ChangelogEntryView.rowCount`).
///
/// Flat rows, not one view per entry: a lazy stack knows the height of what it
/// has built and guesses the rest from that, and rows are an even unit to guess
/// from — the scroller's thumb jumped at every correction when the unit was a
/// whole entry (AX probe and screen recording, 2026-10-14). The ids are the
/// `ForEach`'s own data; with them `ScrollViewProxy.scrollTo` reached rows not
/// built yet (see `ChangelogEntriesView.scrollToBreaking`). The ids are the row
/// alone, not the entry's, so picking another version updates the rows in place
/// rather than rebuilding every one of them.
///
/// Lazy, not eager: TablePro's 0.67.0 alone carries 205 change lines. And with
/// every row built, each accessibility update walks every selectable row's
/// responder (`ResponderNode.visitFocusResponders`): openclaw's long scroll,
/// built eagerly, held the main thread for tens of seconds per accessibility
/// action while an accessibility client was attached (measured 2026-10-14).
///
/// Not selectable. `.textSelection(.enabled)` on the notes cost about a third
/// of the main thread while scrolling — selectable text is laid out through
/// TextKit, and every frame re-ran accessibility and cursor hit-testing over its
/// rows. Without it the same 30-page scroll took ~1.7–2.2 s instead of ~3.6 s
/// (2026-10-14). Each version gets a Copy button instead
/// (`ChangelogEntryView.CopyNotesButton`), top right of the notes in every
/// layout: over this stack (`ChangelogEntriesView.columnsBody`), and in the
/// floating version header of `ChangelogSectionsList`.
private struct ChangelogRowsStack: View {
    /// The entry whose breaking changes are tinted, and which of its rows
    /// (`ChangelogEntryView.breakingRows`): none means its title.
    struct Tint {
        let entry: Int
        let rows: IndexSet
    }

    let changelog: Changelog
    /// Index into `changelog.entries`.
    let entry: Int
    var itemStyle: ChangelogEntriesView.ItemStyle = .bulleted
    var tint: Tint?
    /// Where the title and breaking row are recorded while built, by id, with
    /// their heights (`ChangelogEntriesView.NotesScroll`).
    var scroll: ChangelogEntriesView.NotesScroll?

    /// The gap between the title and the first row.
    private static let titleGap: CGFloat = 8

    private struct RowKey: Hashable {
        /// -1 for the title.
        let row: Int
    }

    private struct Row: Identifiable {
        let id: AnyHashable
        let part: ChangelogEntryView.Part
        /// The title or the first breaking row: one `scrollToBreaking` may go
        /// to, so it starts a block. Breaking whether tinted or not, so tinting
        /// changes no block and no id.
        let startsBlock: Bool
        /// Space below this row. Below, not above, so a row's own frame is the
        /// top `scrollTo(_:anchor: .top)` lines up.
        let gapBelow: CGFloat
    }

    /// Up to `blockSize` consecutive rows, laid out together. The title or a
    /// breaking row always starts a block, so its id is the block's and
    /// `scrollTo` can still reach it.
    ///
    /// The lazy stack walks every item of its `ForEach` on each frame it places
    /// (`LazySubviewPlacements` → `ForEachState.forEachItem`): one row per item
    /// was openclaw's ~1,500 items, 18% of the main thread while scrolling.
    /// Blocks of 12 cut the main-thread time of the same 30-page scroll from
    /// ~5.4 s to ~3.6 s; blocks of 24 measured the same as 12 (2026-10-14).
    private struct Block: Identifiable {
        let rows: [Row]
        var id: AnyHashable { rows[0].id }
    }
    private static let blockSize = 12

    private var blocks: [Block] {
        var blocks: [Block] = []
        var current: [Row] = []
        func flush() {
            if !current.isEmpty { blocks.append(Block(rows: current)) }
            current = []
        }
        for row in rows {
            if row.startsBlock || current.count == Self.blockSize { flush() }
            current.append(row)
            // A breaking row is a block of its own: its block's top and height
            // are the row's.
            if row.startsBlock, row.part != .title { flush() }
        }
        flush()
        return blocks
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(block.rows) { row in
                        ChangelogEntryView(entry: changelog.entries[entry], itemStyle: itemStyle,
                                           syntax: changelog.itemSyntax, part: row.part,
                                           tinted: tint?.entry == entry ? tint?.rows : nil)
                            .padding(.bottom, row.gapBelow)
                    }
                }
                .onAppear { scroll?.built.insert(block.id) }
                .onDisappear { scroll?.built.remove(block.id) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    scroll?.heights[block.id] = height
                }
            }
        }
    }

    /// The title row's id.
    static let titleID = AnyHashable(RowKey(row: -1))
    /// The id of a row under the title.
    static func rowID(_ row: Int) -> AnyHashable { AnyHashable(RowKey(row: row)) }

    private var rows: [Row] {
        let item = changelog.entries[entry]
        let count = ChangelogEntryView.rowCount(of: item)
        let spacing = ChangelogEntryView.rowSpacing(of: item, itemStyle: itemStyle)
        let firstBreaking = ChangelogEntryView.breakingRows(of: item).first
        var rows = [Row(id: Self.titleID, part: .title, startsBlock: true, gapBelow: count == 0 ? 0 : Self.titleGap)]
        for row in 0..<count {
            rows.append(Row(
                id: Self.rowID(row),
                part: .row(row),
                startsBlock: row == firstBreaking,
                gapBelow: row == count - 1 ? 0 : spacing))
        }
        return rows
    }
}

/// Every version's notes as one long scroll: a native list with a section per
/// version, whose header — version, date and Copy — floats over the top of the
/// notes while that version is read, and is pushed off by the next one's. The
/// same list and header band as the Release Log's days (`ReleaseLogView.feed`).
///
/// A native list, not a lazy stack with its title drawn over it: in every
/// 20th frame recorded over 18 page-downs, the floating header named the
/// version under it (2026-10-14). The overlay this replaced learned where the
/// rows were after they had moved, and a fast scroll caught it a frame behind
/// — two titles at once, or one with no band behind it (user's screen
/// recording, 2026-10-14). A lazy stack's own pinned section
/// headers made the scroller's thumb jump again: 10 of 300 small steps off by
/// more than 0.02, against 2 for flat rows (2026-10-14).
private struct ChangelogSectionsList: View {
    let changelog: Changelog
    var itemStyle: ChangelogEntriesView.ItemStyle = .bulleted
    var tint: ChangelogRowsStack.Tint?
    /// The version whose header's frame is measured, for `NotesScroll.bandInset`:
    /// the one a scroll is landing on. One only: a header's frame changes on
    /// every frame of a scroll.
    var measured: Int?
    /// Where the rows `scrollToBreaking` may go to are recorded while built,
    /// with their heights, and the header's height (`ChangelogEntriesView.NotesScroll`).
    let scroll: ChangelogEntriesView.NotesScroll

    /// The gap between the header and the first row, and below the last.
    private static let sectionInset: CGFloat = 10

    private struct RowKey: Hashable {
        let entry: Int
        let row: Int
    }

    /// The id of `entry`'s `row`, tinted or not.
    static func rowID(entry: Int, row: Int) -> AnyHashable { AnyHashable(RowKey(entry: entry, row: row)) }

    private struct Row: Identifiable {
        let id: AnyHashable
        let row: Int
        /// Padding around the row, inside it: a list row's own insets only
        /// partly took (top yes, bottom no; 2026-10-14), so the list's are
        /// zero, as in the Release Log.
        let padding: EdgeInsets
    }

    /// `entry`'s rows. The ids are the `ForEach`'s own data, so `scrollTo` can
    /// reach a row not built yet (`ChangelogEntriesView.scrollToBreaking`).
    private func rows(of index: Int, tinted: IndexSet?) -> [Row] {
        let entry = changelog.entries[index]
        let count = ChangelogEntryView.rowCount(of: entry)
        let spacing = ChangelogEntryView.rowSpacing(of: entry, itemStyle: itemStyle)
        return (0..<count).map { row in
            Row(id: Self.rowID(entry: index, row: row),
                row: row,
                padding: EdgeInsets(top: row == 0 ? Self.sectionInset : 0, leading: 16,
                                   bottom: row == count - 1 ? Self.sectionInset : spacing, trailing: 16))
        }
    }

    var body: some View {
        List {
            ForEach(changelog.entries.indices, id: \.self) { index in
                let entry = changelog.entries[index]
                let tinted = tint?.entry == index ? tint?.rows : nil
                Section {
                    ForEach(rows(of: index, tinted: tinted)) { row in
                        ChangelogEntryView(entry: entry, itemStyle: itemStyle, syntax: changelog.itemSyntax,
                                           part: .row(row.row), tinted: tinted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(row.padding)
                            .onAppear { scroll.built.insert(row.id) }
                            .onDisappear { scroll.built.remove(row.id) }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                scroll.heights[row.id] = height
                            }
                            // Under the measured header (`NotesScroll.readBandInset`).
                            .onGeometryChange(for: CGRect?.self) {
                                row.row == 0 && index == measured ? $0.frame(in: .global) : nil
                            } action: { frame in
                                if row.row == 0, index == measured, let frame { scroll.measuredFirstRow = (index, row.id, frame) }
                            }
                            .onDisappear {
                                if row.row == 0, scroll.measuredFirstRow?.id == row.id { scroll.measuredFirstRow = nil }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    ChangelogEntryView.Header(entry: entry, tinted: tinted?.isEmpty == true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scroll.headerHeight = $0 }
                        .onGeometryChange(for: CGRect?.self) {
                            index == measured ? $0.frame(in: .global) : nil
                        } action: { frame in
                            if index == measured, let frame { scroll.measuredHeader = (index, frame) }
                        }
                        .onAppear { scroll.shownHeaders.insert(index) }
                        .onDisappear {
                            scroll.shownHeaders.remove(index)
                            if scroll.measuredHeader?.entry == index { scroll.measuredHeader = nil }
                        }
                        // Not all of them: the list still put the header 8 pt
                        // in and 4.125 pt down, in a band 37.5 pt tall for a
                        // 29.25 pt header (`NotesScroll.bandInset`; 2026-10-15).
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
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
    /// Versions whose notes mark breaking changes (`ChangelogEntriesView.breakingVersions`).
    var breakingVersions: Set<String> = []
    var showsDatesInline = false
    /// A flagged version's ⚠, clicked: show that version's breaking changes.
    var showBreaking: (String) -> Void = { _ in }

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
                                if breakingVersions.contains(entry.version) {
                                    // The sidebar row's ⚠, on the version it is about.
                                    // A button of its own inside the row's: the row
                                    // selects the version, this also takes the notes
                                    // to the part it is about.
                                    Button { showBreaking(entry.version) } label: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("This version’s notes mark breaking changes. Click to show them.")
                                    .accessibilityLabel("This version’s notes mark breaking changes. Click to show them.")
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

// MARK: - One changelog entry

/// One part of a changelog entry — its title, or one row under it — as
/// `ChangelogRowsStack` lays them out. The title is either a classic version
/// heading, or a post-style title with date/build metadata underneath.
private struct ChangelogEntryView: View {
    /// What of the entry to draw: its title, or row `n` of `rowCount(of:)`.
    enum Part: Hashable {
        case title
        case row(Int)
    }

    let entry: Changelog.Entry
    var itemStyle: ChangelogEntriesView.ItemStyle = .bulleted
    /// Carried down from the `Changelog` so a bullet knows whether its text is
    /// Markdown; see `rendered(_:syntax:)`.
    var syntax: Changelog.ItemSyntax = .plain
    let part: Part
    /// The rows that mark this entry breaking (`breakingRows`) when the reader
    /// asked to see them (`ChangelogEntriesView.showBreaking`); nil otherwise.
    /// Empty: nothing in the notes can be pointed at, so the title is tinted.
    var tinted: IndexSet?

    private var displayDate: String? {
        guard let date = entry.date else { return nil }
        return Self.displayDate(for: date)
    }

    /// The rows that mark `entry` breaking, as indexes into the rows this view
    /// draws for it: its Markdown blocks, else its `content`, else its `items`
    /// (`CLIToolChangelog.breakingBlocks`). Empty when none can be pointed at.
    static func breakingRows(of entry: Changelog.Entry) -> IndexSet {
        if let markdown = entry.markdown {
            let blocks = ChangelogMarkdownView.blocks(for: markdown)
            return blocks.isEmpty
                ? CLIToolChangelog.breakingItems(entry.items) : CLIToolChangelog.breakingBlocks(in: blocks)
        }
        return entry.content.isEmpty
            ? CLIToolChangelog.breakingItems(entry.items) : CLIToolChangelog.breakingBlocks(in: entry.content)
    }

    /// How many rows the entry draws under its title, counted the way
    /// `breakingRows` indexes them.
    static func rowCount(of entry: Changelog.Entry) -> Int {
        if let markdown = entry.markdown {
            let blocks = ChangelogMarkdownView.blocks(for: markdown)
            return blocks.isEmpty ? entry.items.count : blocks.count
        }
        return entry.content.isEmpty ? entry.items.count : entry.content.count
    }

    /// The gap between two rows of `entry`.
    static func rowSpacing(of entry: Changelog.Entry, itemStyle: ChangelogEntriesView.ItemStyle) -> CGFloat {
        if entry.markdown != nil { return 6 }
        if entry.content.isEmpty { return itemStyle == .paragraphs ? 14 : 6 }
        return 8
    }

    var body: some View {
        switch part {
        case .title:
            title
                // Nothing in the notes to point at: the version itself is.
                .breakingTint(tinted?.isEmpty == true, spacing: 8)
        case let .row(index):
            row(index)
                .breakingTint(tinted?.contains(index) == true,
                              spacing: Self.rowSpacing(of: entry, itemStyle: itemStyle))
        }
    }

    /// Row `index` under the title. Rich entries — notes interleaved with images
    /// (WeChat) or category headings (Mac Performance Monitor's Keep a Changelog
    /// file, a GitHub-sourced app whose release body had ≥2 real ones — see
    /// `Changelog.Entry.Block`) — walk `content` so a screenshot or a heading
    /// lands exactly where it does on the vendor's page. Text-only entries (the
    /// common case) just bullet `items`.
    @ViewBuilder
    private func row(_ index: Int) -> some View {
        if let markdown = entry.markdown {
            // Notes that ARE Markdown (Sparkle's inline notes) are drawn as the
            // author wrote them — their own headings, nesting and code — rather
            // than through `content`/`items`, which flatten that structure.
            let blocks = ChangelogMarkdownView.blocks(for: markdown)
            if blocks.isEmpty {
                // Drawn as plain bullets if Foundation parses no blocks at all, so
                // a body it cannot read shows its lines instead of an empty pane.
                ChangelogMarkdownView.row(ChangelogMarkdown.Block(
                    kind: .listItem(depth: 1, marker: "•"), text: AttributedString(entry.items[index])))
            } else {
                ChangelogMarkdownView.row(blocks[index])
            }
        } else if entry.content.isEmpty {
            noteRow(entry.items[index])
        } else {
            switch entry.content[index] {
            case let .note(text): noteRow(text)
            case let .image(url): noteImage(url)
            case let .heading(text): headingRow(text)
            }
        }
    }

    /// The entry's notes as plain text, for `CopyNotesButton`: its Markdown as
    /// written, else its `content` (headings as lines, notes as `- ` items, images
    /// left out), else its `items` as `- ` items.
    static func plainText(of entry: Changelog.Entry) -> String {
        if let markdown = entry.markdown { return markdown }
        if entry.content.isEmpty { return entry.items.map { "- \($0)" }.joined(separator: "\n") }
        return entry.content.compactMap { block -> String? in
            switch block {
            case let .heading(text): return "\n\(text)"
            case let .note(text): return "- \(text)"
            case .image: return nil
            }
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copies one version's notes: the notes are not selectable
    /// (`ChangelogRowsStack`), so this is how their text gets out. Turns into a
    /// checkmark for a moment, so the click visibly landed.
    struct CopyNotesButton: View {
        let entry: Changelog.Entry
        @State private var copied = false
        @State private var resetTask: Task<Void, Never>?

        static func label(for entry: Changelog.Entry) -> String {
            let name = entry.version.isEmpty ? (entry.title ?? "") : entry.version
            return String(localized: "Copy the \(name) release notes")
        }

        static func copy(_ entry: Changelog.Entry) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ChangelogEntryView.plainText(of: entry), forType: .string)
        }

        var body: some View {
            let label = Self.label(for: entry)
            Button {
                Self.copy(entry)
                copied = true
                resetTask?.cancel()
                // Back to the copy glyph, so a second copy confirms again.
                resetTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    copied = false
                }
            } label: {
                // Both glyphs always laid out, one shown: they differ in size,
                // and swapping them changed the header's height on each click.
                ZStack {
                    Image(systemName: "doc.on.doc").opacity(copied ? 0 : 1)
                    Image(systemName: "checkmark").opacity(copied ? 1 : 0)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(label)
            .accessibilityLabel(label)
        }
    }

    /// A version's header over its notes in `ChangelogSectionsList`: one line
    /// of title, version and date, and the Copy button at its trailing end. The
    /// band of the Release Log's day headers (`ReleaseLogView.dayHeader`), so
    /// the two long scrolls read alike.
    struct Header: View {
        let entry: Changelog.Entry
        /// Nothing in the notes to point at: the version itself is breaking.
        var tinted = false

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Primary: the list drew its section headers dimmed (seen 2026-10-14).
                if let title = entry.title {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    if !entry.version.isEmpty {
                        Text(entry.version).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(entry.version).font(.headline).foregroundStyle(.primary)
                }
                if let date = entry.date {
                    Text(ChangelogEntryView.displayDate(for: date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CopyNotesButton(entry: entry)
            }
            .lineLimit(1)
            .breakingTint(tinted, spacing: 12)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    /// A classic version heading, or a post-style title with its metadata.
    @ViewBuilder
    private var title: some View {
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
            .frame(maxWidth: ImageStore.maxDisplayPointWidth, alignment: .leading)
            .padding(.vertical, 2)
    }

    /// A category heading (`Added`, `Fixed`, …) grouping the notes that follow it.
    /// Deliberately smaller than the version title above and left-aligned like a
    /// bullet, not indented — it is a sub-section of THIS entry, not a nested
    /// entry of its own. Markdown-rendered like a bullet (`rendered(_:syntax:)`),
    /// since a GitHub-sourced heading carries the same inline syntax an item does.
    @ViewBuilder
    private func headingRow(_ text: String) -> some View {
        Text(Self.rendered(text, syntax: syntax))
            .font(.subheadline).bold()
            .padding(.top, 2)
    }

    fileprivate static func displayDate(for raw: String) -> String {
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

// MARK: - Markdown notes

/// `Changelog.Entry.markdown` drawn block by block (`ChangelogMarkdown.blocks`):
/// headings, list items indented by depth, code in a box, quotes with a rule.
/// Inline emphasis, code spans and links are already on each block's text, which
/// `Text` draws. Matches the bulleted rows and `headingRow` above in size and
/// spacing, so a Markdown entry sits in the pane like every other one. Each
/// block is one row of the notes (`ChangelogEntryView.row`).
@MainActor
private enum ChangelogMarkdownView {
    @ViewBuilder
    static func row(_ block: ChangelogMarkdown.Block) -> some View {
        switch block.kind {
        case let .heading(level):
            Text(block.text)
                .font(level <= 2 ? .headline : .subheadline).bold()
                .padding(.top, 6)
        case .paragraph:
            Text(block.text)
                .fixedSize(horizontal: false, vertical: true)
        case let .listItem(depth, marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // A later paragraph of an item keeps the marker's width, invisible,
                // so its text lines up with the item's first line.
                Text(marker ?? "•").foregroundStyle(.secondary).opacity(marker == nil ? 0 : 1)
                Text(block.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth - 1) * 18)
        case .code:
            Text(block.text)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.tertiary).frame(width: 3)
                Text(block.text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Parsed once per body, not on every redraw of the pane. Bounded by the
    /// entries a user actually opens; cleared wholesale if that ever grows large.
    private static var cache: [String: [ChangelogMarkdown.Block]] = [:]

    static func blocks(for markdown: String) -> [ChangelogMarkdown.Block] {
        if let hit = cache[markdown] { return hit }
        if cache.count > 200 { cache.removeAll() }
        let blocks = ChangelogMarkdown.blocks(from: markdown)
        cache[markdown] = blocks
        return blocks
    }
}

/// The tint on what marks a version breaking, once the reader asked to see it
/// (`ChangelogEntryView.tinted`): the sidebar's orange, washed behind the
/// row with a solid bar at its leading edge, reaching out by half the stack's
/// `spacing` so consecutive tinted rows read as one block.
private struct BreakingTint: ViewModifier {
    let isOn: Bool
    let spacing: CGFloat

    func body(content: Content) -> some View {
        content
            // Full width while tinted, so a short line's tint spans the pane;
            // untinted rows lay out exactly as they always have.
            .frame(maxWidth: isOn ? .infinity : nil, alignment: .leading)
            .background {
                if isOn {
                    Rectangle()
                        .fill(Color.orange.opacity(0.16))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.orange).frame(width: 3) }
                        .padding(.horizontal, -10)
                        .padding(.vertical, -spacing / 2)
                        .transition(.opacity)
                }
            }
    }
}

private extension View {
    func breakingTint(_ isOn: Bool, spacing: CGFloat) -> some View {
        modifier(BreakingTint(isOn: isOn, spacing: spacing))
    }
}

// MARK: - Inline release notes

extension View {
    /// What a click on a link inside rendered release notes does: a web page or a
    /// mail address opens, anything else is dropped (`ReleaseNoteLinkPolicy`). Put
    /// on the root of every view that draws notes, so the nested rows inherit it:
    /// `ChangelogEntriesView` (structured notes, and the Markdown rows in them) and
    /// `ReleaseNotesText` (inline notes). Without it SwiftUI hands any scheme in
    /// the vendor's text (`smb:`, `ssh:`, `shortcuts:`) to `NSWorkspace`.
    ///
    /// `NSWorkspace` rather than SwiftUI's own `openURL`, which errors -50 in this
    /// app's windows (see `AlcoveSettingsPage`).
    fileprivate func releaseNoteLinks() -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard ReleaseNoteLinkPolicy.allows(url) else { return .discarded }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}

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
        .releaseNoteLinks()
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

    static func removeAll() {
        guard !byURL.isEmpty else { return }
        Log.changelog.info("perf webview cache cleared: \(byURL.count, privacy: .public) view(s)")
        guardians.values.forEach { $0.cancel() }
        guardians = [:]
        byURL = [:]
        order = []
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

    /// Whether this pane has ever finished a navigation successfully. #292: a
    /// rejection that happens before the very first load ever commits leaves a
    /// permanently blank pane, indistinguishable from "this app has no notes" —
    /// that is the case `reject(_:url:reason:isMainFrame:)` shows a message for.
    /// A rejection that happens later, after the reader has already shown real
    /// content (a page that redirects itself mid-session), leaves that content
    /// alone instead: replacing something the user is reading with an error
    /// panel over one blocked navigation would be a worse outcome than the
    /// rejection itself.
    private var hasCommittedFirstLoad = false

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
        // else is left alone by the outbound-link rule:
        //   • sub-frames — `decidePolicyFor` fires for iframes too, and a changelog
        //     page that embeds a video or a third-party widget would otherwise have
        //     every frame cancelled and thrown at the browser, one window each;
        //   • server-side redirects and SPA routing — a vendor moving
        //     docs.x.com → x.com/docs is normal, so cross-host HTTPS redirects stay
        //     allowed when the destination passes `ChangelogURLPolicy`.
        //
        // The policy IS reapplied to every main-frame navigation, including a
        // server redirect. Vetting only the recipe's starting URL let an accepted
        // vendor URL redirect to an IP literal or a reserved local hostname and
        // load an origin the policy would have refused at the door. This remains
        // a structural gate — it cannot see which address an ordinary DNS name
        // resolves to — but the URL the user lands on now gets the same check as
        // the URL we start from.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        if let url = navigationAction.request.url,
           url.scheme?.lowercased() == "http" {
            // Same category `ChangelogURLPolicy.rejectionReason` would report for
            // this URL (`.notHTTPS`) — reused rather than given its own case so
            // there is exactly one place that owns the log/display text for "this
            // navigation isn't https". This check exists as its own branch
            // because it is broader than the policy check below: it also catches
            // a sub-frame loading http (mixed content), where `isMainFrame` would
            // otherwise let it through.
            reject(webView, url: url, reason: .notHTTPS, isMainFrame: isMainFrame)
            decisionHandler(.cancel); return
        }

        if isMainFrame,
           let url = navigationAction.request.url,
           let reason = ChangelogURLPolicy.rejectionReason(url) {
            reject(webView, url: url, reason: reason, isMainFrame: isMainFrame)
            decisionHandler(.cancel); return
        }

        guard navigationAction.navigationType == .linkActivated,
              isMainFrame,
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

    /// #292: `decidePolicyFor` used to cancel a rejected navigation with nothing
    /// else — no log line, and if the rejection landed on the pane's very first
    /// (still-uncommitted) navigation, a permanently blank pane that reads exactly
    /// like "this app has no changelog". Every rejection is now logged with the
    /// URL and the reason, and — only in that blank-forever case — the pane shows
    /// the reason instead of staying blank.
    ///
    /// `.error`, not `.info`: per `Log`'s own doc comment, `.info` is memory-only
    /// for a third-party subsystem and would be gone by the time anyone went
    /// looking for why a changelog pane went dark.
    private func reject(_ webView: WKWebView, url: URL, reason: ChangelogURLPolicy.RejectionReason, isMainFrame: Bool) {
        Log.changelog.error("webview navigation blocked (\(reason.logToken, privacy: .public)) mainFrame=\(isMainFrame ? "yes" : "no", privacy: .public) url=\(Redactor.url(url), privacy: .public) origin=\(self.originHost ?? "?", privacy: .public)")
        guard isMainFrame, !hasCommittedFirstLoad else { return }
        showBlockedNotice(webView, reason: reason)
    }

    /// Puts `reason` on screen in place of a blank pane. `WorkbenchWindowView`'s
    /// SwiftUI layer already has a `ContentUnavailableView` for "nothing to show"
    /// (`ReleaseNotesPane.emptyNotes`, `FormulaDetailPane.noNotes`), but this
    /// `WKWebView` is owned by `WebViewCache` and mounted through a plain
    /// `NSViewRepresentable` that only ever creates it — there is no channel from
    /// here back to that SwiftUI state without threading a binding through the
    /// cache for every call site that can hand out a cached view. Loading a small
    /// HTML page directly into the same pane keeps the fix self-contained to this
    /// type, at the cost of a hand-rolled (not SwiftUI) message.
    ///
    /// #299: both strings below now go through `String(localized:)` — the title
    /// here, and `reason.localizedDescription` in `ChangelogURLPolicy`. Neither
    /// ever carries interpolated URL content (see `RejectionReason`'s doc
    /// comment), but a *translation* of a fixed category can still contain `&`,
    /// `<`, `>`, or a quote mark — French and German punctuation both do — so the
    /// escaping below now covers all five HTML-significant characters, not just
    /// the two an English-only literal happened to need.
    ///
    /// `check_localizable_keys.py` cannot see either string: it diffs
    /// `Localizable.xcstrings` against the keys `SWIFT_EMIT_LOC_STRINGS` recorded
    /// for `String(localized:)` call sites, and both calls here are ordinary call
    /// sites like any other — so this is not a blind spot in that checker, it
    /// would have caught the original English literal too had it gone through
    /// `String(localized:)` in the first place. The actual blind spot was this
    /// function loading a *hand-built HTML string* instead of calling
    /// `String(localized:)` at all; nothing short of grepping `WKWebView`-bound
    /// strings for the absence of `String(localized:)` would catch a *future*
    /// literal slipped in here the same way, and that is a much noisier check to
    /// add than the value of catching one call site.
    private func showBlockedNotice(_ webView: WKWebView, reason: ChangelogURLPolicy.RejectionReason) {
        let title = ChangelogURLPolicy.htmlEscaped(String(localized: "Can’t show this page safely"))
        let body = ChangelogURLPolicy.htmlEscaped(reason.localizedDescription)
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body {
            display: flex; align-items: center; justify-content: center;
            height: 100vh; margin: 0; text-align: center;
            font-family: -apple-system, sans-serif;
            background: Canvas; color: GrayText;
          }
          .box { max-width: 320px; padding: 24px; }
          .title { color: CanvasText; font-weight: 600; margin-bottom: 6px; }
        </style></head>
        <body><div class="box">
          <div class="title">\(title)</div>
          <div>\(body)</div>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
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
        hasCommittedFirstLoad = true
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

extension EnvironmentValues {
    @Entry fileprivate var workbenchWindowOpen = false
}

/// Renders nothing while the workbench window is closed. Closing the window
/// does not tear its SwiftUI tree down: the hosting view stays alive and keeps
/// re-rendering on model changes, so emptying `WebViewCache` alone left the
/// mounted page (and its WebContent process) alive, and a later re-render built
/// a fresh one with no window at all — both seen in WebKit's own log on
/// 2026-09-28.
private struct CachedWebView: View {
    let url: URL
    @Environment(\.workbenchWindowOpen) private var windowOpen

    var body: some View {
        if windowOpen {
            CachedWebViewRepresentable(url: url)
        } else {
            Color.clear
        }
    }
}

private struct CachedWebViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WebViewCache.view(for: url)
    }

    // The cached view already holds the loaded page; nothing to do on update.
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// Update All for the tool groups in the workbench sidebar's header
/// (`WorkbenchWindowView.otherToolsBulkUpdate`), drawn from
/// `CLIRowSnapshot.updateAllHeader`. A view of its own so that what it reads —
/// the rows' smoothed Cancels and lines, which change with every output line
/// of a running update — redraws it alone, not the whole workbench.
private struct OtherToolsUpdateAllButton: View {
    let tools: CLIToolsModel
    /// The copies it updates and cancels (`CLIToolsModel.updateAll(in:)`):
    /// "Other tools" without the managers, or one manager's level.
    let scope: Set<CLIToolID>

    var body: some View {
        let header = tools.rowSnapshot(in: scope).updateAllHeader
        let running: InstallRowSmoothing<CLIToolID>.GroupCancel? = if case .running(let cancel) = header { cancel } else { nil }
        if header != .hidden {
            Button("Update All") { Task { await tools.updateAll(in: scope) } }
                .controlSize(.small)
                .buttonStyle(.bordered)
                // Not disabled by another run: behind one it waits its turn
                // (`CLIRunQueue`), and can be taken back meanwhile.
                .disabled(header != .update(startable: true))
                .help(CLIToolPresentation.updateAllHelp)
                .opacity(running != nil ? 0 : 1)
                .overlay(alignment: .trailing) {
                    // Its Cancel beside the spinner, waiting or running, as
                    // Homebrew's Upgrade All has (`CLIToolsModel.updateAllCancel`).
                    if let cancel = running {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            InstallCancelButton(state: cancel.state, pending: cancel.pending) { tools.cancelRow(in: scope) }
                        }
                    }
                }
                // The rest of a double-click on Update All is not a click on its Cancel.
                .swallowsClicksAfterSwap(of: running != nil)
        }
    }
}

/// Upgrade All for the Homebrew group in the workbench sidebar
/// (`WorkbenchWindowView.brewBulkUpgrade`), drawn from
/// `BrewRowSnapshot.upgradeAllHeader`. A view of its own so that what it reads —
/// the brew runs' smoothed Cancels and its count, which move with every
/// formula poured — redraws it alone, not the whole workbench.
///
/// While it runs, its progress and a spinner take the button's place — drawn
/// over the button, which keeps its room unseen: the header's height is the
/// button's, and the shorter spinner in its stead moved every row below 1 pt
/// up and back (2026-10-06).
private struct BrewUpgradeAllButton: View {
    let model: AppListModel

    var body: some View {
        let header = model.brewRowSnapshot.upgradeAllHeader
        if header != .hidden {
            let running = header != .update
            ZStack(alignment: .trailing) {
                // Never disabled by another run: behind one it waits its turn
                // (`CLIRunQueue`), "Queued" with its Cancel.
                Button("Upgrade All") { Task { await model.upgradeBrewFormulae() } }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help(String(localized: "Runs `brew upgrade --formula` — upgrades every outdated CLI formula at once. Casks are managed per-row above."))
                    .opacity(running ? 0 : 1)
                    .accessibilityHidden(running)
                if case .running(let cancel, let progress) = header {
                    HStack(spacing: 6) {
                        if let progress {
                            Text(progress.text)
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        ProgressView().controlSize(.small)
                        BrewUpgradeCancelButton(cancel: cancel, jobID: AppListModel.upgradeAllJobID, model: model)
                    }
                }
            }
            // The rest of a double-click on Upgrade All is not a click on its Cancel.
            .swallowsClicksAfterSwap(of: running)
        }
    }
}
