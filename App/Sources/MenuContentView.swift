import SwiftUI
import AppKit
import DuoUpdaterCore

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
            // focus from whatever you were in, and if a Duo Updater window is parked
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
            // `isRoundInFlight`, not `isScanning`: a user-present refresh clears the
            // saved release notes BEFORE it raises `isScanning`, and that await lets
            // a cold launch paint here with no rows yet — which read "No apps yet"
            // over a scan that was about to start (#253's gap, one surface over).
            let emptyTitle = model.listActivity.isRoundInFlight
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

private struct AppRow: View {
    let result: UpdateResult
    @Bindable var model: AppListModel
    @Environment(\.openWindow) private var openWindow

    private var stage: InstallStage? { model.installing[result.id] }
    private var installError: String? { model.installErrors[result.id] }

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
            // No optical nudge here: this mark is nearly cap-height, so it is judged
            // by its edges rather than its centre. See `RunningIndicator.opticalNudge`.
            if let runtime {
                RuntimeTag(runtime: runtime, bundle: result.app.path,
                           frameworks: result.app.linkedFrameworks)
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
            string: installStageLabel(stage),
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
                        openStagedPackage: { Task { await model.openStagedPackage(result) } },
                        retry: { Task { await model.retry(result) } },
                        restart: { Task { await model.restart(result) } },
                        relaunchStaged: { Task { await model.relaunchStagedUpdate(result) } },
                        confirmQuit: { model.confirmQuit(result.id, proceed: true) },
                        openSelfUpdater: { model.openSelfUpdater(result) },
                        openToolbox: { model.openToolbox() },
                        openTestFlight: { model.openTestFlight() }),
                    runningVersion: model.runningVersion(result.id),
                    helperEnabled: model.helperEnabled,
                    downloadReadout: downloadReadout,
                    showsStageLabel: showsStageLabel)
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
            } else if let note = model.installNotes[result.id] ?? model.stagedPackageNote(for: result) {
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
            let offered = result.remote?.displayVersion ?? String(localized: "this version")
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
                Button("Open TestFlight") { model.openTestFlight() }
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
        case .stagedRelaunch(let staged):
            // Relaunch applies this staged build, which `actionableStaged` guarantees
            // is the latest — so the line is a plain installed → staged. (A staged
            // build that trails the latest isn't shown as Relaunch; it goes through
            // the normal updateAvailable line/Update button below.)
            stagedVersionLine(staged)
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

}

// MARK: - Shared version-line formatting

extension UpdateResult {

}
