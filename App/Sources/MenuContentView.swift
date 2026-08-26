import SwiftUI
import AppKit
import DuoUpdaterCore

/// Caches app icons by path. `NSWorkspace.icon(forFile:)` hits the disk, and rows
/// re-render on every install-progress tick — without a cache that's one icon
/// lookup per row per tick, a real source of stutter while downloads run.
@MainActor
enum AppIconCache {
    // NSCache (vs a plain dict): it evicts under memory pressure on its own, so a
    // large library's worth of cached icons can't grow unbounded.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        // Cache miss = a synchronous disk hit on the main actor. Time it: if app
        // switches stutter, a slow icon read here is one suspect.
        let start = Date()
        let image = NSWorkspace.shared.icon(forFile: path)
        let ms = Date().timeIntervalSince(start) * 1000
        if ms > 2 {
            Log.app.info("perf icon miss: \(ms, format: .fixed(precision: 1), privacy: .public)ms for \((path as NSString).lastPathComponent, privacy: .public)")
        }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// Drop the cached icon for a path so the next lookup re-reads from disk.
    /// Called after an in-place install: the bundle is replaced but its path is
    /// unchanged, so the stale icon would otherwise persist until app restart.
    static func invalidate(_ path: String) { cache.removeObject(forKey: path as NSString) }

    /// The real App Store.app icon, used as the source tag for store-managed apps.
    /// Resolved once (the path is fixed) and shared through the same icon cache.
    static let appStore = icon(for: "/System/Applications/App Store.app")
}

/// Carries the measured height of the popover's update list up to the frame, so it
/// can hug its content instead of guessing a per-row height.
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
    /// Popover filter text. When non-empty it overrides the pending/Show-all split
    /// and searches across *every* app, so an up-to-date app is still findable.
    @State private var searchText = ""
    /// Measured height of the visible update list, so the popover hugs its content
    /// exactly (capped at 380) instead of overshooting with a per-row estimate.
    @State private var listContentHeight: CGFloat = 0
    @Environment(\.openWindow) private var openWindow

    /// Whether the user is actively filtering — drives the search-across-all
    /// behavior and the "no matches" empty state.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var visible: [UpdateResult] {
        // While searching, look across every app (not just pending ones): typing a
        // name should find an up-to-date app too, not come back empty.
        if isSearching {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            return model.results.filter { matches($0, query) }
        }
        return showAll ? model.results
            : model.results.filter {
                model.isActionableUpdate($0) || model.needsRestart.contains($0.id)
                    || model.pendingBatchRestart[$0.id] != nil
                    || model.actionableStaged($0) != nil
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
            }
    }

    /// Match the query against an app's name and bundle id (so "com.google" finds
    /// Chrome), case- and diacritic-insensitively.
    private func matches(_ result: UpdateResult, _ query: String) -> Bool {
        if result.app.name.localizedCaseInsensitiveContains(query) { return true }
        if let bundleID = result.app.bundleID,
           bundleID.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.needsAccessibilitySetup {
                setupBanner
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
            // Only worth showing once the list is long enough to be hard to scan;
            // stays put while a query is active even if it filters down to a few.
            if model.results.count > 8 || isSearching {
                AppSearchField(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            content
            if showBrewRow {
                Divider()
                brewFormulaRow
            }
            Divider()
            footer
        }
        .frame(width: MenuLayoutMetrics.width)
        .task {
            model.refreshPermissionStatus()
            // One-time wiring: arm the background-check loop and teach the
            // notification's "View" action how to open the window.
            model.start(showUpdates: {
                openWindow(id: WorkbenchWindowView.windowID)
                model.surfaceWindow(sceneID: WorkbenchWindowView.windowID)
            })
            // First open: full (networked) check. Every later open: a cheap
            // local rescan to catch background self-updates and surface Restart.
            if model.results.isEmpty {
                Log.app.info("menu .task: results empty → full refresh()")
                await model.refresh()
            } else {
                Log.app.info("menu .task: results present → refreshLocal()")
                await model.refreshLocal()
            }
        }
        // CLI formulae: a separate brew-upgrade surface (formula-only), kicked off
        // concurrently so it never delays the app check above.
        .task { await model.refreshBrewFormulae() }
    }

    @ViewBuilder
    private var content: some View {
        if model.results.isEmpty {
            let emptyTitle = model.isScanning
                ? String(localized: "Scanning…")
                : String(localized: "No apps yet")
            ContentUnavailableView(
                emptyTitle,
                systemImage: "magnifyingglass"
            )
            .frame(height: 200)
        } else if visible.isEmpty {
            if isSearching {
                ContentUnavailableView.search(text: searchText)
                    .frame(height: 200)
            } else {
                // Same rule as `statusLine`: with unanswered rows this is not a
                // "clean run" screen, and the seal is the strongest success signal
                // in the whole popover.
                if model.failedCheckCount > 0 {
                    ContentUnavailableView(
                        "No updates found",
                        systemImage: "questionmark.circle",
                        description: Text("Some apps could not be checked — see above.")
                    )
                    .frame(height: 200)
                } else {
                    ContentUnavailableView(
                        "Everything is up to date",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Toggle “Show all” to see every app.")
                    )
                    .frame(height: 200)
                }
            }
        } else if listOverflows {
            // Long enough that it scrolls no matter how the rows measure, so there
            // is nothing left for the measurement below to decide: pin the frame and
            // let a LazyVStack realize only the rows actually on screen.
            //
            // This is the "Show all" list, and sizing all of it through the non-lazy
            // stack was the popover's one real stall: a 127-app list spent ~880ms of
            // main-thread layout inside `ScrollViewLayoutComputer → StackLayout`
            // asking every row for its size (sample, 2026-08-23) — on every toggle,
            // not just the first.
            ScrollView {
                LazyVStack(spacing: 0) { rows }
            }
            .frame(height: Self.maxListHeight)
        } else {
            ScrollView {
                // Plain VStack (not lazy) so the background GeometryReader measures
                // the *full* content height — a LazyVStack only reports realized rows,
                // which would feed back a too-short frame. Only reached for lists too
                // short to fill the cap, so sizing every row is cheap here.
                VStack(spacing: 0) { rows }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                    })
            }
            // Hug the measured content exactly, capped at 380 (then it scrolls). Using
            // the true height — not a per-row estimate — means no dead space at the
            // bottom for short lists. 54 is just the pre-measurement placeholder.
            .frame(height: min(Self.maxListHeight, listContentHeight == 0 ? 54 : listContentHeight))
            .onPreferenceChange(ListHeightKey.self) { listContentHeight = $0 }
        }
    }

    /// Tallest the list gets before it scrolls.
    private static let maxListHeight: CGFloat = 380

    /// Shortest a row can possibly be: the 30pt icon plus its 7pt vertical padding.
    /// A row with an install error or a note is taller, which only makes the list
    /// overflow sooner — so this stays a lower bound in the safe direction.
    private static let minRowHeight: CGFloat = 44

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

    /// How many rows failed this cycle with a GitHub rate-limit error.
    private var rateLimitedCount: Int {
        model.results.filter(\.status.isRateLimitError).count
    }

    /// Show the aggregate nudge only when several apps are rate-limited at once
    /// and no token is configured. A single transient stays a per-row retry, but
    /// a cluster means the unauthenticated 60/hour cap is biting and a token is
    /// the real fix.
    private var showRateLimitBanner: Bool {
        !model.hasGitHubToken && rateLimitedCount >= 2
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
    private var checkFailureBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.failedCheckCount) apps could not be checked")
                        .font(.caption).fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(model.failedCheckSummary ?? String(localized: "Every update source failed"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
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

    /// Aggregate counterpart to the per-row "Rate-limited" badge: one tap
    /// deep-links to Settings → GitHub to add a token (60/hour → 5000/hour).
    private var rateLimitBanner: some View {
        Button {
            model.requestedSettingsSection = .github
            openWindow(id: SettingsView.windowID)
            model.surfaceWindow(sceneID: SettingsView.windowID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hitting GitHub’s rate limit").font(.caption).fontWeight(.medium)
                    Text("\(rateLimitedCount) apps couldn’t be checked — add a token")
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
                    Text("Duo Updater")
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
                        .help("What's New — Duo Updater's own release notes")
                        .accessibilityLabel("What's New")
                    }
                }
                .padding(.top, 2)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        // Keep both refresh states in the same 16pt layout box.
                        Group {
                            if model.isScanning || model.isChecking {
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
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
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
                // all seven shipped languages: nothing truncates at realistic
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
                if model.canUpdateAll {
                    Button("Update All") { Task { await model.installAll() } }
                        .lineLimit(1)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Install every pending update that can be applied automatically")
                } else {
                    Color.clear.frame(width: 0, height: 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
        }
        .padding(.horizontal, 12)
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
        let updates = model.updateCount
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
                .toggleStyle(.checkbox)
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
                openWindow(id: TrafficWindowView.windowID)
                model.surfaceWindow(sceneID: TrafficWindowView.windowID)
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
        let title = String(localized: "Download Traffic — what keeping these apps updated has cost")
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

    /// Reserve the brew row for any machine with Homebrew installed — always, even
    /// when nothing's outdated: it then shows an "up to date" placeholder so the brew
    /// surface stays present and discoverable (and the row never inserts/removes under
    /// the cursor as the outdated count changes). Brew-less machines never see it.
    private var showBrewRow: Bool {
        model.brewInstalled
    }

    /// A single footer row mirroring a bare terminal `brew upgrade`, scoped to CLI
    /// formulae. Casks are managed per-app in the list above, so this never
    /// double-counts them.
    @ViewBuilder
    private var brewFormulaRow: some View {
        if model.brewUpgrading {
            // Keep the same `terminal` identity icon the idle/checking states show, so
            // the row stays recognizably "the brew CLI surface" mid-upgrade — only the
            // trailing control swaps to a spinner. Mirror the real row's icon + two-line
            // VStack structure EXACTLY (like the checking state does) so clicking
            // Upgrade doesn't collapse the row from two lines to one and jolt the
            // popover's height — the live `brew upgrade` line goes on the subtitle row.
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Upgrading Homebrew formulae")
                        .font(.caption).fontWeight(.medium)
                    Text(model.brewBulkProgressText ?? String(localized: "Running brew upgrade…"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .monospacedDigit()
                }
                Spacer()
                ProgressView().controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else if !model.brewChecked && model.brewOutdatedFormulae.isEmpty {
            // First check still in flight — mirror the real row's structure (icon +
            // two-line VStack) EXACTLY so it's the same height and the result swaps in
            // without moving anything below it. The row height is driven by the
            // two-line VStack, so the trailing spinner-vs-button difference is moot.
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Checking Homebrew…")
                        .font(.caption).fontWeight(.medium)
                    Text("Reading outdated formulae")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                ProgressView().controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else if model.brewOutdatedFormulae.isEmpty {
            // Checked, nothing outdated — the placeholder. Keeps the same icon +
            // two-line structure as the outdated row, with a green seal instead of an
            // Upgrade button, so the brew surface stays present and recognizably idle.
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Homebrew packages up to date")
                        .font(.caption).fontWeight(.medium)
                    Text(brewUpToDateSummary)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            let count = model.brewOutdatedFormulae.count
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    // "package", not "formula": this surface also carries casks that
                    // install no app (CLIs, fonts), which have no per-app row.
                    Text("\(count) brew packages outdated")
                        .font(.caption).fontWeight(.medium)
                    if let error = model.brewUpgradeError {
                        Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
                    } else {
                        Text(brewFormulaSummary)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Upgrade") { Task { await model.upgradeBrewFormulae() } }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .help("Runs `brew upgrade --formula`, then upgrades any listed cask by name. Covers command-line formulae plus casks that install no app (CLIs, fonts) — those have no row of their own. GUI casks are managed per-app above and are never touched. The count reads your local tap; brew refreshes itself during the upgrade, so it still lands the latest.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// "wget, fd, ripgrep…" — the first few outdated formula names as a one-line hint.
    private var brewFormulaSummary: String {
        let names = model.brewOutdatedFormulae.prefix(4).map(\.name)
        let more = model.brewOutdatedFormulae.count > names.count ? "…" : ""
        return names.joined(separator: ", ") + more
    }

    /// Subtitle for the up-to-date placeholder — the count of top-level formulae we
    /// track, so the idle row still says something concrete. Falls back to a plain
    /// line when the leaf count isn't available yet.
    private var brewUpToDateSummary: String {
        let n = model.brewFormulae.count
        guard n > 0 else { return String(localized: "All command-line formulae are current.") }
        return String(localized: "\(n) top-level formulae · all current")
    }
}

/// The readouts a downloading row can wear, widest first — `AppRow` walks them
/// in this order and takes the first one the app's name leaves room for.
///
/// The widths are what the group actually lays out to: the indicator, the 4pt
/// HStack spacing, and the percentage's fixed 32pt slot.
private enum DownloadReadout: CaseIterable {
    case barAndPercent      // 86pt
    case ringAndPercent     // 51pt
    case ringOnly           // 15pt

    static let bar: CGFloat = 50
    static let ring: CGFloat = 15
    static let spinner: CGFloat = 16
    static let percent: CGFloat = 32

    var contentWidth: CGFloat {
        switch self {
        case .barAndPercent: Self.bar + 4 + Self.percent
        case .ringAndPercent: Self.ring + 4 + Self.percent
        case .ringOnly: Self.ring
        }
    }
}

/// A determinate progress ring, 15pt across — the compact stand-in for the
/// bar-plus-percentage readout on rows whose name needs the horizontal space.
///
/// Drawn rather than borrowed from `ProgressView(value:).progressViewStyle(.circular)`
/// so the diameter and the tint are ours to fix at the size the row can afford.
/// The floor on `trim` keeps a just-started download visibly a ring rather than
/// a bare grey circle.
private struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

private struct AppRow: View {
    let result: UpdateResult
    @Bindable var model: AppListModel
    @Environment(\.openWindow) private var openWindow
    @State private var showRegionHint = false
    @State private var showMajorWarning = false
    @State private var showMacCompatHint = false

    private var stage: InstallStage? { model.installing[result.id] }
    private var installError: String? { model.installErrors[result.id] }

    /// How wide the name line wants to be — the name plus whatever shares its
    /// row (the running dot, a channel chip). Measured with AppKit rather than
    /// left to `ViewThatFits`: the progress control is inflexible, so an HStack
    /// hands it its ideal width and it never feels the pressure a long name is
    /// under. Measuring is the only way to see the collision coming.
    private var nameLineWidth: CGFloat {
        var width = NSAttributedString(
            string: result.app.name,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).size().width
        if model.isRunning(result) { width += 6 + 6 }   // dot + HStack spacing
        let tag = ChannelTag.measuredWidth(for: result.app.releaseChannel)
        if tag > 0 { width += tag + 6 }
        return width
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
        let installed = result.installedDisplay ?? "?"
        let from = bump.map { "\(installed) (\($0.installed))" } ?? installed
        let to = bump.map { "\(latest) (\($0.remote))" } ?? latest
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

    /// How much of a download readout the name leaves room for. Widest first —
    /// the number is worth keeping as long as it fits, so the bar is what goes
    /// before the percentage does.
    private var downloadReadout: DownloadReadout {
        for style in DownloadReadout.allCases where nameFits(besideReadout: style.contentWidth) {
            return style
        }
        return .ringOnly
    }

    /// Whether the spinner keeps its stage name ("Extracting", "Installing").
    /// Measured per label, not per widest label: "Queued" is 12pt narrower than
    /// "Extracting", and that difference decides the case for a long name.
    private func showsStageLabel(_ stage: InstallStage) -> Bool {
        let label = NSAttributedString(
            string: stageLabel(stage),
            attributes: [.font: NSFont.preferredFont(forTextStyle: .caption2)]
        ).size().width
        return nameFits(besideReadout: max(64, DownloadReadout.spinner + 4 + label))
    }

    /// The width the trailing slot reserves. 64pt is the shared one every button
    /// and badge uses; a readout that has already given up width for the name
    /// must give up its reservation too, or it hands back only the difference.
    ///
    /// A *floor*, not the control's width, and that distinction is what keeps
    /// this honest in other languages. Measured on the real popover, the buttons
    /// run past 64pt as soon as the labels are translated — Update is 58.5pt in
    /// English, 73.0 in Russian, 88.0 in German; Relaunch is 68.5 / 102.5 / 81.5.
    /// Because the HStack hands a control its ideal width and the `Spacer` eats
    /// the slack, a wider button simply takes what it needs and the name column
    /// gets the rest (227.5pt in English, 214.5 in German, 193.5 in Russian). So
    /// the reservation being English-shaped costs nothing.
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
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(result.app.name).font(.body)
                        if model.isRunning(result) { RunningIndicator(size: 6) }
                        ChannelTag(channel: result.app.releaseChannel)
                    }
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
                trailing
                    .frame(minWidth: trailingSlot, alignment: .trailing)
            }
            if let installError {
                VStack(alignment: .leading, spacing: 3) {
                    Text(installError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
            } else if let note = model.installNotes[result.id] {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
        Divider()
        if result.hasUpdate {
            let offered = result.remote?.displayVersion ?? String(localized: "this version")
            if model.prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) {
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
        // The way back out of a dismissed administrator prompt. Shown only while
        // that is actually why the row reads "Open", so it never appears as a
        // mysterious no-op on an app that was never asked about.
        if model.isElevationDeclined(result) {
            Button("Ask for administrator access again") { model.allowElevatedInstall(result) }
        }
        if let version = model.backupVersion(result.id) {
            Divider()
            Button("Roll back to \(version)") { Task { await model.rollback(result) } }
        }
        // Store-managed apps update through Apple's own apps — give a direct way
        // to jump there from the row, since we don't drive those installs.
        if appStorePageURL != nil || result.app.isTestFlightApp {
            Divider()
            if appStorePageURL != nil {
                Button("Open in App Store") { openAppStorePage() }
            }
            if result.app.isTestFlightApp {
                // TestFlight has no working per-app deep link on macOS (the iOS
                // `itms-beta://…/v1/app/<id>` form just opens the app list), so this
                // only launches TestFlight — labelled plainly to not over-promise.
                Button("Open TestFlight") { openTestFlight() }
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
        if let staged = model.actionableStaged(result) {
            // Relaunch applies this staged build, which `actionableStaged` guarantees
            // is the latest — so the line is a plain installed → staged. (A staged
            // build that trails the latest isn't shown as Relaunch; it goes through
            // the normal updateAvailable line/Update button below.)
            stagedVersionLine(staged)
        } else if let older = model.downgradeNote(result) {
            // Vendor's latest is *older* than what's installed — show it muted with a
            // down-arrow (only reachable under "Show all", since the row is upToDate).
            downgradeVersionLine(older)
        } else if let from = model.pendingBatchRestart[result.id] {
            // Update All has landed the new bundle but intentionally postpones its
            // process-version sweep/restarts until every installer is finished.
            // Keep the row concrete instead of flashing a false completion.
            restartVersionLine(from: .init(marketing: from))
        } else if model.needsRestart.contains(result.id),
                  let from = model.restartFromSide(result.id) {
            // Self-updated on disk, restart pending. Show the running version → the
            // installed version so the row reads as a real change, not a static
            // "v1.6.1". `lsappinfo` only exposes the running *build*; `restartFromVersion`
            // recovers the marketing version from the rollback backup when it can, so
            // the from side reads "26.609.71450 (3965)" rather than a bare "3965".
            restartVersionLine(from: from)
        } else {
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
    @ViewBuilder
    private func stagedVersionLine(_ staged: StagedSelfUpdate) -> some View {
        HStack(spacing: 4) {
            Text(result.app.shortVersion ?? "?")
            Image(systemName: "arrow.right").font(.caption2)
            Text(staged.version).fontWeight(.semibold).foregroundStyle(.tint)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// The installed-version side of the "from → to" line.
    @ViewBuilder
    private func fromVersion(latest: String) -> some View {
        let marketing = result.installedDisplay ?? "?"
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
        if let bump = result.buildBump(latest: latest) {
            Text("\(latest) ").foregroundStyle(.secondary)
            + Text("(\(bump.remote))").fontWeight(.semibold).foregroundStyle(.tint)
        } else {
            Text(latest).fontWeight(.semibold).foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let appName = model.awaitingQuitConfirm[result.id] {
            // An incremental App Store update finished downloading but the app is
            // running, so App Store is asking to quit it. We paused rather than
            // quitting the user's app mid-work — tapping this presses Continue (and
            // we reopen the app once the new build lands).
            quitToFinishButton(appName)
        } else if model.relaunching.contains(result.id) {
            // Mid-relaunch: the app is quit and we're waiting for the swap to land —
            // either its own ShipIt (staged self-update) or storedownloadd after we
            // pressed App Store's Continue. A spinner here both signals progress and
            // (because it replaces the button) prevents a second click firing again.
            relaunchingIndicator
        } else if model.pendingBatchRestart[result.id] != nil {
            pendingBatchRestartButton
        } else if model.justUpdated.contains(result.id) {
            // Just landed and fully in effect — a brief confirmation so the row reads
            // as "done", not as a progress bar that vanished. It clears itself after a
            // couple of seconds, then the up-to-date row filters out.
            updatedIndicator
        } else if let stage {
            installProgress(stage)
        } else if model.prefs.isIgnored(result.app) {
            // Surfaced only under "Show all" — a muted tag with manage actions in
            // the context menu, so an ignored app never offers an Update button.
            ignoredTag
        } else if result.hasUpdate
            && model.prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) {
            skippedTag
        } else if let staged = model.actionableStaged(result) {
            // The app's own updater already downloaded *the latest* and is waiting to
            // swap it in on the next quit ("Relaunch to update"). Offer the relaunch
            // — never our own Update — so we don't re-download the same bytes or
            // collide with the pending swap. Only when the staged build IS the latest:
            // a staged build that trails a newer release falls through to Update (a
            // direct jump), since relaunching to it wouldn't get you current.
            relaunchToUpdateButton(staged)
        } else if model.needsRestart.contains(result.id) && !result.hasUpdate {
            // Restart is derived from disk-vs-running version, not the remote
            // check — so surface it directly off `needsRestart` rather than from
            // inside the status switch. That keeps the button steady across a
            // refresh's transient `.unknown`/`.checking` statuses, instead of
            // briefly flashing the source hint ("—") until the check finishes.
            restartButton
        } else {
            switch result.status {
            case .updateAvailable:
                if result.remote?.sourceName == "Toolbox" || result.app.isToolboxManaged {
                    // Toolbox owns the install. Either Toolbox's own cache detected
                    // it, or we borrowed a vendor probe to read the version reliably
                    // (Android Studio previews — see `prefersVendorProbeOverToolbox`);
                    // either way the action is "open Toolbox", never an in-place swap.
                    toolboxButton
                } else if result.remote?.sourceName == "TestFlight" {
                    // Detected via TestFlight's cache — it installs, we just route.
                    testFlightButton
                } else if model.defersToSelfUpdater(result) {
                    // Running self-updating app + "defer while running" policy:
                    // open its own update path instead of swapping under it.
                    openSelfUpdaterButton
                } else if result.isMajorUpgrade && (model.canAutoInstall(result) || model.requiresInstaller(result)) {
                    majorUpgradeBadge
                } else if model.canAutoInstall(result) {
                    autoUpdateButton
                } else if model.requiresInstaller(result) {
                    installerButton
                } else if let info = result.remote?.appStore {
                    appStoreTrailing(info)
                } else {
                    openButton
                }
            case .error:
                errorBadge
            case .unknown:
                Text(sourceHint).font(.caption2).foregroundStyle(.tertiary)
            case .appStoreManaged:
                appStoreManagedLabel
            case .toolboxManaged:
                toolboxButton
            case .testFlightManaged:
                testFlightManagedLabel
            case .upToDate:
                // needsRestart is handled above, before the status switch.
                if result.app.isMASApp {
                    // We checked it against the store and it's current — but keep
                    // the "App Store" signal so a managed app never looks like an
                    // app we can update ourselves (a bare ✅ reads the same as
                    // Sparkle/brew). Same label as `.appStoreManaged`.
                    appStoreManagedLabel
                } else if result.app.isTestFlightApp {
                    // Current on TestFlight — keep the channel tag rather than a
                    // bare check, so it never reads like a self-updatable app.
                    testFlightManagedLabel
                } else {
                    Image(systemName: "checkmark").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func installProgress(_ stage: InstallStage) -> some View {
        if case .downloading(let f) = stage {
            downloadProgress(f)
        } else {
            stageProgress(stage)
        }
    }

    /// The download readout, as wide as the name can afford. Every variant ends
    /// on the row's trailing edge and carries the percentage where there's room
    /// for it — losing the bar costs nothing you can't read off the number, but
    /// losing the number leaves the row saying only "something is happening".
    @ViewBuilder
    private func downloadProgress(_ f: Double) -> some View {
        switch downloadReadout {
        case .barAndPercent:
            HStack(spacing: 4) {
                ProgressView(value: f).frame(width: 50).controlSize(.small)
                percentLabel(f)
            }
            // Centre the bar+label as a tight group in the same minimum-width slot
            // the buttons use, so it lines up down the list. It has to be a
            // *minimum*: the bar plus the percentage is wider than 64pt, and a hard
            // width made the number overflow past the row's trailing edge. The
            // percentage's own fixed width keeps the row from reflowing as it
            // counts up.
            .frame(minWidth: 64, alignment: .center)
        case .ringAndPercent:
            HStack(spacing: 4) {
                ProgressRing(value: f)
                percentLabel(f)
            }
        case .ringOnly:
            // Only for a name long enough that even 32pt of digits would wrap it.
            ProgressRing(value: f)
                .help("Downloading \(result.app.name) — \(Int(f * 100))%")
        }
    }

    /// Fixed-width, right-aligned, monospaced digits: "2%" and "100%" both end at
    /// the same edge, so neither the bar nor the row moves as it counts up.
    /// "100%" at caption2 with monospaced digits measures 28.6pt, so the old 29pt
    /// slot left 0.4pt of slack and SwiftUI wrapped it to "100" over "%". 32pt
    /// gives it real room, and lineLimit+fixedSize make a wrap impossible however
    /// the metrics land.
    private func percentLabel(_ f: Double) -> some View {
        Text("\(Int(f * 100))%")
            .font(.caption2).foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 32, alignment: .trailing)
    }

    /// The non-download stages: a spinner, named where the name column can spare
    /// the width. When it can't, the stage moves into the tooltip.
    @ViewBuilder
    private func stageProgress(_ stage: InstallStage) -> some View {
        if showsStageLabel(stage) {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(stageLabel(stage))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 64, alignment: .center)
        } else {
            ProgressView().controlSize(.small)
                .help("\(stageLabel(stage)) \(result.app.name)")
        }
    }

    private func stageLabel(_ stage: InstallStage) -> String {
        switch stage {
        case .queued: return String(localized: "Queued")
        case .checking: return String(localized: "Checking")
        case .downloading(let f): return String(localized: "\(Int(f * 100))%")
        case .verifyingSignature, .verifyingCodeSignature: return String(localized: "Verifying")
        case .extracting: return String(localized: "Extracting")
        case .installing: return String(localized: "Installing")
        case .runningCommand: return String(localized: "Installing")
        case .done: return String(localized: "Installed")
        }
    }

    private var autoUpdateButton: some View {
        Button("Update") { Task { await model.install(result) } }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
    }

    /// Muted tag for an app the user has chosen to ignore — right-click to manage.
    private var ignoredTag: some View {
        Text("Ignored").font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.7)
            .help("Hidden from update checks — right-click to stop ignoring")
    }

    /// Muted tag for an update whose offered version the user skipped.
    private var skippedTag: some View {
        Text("Skipped").font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.7)
            .help("You skipped this version — right-click to un-skip")
    }

    /// On disk it's current, but the running instance is older — offer a
    /// relaunch so the update actually takes effect.
    private var restartButton: some View {
        Button("Relaunch") { Task { await model.restart(result) } }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help(restartHelp)
    }

    /// The bundle is current, but Update All is still busy with other apps and has
    /// not reached its deferred restart phase. Keep an explicit action available so
    /// a slow unrelated installer never makes this completed download look lost.
    private var pendingBatchRestartButton: some View {
        Button("Relaunch now") { Task { await model.restart(result) } }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("Installed \(result.app.shortVersion ?? String(localized: "the new version")) — waiting for Update All to finish before relaunching; click to relaunch now")
    }

    /// The app self-downloaded a newer build (Squirrel/ShipIt staged it); a
    /// relaunch swaps it in. Unlike `restartButton` this routes to
    /// `relaunchStagedUpdate`, which quits the app and lets *its own* ShipIt do the
    /// swap+relaunch (reopening it ourselves makes ShipIt abort). No extra download
    /// — the bytes are already staged on disk.
    private func relaunchToUpdateButton(_ staged: StagedSelfUpdate) -> some View {
        Button("Relaunch") { Task { await model.relaunchStagedUpdate(result) } }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(result.app.name) already downloaded \(staged.version) — relaunch to apply it (no extra download; a large app may take a minute to swap & reopen)")
    }

    /// An incremental App Store update is downloaded but the app is running, so the
    /// store wants to quit it to install. Tapping presses the store's Continue (via
    /// the AX installer's awaited `confirmQuit`); the app quits, the update lands,
    /// and we reopen it. Labelled "Relaunch" like every other quit-to-apply action.
    private func quitToFinishButton(_ appName: String) -> some View {
        Button("Relaunch") { model.confirmQuit(result.id, proceed: true) }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(appName.isEmpty ? result.app.name : appName) must quit to finish updating — click to quit it, install, and reopen")
    }

    /// Shown while a staged relaunch is in flight: the app is quit and its own
    /// ShipIt is swapping the bundle. Matches the install spinner's footprint.
    private var relaunchingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Relaunching…")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 64, alignment: .center)
        .help("Quit \(result.app.name) — waiting for it to swap in the new version and reopen")
    }

    private var updatedIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Updated")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 64, alignment: .center)
        .help("\(result.app.name) updated to \(result.app.shortVersion ?? String(localized: "the latest version"))")
    }

    private var restartHelp: String {
        let disk = result.app.shortVersion ?? String(localized: "the new version")
        if let running = model.runningVersion(result.id) {
            return String(localized: "Running \(running) but \(disk) is installed — relaunch to apply it")
        }
        return String(localized: "You’re running an older version — relaunch to finish updating")
    }

    /// pkg cask: download the official installer and open it (system installer
    /// asks for admin). Not an in-place swap, so it's a plain bordered button.
    @ViewBuilder
    private var installerButton: some View {
        if let staged = model.stagedPackage(for: result) {
            // Already downloaded and handed to macOS's installer. Re-opening costs
            // nothing (and re-uses the installer window if it's still open), so don't
            // make the user pull hundreds of megabytes down a second time because
            // they dismissed it.
            Button("Install") { Task { await model.openStagedPackage(result) } }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help("\(staged.url.lastPathComponent) is already downloaded — opens it in macOS's installer (asks for admin). Nothing is downloaded again.")
        } else {
            Button("Update") { Task { await model.install(result) } }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("Downloads the official installer and opens it (asks for admin)")
        }
    }

    /// Major version bumps may cross a paid app's license boundary. Like the
    /// region-lock case, we don't offer a one-click button — an amber badge
    /// opens a popover that explains the risk before any install.
    private var majorUpgradeBadge: some View {
        Button { showMajorWarning = true } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help("Major version upgrade — click before updating")
        .popover(isPresented: $showMajorWarning, arrowEdge: .bottom) {
            majorUpgradePopover
        }
    }

    private var majorUpgradePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Major version upgrade", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("\(result.app.name) \(result.app.shortVersion ?? "?") → \(result.remote?.displayVersion ?? "?") is a major new version. If this is a commercial app, it may need a new license — with an expired subscription the update can drop into a limited/trial mode.")
                .font(.callout)
            Text("Continue only if it’s free or your license covers the new version. Your current version is moved to the Trash, so you can restore it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Update anyway") {
                showMajorWarning = false
                Task { await model.install(result) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290)
    }

    /// Fallback for updates we can detect but not install in place (GitHub
    /// releases, self-updating apps like Chrome). Opens the official download /
    /// releases page in the browser so the user can grab it through the app's own
    /// channel; only reveals in Finder if there's no URL to open.
    private var openButton: some View {
        Button("Open") { openAction() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help(openHelp)
    }

    /// Shown for a running self-updating app under the "defer while running"
    /// policy: open the app's own update path rather than installing over it.
    private var openSelfUpdaterButton: some View {
        Button("Open") { model.openSelfUpdater(result) }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("\(result.app.name) is running — open it and let its own updater apply \(result.remote?.displayVersion ?? String(localized: "the update")). Quit it, or pick “Always replace” in Settings, to install directly.")
    }

    private func openAction() {
        guard let url = result.remote?.pageURL else {
            NSWorkspace.shared.activateFileViewerSelecting([result.app.path])
            return
        }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            // App-internal deep link (e.g. chrome://settings/help). Hand it to the
            // app itself so it acts through its own update channel — for Chrome,
            // opening that page triggers a Keystone update check + download.
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: result.app.path, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// JetBrains Toolbox manages this app's updates. Toolbox registers no URL
    /// scheme, so there's no per-tool deep link — we just open the Toolbox window,
    /// where the user updates it through its own channel.
    private var toolboxButton: some View {
        Button("Toolbox") { openToolbox() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")
    }

    private func openToolbox() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.jetbrains.toolbox") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// TestFlight manages this beta's updates. There's no per-app deep link we can
    /// rely on, so we just open TestFlight, where the user installs the update
    /// through its own channel.
    private var testFlightButton: some View {
        Button("TestFlight") { openTestFlight() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by TestFlight — open TestFlight to update \(result.app.name)")
    }

    private func openTestFlight() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.TestFlight") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private var openHelp: String {
        guard let url = result.remote?.pageURL else { return String(localized: "Reveal in Finder") }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            return String(localized: "Open \(result.app.name)’s built-in updater (it updates itself)")
        }
        return String(localized: "Open the official download page")
    }

    /// App Store apps: when the app is in the signed-in region, a Get button
    /// deep-links to the product page; when it isn't, a globe badge opens a
    /// popover explaining the region lock (the store would just say "App Not
    /// Available").
    @ViewBuilder
    private func appStoreTrailing(_ info: AppStoreAvailability) -> some View {
        if info.isLatestMacIncompatible {
            // A newer build exists but Apple has marked it as no longer running on
            // Macs — installing it here is impossible, so flag it rather than
            // offering a "Get" the store would reject.
            Button { showMacCompatHint = true } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("The latest version no longer supports this Mac — click for details")
            .popover(isPresented: $showMacCompatHint, arrowEdge: .bottom) {
                macCompatHintPopover(info)
            }
        } else if info.isRegionMismatch {
            Button { showRegionHint = true } label: {
                Image(systemName: "globe.badge.chevron.backward")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("Not available in your App Store region — click for details")
            .popover(isPresented: $showRegionHint, arrowEdge: .bottom) {
                regionHintPopover(info)
            }
        } else if result.app.isiOSAppOnMac {
            // Wrapped iPhone/iPad app: mas can't update it and the AX route is
            // unreliable for these, so the dependable path is the App Store app
            // itself. Send the user to its product page, where an available update
            // shows an "Update" button — rather than offering a one-click that fails.
            Button("App Store") { openInAppStore(info) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("Update \(result.app.name) in the App Store — iPhone/iPad apps can’t be updated from here")
        } else {
            // A redirect, not a one-click — the App Store route needs the privileged
            // helper approved (`UpdatePolicy.canAutoInstall`, case "App Store"). But
            // the row IS an installed app with a pending update, which the store
            // itself calls **Update**; "Get" reads as "not installed yet", and no row
            // that reaches here ever is. The help text carries the real reason.
            Button("Update") { openInAppStore(info) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help(appStoreRedirectHelp)
        }
    }

    /// Why this row hands off to the App Store instead of installing in place.
    /// Approving the helper is the one lever the user actually has, so name it when
    /// that's what's missing — otherwise the button just looks like something we
    /// decline to do, with nothing to act on.
    private var appStoreRedirectHelp: String {
        if !model.helperEnabled {
            return String(localized: "Opens \(result.app.name) in the App Store. Turn on the background helper in Settings to install App Store updates in one click.")
        }
        return String(localized: "Update \(result.app.name) in the App Store")
    }

    private func openInAppStore(_ info: AppStoreAvailability) {
        if let url = info.deepLink ?? result.remote?.pageURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func regionHintPopover(_ info: AppStoreAvailability) -> some View {
        let here = info.homeRegion.map(Self.regionName) ?? String(localized: "your region")
        let there = Self.regionName(info.availableRegion)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Region-locked", systemImage: "globe.badge.chevron.backward")
                .font(.headline)
            Text("\(result.app.name) isn’t in your App Store region (\(here)). It’s listed in \(there)\(result.remote?.displayVersion.map { String(localized: " — latest \($0)") } ?? "").")
                .font(.callout)
            // The region lock blocks a *fresh install* (the product page is "App Not
            // Available" under a \(here) account), but it does NOT block updating an
            // app you already have: an installed region-locked app still shows up in
            // App Store's own Updates list, and DuoUpdater can drive that update
            // entirely in the background. The catch is timing — the store surfaces
            // these into its Updates list on its own schedule.
            Text("You already have it installed, so it can still be updated — DuoUpdater drives the App Store’s Updates list in the background (a fresh install would need a \(there) account). It only works once the App Store has listed this update; if it hasn’t yet, try again later.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Update in background") {
                    showRegionHint = false
                    Task { await model.install(result) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Open App Store") { openInAppStore(info) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func macCompatHintPopover(_ info: AppStoreAvailability) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not supported on this Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("\(result.app.name) is an iPhone/iPad app running on Apple Silicon. Its latest version\(result.remote?.displayVersion.map { " (\($0))" } ?? "") no longer supports Mac, so the App Store won't install it on this device.")
                .font(.callout)
            Text("You can keep using the installed version (\(result.app.shortVersion ?? String(localized: "current"))). Updating isn't possible until the developer ships a Mac-compatible build again — it's the vendor's choice, not a refresh problem.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open App Store anyway") { openInAppStore(info) }
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290)
    }

    private static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    /// The "App Store" tag shown for any store-managed app — whether it's up to
    /// date or the lookup returned nothing. Either way, updates are the store's
    /// job, so the row never offers an action we can't perform.
    private var appStoreManagedLabel: some View {
        Image(nsImage: AppIconCache.appStore)
            .resizable()
            .frame(width: 16, height: 16)
            .help("Managed by the App Store — it handles this app's updates")
    }

    /// The "TestFlight" tag shown for a TestFlight-managed app that's current (or
    /// whose cache returned nothing). Updates are TestFlight's job, so the row
    /// shows the channel rather than an action we can't perform here.
    private var testFlightManagedLabel: some View {
        Text("TestFlight").font(.caption2).foregroundStyle(.tertiary)
            .help("Managed by TestFlight — it handles this beta's updates")
    }

    /// A source was tried and failed — most often a transient GitHub rate-limit.
    /// Unlike `.unknown`'s dead "—", this state is retryable, so it's a button:
    /// one click re-checks just this app. The tooltip carries the failure reason.
    private var errorBadge: some View {
        HStack(spacing: 6) {
            // Name the failure inline so a wall of orange retry buttons isn't
            // indistinguishable — a rate-limit (the common no-token case) reads
            // differently from a one-off network error without needing a hover.
            let statusLabel = result.status.isRateLimitError
                ? String(localized: "Rate-limited")
                : String(localized: "Failed")
            Text(statusLabel)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(result.status.isRateLimitError ? Color.orange : Color.secondary)
            Button { Task { await model.retry(result) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help(errorText.isEmpty
                ? String(localized: "Update check failed — click to retry")
                : String(localized: "\(errorText) — click to retry"))
        }
    }

    private var errorText: String {
        if case .error(let e) = result.status { return e }
        return ""
    }

    private var sourceHint: String {
        if result.app.isMASApp { return String(localized: "App Store") }
        if result.app.sparkleFeedURL != nil { return String(localized: "Sparkle") }
        return "—"
    }
}

// MARK: - Shared version-line formatting

extension UpdateResult {

}
