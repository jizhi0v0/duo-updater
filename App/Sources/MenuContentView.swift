import SwiftUI
import AppKit
import DuoUpdaterCore

/// Carries the measured height of the popover's update list up to the frame, so it
/// can hug its content instead of guessing a per-row height.
/// The tool groups' page's own height: its header's and its rows', summed.
struct ToolsPageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum MenuLayoutMetrics {
    static let width: CGFloat = 370

    // AppRow's fit threshold was measured at the original 360pt popover width.
    // Carry any future width change into that budget instead of leaving the row
    // logic calibrated to stale geometry.
    private static let calibratedWidth: CGFloat = 360
    static let appRowFitBudget: CGFloat = 260 + (width - calibratedWidth)
}

struct MenuContentView: View {
    @Bindable var model: AppListModel
    @State private var showAll = false
    /// A row the list should scroll to once it is drawn — the failed-check
    /// banner's click (`showFailedRows`). Cleared when the scroll is done.
    @State private var scrollTarget: String?
    /// Popover filter text. When non-empty it overrides the pending/Show-all split
    /// and searches across *every* app, so an up-to-date app is still findable.
    @State private var searchText = ""
    /// Measured height of the visible update list, so the popover hugs its content
    /// exactly (capped at 380) instead of overshooting with a per-row estimate.
    @State private var listContentHeight: CGFloat = 0
    /// The tool groups' page (`ToolsPage`) stands in the app list's place.
    /// Not remembered: the popover's view tree outlives its window, so it is
    /// reset each time the popover closes (`onDisappear`).
    @State private var toolsPageOpen = false
    /// The page's height, taken as it opens (`setToolsPage`) and held while
    /// it is open, so its search filters rows without resizing the popover.
    @State private var toolsPageOpenHeight: CGFloat = 200
    /// What the page's own rows need (`ToolsPageHeightKey`), measured while it
    /// waits off to the side.
    @State private var toolsPageContentHeight: CGFloat = 0
    /// The page's own search, which the one field edits while the page is
    /// open, kept as the apps' is. The apps' search is never touched: clearing it as the page
    /// opened, and putting it back as it closed, changed the list in the
    /// middle of the slide — "No Results" cross-fading with the rows, left
    /// drawn over both (owner, 2026-10-24).
    @State private var toolsSearchText = ""
    /// The groups the page opened with, in that order (`ToolsPage.held`).
    /// Taken as it opens and dropped once it has slid out, so the closed page
    /// — whose height the next open is measured from — draws the rows that
    /// open will: kept from the last open, a group whose update had ended was
    /// measured, then dropped, leaving a row's height blank (review, round 8).
    @State private var toolsPageHeld: [String]?
    @Environment(\.openWindow) private var openWindow

    /// Opens or closes the tool groups' page, sliding it in from the right
    /// over the app list and back out — a level below "Other tools", as its
    /// header says. The search field stays where it is and searches whatever
    /// is shown, each side with its own text, kept (`toolsSearchText`).
    private func setToolsPage(_ open: Bool) {
        if open {
            // The page's own height, up to the cap, whatever the app list's:
            // held at a taller list's, a page of a few groups opened over
            // blank space (owner, 2026-10-24: "the stable height looks like a
            // bug"); squeezed to a shorter one's, it showed half a row. The
            // list's height stands in until the page has measured itself.
            let own = toolsPageContentHeight > 0 ? toolsPageContentHeight : toolsPageHeight
            toolsPageOpenHeight = min(Self.maxListHeight, own)
            toolsPageHeld = ToolsPage.entries(model.cliTools).map(\.id)
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            toolsPageOpen = open
        } completion: {
            // Not while sliding out: a row leaving then moved the rest.
            if !toolsPageOpen { toolsPageHeld = nil }
        }
    }

    /// Whether the user is actively filtering — drives the search-across-all
    /// behavior and the "no matches" empty state.
    private var isSearching: Bool {
        !SearchMatch.trimmed(searchText).isEmpty
    }

    private var visible: [UpdateResult] {
        // The apps an interrupted install left gone first: they have no scanned
        // row, and the way back is the most urgent thing the list offers.
        let standIns = model.interruptedStandIns
        // While searching, look across every app (not just pending ones): typing a
        // name should find an up-to-date app too, not come back empty.
        if isSearching {
            let query = SearchMatch.trimmed(searchText)
            return (standIns + model.results).filter { matches($0, query) }
        }
        return standIns + (showAll ? model.results
            : model.results.filter {
                // The same predicate the menu-bar badge counts, so what the list
                // shows and what the badge says can't drift apart — everything below
                // it is a transient state that belongs on screen but not in a count.
                model.needsAction($0)
                    // Hold a just-completed row for its brief "Updated ✓" beat, even
                    // though it's no longer an actionable update, before it drops out.
                    || model.justUpdated.contains($0.id)
                    // Work still in flight on this row. Without these it drops out the
                    // instant `recheck` publishes the new, now up-to-date version —
                    // which lands *before* `computeRestartInfo`'s lsappinfo sweep has
                    // granted it a restart ticket. For a single pending update that
                    // empties the list, so the "Everything is up to date" placeholder
                    // and its fixed 200pt frame flash in for the length of that sweep
                    // before the row jumps back as "Relaunching…".
                    || model.installing[$0.id] != nil
                    || model.relaunching.contains($0.id)
                    // Cut off by an earlier update: it offers Restore whatever
                    // its check says (`RowActionState.interruptedInstall`).
                    || model.interruptedInstall(for: $0) != nil
            })
    }

    /// Match the query against an app's name and bundle id (so "com.google" finds
    /// Chrome), by the rule every search field shares — the workbench's and the
    /// Settings sidebar's too (`SearchMatch`: case, diacritics and width folded).
    private func matches(_ result: UpdateResult, _ query: String) -> Bool {
        SearchMatch.matches(query, in: [result.app.name, result.app.bundleID])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.needsAccessibilitySetup {
                setupBanner
                Divider()
            }
            if model.gitHubTokenRejected {
                tokenRejectedBanner
                Divider()
            }
            if showRateLimitBanner {
                rateLimitBanner
                Divider()
            }
            if showCheckFailureBanner {
                checkFailureBanner
                Divider()
            }
            // One field for both: it keeps its place when the page opens, so
            // nothing below it moves (2026-10-24: hidden on the page, every row
            // shifted by its height).
            if showsSearchField {
                AppSearchField(
                    text: toolsPageOpen ? $toolsSearchText : $searchText,
                    prompt: toolsPageOpen ? String(localized: "Search tools") : String(localized: "Search apps"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            // The tool groups' page stands in the list's place, at its own
            // height (`setToolsPage`).
            // Both stay in the tree and slide by offset, side by side. With an
            // insertion and a removal instead, quick clicks left the views of
            // interrupted slides drawn over each other until each finished —
            // "Checking…" over the groups' rows, recorded on a cold launch on
            // 2026-10-24 — and the placeholder showed through the page.
            // One strip of the two, moved as one: offset apart, the
            // placeholder kept still while the page slid over it.
            content
                .frame(width: MenuLayoutMetrics.width)
                .allowsHitTesting(!toolsPageOpen)
                .accessibilityHidden(toolsPageOpen)
                .frame(height: toolsPageOpen ? toolsPageOpenHeight : nil, alignment: .top)
                // An overlay, so the closed page adds nothing to the height.
                .overlay(alignment: .topLeading) {
                    ToolsPage(tools: model.cliTools, held: toolsPageHeld, height: toolsPageOpenHeight,
                              // Its own search: the apps' filtered the closed page
                              // down to its header, and the page measured that
                              // (31 pt) as its height.
                              query: toolsSearchText,
                              close: { setToolsPage(false) },
                              show: { tag in
                                  model.requestedWorkbenchCLITool = tag
                                  openWindow(id: WorkbenchWindowView.windowID)
                                  model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
                              })
                        .frame(width: MenuLayoutMetrics.width)
                        .onPreferenceChange(ToolsPageHeightKey.self) { toolsPageContentHeight = $0 }
                        .allowsHitTesting(toolsPageOpen)
                        .accessibilityHidden(!toolsPageOpen)
                        .alignmentGuide(.leading) { _ in -MenuLayoutMetrics.width }
                }
                .offset(x: toolsPageOpen ? -MenuLayoutMetrics.width : 0)
                .frame(width: MenuLayoutMetrics.width, alignment: .leading)
                .clipped()
            if showCommandLineRow {
                Divider()
                // Target first, then open — the Changelog deep link's order.
                CommandLineRow(
                    model: model,
                    showInWindow: {
                        model.requestedWorkbenchCLITools = true
                        openWindow(id: WorkbenchWindowView.windowID)
                        model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
                    },
                    showHomebrew: {
                        model.requestedWorkbenchHomebrew = true
                        openWindow(id: WorkbenchWindowView.windowID)
                        model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
                    },
                    showBrewUnchecked: {
                        model.requestedWorkbenchBrewUnchecked = true
                        openWindow(id: WorkbenchWindowView.windowID)
                        model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
                    },
                    toolsPageOpen: toolsPageOpen,
                    toggleToolsPage: { setToolsPage(!toolsPageOpen) })
            }
            Divider()
            footer
        }
        .frame(width: MenuLayoutMetrics.width)
        .onDisappear {
            toolsPageOpen = false
            toolsPageHeld = nil
        }
        .task {
            // Take activation the moment the popover appears, because otherwise the
            // user's first click inside it is spent doing exactly that.
            //
            // A MenuBarExtra popover opens WITHOUT its app becoming active —
            // measured: the panel is on screen at layer 101 while
            // `frontmostApplication` still reads the app the user came from. The
            // first interaction then goes into activating us instead of doing what
            // it was aimed at, and the row menu it opened is dismissed with the
            // action never running. From the second interaction on everything works,
            // which is the whole shape of the bug that was reported: the first
            // Changelog does nothing, a second click on any row opens it, and
            // reopening the popover makes every attempt "the first" again. It also
            // explains why having any window already open hid it — with a window up
            // the app is already active, so no click is spent on activation.
            //
            // The cost, accepted deliberately: clicking the menu bar icon now takes
            // focus from whatever you were in, and if a DuoUpdater window is parked
            // on another Space, macOS may follow it there — so a peek at the popover
            // from a fullscreen app can leave fullscreen. The alternative, deferring
            // activation until the first interaction, is the bug above wearing a
            // different hat: that interaction is the one that gets eaten. Fullscreen
            // plus a window on another Space is a narrower case than "the first
            // click never works", which was every click.
            NSApp.activate(ignoringOtherApps: true)

            model.refreshPermissionStatus()
            // One-time wiring: arm the background-check loop and teach the
            // notification's "View" action how to open the window.
            model.start(showUpdates: {
                openWindow(id: WorkbenchWindowView.windowID)
                model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
            })
            // Every lane decides what an open calls for (`AppListModel.refreshes`):
            // the apps a full check on the first open, or while TestFlight is
            // still owed a read, and otherwise a cheap rescan that catches
            // background self-updates and surfaces Restart
            // (`AppsRefreshPolicy`); brew and the other tools beside it. Waits
            // for the apps only.
            await model.refreshes.handle(.popoverOpen, waitingFor: model.appsLane)
            // After the check, so the rows it names are this open's rows.
            model.offerFullDiskAccessIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        // `isRoundInFlight`, not `isScanning`: a user-present refresh clears the
        // saved release notes BEFORE it raises `isScanning`, and that await lets
        // a cold launch paint here with no rows yet — which read "No apps yet"
        // over a scan that was about to start (#253's gap, one surface over).
        switch PopoverListContent.decide(
            hasRows: !model.results.isEmpty,
            visibleIsEmpty: visible.isEmpty,
            isSearching: isSearching,
            isRoundInFlight: model.listActivity.isRoundInFlight,
            answeredThisLaunch: model.answeredThisLaunch,
            failedCheckCount: model.failedCheckCount
        ) {
        case .scanning:
            placeholder(String(localized: "Scanning…"), systemImage: "magnifyingglass")
        case .noApps:
            placeholder(String(localized: "No apps yet"), systemImage: "magnifyingglass")
        case .checking:
            // Same icon and frame as "Scanning…", which it follows, so the
            // placeholder changes its word and nothing else.
            placeholder(String(localized: "Checking…"), systemImage: "magnifyingglass")
        case .noMatches:
            ContentUnavailableView.search(text: searchText)
                .frame(height: 200)
        case .noUpdatesFound:
            // Same rule as `statusLine`: with unanswered rows this is not a
            // "clean run" screen, and the seal is the strongest success signal
            // in the whole popover.
            placeholder(String(localized: "No updates found"), systemImage: "questionmark.circle",
                        description: Text("Some apps could not be checked — see above."))
        case .upToDate:
            placeholder(String(localized: "Everything is up to date"), systemImage: "checkmark.seal.fill",
                        description: Text("Toggle “Show all” to see every app."))
        case .rows:
            rowList
        }
    }

    /// An empty list's placeholder. Its icon is fitted to one box, so every
    /// state draws it the same size: at the system's size the glyphs' own
    /// proportions differed — the magnifier 34 pt across, the seal 39
    /// (rendered at 370 × 200, 2026-10-24). In a 41 pt box each measures
    /// 39–40, the seal as before.
    private func placeholder(_ title: String, systemImage: String, description: Text? = nil) -> some View {
        ContentUnavailableView {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage).resizable().scaledToFit().frame(width: 41, height: 41)
            }
        } description: {
            description
        }
        .frame(height: 200)
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            scrollingRows(proxy)
        }
    }

    /// Scrolls to `scrollTarget` once this scroll view is drawn. On each of the
    /// two below, not around both: turning "Show all" on usually swaps the short
    /// list for the long one, and the task goes with the one that leaves, so the
    /// scroll lands in the one that is drawn.
    private func scrollingToTarget(_ list: some View, _ proxy: ScrollViewProxy) -> some View {
        list.task(id: scrollTarget) {
            guard let id = scrollTarget else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation { proxy.scrollTo(id, anchor: .top) }
            scrollTarget = nil
        }
    }

    @ViewBuilder
    private func scrollingRows(_ proxy: ScrollViewProxy) -> some View {
        if listOverflows {
            // Long enough that it scrolls no matter how the rows measure, so there
            // is nothing left for the measurement below to decide: pin the frame and
            // let a LazyVStack realize only the rows actually on screen.
            //
            // This is the "Show all" list, and sizing all of it through the non-lazy
            // stack was the popover's one real stall: a 127-app list spent ~880ms of
            // main-thread layout inside `ScrollViewLayoutComputer → StackLayout`
            // asking every row for its size (sample, 2026-08-23) — on every toggle,
            // not just the first.
            scrollingToTarget(ScrollView {
                LazyVStack(spacing: 0) { rows }
            }, proxy)
            .frame(height: Self.maxListHeight)
        } else {
            scrollingToTarget(ScrollView {
                // Plain VStack (not lazy) so the background GeometryReader measures
                // the *full* content height — a LazyVStack only reports realized rows,
                // which would feed back a too-short frame. Only reached for lists too
                // short to fill the cap, so sizing every row is cheap here.
                VStack(spacing: 0) { rows }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                    })
            }, proxy)
            // Hug the measured content exactly, capped at 380 (then it scrolls). Using
            // the true height — not a per-row estimate — means no dead space at the
            // bottom for short lists. 54 is just the pre-measurement placeholder.
            .frame(height: min(Self.maxListHeight, listContentHeight == 0 ? 54 : listContentHeight))
            .onPreferenceChange(ListHeightKey.self) { listContentHeight = $0 }
        }
    }

    /// Tallest the list gets before it scrolls.
    private static let maxListHeight: CGFloat = 380

    /// The app list's height as it stands — its placeholders' 200, or the
    /// rows' measured height up to the cap: the page's until it has measured
    /// its own.
    private var toolsPageHeight: CGFloat {
        if visible.isEmpty { return 200 }
        if listOverflows { return Self.maxListHeight }
        return min(Self.maxListHeight, listContentHeight == 0 ? 54 : listContentHeight)
    }

    /// Only worth showing once the list is long enough to be hard to scan;
    /// stays put while a query is active even if it filters down to a few.
    private var showsSearchField: Bool { model.results.count > 8 || isSearching }

    /// Shortest a row can possibly be: the 30pt icon plus its 7pt vertical padding.
    /// A row with an install error or a note is taller, which only makes the list
    /// overflow sooner — so this stays a lower bound in the safe direction.
    ///
    /// The row's own height, not a second copy of it. `AppRow` declares that number
    /// (see `plainRowHeight`), and the two are not independent: this one has to be a
    /// FLOOR on it, so a row height lowered here-but-not-there would make
    /// `listOverflows` claim a short list overflows and pin the frame at
    /// `maxListHeight` with dead space under the last row.
    private static let minRowHeight: CGFloat = AppRow.plainRowHeight

    /// Whether the list must scroll whatever the rows measure. `count * minRowHeight`
    /// is a floor on the content height, so this is only ever true when it genuinely
    /// overflows — never a guess that hides rows behind a too-short frame.
    private var listOverflows: Bool {
        CGFloat(visible.count) * Self.minRowHeight >= Self.maxListHeight
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(Array(visible.enumerated()), id: \.element.id) { index, result in
            // Divider *between* rows only — a trailing one after the last row left
            // a dangling line floating over the empty space below a short list.
            if index > 0 { Divider() }
            AppRow(result: result, model: model)
        }
    }

    /// Shown when the incremental App Store route is selected but Accessibility isn't
    /// granted and an App Store update is actually waiting on it — a contextual nudge
    /// for users who skipped onboarding, routing back to the setup window.
    private var setupBanner: some View {
        Button {
            openWindow(id: WelcomeView.windowID)
            model.surfaceWindow(sceneID: WelcomeView.windowID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility needed").font(.caption).fontWeight(.medium)
                    Text("App Store updates need it — finish setup")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.orange.opacity(0.08))
    }

    /// How many rows failed this cycle with a GitHub rate-limit error: app rows,
    /// and the command-line tools whose channel is the GitHub API (bun, OpenCode,
    /// herdr), which spend the same hourly budget.
    private var rateLimitedCount: Int {
        model.results.filter(\.status.isRateLimitError).count
            + model.cliTools.statuses.filter(\.isRateLimitError).count
    }

    /// Show the aggregate nudge only when several apps are rate-limited at once
    /// and no token is configured. A single transient stays a per-row retry, but
    /// a cluster means the unauthenticated 60/hour cap is biting and a token is
    /// the real fix. Not while GitHub is rejecting the token there is: that
    /// banner is the fix to make first.
    ///
    /// And whenever GitHub's budget is closed with a row it stopped, token or
    /// not: then nothing is asked until it reopens (`GitHubRateLimitGate`), and
    /// the banner says when — where the generic banner below would offer a
    /// Retry that cannot be sent.
    private var showRateLimitBanner: Bool {
        if model.gitHubPausedUntil != nil, rateLimitedCount >= 1 { return true }
        return !model.gitHubTokenRejected && !model.hasGitHubToken && rateLimitedCount >= 2
    }

    /// Show the "couldn't be checked" banner whenever any row errored — except when
    /// the rate-limit banner above is already accounting for every one of them. That
    /// banner is the more specific answer (add a token), so stacking a generic
    /// "retry" underneath it in this compact popover would only cost room.
    ///
    /// Suppressed for the whole round, via `isRefreshing` rather than
    /// `isScanning`/`isChecking`: rows carry the previous cycle's `.error` until the
    /// new answer replaces them, and those two flags leave a gap between them (the
    /// TestFlight read, up to 2s) where both are false and the stale errors are still
    /// on screen — the banner flashed in and out on every refresh, which is exactly
    /// what this was meant to prevent.
    private var showCheckFailureBanner: Bool {
        guard model.failedCheckCount > 0, !model.isRefreshing else { return false }
        // Never stack with the rate-limit banner. That one is the more specific
        // answer to the same rows (add a token) and wears the same orange triangle
        // and tint; two of them would state one problem twice, with two different
        // numbers, and the generic subtitle would just echo the rate-limit message
        // (`failedCheckSummary` reports the modal error, which is that one whenever
        // rate-limits dominate). Deliberately not the `==` it used to be: a cluster of
        // rate-limits plus one unrelated DNS failure is the common case, not the
        // exception, and it is the one where they doubled up.
        if showRateLimitBanner { return false }
        return true
    }

    /// The one thing a failed check has to do: not look like a successful one.
    ///
    /// `.error` rows are hidden unless "Show all" is on and the header counts only
    /// actionable updates, so a round where every source failed used to render as
    /// "127 apps · up to date" — see `AppListModel.failedCheckResults`. This says how
    /// many rows we have no answer for, names the error most of them share, and
    /// re-checks just those rows rather than everything.
    ///
    /// It also names them (#1622: a count alone left the reader to find the app
    /// by scrolling), and clicking the text shows them: "Show all" on, since
    /// that is the only list `.error` rows are in, and scrolled to the first.
    private var checkFailureBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: showFailedRows) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(model.failedCheckCount) apps could not be checked")
                            .font(.caption).fontWeight(.medium)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        // The chevron the popover's other clickable banners
                        // carry, here rather than at the edge, where Retry is.
                        HStack(spacing: 3) {
                            Text(verbatim: failedAppNames)
                                .lineLimit(1).truncationMode(.tail)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.caption2)
                        Text(model.failedCheckSummary ?? String(localized: "Every update source failed"))
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show these apps in the list")
            .layoutPriority(1)
            Spacer()
            if model.isRetryingFailedChecks {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.retryFailedChecks() }
                } label: {
                    HStack(spacing: 3) {
                        Text("Retry")
                        Text("\(model.failedCheckCount)").monospacedDigit()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .help("Check these apps again — the settled rows are left alone")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    /// "Zed, VLC, and 3 more", in list order (`CheckFailureRules.bannerNames`).
    private var failedAppNames: String {
        let (named, more) = CheckFailureRules.bannerNames(model.failedCheckResults.map(\.app.name))
        let items = more > 0 ? named + [String(localized: "\(more) more")] : named
        return ListFormatter.localizedString(byJoining: items)
    }

    /// The banner's click: everything that would keep the failed rows off the
    /// list goes (the tool groups' page, a search, "Show all" off), then the
    /// list scrolls to the first of them (`rowList`).
    private func showFailedRows() {
        if toolsPageOpen { setToolsPage(false) }
        searchText = ""
        showAll = true
        scrollTarget = model.failedCheckResults.first?.id
    }

    /// GitHub answered the token with a 401 and the check carried on without it
    /// (`AppListModel.gitHubTokenRejected`). Deep-links to the token, as the
    /// rate-limit banner does.
    private var tokenRejectedBanner: some View {
        Button {
            model.requestedSettingsSection = .github
            model.requestedSettingsAnchor = .githubToken
            openWindow(id: SettingsView.windowID)
            model.surfaceWindow(sceneID: SettingsView.windowID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GitHub rejected your token").font(.caption).fontWeight(.medium)
                    Text("Update or remove it in Settings")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.orange.opacity(0.08))
    }

    /// Aggregate counterpart to the per-row "Rate-limited" badge: one tap
    /// deep-links to Settings → GitHub to add a token (60/hour → 5000/hour).
    /// With the budget closed, when checking resumes — and the token to add
    /// when there is none; otherwise the token to add.
    private var rateLimitBannerDetail: String {
        guard let until = model.gitHubPausedUntil else {
            return String(localized: "\(rateLimitedCount) items couldn’t be checked — add a token")
        }
        let time = until.formatted(date: .omitted, time: .shortened)
        return model.hasGitHubToken
            ? String(localized: "\(rateLimitedCount) items wait until \(time), when GitHub takes requests again")
            : String(localized: "\(rateLimitedCount) items wait until \(time) — or add a token")
    }

    private var rateLimitBanner: some View {
        Button {
            model.requestedSettingsSection = .github
            model.requestedSettingsAnchor = .githubToken
            openWindow(id: SettingsView.windowID)
            model.surfaceWindow(sceneID: SettingsView.windowID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hitting GitHub’s rate limit").font(.caption).fontWeight(.medium)
                    Text(rateLimitBannerDetail)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.orange.opacity(0.08))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("DuoUpdater")
                        .font(.system(size: 16, weight: .medium))
                    if let version = AppListModel.runningSelfVersion {
                        // The version and the sparkles are ONE button, not a label
                        // beside a 10pt glyph. Since the self-update banner went
                        // away this is the only route into the notes anywhere in
                        // the app, and a lone sparkle that small reads as
                        // decoration; the version number is the natural thing to
                        // click for "what changed", and taking both roughly
                        // triples the hit target.
                        Button {
                            openWindow(id: SelfChangelogView.windowID)
                            model.surfaceWindow(sceneID: SelfChangelogView.windowID)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("v\(version)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "sparkles")
                                    .foregroundStyle(model.silentSelfUpdate == nil ? Color.secondary : Color.yellow)
                            }
                            // Baseline-aligned rather than nudged: a symbol has a
                            // text baseline of its own, so this lands the sparkle
                            // on the version's without a hand-tuned offset.
                            .font(.system(size: 10))
                            .fixedSize()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("What's New — DuoUpdater's own release notes")
                        .accessibilityLabel("What's New")
                    }
                }
                .padding(.top, 2)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        Task { await model.refreshes.handle(.manual) }
                    } label: {
                        // Keep both refresh states in the same 16pt layout box.
                        Group {
                            if model.listActivity.isRoundInFlight {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.72)
                                    .offset(y: 1)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canRefresh)
                    .help("Rescan and check for updates")
                    Button {
                        openWindow(id: SettingsView.windowID)
                        model.surfaceWindow(sceneID: SettingsView.windowID)
                    } label: {
                        Image(systemName: "gearshape")
                            .padding(.top, 5)
                            // A setting added by an update the user has just taken.
                            // The dot lives on the way IN to Settings, because a
                            // dot only on the control itself would be behind a
                            // window nobody has a reason to open.
                            .overlay(alignment: .topTrailing) {
                                if !model.prefs.pendingSpotlights.isEmpty {
                                    SpotlightDot(size: 5).offset(x: 3, y: 3)
                                }
                            }
                    }
                    .buttonStyle(.borderless)
                    .help(model.prefs.pendingSpotlights.isEmpty
                          ? String(localized: "Settings")
                          : String(localized: "Settings — something new in here"))
                }
                .font(.system(size: 13))
                .offset(y: -1)
            }
            .padding(.top, 10)

            HStack(alignment: .top, spacing: 8) {
                // One line, at full size, truncating when it must. The slot is
                // whatever the Update All button leaves — expressed as a frame,
                // not as a trailing `Spacer`.
                //
                // Both halves of that matter, and they pull opposite ways.
                // `fixedSize` made the line DEMAND its ideal width, so when the
                // line outgrew the slot nothing gave: the whole header — title
                // included — slid left and the button hung past the popover's
                // edge (reproduced in es and fr by pushing the count to four
                // digits). But a greedy `Spacer` at the same priority as the text
                // takes room the line still wants, which clipped fr and es at six
                // updates with the button's own width sitting unused beside them.
                // A `fixedSize` button plus `maxWidth: .infinity` here serves the
                // button its ideal first and hands the line exactly the rest,
                // where `lineLimit` truncates instead of overflowing. Verified in
                // all eleven shipped languages: nothing truncates at realistic
                // counts, and the four-digit case ends in an ellipsis inside the
                // popover instead of over its edge. The tooltip carries the whole
                // line either way.
                Text(statusLine)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(Text(statusLine))
                // One view for the slot, so the guard sees Update All and Cancel
                // All take turns: the second click of a double-click on Update
                // All was Cancel All on the batch it had just started.
                ZStack {
                    if model.isInstallingAll {
                        // Update All's own slot while it runs (§6). Disabled once
                        // clicked, saying so, until the batch has ended.
                        Button(cancelAllTitle) {
                            model.cancelInstallAll()
                        }
                        .lineLimit(1)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(model.isCancellingAll)
                        .help("Stop Update All: updates that haven’t started are dropped, and ones already installing finish")
                    } else if model.isStartingInstallAll || model.canUpdateAll {
                        // Greyed from the click until the batch claims its rows.
                        Button("Update All") { Task { await model.installAll() } }
                            .lineLimit(1)
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(model.isStartingInstallAll)
                            .help("Install every pending update that can be applied automatically")
                    } else {
                        Color.clear.frame(width: 0, height: 20)
                    }
                }
                // The apps' button: over the tool groups' page it read as that
                // page's. Kept in its place, so the line beside it doesn't move.
                .opacity(toolsPageOpen ? 0 : 1)
                .allowsHitTesting(!toolsPageOpen)
                .accessibilityHidden(toolsPageOpen)
                .swallowsClicksAfterSwap(of: model.isInstallingAll)
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
        }
        .padding(.horizontal, 12)
    }

    /// Cancel All's title. Once clicked it follows the rows as they draw
    /// (`AppListModel.cancelAllPhase`): greyed as it was while a cancel has not
    /// lasted long enough for the rows to say so, "Cancelling…" while one is
    /// being stopped, and "Finishing…" once all that is left is installs past
    /// the point a cancel can reach, which run to their end.
    private var cancelAllTitle: String {
        guard model.isCancellingAll else { return String(localized: "Cancel All") }
        switch model.cancelAllPhase ?? .pending {
        case .pending: return String(localized: "Cancel All")
        case .cancelling: return String(localized: "Cancelling…")
        case .finishing: return String(localized: "Finishing…")
        }
    }

    private var statusLine: String {
        // `isRefreshing`, not `isChecking`: the scan leg and the TestFlight read come
        // first, and during those the line below would report the PREVIOUS round's
        // unanswered rows as if they were this round's verdict.
        let base = statusBaseLine
        if model.isRefreshing { return base }
        // The timestamp joins on with a separator and no verb. "checked" was a
        // word the relative time already implies, and it cost more room than the
        // header has: translated, the line ran 247pt against the 167pt left over
        // once "Обновить всё" had taken its width, so the half that says *when*
        // was the half being cut off. Nothing to translate in " · ", so this is
        // plain interpolation rather than a key with no words in it.
        if let last = model.lastCheck {
            return "\(base) · \(Self.checkedAgo(last))"
        }
        return base
    }

    private var statusBaseLine: String {
        if model.isRefreshing {
            return String(localized: "Checking \(model.results.count) apps…")
        }
        // `actionCount`, not `updateCount`: an app whose new version is on disk and
        // only needs a relaunch HAS an update — it just already downloaded it — so
        // it is counted here rather than given a line of its own. That also makes
        // this number, the badge, and the number of rows below the same number,
        // which is the whole point. (A separate "nearly up to date · N to relaunch"
        // clause was measured instead and abandoned: with Update All beside it the
        // line has 224-274pt depending on the language's button, Spanish already
        // sits 9pt from truncation at two updates, and the appended half is exactly
        // what the tail truncation eats.)
        let updates = model.actionCount
        let failed = model.failedCheckCount
        // "up to date" is a claim about every app, and it is only true when every
        // app actually answered. With rows still in `.error` the honest line names
        // them instead — the banner above carries the reason and the retry.
        if updates > 0 {
            return String(localized: "\(updates) updates available")
        }
        if failed > 0 {
            return String(localized: "\(failed) of \(model.results.count) apps not checked")
        }
        return String(localized: "\(model.results.count) apps · up to date")
    }

    /// "just now" / "2m ago". Guards the just-finished case: the
    /// relative formatter rounds a sub-second (or microscopically future, from
    /// clock jitter) interval to "in 0 seconds", which read as a wrong-tense
    /// "checked in 0s" right after a refresh. Anything within a few seconds is
    /// "just now"; older falls back to the relative formatter.
    private static func checkedAgo(_ date: Date) -> String {
        if date.timeIntervalSinceNow > -5 { return String(localized: "just now") }
        let abbreviated = relative.localizedString(for: date, relativeTo: .now)
        // CLDR spells the narrow past form as a signed number in some locales:
        // Russian renders "7 seconds ago" as "-7 с" and French as "-7 s", where
        // English gets "7s ago". Dropped into "checked …" that reads as a
        // negative count, so those locales fall through to the next style up,
        // which spells the direction out ("7 сек. назад", "il y a 7 s"). Every
        // locale whose narrow form already reads as elapsed time keeps it —
        // English, German, Spanish, Chinese and Japanese are untouched.
        guard abbreviated.hasPrefix("-") || abbreviated.hasPrefix("\u{2212}") else { return abbreviated }
        return spelledOut.localizedString(for: date, relativeTo: .now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// The fallback for locales whose abbreviated form comes out signed.
    private static let spelledOut: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var footer: some View {
        HStack {
            Toggle("Show all", isOn: $showAll)
                .toggleStyle(PopoverCheckboxStyle())
                .font(.caption)
            Spacer()
            Button {
                openWindow(id: ReleaseLogView.windowID)
                model.surfaceWindow(sceneID: ReleaseLogView.windowID)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Release Log — when the apps you track shipped each version")
            Button {
                openWindow(id: NetworkWindowView.windowID)
                model.surfaceWindow(sceneID: NetworkWindowView.windowID)
            } label: {
                Image(systemName: "chart.bar")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help(footerTrafficHelp)
            Button {
                openWindow(id: WorkbenchWindowView.windowID)
                model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Open Window — release notes and settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footerTrafficHelp: String {
        let title = String(localized: "Network — what keeping these apps updated has cost, and every request behind it")
        guard let month = model.trafficSummary.calendarMonths(1).last, month.bytes > 0 else {
            return title
        }
        // The figure that used to sit in the footer, now that the row is icons
        // only. A localized key rather than interpolated English: the separator
        // has nothing to translate, but "downloaded this month" does — and each
        // locale wants its own punctuation around the number (fr's space before
        // the colon, zh's full-width one).
        let figure = String(localized: "Downloaded this month: \(ByteFormat.string(month.bytes))")
        return "\(title) · \(figure)"
    }

    /// Reserve the command-line row as soon as either half has something to show:
    /// Homebrew installed — always, even when nothing's outdated, so the row never
    /// inserts or removes under the cursor as counts change — or an install of
    /// another tool. The launch scan (`CLIToolsModel.scanInstalls`, local and fast)
    /// answers that long before the networked check, so the check lands in a row
    /// that is already there. Neither, no row.
    private var showCommandLineRow: Bool {
        model.brewInstalled || !model.cliTools.sightings.isEmpty
    }
}

/// The footer's "Show all" box. AppKit's `.checkbox` draws its unchecked box as a
/// dark fill with no edge, which on the popover's glass measured 1.36:1 against
/// the background (2026-10-21) — the box all but vanished. An outlined square drawn
/// as the footer's icon buttons are measured 5.80:1, level with them.
private struct PopoverCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            // Only the box is a borderless button, so AppKit draws it as it draws
            // the footer's icon buttons; the label inside it would dim with it.
            Button {
                configuration.isOn.toggle()
            } label: {
                if configuration.isOn {
                    Image(systemName: "checkmark.square.fill")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "square")
                        .imageScale(.large)
                }
            }
            .buttonStyle(.borderless)
            configuration.label
                .contentShape(Rectangle())
                .onTapGesture { configuration.isOn.toggle() }
        }
        // Still a checkbox to VoiceOver and to AX scripts that press it.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

/// The groups under "Other tools", on a page of the popover in the app list's
/// place, opened by the chevron beside "Other tools": one row per group with
/// something to say — an update, a run, a failure — as the workbench draws them
/// (`CLIToolPresentation.groups`): Claude Code, npm · nvm, mise tools. Each has
/// its own Update and Cancel over its copies only (`CLIToolsModel.rowSnapshot(in:)`);
/// "Other tools" below keeps Update All. It opens at its own height, up to the app
/// list's cap (`MenuContentView.setToolsPage`), so the popover fits the groups
/// while it is open; past the cap the page scrolls. The height holds while it is
/// open: its search filters rows without resizing the popover.
struct ToolsPage: View {
    let tools: CLIToolsModel
    /// The groups the page opened with, in that order: they keep their rows
    /// until it closes — one whose update ended says so on its line — so a row
    /// never leaves from under the pointer: when mise tools' row went at the
    /// end of its update, the page, scrolled to its end, jumped 34 pt (recorded
    /// 2026-10-24). Nil while closed; the popover owns it
    /// (`MenuContentView.toolsPageHeld`).
    let held: [String]?
    let height: CGFloat
    /// The popover's search field, which searches the groups here: a group's
    /// name or one of its tools' ("node" finds mise tools).
    let query: String
    let close: () -> Void
    /// Opens the workbench on a copy (its tag), from a row's right-click menu,
    /// as the app rows' Changelog does.
    let show: (String) -> Void

    /// One group's row: who it is and its snapshot.
    struct Entry: Identifiable {
        let id: String
        let title: String
        let statuses: [CLIToolStatus]
        let scope: Set<CLIToolID>
        let snapshot: CLIRowSnapshot<CLIToolID>
    }

    /// The groups with work, and those `keeping` names whatever they say now,
    /// in `keeping`'s order first, then the rest: managers' groups, then the
    /// single tools'.
    @MainActor static func entries(_ tools: CLIToolsModel, keeping: [String] = []) -> [Entry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let kept = Set(keeping)
        // The managers' groups first, as the workbench draws their levels
        // above "Other tools" (owner, 2026-10-24): one manager and its many
        // packages, as Homebrew is.
        let groups = CLIToolPresentation.groups(tools.statuses)
        let ordered = groups.filter { $0.manager != nil } + groups.filter { $0.manager == nil }
        let entries: [Entry] = ordered.compactMap { group in
            let scope = Set(group.statuses.map(\.toolID))
            let snapshot = tools.rowSnapshot(in: scope)
            guard kept.contains(group.id) || snapshot.tools.contains(where: {
                $0.phase != .idle || $0.error != nil || $0.state == .updateAvailable
            }) else { return nil }
            let title = group.prefix.map { "\(group.title) · \(CLIToolPresentation.prefixLabel($0, home: home))" }
                ?? group.title
            return Entry(id: group.id, title: title, statuses: group.statuses, scope: scope, snapshot: snapshot)
        }
        return CLIToolPresentation.holding(entries, to: keeping.isEmpty ? nil : keeping, id: \.id)
    }

    /// A part's height into `ToolsPageHeightKey`, which sums the parts.
    private static var measured: some View {
        GeometryReader { Color.clear.preference(key: ToolsPageHeightKey.self, value: $0.size.height) }
    }

    /// Whether the chevron has a page to open.
    @MainActor static func hasGroups(_ tools: CLIToolsModel) -> Bool { !entries(tools).isEmpty }

    var body: some View {
        let entries = Self.entries(tools, keeping: held ?? [])
        let trimmed = SearchMatch.trimmed(query)
        let shown = trimmed.isEmpty ? entries : entries.filter { entry in
            SearchMatch.matches(trimmed, in: [entry.title] + entry.statuses.compactMap(\.name))
        }
        VStack(spacing: 0) {
            // Where the page sits: under "Other tools", whose row below stays
            // marked while it is open. The back chevron leads, as in a menu's
            // submenu turned into a page.
            Button(action: close) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                    Text("Other tools").fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Hide groups"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Self.measured)
            Divider().background(Self.measured)
            if shown.isEmpty, !trimmed.isEmpty {
                // In the list's place, as the app list does. Over an emptied
                // scroll view it drew nothing, and the popover's whole
                // accessibility tree read empty (2026-10-24).
                ContentUnavailableView.search(text: trimmed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { rows(shown) }
            }
        }
        // The height it opens at is every row's, whatever its search holds
        // (kept, as the apps' is): a hidden copy of them all, measured.
        .background(alignment: .top) {
            rows(entries)
                .fixedSize(horizontal: false, vertical: true)
                .background(Self.measured)
                .hidden()
                .accessibilityHidden(true)
        }
        .frame(height: height, alignment: .top)
        // A shade apart from the app list it covers: a level below it.
        .background(Color.primary.opacity(0.04))
    }

    private func rows(_ list: [Entry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider() }
                row(entry)
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        let popover = entry.snapshot.popover
        // The workbench selects the group's first copy with work, else its first.
        let target = entry.snapshot.tools.first(where: {
            $0.phase != .idle || $0.error != nil || $0.state == .updateAvailable
        })?.id.tag ?? entry.statuses.first?.toolID.tag
        // A left click does nothing, as on an app row: the row looks like one,
        // and its Update sits beside it, so a click a little off it opened the
        // workbench and closed the popover (owner, 2026-10-24). The workbench
        // is on its right-click menu.
        return HStack(spacing: 10) {
            if let first = entry.statuses.first {
                CLIToolIcon(kind: first.kind, size: 30, managed: first.managedItem?.descriptor)
                    .frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.title).lineLimit(1)
                line(entry, popover).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch popover?.button {
            case .update:
                Button { Task { await tools.updateAll(in: entry.scope) } } label: {
                    Text("Update").frame(minWidth: PopoverRowAction.buttonLabelMinWidth)
                }
                .lineLimit(1)
                .fixedSize()
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help(CLIToolPresentation.updateAllHelp)
            case .cancel(let group):
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    InstallCancelButton(state: group.state, pending: group.pending, count: group.live,
                                        queuedOnly: group.queuedOnly) {
                        tools.cancelRow(in: entry.scope)
                    }
                }
            case .spinnerOnly:
                ProgressView().controlSize(.small)
            case .some(.none), .copy, nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if let target {
                Button(String(localized: "Show in Window")) { show(target) }
            }
        }
    }

    /// Its versions while it has one copy with an update and nothing runs —
    /// "2.1.308 → 2.1.309" says more than "1 update" — else what its row says.
    private func line(_ entry: Entry, _ popover: CLIPopoverRow<CLIToolID>?) -> Text {
        if entry.statuses.count == 1, let status = entry.statuses.first, status.state == .updateAvailable,
           popover?.isRunning == false, popover?.button == .update(admin: status.needsAdministrator) {
            // The app rows' caption: the new version tinted.
            if let installed = status.installedVersion, let latest = status.latestVersion {
                return Text(verbatim: "\(installed) → ") + Text(verbatim: latest).foregroundColor(.accentColor)
            }
            return Text(verbatim: CLIToolPresentation.versionCaption(status))
        }
        let parts = (popover?.lines ?? []).map { CommandLineWording.line($0, tools: tools) }
        return parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { $0 + Text(verbatim: " · ") + $1 }
    }
}

enum CommandLineWording {
    /// One part of a command-line row's line (`CLIPopoverRow.Line`), worded:
    /// the popover's "Other tools" row and each group on its page (`ToolsPage`).
    @MainActor static func line(_ line: CLIPopoverRow<CLIToolID>.Line, tools: CLIToolsModel) -> Text {
        switch line {
        case .queued: return Text(String(localized: "Queued"))
        case .updating(let kind?): return Text(String(localized: "Updating \(kind.displayName)"))
        case .updating(nil): return Text(String(localized: "Updating command-line tools"))
        // The same sentence as a kind's, with the manager's group in it: "Updating mise tools".
        case .updatingGroup(let group): return Text(String(localized: "Updating \(group)"))
        case .progress(.cancelling): return Text(String(localized: "Cancelling…")).monospacedDigit()
        case .progress(.line(let text)): return Text(text).monospacedDigit()
        case .progress(.updating): return Text(String(localized: "Updating…")).monospacedDigit()
        case .checking: return Text(String(localized: "Checking…"))
        case .error(let error): return Text(error).foregroundStyle(.red)
        case .updates(let count): return Text(String(localized: "\(count) updates"))
        case .needSudo(let count): return Text(CLIToolPresentation.needSudo(count) ?? "")
        case .heldBack(let count): return Text(String(localized: "\(count) held back"))
        case .withheld(let id, let withheld):
            // In the user's terms, as the copy's own row says it.
            return Text(tools.status(id).map { CLIToolsModel.reason(withheld, of: $0) }
                ?? CLIToolsModel.reason(withheld, of: id.kind))
        case .notChecked(let count): return Text(String(localized: "\(count) not checked"))
        case .updated(let kind, let version): return Text(String(localized: "\(kind.displayName) updated to \(version)"))
        case .updatedItem(let name, let version): return Text(String(localized: "\(name) updated to \(version)"))
        case .updatedCount(let count): return Text(String(localized: "\(count) updated"))
        // A running process keeps the binary it started with; for Claude Code
        // that is every open session.
        case .takesEffect(.claudeCode): return Text(String(localized: "New sessions use it; restart open ones"))
        case .takesEffect: return Text(String(localized: "Takes effect the next time it runs"))
        case .upToDate: return Text(String(localized: "Up to date"))
        }
    }
}

/// The popover's rows for command-line tools, as the workbench's CLI tab holds
/// them: one for Homebrew's packages and one for every other tool (Claude Code,
/// bub, fx, …), each with its own state and its own Update. A later tool joins
/// the second row rather than getting its own. A row is there while its half
/// has anything installed, whatever state it is in.
///
/// Plain rows, built like the app rows above them: on 2026-10-06 one merged
/// row, a card stack that fanned out on hover and two tiles side by side were
/// each tried and each read as something pasted onto the popover's list.
///
/// The merged row had one trailing control for both halves, so it could show
/// the Update button or brew's "not checked" mark, never both. Here Homebrew's
/// row says how many packages brew didn't read beside its updates.
private struct CommandLineRow: View {
    let model: AppListModel
    /// Opens the workbench on the CLI tab with "Other tools" open.
    let showInWindow: () -> Void
    /// Opens the workbench on the CLI tab with the Homebrew group open.
    let showHomebrew: () -> Void
    /// Opens the workbench on the brew packages Homebrew didn't read.
    let showBrewUnchecked: () -> Void

    private var tools: CLIToolsModel { model.cliTools }

    /// One half's state.
    private struct Half {
        /// Homebrew's half, whose text opens the Homebrew group rather than
        /// "Other tools".
        var isHomebrew = false
        let icon: String
        let title: String
        /// What the row says, run together on its second line.
        let lines: [Text]
        /// The mark before the button: a spinner, a seal, why not checked.
        var mark: AnyView? = nil
        /// The Update button, when one is offered.
        var button: AnyView? = nil
        /// Its run's Cancel stands where `button`'s Update did.
        var running = false
        /// A chevron beside the title opens the groups' page (`ToolsPage`).
        var expandable = false
    }

    /// Whether the popover shows the tool groups (`ToolsPage`) in the app list's
    /// place. Owned by the popover, which resets it each time it closes.
    let toolsPageOpen: Bool
    /// Opens or closes that page (`MenuContentView.setToolsPage`).
    let toggleToolsPage: () -> Void

    var body: some View {
        let halves = [brewHalf, toolsHalf(expandable: ToolsPage.hasGroups(tools))].compactMap { $0 }
        VStack(spacing: 0) {
            ForEach(halves.indices, id: \.self) { i in
                if i > 0 { Divider() }
                row(halves[i])
            }
        }
    }

    /// The chevron beside "Other tools": its own click, apart from the title
    /// and the line beside it, which open the workbench. It points the way
    /// the groups' page moves — forward to slide it in from the right, back
    /// while it is open to slide it out — never down: the page is a level of
    /// its own, not rows unfolding under this one.
    private var stackToggle: some View {
        Button(action: toggleToolsPage) {
            Image(systemName: toolsPageOpen ? "chevron.backward" : "chevron.forward")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(toolsPageOpen ? String(localized: "Hide groups") : String(localized: "Show groups"))
    }

    private func row(_ half: Half) -> some View {
        let status = half.lines.dropFirst().reduce(half.lines.first ?? Text(verbatim: "")) {
            $0 + Text(verbatim: " · ") + $1
        }
        // AppRow's columns: a 30pt icon slot and 10pt to the text, so these
        // titles start on the app names' edge above them, not 14pt left of it.
        return HStack(spacing: 10) {
            Image(systemName: half.icon).foregroundStyle(.secondary).frame(width: 30)
            // The text opens the workbench, where each package and copy has its
            // own row; the controls stay the row's actions.
            if half.expandable {
                // The title and its line each open the workbench; the chevron
                // between them has its own click.
                let open = half.isHomebrew ? showHomebrew : showInWindow
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        Button(action: open) { Text(verbatim: half.title).font(.caption).fontWeight(.medium) }
                            .buttonStyle(.plain)
                            .help(String(localized: "Show in Window"))
                        stackToggle
                    }
                    Button(action: open) {
                        status.font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Show in Window"))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: half.isHomebrew ? showHomebrew : showInWindow) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: half.title).font(.caption).fontWeight(.medium)
                        status.font(.caption2).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Show in Window"))
            }
            // Whatever the row says: a text in this line did not fit beside the
            // Update button in 17 of 22 language and count pairs (measured
            // 2026-10-17), so it is a mark, as Homebrew's not-checked one is.
            if !half.isHomebrew, !stillRunningLines.isEmpty {
                StillRunningMark(lines: stillRunningLines, showInWindow: showInWindow)
            }
            half.mark
            half.button.swallowsClicksAfterSwap(of: half.running)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Marked while its page is open above: the page is this row's level.
        .background(half.expandable && toolsPageOpen ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    // MARK: Homebrew

    private var brewHalf: Half? {
        // What it says, its mark and its button: `BrewRowSnapshot.popover`.
        guard let row = model.brewRowSnapshot.popover else { return nil }
        let mark: (any View)? = switch row.mark {
        case .spinner: spinner
        case .seal: seal
        case .unchecked: uncheckedMark
        case nil: nil
        }
        let button: (any View)? = switch row.button {
        case .update:
            updateButton(
                help: String(localized: "Runs `brew upgrade --formula`, then upgrades any listed cask by name. Covers command-line formulae plus casks that install no app (CLIs, fonts) — those have no row of their own. GUI casks are managed per-app above and are never touched. The count reads your local tap; brew refreshes itself during the upgrade, so it still lands the latest.")
            ) { await model.upgradeBrewFormulae() }
        // One Cancel where the Update button stood, for Upgrade All and for
        // a formula's own upgrade from the workbench alike, as the Other
        // tools row's (2026-10-20: a formula's showed nothing here).
        case .cancel(let group):
            InstallCancelButton(state: group.state, pending: group.pending, count: group.live,
                                queuedOnly: group.queuedOnly) {
                model.cancelBrewRow()
            }
        case .none, .copy, .spinnerOnly: nil
        }
        return Half(isHomebrew: true, icon: "mug", title: "Homebrew", lines: row.lines.map(brewLine),
                    mark: mark.map { AnyView($0) }, button: button.map { AnyView($0) }, running: row.isRunning)
    }

    /// One part of the Homebrew row's line (`BrewPopoverRow.Line`), worded.
    private func brewLine(_ line: BrewPopoverRow.Line) -> Text {
        switch line {
        case .progress(let progress): return Text(progress.text).monospacedDigit()
        case .upgrading(let name): return Text(String(localized: "Upgrading \(name)"))
        case .checking: return Text(String(localized: "Checking…"))
        case .error(let error): return Text(error).foregroundStyle(.red)
        case .updates(let count): return Text(String(localized: "\(count) updates"))
        // Packages brew wouldn't read: no count here can include them.
        case .notChecked(let count): return Text(String(localized: "\(count) not checked"))
        // Formulae Homebrew is phasing out (`BrewLifecycle`): checked, so not
        // in either count, but nothing else here would say so.
        case .deprecated(let count): return Text(String(localized: "\(count) deprecated"))
        case .upToDate: return Text(String(localized: "Up to date"))
        }
    }

    private var uncheckedMark: some View {
        BrewUncheckedMark(
            anyTapNotTrusted: model.brewUnchecked.contains { $0.reason == .tapNotTrusted },
            anyMovedToCask: model.brewUnchecked.contains { $0.reason == .movedToCask },
            anyRenamed: model.brewUnchecked.contains { if case .renamed = $0.reason { true } else { false } },
            anyRemoved: model.brewUnchecked.contains { $0.reason == .removed },
            showInWindow: showBrewUnchecked)
    }

    // MARK: Other tools

    /// "Other tools": every command-line tool but Homebrew's, managers' items
    /// too. Its Update is Update All over all of them, its Cancel every copy's.
    private func toolsHalf(expandable: Bool) -> Half? {
        // What it says, its mark and its button: `CLIRowSnapshot.popover`.
        guard let row = tools.rowSnapshot.popover else { return nil }
        let mark: (any View)? = switch row.mark {
        case .spinner: spinner
        case .seal: seal
        case .question: question
        case nil: nil
        }
        let button: (any View)? = switch row.button {
        case .update: updateButton(help: CLIToolPresentation.updateAllHelp) { await tools.updateAll() }
        // One Cancel where the Update button stood, for every copy the row
        // says is updating — Update All's, and a click's of its own from the
        // workbench, which had none here (2026-10-20).
        case .cancel(let group):
            InstallCancelButton(state: group.state, pending: group.pending, count: group.live,
                                queuedOnly: group.queuedOnly) {
                tools.cancelRow()
            }
        case .none, .copy, .spinnerOnly: nil
        }
        return Half(icon: "terminal", title: String(localized: "Other tools"),
                    lines: row.lines.map { CommandLineWording.line($0, tools: tools) },
                    mark: mark.map { AnyView($0) }, button: button.map { AnyView($0) }, running: row.isRunning,
                    expandable: expandable)
    }

    /// One line per tool with processes still on the copy from before its
    /// update (`CLIToolsModel.usage`), as the workbench row says it, for the
    /// row's mark (`StillRunningMark`). Empty when none has.
    private var stillRunningLines: [String] {
        tools.statuses.compactMap { status in
            guard let usage = tools.liveUsage(status.toolID),
                  let line = CLIToolWording.stillRunning(usage, of: status.kind) else { return nil }
            return "\(status.name ?? status.kind.displayName): \(line)"
        }
    }

    // MARK: Parts

    /// Never disabled by another run: a click behind one waits its turn
    /// (`CLIRunQueue`).
    private func updateButton(help: String, action: @escaping () async -> Void) -> some View {
        // The app rows' button: small, its label at least
        // `PopoverRowAction.buttonLabelMinWidth` wide, so the column of buttons
        // ends on one edge down the whole popover. Its own size, never scaled.
        Button { Task { await action() } } label: {
            Text("Update").frame(minWidth: PopoverRowAction.buttonLabelMinWidth)
        }
        .lineLimit(1)
        .fixedSize()
        .controlSize(.small)
        .buttonStyle(.borderedProminent)
        .help(help)
    }

    private var spinner: some View { ProgressView().controlSize(.small) }
    private var seal: some View { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
    private var question: some View { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
}

/// The command-line tools row's mark while a tool has processes still on its
/// old copy: what the workbench row says, on hover and on a click, and the
/// way there.
private struct StillRunningMark: View {
    let lines: [String]
    let showInWindow: () -> Void

    @State private var showTip = false

    private var summary: String { String(localized: "Old version still running — click for details") }

    var body: some View {
        // Not `clock.arrow.circlepath`: the footer's Release Log button is
        // that symbol, two rows below.
        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            .foregroundStyle(.orange)
            .contentShape(Rectangle())
            .onTapGesture { showTip = true }
            .help(([summary] + lines).joined(separator: "\n"))
            .accessibilityLabel(summary)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showTip = true }
            .popover(isPresented: $showTip, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Restart to use the version installed now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(String(localized: "Show in Window")) {
                            showTip = false
                            showInWindow()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(width: 260, alignment: .leading)
            }
    }
}

/// The trailing mark on the command-line row when nothing is outdated but some packages
/// went unchecked (`BrewUncheckedPackage`). An info mark rather than a warning:
/// nothing failed, brew just declined to read them. Clicking explains why, like
/// `StagedVersionUnknownMark`, and offers the workbench rows that name them.
private struct BrewUncheckedMark: View {
    /// Links Homebrew's tap-trust docs only when that is a reason in play: a
    /// package brew can't read for another reason (tap gone, broken definition)
    /// isn't fixed by trusting anything.
    let anyTapNotTrusted: Bool
    /// A formula Homebrew replaced with a cask is among them: the sentence above
    /// speaks of taps, which isn't what happened to it.
    let anyMovedToCask: Bool
    /// A renamed formula is among them — the one that stops every formula's check.
    let anyRenamed: Bool
    let anyRemoved: Bool
    let showInWindow: () -> Void

    private static let tapTrustDocs = URL(string: "https://docs.brew.sh/Tap-Trust")!

    @State private var showTip = false

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onTapGesture { showTip = true }
            .help(String(localized: "Not checked — click for why"))
            .accessibilityLabel(String(localized: "Not checked — click for why"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showTip = true }
            .popover(isPresented: $showTip, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Homebrew didn’t read these packages from their taps — for example because a tap isn’t trusted — so their updates can’t be checked. They’re listed in the Brew section of the DuoUpdater window."))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if anyRenamed {
                        Text(String(localized: "A formula Homebrew renamed has to be migrated before Homebrew can check any formula for updates — the window shows the command."))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if anyMovedToCask {
                        Text(String(localized: "A formula Homebrew replaced with a cask gets no more updates as a formula — the window shows the commands that switch it to the cask."))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if anyRemoved {
                        Text(String(localized: "A formula Homebrew removed gets no more updates."))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if anyTapNotTrusted {
                        // NSWorkspace rather than SwiftUI `openURL`, which errors -50
                        // in this app's windows (see `AlcoveSettingsPage`).
                        Button {
                            NSWorkspace.shared.open(Self.tapTrustDocs)
                            showTip = false
                        } label: {
                            Text(String(localized: "Homebrew docs: Tap Trust")).underline()
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .help(Self.tapTrustDocs.absoluteString)
                    }
                    HStack {
                        Spacer()
                        Button(String(localized: "Show in Window")) {
                            showTip = false
                            showInWindow()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(width: 260, alignment: .leading)
            }
    }
}

/// The "?" that stands in for the target version when an app has staged its own
/// update where we cannot read it
/// (`RowVersionLineState.stagedRelaunchVersionUnknown`).
/// Clicking it explains why; a tooltip alone only reaches people who already
/// suspect the "?" means something. A tap rather than a Button, like
/// `FullDiskAccessMark`. Shared by the popover row and the workbench detail header.
struct StagedVersionUnknownMark: View {
    let appName: String
    /// Whether the privileged helper is off. Only it can read a build staged as
    /// root (#588), so the explanation then offers to turn it on.
    let helperOff: Bool
    /// The existing "Turn On Helper…" action (`AppListModel.enableAppStoreHelper`).
    let enableHelper: () -> Void

    @State private var showTip = false

    var body: some View {
        Text(verbatim: "?")
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
            .onTapGesture { showTip = true }
            .help(String(localized: "Version unknown — click for why"))
            .accessibilityLabel(String(localized: "Version unknown — click for why"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showTip = true }
            .popover(isPresented: $showTip, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "\(appName) has already downloaded an update itself, but which version can't be read from here — usually because it installs with administrator rights. Relaunch to apply it."))
                    if helperOff {
                        Text(String(localized: "With DuoUpdater's helper turned on, the version can be read."))
                            .foregroundStyle(.secondary)
                        Button("Turn On Helper…") {
                            showTip = false
                            enableHelper()
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.callout)
                .foregroundStyle(.primary)
                // The anchor sits in a one-line, scale-to-fit version line, and
                // popover content inherits that environment: without resetting
                // both, the explanation renders as a single truncated line.
                .lineLimit(nil)
                .minimumScaleFactor(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 260, alignment: .leading)
            }
    }
}

private struct AppRow: View {
    let result: UpdateResult
    @Bindable var model: AppListModel
    @Environment(\.openWindow) private var openWindow

    private var stage: InstallStage? { model.installRows.stages[result.id] }
    private var installError: String? { model.installErrorText(for: result) }

    /// The row's height when nothing is stacked under the name line. See the
    /// `.frame` in `body` for why it is fixed and where the number comes from.
    static let plainRowHeight: CGFloat = 44

    /// The note drawn under the name line when there is no install error — an
    /// install note, else the staged-package line.
    ///
    /// Read TWICE per row, by the view that draws it and by the frame that has to
    /// know whether the row is taller than `plainRowHeight`, so `body` binds it
    /// once and passes the value to both. Behind it, `stagedPackageNote` stats the
    /// disk for a row that has a package staged and builds a localized string;
    /// asking twice on a per-row, per-repaint path is exactly the cost the frame
    /// below exists to remove.
    private var secondaryNote: String? {
        model.installNotes[result.id] ?? model.stagedPackageNote(for: result)
    }

    /// How wide the name line wants to be — the name plus whatever shares its
    /// row (the running dot, a channel chip). Measured with AppKit rather than
    /// left to `ViewThatFits`: the progress control is inflexible, so an HStack
    /// hands it its ideal width and it never feels the pressure a long name is
    /// under. Measuring is the only way to see the collision coming.
    ///
    /// The runtime symbol is deliberately **not** counted here. It is the one thing
    /// on this line that yields rather than pushes: `ViewThatFits` drops it before
    /// the name gives up a line. Budgeting for it would spend width on something
    /// that may not be drawn — and spend it in the worst place, pushing rows from
    /// the progress bar down to a bare ring during a download, which is exactly
    /// when the row has the most to say.
    private var nameLineWidth: CGFloat {
        var width = NSAttributedString(
            string: result.app.name,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).size().width
        if model.isRunning(result) { width += 6 + 6 }   // dot + HStack spacing
        let tag = ChannelTag.measuredWidth(for: result.effectiveReleaseChannel)
        if tag > 0 { width += tag + 6 }
        if !model.fullDiskAccessNeedsAffecting(result).isEmpty {
            width += FullDiskAccessMark.width() + 6
        }
        return width
    }

    /// The name, its running dot, its channel chip — and the runtime symbol, if the
    /// row can afford it.
    ///
    /// The choice is handed to `ViewThatFits` rather than made by arithmetic here,
    /// and that is a correction rather than a shortcut. Measuring it by hand needs
    /// the width of the trailing control, and this row does not know it: the slot is
    /// a 64pt *minimum* and the real control runs far past it ("Reveal in Finder" is
    /// nearly twice that, and every label is localized). Budgeting against the
    /// minimum said the symbol fit where it did not, and wrapped "Postman Collection
    /// Runner" onto a second line — a name losing a line to a decorative glyph,
    /// which is exactly what must not happen. `ViewThatFits` is asked at layout
    /// time, when the true remaining width is known, and its second candidate is the
    /// line as it looked before this feature.
    @ViewBuilder
    private var nameLine: some View {
        if model.prefs.showRuntimeTags, let runtime = result.app.runtime {
            ViewThatFits(in: .horizontal) {
                nameLine(tagged: runtime)
                nameLine(tagged: nil)
            }
        } else {
            nameLine(tagged: nil)
        }
    }

    private func nameLine(tagged runtime: AppRuntime?) -> some View {
        HStack(spacing: 6) {
            Text(result.app.name).font(.body)
            if model.isRunning(result) {
                RunningIndicator(size: 6).offset(y: RunningIndicator.opticalNudge)
            }
            ChannelTag(channel: result.effectiveReleaseChannel)
            FullDiskAccessMark(
                needs: model.fullDiskAccessNeedsAffecting(result),
                grant: { model.presentFullDiskAccessPermissionFlow() })
            // No optical nudge here: this mark is nearly cap-height, so it is judged
            // by its edges rather than its centre. See `RunningIndicator.opticalNudge`.
            if let runtime {
                RuntimeTag(runtime: runtime, bundle: result.app.path,
                           frameworks: result.app.linkedFrameworks, buildSDK: result.app.buildSDK)
            }
        }
    }

    /// What the version line under the name wants out of the same column.
    ///
    /// It never wraps — it shrinks to `minimumScaleFactor(0.75)` and then
    /// truncates, which is how Warp's date-style versions became
    /// "0.2026.08.18.02.52…  →  0.2026.08.19.08.15…" the moment a download
    /// widened the readout from a 64pt button to the 86pt bar. Neither end of
    /// the version was readable, which is the whole point of the line.
    ///
    /// The arrow and its two 4pt gaps don't scale, so the line survives in
    /// `0.75 * natural + 4.25` — that's what it needs, and what this reports.
    private var versionLineDemand: CGFloat {
        guard case .updateAvailable(let latest) = result.status else { return 0 }
        let caption = NSFont.preferredFont(forTextStyle: .caption1)
        func measure(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: caption]).size().width
        }
        let bump = result.buildBump(latest: latest)
        let (installed, offered) = result.updateLineSides(latest: latest)
        let from = bump.map { "\(installed) (\($0.installed))" } ?? installed
        let to = bump.map { "\(offered) (\($0.remote))" } ?? offered
        let natural = measure(from) + measure(to) + Self.versionArrowWidth
        return 0.75 * natural + 0.25 * Self.versionArrowWidth
    }

    /// The arrow glyph plus the HStack's two 4pt gaps around it.
    private static let versionArrowWidth: CGFloat = 17

    /// The widest thing in the name column — the name, or a version line long
    /// enough to be the binding constraint. Warp's name is 31.8pt and its
    /// version line needs 177.4pt; budgeting on the name alone is what let the
    /// bar squeeze the versions into ellipses.
    private var nameColumnDemand: CGFloat { max(nameLineWidth, versionLineDemand) }

    /// Whether the name column still holds together next to a readout `width`
    /// wide. Six readout widths were rendered against the real row layout and
    /// each one's wrap point recorded; at the original 360pt popover the budget
    /// came out as `260 - width`,
    /// taking the low end of the six intercepts (261…267.6) and 4pt of slack on
    /// top. The slack is the lesson from the percentage label, which wrapped
    /// because its slot was sized to the exact measurement.
    private func nameFits(besideReadout width: CGFloat) -> Bool {
        nameColumnDemand <= MenuLayoutMetrics.appRowFitBudget - width - 4
    }

    /// What the install's Cancel takes beside the readout: its glyph and the 4pt
    /// between. Nothing once the cancel was accepted — "Cancelling…" replaces
    /// the readout and the glyph is gone (`PopoverRowAction.installCancel`).
    private var cancelReserve: CGFloat {
        guard let cancel = model.installRows.cancels[result.id], cancel != .cancelling else { return 0 }
        return InstallCancelButton.width + 4
    }

    /// How much of a download readout the name leaves room for. Widest first —
    /// the number is worth keeping as long as it fits, so the bar is what goes
    /// before the percentage does.
    private var downloadReadout: DownloadReadout {
        for style in DownloadReadout.allCases where nameFits(besideReadout: style.contentWidth + cancelReserve) {
            return style
        }
        return .ringOnly
    }

    /// Whether the spinner keeps its stage name ("Extracting", "Installing").
    /// Measured per label, not per widest label: "Queued" is 12pt narrower than
    /// "Extracting", and that difference decides the case for a long name.
    private func showsStageLabel(_ stage: InstallStage) -> Bool {
        let label = NSAttributedString(
            string: installProgressLabel(stage, cancel: model.installRows.cancels[result.id]),
            attributes: [.font: NSFont.preferredFont(forTextStyle: .caption2)]
        ).size().width
        return nameFits(besideReadout: max(64, DownloadReadout.spinner + 4 + label) + cancelReserve)
    }

    /// The width the trailing slot reserves. 64pt is the shared one every button
    /// and badge uses; a readout that has already given up width for the name
    /// must give up its reservation too, or it hands back only the difference.
    ///
    /// A *floor*, not the control's width, and that distinction is what keeps
    /// this honest in other languages. Measured on the real popover, the buttons
    /// run past 64pt, and in English too since they gained a floor of their own
    /// (`PopoverRowAction.buttonLabelMinWidth`): Update is 73.0pt in English,
    /// Relaunch 73.0. Measured before that floor, and above it either way: Update
    /// 73.0 in Russian, 88.0 in German; Relaunch 102.5 / 81.5.
    /// Because the HStack hands a control its ideal width and the `Spacer` eats
    /// the slack, a wider button simply takes what it needs and the name column
    /// gets the rest (213pt in English beside a 73pt button; 214.5 in German and
    /// 193.5 in Russian, measured before the floor). So the reservation being
    /// English-shaped costs nothing.
    ///
    /// What would cost something is a *decision* made against a stale number, and
    /// there is exactly one localized thing on this path: the stage label. That is
    /// why `showsStageLabel` measures its own text rather than assuming 64 —
    /// everything else in the trailing slot during an install (the bar, the ring,
    /// the fixed-width percentage) is the same size in every language.
    private var trailingSlot: CGFloat {
        guard let stage else { return 64 }
        if case .downloading = stage { return downloadReadout == .barAndPercent ? 64 : 24 }
        return showsStageLabel(stage) ? 64 : 24
    }

    var body: some View {
        // Bound here, not read from `secondaryNote` at each of its two use sites —
        // see that property. Only reached when there is no install error, which
        // wins the branch below.
        let note = installError == nil ? secondaryNote : nil
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    nameLine
                    versionLine
                }
                Spacer()
                // Minimum-width action slot, trailing-aligned: every control ends on
                // the row's own trailing edge, so a narrow indicator (a bare ✓) shares
                // a right edge with a wide button ("Relaunch now") *and* with the brew
                // footer's badge below, which is flush right against the same 12pt
                // padding. Centring instead inset the narrow ones by ~27pt and broke
                // that shared edge. The minimum still reserves a slot so the name
                // column can't run right up to the control.
                // …except when a long name has pushed the progress readout down to
                // a ring: reserving 64pt there would hand back only 22 of the 70pt
                // the ring saves, and the name would wrap anyway. 24pt still keeps
                // the name off the control, and trailing alignment means the ring
                // ends on the same edge every other control does.
                PopoverRowAction(
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
                    runningVersion: model.restartFromVersion(result.id),
                    helperEnabled: model.helperEnabled,
                    keepBackups: model.prefs.keepBackups,
                    downloadReadout: { downloadReadout },
                    showsStageLabel: showsStageLabel,
                    testFlightUnboundedReason: model.testFlightUnboundedReason,
                    installCancel: model.installRows.cancels[result.id],
                    installCancelPending: model.installRows.cancelPending.contains(result.id))
                    .frame(minWidth: trailingSlot, alignment: .trailing)
            }
            if let installError {
                VStack(alignment: .leading, spacing: 3) {
                    // One line, with the whole message on hover. This note used
                    // to be unbounded, so a long one grew the row by three or four
                    // lines and pushed everything below it down — and the popover
                    // is 370pt wide, the narrowest place any of this copy is shown.
                    // The clamp applies to every install error, not just the short
                    // ones written for it, so a longer message (the post-install
                    // verification note, say) loses whatever falls past one line —
                    // the tooltip is what keeps the rest reachable.
                    Text(installError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // After the frame, not before it: the note is the full row
                        // width and a truncated one is exactly the case where the
                        // pointer is most likely to be past the end of the text.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(installError)
                    if model.showsAppStoreUpdatesFallback(result.id) {
                        Button("Open App Store") { model.openAppStoreUpdatesPage() }
                            .font(.caption2)
                            .buttonStyle(.link)
                    }
                    if model.showsHelperApprovalFallback(result.id) {
                        Button("Turn On Helper…") { model.enableAppStoreHelper() }
                            .font(.caption2)
                            .buttonStyle(.link)
                    }
                    if model.showsHelperRestartFallback(result.id) {
                        let restartHelperLabel = model.restartingHelper
                            ? String(localized: "Restarting…")
                            : String(localized: "Restart Helper…")
                        Button(restartHelperLabel) {
                            Task { await model.restartAppStoreHelper(result.id) }
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                        .disabled(model.restartingHelper)
                    }
                    if let failure = model.reportableFailure(for: result) {
                        Button("Report this problem…") {
                            model.openFailureReport(failure)
                            openWindow(id: FailureReportView.windowID)
                            model.surfaceWindow(sceneID: FailureReportView.windowID)
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }
                }
            } else if let note {
                // The staged-package line is the fallback, not an override: once
                // an install note exists ("Opened the installer for … — finish it
                // there") it is the more specific thing to say about the same
                // package.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // Say how tall this row is instead of making the list work it out.
        //
        // A `LazyVStack` asks every row it places for its size, and answering used to
        // mean descending the whole row — the stack, the two text lines, the trailing
        // control — which a fast drag pays for in bursts as it realizes rows faster
        // than they can be sized. That is what dropped frames. A fixed frame answers
        // from the modifier instead.
        //
        // What that actually buys, measured over a 25 s full-range scroll of the
        // "Show all" list with the runtime tags off (2026-09-07, `sample(1)`, as a
        // share of wall clock): the main thread goes from 60.0% busy to 42.5%, and
        // the popover stops dropping frames. The saving is in re-running row bodies
        // — `ViewBodyAccessor.updateBody` 12.0% -> 3.6%, `AppRow.body` 8.0% -> 3.2%,
        // AttributeGraph 43.5% -> 27.3%.
        //
        // NOT in the stack's own sizing pass, which is where this was expected to
        // land: `LazyHVStack.lengthAndSpacing` is 14.7% before and 16.7% after. The
        // stack still asks every row how tall it is. What changed is that answering
        // no longer runs the row's body. Do not "fix" the remaining 16.7% by
        // reaching for the frame again — it is already fixed.
        //
        // 44 is not a guess and not a target: it is what the row already measures.
        // A height probe over 161 rows of the real list returned 44.00pt for every
        // one, including rows carrying a channel chip, a runtime mark or a running
        // dot, and it is the same 44 the row-state gallery already draws the
        // trailing control into. Nothing about the row's appearance changes here.
        //
        // `nil` — natural height — for the rows this was NOT measured on. An install
        // error or a note adds a second line to the `VStack` above, and none of the
        // 161 was in that state, so those rows keep sizing themselves. They are rare
        // and transient, so the fast path still covers essentially the whole list.
        //
        // ⚠️ A frame does not clip: content taller than this OVERFLOWS and draws over
        // the row below. The condition above only knows the two things that stack
        // UNDER the name line, so trailing content that grows past the icon's 30pt —
        // a two-line status, a stacked readout — would overlap silently. Every
        // inline branch of `PopoverRowAction` is a single-line `HStack` today (the
        // tall `VStack`s in that file are `.popover` content, not row content), but
        // that is an audit, not a gate: `make gallery` draws the trailing control
        // into its own forced 44pt slot, so it would clip such a control too and
        // still pass. Re-measure the row rather than assume, if one is added.
        .frame(height: installError == nil && note == nil ? Self.plainRowHeight : nil)
        .contentShape(Rectangle())
        .contextMenu { rowMenu }
    }

    /// Right-click actions: launch the app, jump to its changelog in the workbench,
    /// skip the offered version, ignore the app, and (when a backup exists) roll
    /// back to the previous version.
    @ViewBuilder
    private var rowMenu: some View {
        // Via `AppRestarter.launchApp`, not `NSWorkspace.open` — the latter blocks
        // the main thread until the app has finished launching.
        Button("Open") { Task { await AppRestarter.launchApp(result.app.path) } }
        Button("Changelog") { openChangelog() }
        // Ask about this one app. Same entry point as the retry on a failed row —
        // one question, one answer — and the cheap way to correct a row whose
        // running dot has gone stale (issue #247). Disabled while the row is busy,
        // which is also what `retry` itself refuses on.
        Button("Check Again") { Task { await model.retry(result) } }
            .disabled(stage != nil)
        Divider()
        if result.hasUpdate {
            let offered = result.offeredDisplay ?? String(localized: "this version")
            if model.prefs.isVersionSkipped(result.app, version: result.remote?.versionSide) {
                Button("Don’t skip \(offered)") { model.prefs.clearSkip(result.app) }
            } else {
                Button("Skip \(offered)") { model.skipThisVersion(result) }
            }
        }
        let ignoreLabel = model.prefs.isIgnored(result.app)
            ? String(localized: "Stop ignoring \(result.app.name)")
            : String(localized: "Ignore \(result.app.name)")
        Button(ignoreLabel) {
            model.toggleIgnore(result)
        }
        // The way back out of a download the user has decided against. Without
        // it a staged package can only be applied or superseded — someone who
        // changes their mind has no way to say so, and the row goes on offering
        // Install (clearing it by hand meant quitting the app and deleting a
        // defaults key).
        if model.canDiscardStagedPackage(result) {
            Button("Discard Downloaded Installer") {
                Task { await model.discardStagedPackage(result) }
            }
        }
        // The way back out of a dismissed administrator prompt. Shown only while
        // that is actually why the row reads "Open", so it never appears as a
        // mysterious no-op on an app that was never asked about.
        if model.isElevationDeclined(result) {
            Button("Ask for administrator access again") { model.allowElevatedInstall(result) }
        }
        if let version = model.backupVersion(result.id) {
            Divider()
            // Disabled on the same rule `rollback` refuses on (`canRollback`: busy
            // installing, relaunching or replacing the bundle), so the entry never
            // looks live and does nothing.
            Button("Restore \(version)") { Task { await model.rollback(result) } }
                .disabled(!model.canRollback(result.id))
        }
        // Store-managed apps update through Apple's own apps — give a direct way
        // to jump there from the row, since we don't drive those installs.
        if appStorePageURL != nil || result.app.isTestFlightApp {
            Divider()
            if appStorePageURL != nil {
                Button("Open in App Store") { openAppStorePage() }
            }
            if result.app.isTestFlightApp {
                // Opens TestFlight on this app's own page (`Frontier.appPageURL`),
                // or on its list when the store has no id for it.
                Button("Open TestFlight") { model.openTestFlight(for: result) }
            }
        }
    }

    /// Deep link to this app's App Store product page: the freshest link from a
    /// check if we have one, else the locally-indexed adamID. Nil when neither is
    /// available (e.g. a sideloaded copy Spotlight reports as adamID 0).
    private var appStorePageURL: URL? {
        if let url = result.remote?.appStore?.deepLink { return url }
        guard let id = result.app.appStoreAdamID else { return nil }
        return URL(string: "macappstore://apps.apple.com/app/id\(id)")
    }

    private func openAppStorePage() {
        if let url = appStorePageURL { NSWorkspace.shared.open(url) }
    }

    /// Open the workbench and select this app, so its changelog is showing. Mirrors
    /// the Settings deep-link pattern: set the target on the model first, then open
    /// and surface the window (`WorkbenchWindowView` consumes the target on appear).
    private func openChangelog() {
        model.requestedWorkbenchAppID = result.id
        openWindow(id: WorkbenchWindowView.windowID)
        model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
    }

    @ViewBuilder
    private var versionLine: some View {
        switch model.versionLineState(for: result) {
        case .interrupted(let oldVersion):
            // The version from before the cut-off update: the copy on disk may
            // be gone or broken, and Restore puts this one back.
            Text(interruptedVersionLine(oldVersion))
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .stagedRelaunch(let staged):
            // Relaunch applies this staged build, which `actionableStaged` guarantees
            // is the latest — so the line is a plain installed → staged. (A staged
            // build that trails the latest isn't shown as Relaunch; it goes through
            // the normal updateAvailable line/Update button below.)
            stagedVersionLine(staged)
        case .stagedRelaunchVersionUnknown:
            // Relaunch applies an update the app staged where we cannot read it —
            // so no target version, only a question mark that explains itself on click.
            HStack(spacing: 4) {
                Text(result.installedDisplay ?? "?")
                Image(systemName: "arrow.right").font(.caption2)
                StagedVersionUnknownMark(
                    appName: result.app.name, helperOff: !model.helperEnabled,
                    enableHelper: model.enableAppStoreHelper)
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        case .restart(let from):
            // Update All has landed the new bundle but intentionally postpones its
            // process-version sweep/restarts until every installer is finished; a
            // normal pending restart reaches the same line with the recovered
            // running version/build. Either one outranks an action-less downgrade
            // note because this line explains the Relaunch button (#210).
            restartVersionLine(from: from)
        case .downgrade(let older):
            // Vendor's latest is *older* than what's installed — show it muted with a
            // down-arrow only when no pending relaunch has a more important fact.
            downgradeVersionLine(older)
        case .status:
            switch result.status {
            case .updateAvailable(let latest):
            HStack(spacing: 4) {
                fromVersion(latest: latest)
                Image(systemName: "arrow.right").font(.caption2)
                toVersion(latest: latest)
            }
            .font(.caption)
            // When an earlier update was installed but never restarted, the "from"
            // above is the *staged* on-disk version — the live process is still
            // older. That used to be spelled out inline as "· current <running>",
            // but a third version number does not fit this row: at Chrome's four
            // segments the line truncated to "current 151.0…", cutting off the only
            // digits that differed from the two versions already on the line. The
            // workbench's row never showed it either. So it lives on the hover
            // instead, where it can be read in full, and the line keeps to the one
            // comparison that decides the click: what you have vs what is offered.
            .help(model.restartFromVersion(result.id).map {
                String(localized: "Still running \($0) — relaunch pending from an earlier update")
            } ?? "")
            // Long date-style versions (Warp) would otherwise wrap mid-number;
            // keep it one line and shrink slightly instead.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            default:
                Text("v\(result.installedDisplay ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// installed ↓ older — the vendor's latest trails what's installed. Muted (no
    /// alarm) and action-less: you're ahead, nothing to do. The tooltip names the
    /// benign reasons so it doesn't read as "something's wrong".
    @ViewBuilder
    private func downgradeVersionLine(_ older: String) -> some View {
        let installed = result.app.shortVersion ?? "?"
        HStack(spacing: 4) {
            Text(installed)
            Image(systemName: "arrow.down").font(.caption2)
            Text(older)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .help("The vendor's latest is \(older) — older than your \(installed). You're ahead, so there's nothing to do. Usually a beta channel, a pulled release, or a lagging check.")
    }

    /// The relaunch version line: running version → the version on disk. Surfaced
    /// when an app self-updated on disk but the old process is still live, so
    /// "Relaunch" reads as a concrete version bump rather than a static "v1.6.1".
    ///
    /// Both sides are formatted together by `UpdateResult.relaunchLine`, which drops
    /// the build numbers when the marketing versions already tell the two apart —
    /// without that, Chrome's line spent its width repeating digits its own marketing
    /// version ends in, and truncated the running side to do it.
    @ViewBuilder
    private func restartVersionLine(from: UpdateResult.VersionSide) -> some View {
        let line = UpdateResult.relaunchLine(from: from, to: result.relaunchTargetSide)
        HStack(spacing: 4) {
            Text(line.from).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2)
            Text(line.to).fontWeight(.semibold).foregroundStyle(.orange)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// The staged-relaunch version line: installed → staged. `actionableStaged`
    /// guarantees the staged build is the latest, so there's nothing newer to note.
    ///
    /// Formatted by `UpdateResult.stagedRelaunchLine`, which keeps the build
    /// numbers when the marketing versions do not tell the two apart — the same
    /// rule `restartVersionLine` above gets from `relaunchLine`, which this line
    /// went without until an app that ships every build as "1.0" made it read
    /// "1.0 → 1.0".
    @ViewBuilder
    private func stagedVersionLine(_ staged: StagedSelfUpdate) -> some View {
        let line = result.stagedRelaunchLine(staged)
        HStack(spacing: 4) {
            Text(line.from)
            Image(systemName: "arrow.right").font(.caption2)
            Text(line.to).fontWeight(.semibold).foregroundStyle(.tint)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// The installed-version side of the "from → to" line.
    @ViewBuilder
    private func fromVersion(latest: String) -> some View {
        let marketing = result.updateLineSides(latest: latest).installed
        if let bump = result.buildBump(latest: latest) {
            // Marketing version is just context; the build is what changed.
            Text(marketing).foregroundStyle(.secondary)
            + Text(" (\(bump.installed))")
        } else {
            Text(marketing)
        }
    }

    /// The available-version side. When only the build changed, highlight the
    /// build number — not the unchanged marketing version — so the eye lands on
    /// what's actually new.
    @ViewBuilder
    private func toVersion(latest: String) -> some View {
        let offered = result.updateLineSides(latest: latest).offered
        if let bump = result.buildBump(latest: latest) {
            Text("\(offered) ").foregroundStyle(.secondary)
            + Text("(\(bump.remote))").fontWeight(.semibold).foregroundStyle(.tint)
        } else {
            Text(offered).fontWeight(.semibold).foregroundStyle(.tint)
        }
    }

}

// MARK: - Shared version-line formatting

extension UpdateResult {

}
