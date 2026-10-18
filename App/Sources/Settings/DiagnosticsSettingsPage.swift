import SwiftUI
import AppKit
import DuoUpdaterCore

/// Permissions, the last check, and per-recipe detection health.
struct DiagnosticsSettingsPage: View {
    let model: AppListModel
    @Environment(\.openWindow) private var openWindow
    /// A search result being revealed: a recipe row past the first ten opens the
    /// list first, or there would be no row to scroll to.
    @Environment(\.settingsReveal) private var reveal
    @State private var showsAllRecipes = false
    /// The reveal already acted on. A reveal stands for as long as the page is
    /// shown, and every check publishes a new snapshot, so without this the list
    /// reopened at the end of each check after the user had pressed Show Fewer.
    @State private var handledReveal: Int?

    /// Rows shown before "Show All": every flagged recipe (they sort first, and
    /// one is never hidden) and at least this many in all.
    private static let collapsedRecipeCount = 10

    /// bundleID → app name, so a recipe whose id carries a bundle id shows a
    /// friendly name next to it (`RecipeHealth.Entry.displayName(resolving:)` does
    /// the resolving — an id is `vendor:<bundle id>:<channel>`, not a bare bundle
    /// id). A GitHub rule's id carries `owner/repo` and no bundle id, so those
    /// still render as the raw key.
    private var names: [String: String] {
        var map: [String: String] = [:]
        for result in model.results {
            if let id = result.app.bundleID { map[id] = result.app.name }
        }
        return map
    }

    /// bundleID → the installed app's path, for the icon beside each row.
    private var appPaths: [String: String] {
        var map: [String: String] = [:]
        for result in model.results {
            if let id = result.app.bundleID { map[id] = result.app.path.path }
        }
        return map
    }

    private func collapsedLimit(_ entries: [RecipeHealth.Entry]) -> Int {
        max(Self.collapsedRecipeCount, entries.count { !$0.isHealthy })
    }

    /// Once per reveal, and only once the row is in the list: the search can read
    /// a newer snapshot than the model holds (a changelog load records a recipe
    /// between checks), and the page's own reload then brings the row in.
    private func openRecipesIfRevealHidden() {
        guard let reveal, case .recipe(let key) = reveal.anchor,
              reveal.token != handledReveal, let entries = model.recipeHealth,
              let index = entries.firstIndex(where: { $0.key == key })
        else { return }
        handledReveal = reveal.token
        if index >= collapsedLimit(entries) { showsAllRecipes = true }
    }

    var body: some View {
        SettingsPage(section: .diagnostics) {
            permissionsCard
            lastCheckCard
            failuresCard.settingsAnchor(.recentFailures)
            recipesCard.settingsAnchor(.recipes)
        }
        // The model also re-reads it at the end of every check, which keeps an
        // open page current; this covers what was recorded since.
        .task { await model.reloadRecipeHealth() }
        .onChange(of: reveal, initial: true) { openRecipesIfRevealHidden() }
        .onChange(of: model.recipeHealth) { openRecipesIfRevealHidden() }
        .task { await model.reloadRecentFailures() }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        SettingsCard(header: "Permissions") {
            // App Management has no *public* status API, but the private
            // TCCAccessPreflight SPI lets us read it — so show a real check when granted.
            SettingsField(title: "App Management", detail: "Lets DuoUpdater replace apps updated outside the App Store (Sparkle, Homebrew, direct downloads)") {
                if model.appManagementStatus == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    // macOS can't grant it programmatically; the flow is a panel the
                    // user drags the app into, which the button would not otherwise say.
                    Button("Grant…") { model.presentAppManagementPermissionFlow() }
                        .settingsGlassButton()
                        .help("Open System Settings with a panel to drag DuoUpdater into")
                }
            }
            .settingsAnchor(.appManagement)
            SettingsDivider()
            // Optional: without it nothing reads TestFlight's store, CotEditor's
            // container or Open Screen Sharing's group container
            // (`TCCPreflight.admitsOtherAppsData`).
            SettingsField(title: "Full Disk Access", detail: "Needed to check TestFlight betas and the beta or nightly channel of CotEditor and Open Screen Sharing") {
                if model.fullDiskAccessStatus == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Grant…") { model.presentFullDiskAccessPermissionFlow() }
                        .settingsGlassButton()
                }
            }
            .settingsAnchor(.fullDiskAccess)
            SettingsDivider()
            // Privileged helper: a one-time approval that lets App Store ("full")
            // updates run without a password each time.
            HelperStatusRow(helper: model.helperClient)
                .settingsAnchor(.appStoreHelper)
            SettingsDivider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button("Run Setup Again…") {
                        openWindow(id: WelcomeView.windowID)
                        model.surfaceWindow(sceneID: WelcomeView.windowID)
                    }
                    .settingsGlassButton()
                    Button("Relaunch DuoUpdater") { Self.relaunch() }
                        .settingsGlassButton()
                    Spacer(minLength: 0)
                }
                // Next to the button it is about. Granting through the drag panel
                // doesn't trigger the system's usual "Quit & Reopen", so a fresh
                // grant can read Granted above and still not be in effect.
                Text("Just granted a permission? It may not take effect until DuoUpdater relaunches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsRow()
        }
    }

    // MARK: - Last check

    private var lastCheckCard: some View {
        SettingsCard {
            SettingsField(title: "Last checked") {
                Text(model.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Not yet"))
                    .foregroundStyle(.secondary)
            }
            .settingsAnchor(.lastChecked)
        }
    }

    // MARK: - Recent failures

    private var failuresCard: some View {
        SettingsCard(
            header: "Recent failures",
            footer: "Updates that didn’t install in the last 30 days. Kept on this Mac only — nothing is sent. Copy a report to include in an issue or an email."
        ) {
            Toggle("Offer to report failed updates", isOn: Binding(
                get: { model.prefs.offerFailureReports },
                set: { model.prefs.offerFailureReports = $0 }))
                .help("Shows “Report this problem…” under an update’s error, once for each app, version and error. Nothing is sent unless you choose to send it.")
                .settingsRow()
            SettingsDivider()
            if model.recentFailures.isEmpty {
                Text("No failed updates recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRow()
            } else {
                let installed = Set(model.results.map(\.app.id))
                ForEach(Array(model.recentFailures.enumerated()), id: \.element.id) { index, event in
                    if let failure = event.failure {
                        if index > 0 { SettingsDivider() }
                        FailureRow(
                            failure: failure, date: event.date,
                            iconPath: installed.contains(failure.appID) ? failure.appID : nil
                        ) {
                            model.openFailureReport(event)
                            openWindow(id: FailureReportView.windowID)
                            model.surfaceWindow(sceneID: FailureReportView.windowID)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recipes

    private var recipesCard: some View {
        SettingsCard(
            header: "Detection recipes",
            footer: "A recipe is flagged when it fetched successfully but couldn’t read a version — often a sign the vendor changed their page. Cleared automatically on the next successful check."
        ) {
            if let entries = model.recipeHealth, !entries.isEmpty {
                // `.key`, not `.id`: the same bundle id can now appear under two
                // different `source`s (e.g. a Vendor recipe and an Electron
                // manifest read both tracking Notion) since `RecipeHealth` keys
                // its entries on `(id, source)`. `.id` alone is a display key and
                // is no longer guaranteed unique across `entries` — see
                // `RecipeHealth.Entry.key`.
                // `names` and `paths` once for the list, not once per row: each
                // walks every app.
                let names = names
                let paths = appPaths
                let installed = Set(paths.keys)
                let limit = collapsedLimit(entries)
                let shown = showsAllRecipes ? entries : Array(entries.prefix(limit))
                // Ten rows by default: all ~150 laid out up front held every visit
                // back by ~200 ms. Not a LazyVStack — measured, it guessed the
                // list's height, drew the last rows over "Show All" and then slid
                // the bottom of the page into place over ~300 ms.
                ForEach(Array(shown.enumerated()), id: \.element.key) { index, entry in
                    if index > 0 { SettingsDivider() }
                    recipeRow(entry, names: names, paths: paths, installed: installed)
                        .settingsAnchor(.recipe(entry.key))
                }
                if entries.count > limit {
                    SettingsDivider()
                    Button(showsAllRecipes
                           ? String(localized: "Show Fewer")
                           : String(localized: "Show All \(entries.count)")) {
                        showsAllRecipes.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .settingsRow()
                }
            } else if model.recipeHealth == nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading recipe health…").foregroundStyle(.secondary)
                }
                .settingsRow()
            } else {
                Text("No recipe-backed apps have been checked yet this session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRow()
            }
        }
    }

    private func recipeRow(
        _ entry: RecipeHealth.Entry, names: [String: String], paths: [String: String],
        installed: Set<String>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.isHealthy ? .green : .orange)
            // The app the recipe is about, when it is installed here; an empty slot
            // otherwise, so the names still line up.
            Group {
                if let id = entry.bundleID(among: installed), let path = paths[id] {
                    Image(nsImage: AppIconCache.icon(for: path)).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName(resolving: names)).font(.callout)
                if !entry.isHealthy, let detail = entry.lastMissDetail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(entry.source).font(.caption2).foregroundStyle(.tertiary)
        }
        .settingsRow()
    }

    /// Terminate this instance, then spawn a fresh one — the standard "restart
    /// myself" handoff. `open -n` launches a new copy that outlives our exit, so a
    /// permission granted via the drag panel takes effect without the user hunting
    /// for the app in Finder.
    ///
    /// The launch waits for the quit to be certain (`QuitCoordinator`): with an
    /// install in flight the quit waits for it, or the user keeps the app — and
    /// launching first, as this used to, left two copies running side by side.
    private static func relaunch() {
        QuitCoordinator.shared.terminate(thenRun: launchFreshCopy)
    }

    /// offpool-lint:allow — nothing waits on this `open -n`: it runs as the app terminates, so there is no wait for `ChildProcess` to take over.
    private static func launchFreshCopy() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        do {
            try task.run()
        } catch {
            Log.app.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Permissions row for the privileged helper. Observes the client so it flips to
/// "Enabled" once the user approves the background item, and re-queries status on
/// appear (approval happens out-of-app, in System Settings › Login Items).
private struct HelperStatusRow: View {
    @ObservedObject var helper: PrivilegedHelperClient
    /// nil until asked. "Switched on" and "actually answers" are different things —
    /// updating DuoUpdater leaves the previous copy of the helper holding the
    /// slot — and until you press Check there is no way to see which one you have
    /// short of an update failing.
    @State private var answering: Bool?
    /// Guards against a second probe; carries no appearance of its own.
    @State private var inFlight = false
    /// Drives the busy look, and only once a check has been slow enough to be
    /// worth mentioning. A reachable helper answers in tens of milliseconds, and
    /// switching the button to disabled, spinning a spinner and dimming the result
    /// for that long reads as a flicker rather than as progress.
    @State private var checking = false
    @State private var restarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field
            if helper.isEnabled { reachability }
            if let error = helper.lastRegisterError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)  // so the reset command can be copied
                    // Same inset as `settingsRow()` and the reachability line above:
                    // without it several lines of red type run edge to edge across
                    // the card while every other row stops 14pt short.
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
    }

    /// Plain-language result, no protocol vocabulary: people reading this page are
    /// trying to find out whether App Store updates will work, not to learn what
    /// XPC is.
    /// The answer, with the leading icon doubling as the progress indicator: a
    /// spinner occupies exactly the slot the checkmark will, so a check in flight
    /// changes what that 12pt square draws and nothing else — no dimming, no
    /// resizing, no text swapped for text of a different length.
    @ViewBuilder
    private var reachability: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            // Laid out from the start and only drawn once there is something to
            // say: the probe on arrival answers a beat after the page appears,
            // and a line that appeared then pushed everything below it down a row.
            ZStack(alignment: .trailing) {
                HStack(spacing: 6) {
                    statusIcon
                    Text("Responding — App Store updates will work")
                }
                .hidden()
                if checking || answering != nil {
                    HStack(spacing: 6) {
                        statusIcon
                        Text(checking && answering == nil
                             ? String(localized: "Checking…")
                             : (answering == true
                                ? String(localized: "Responding — App Store updates will work")
                                : String(localized: "Switched on but not responding — use Restart Helper")))
                            .foregroundStyle(checking ? Color.secondary
                                             : (answering == true ? Color.green : Color.orange))
                    }
                }
            }
        }
        .font(.caption)
        // Matches `settingsRow()`'s inset — without it this line runs to the card's
        // edge while every row above it stops 14pt short.
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    /// Fixed-size slot: spinner or verdict, same geometry either way.
    @ViewBuilder
    private var statusIcon: some View {
        Group {
            if checking {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Image(systemName: answering == true
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(answering == true ? Color.green : Color.orange)
            }
        }
        .frame(width: 14, height: 14)
    }

    private var checkButton: some View {
        // Title stays put: swapping it for "Checking…" makes the button wider, and
        // in a right-aligned row a wider button grows leftwards — the press moves
        // the thing being pressed. Progress belongs in the result line instead.
        Button("Check") {
            guard !inFlight else { return }
            inFlight = true
            checking = true
            Task {
                // Shown for a minimum beat, not a minimum of work: a healthy helper
                // answers in tens of milliseconds, and a spinner that appears and
                // vanishes inside one frame reads as a glitch rather than as
                // feedback. Every press therefore looks the same from the outside.
                async let settled: Void = Task.sleep(for: .milliseconds(350))
                let reachable = await HelperShellRunner().isAnswering()
                try? await settled
                answering = reachable
                inFlight = false
                checking = false
            }
        }
        .settingsGlassButton()
        .disabled(checking)
        .help("Ask the helper to answer — tells you whether App Store updates can actually run right now")
    }

    private var field: some View {
        Group {
            if helper.isEnabled {
                // One line when it fits, otherwise the buttons drop to a line of
                // their own under the title. At the default window size (680×460)
                // the row is about 390pt wide, and one line didn't fit in any of
                // en, de, es, fr or ru — measured: the title wrapped, "Restart
                // Helper…" truncated, and in Russian "Enabled" itself broke in two.
                // Either way "Enabled" stays last on the title's line — see
                // `enabledLabel`.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text("App Store helper")
                        Spacer(minLength: 8)
                        checkButton
                        restartButton
                        enabledLabel
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("App Store helper")
                            Spacer(minLength: 8)
                            enabledLabel
                        }
                        HStack(spacing: 12) {
                            checkButton
                            restartButton
                        }
                    }
                }
                .settingsRow()
            } else {
                SettingsField(title: "App Store helper") {
                    Button("Enable…") { Task { await helper.register() } }
                        .settingsGlassButton()
                }
            }
        }
        .task { await helper.refreshStatusOffMain() }
        // Probe once on arrival rather than waiting to be asked: this page exists to
        // say whether things work, and "Enabled" alone cannot. It also means the
        // result line is populated from the start, so the first press of Check
        // changes a word rather than growing the card by a row.
        .task { answering = await HelperShellRunner().isAnswering() }
    }

    /// Last on the title's line in both layouts, so this row's "Enabled" lines up
    /// with the "Granted" directly above it: the states read down one column and
    /// the actions sit to their left (or below), instead of the status drifting
    /// inward by however wide the buttons happen to be.
    private var enabledLabel: some View {
        Label("Enabled", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
    }

    // "Enabled" is not the same as "answering". Updating DuoUpdater replaces its
    // bundle while the helper from the old one keeps holding launchd's slot, so the
    // record still reads enabled while every App Store install times out.
    // Re-registering cannot fix that — `register()` on a live record does nothing,
    // measured — so the button offered here is the one that works: kill the stale
    // copy so launchd starts the one belonging to the app that's installed now.
    // Helpers built after this change exit on their own when idle; the button is
    // for the ones already stranded by an older build.
    private var restartButton: some View {
        // Disabled while the authorization panel is up: pressing again would stack
        // a second prompt on the first and kickstart twice.
        Button {
            guard !restarting else { return }
            restarting = true
            Task {
                let restarted = await helper.restartDaemon()
                restarting = false
                // Re-probe rather than assume: the point of the button is that it
                // makes the helper answer again, so show whether it did instead of
                // leaving a stale result on screen.
                if restarted { answering = await HelperShellRunner().isAnswering() }
            }
        } label: {
            // Sized for the wider of its two titles, so the press can't change the
            // row's width — which would move the button under the pointer, and near
            // the threshold flip the row between its one- and two-line layouts.
            ZStack {
                Text("Restart Helper…").hidden()
                Text("Restarting…").hidden()
                Text(restarting ? String(localized: "Restarting…") : String(localized: "Restart Helper…"))
            }
        }
        .settingsGlassButton()
        .disabled(restarting)
        .help("Restart the background helper — use this if App Store updates fail saying the helper isn’t answering. Asks for an administrator password.")
    }
}

/// One recorded failure, with Report… and Copy Report buttons at the top right.
private struct FailureRow: View {
    let failure: InstallFailureEvent
    let date: Date
    /// The app's bundle, when it is still installed where it failed; nil leaves
    /// the slot empty so the names line up, as the recipe rows do.
    let iconPath: String?
    let report: () -> Void
    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Group {
                if let iconPath {
                    Image(nsImage: AppIconCache.icon(for: iconPath)).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(failure.appName)  \(failure.fromVersion ?? "?") → \(failure.toVersion ?? "?")")
                    .font(.callout)
                Text(verbatim: failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Button("Report…", action: report)
                .settingsGlassButton()
                .help("Review the report, then open a GitHub issue or an email with it.")
            Button {
                let text = FailureReportView.reportText(for: failure, at: date)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                // The same confirm-and-revert as the workbench's Copy Report.
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
            .settingsGlassButton()
        }
        .settingsRow()
    }
}
