import SwiftUI
import AppKit
import DuoUpdaterCore

/// Permissions, the last check, and per-recipe detection health.
struct DiagnosticsSettingsPage: View {
    let model: AppListModel
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [RecipeHealth.Entry] = []
    @State private var loaded = false

    /// bundleID → app name, so a Vendor recipe (keyed by bundle id) shows a
    /// friendly name. GitHub recipes are keyed by `owner/repo`, which has no app
    /// to resolve, so those fall back to the raw key.
    private var names: [String: String] {
        var map: [String: String] = [:]
        for result in model.results {
            if let id = result.app.bundleID { map[id] = result.app.name }
        }
        return map
    }

    var body: some View {
        SettingsPage(section: .diagnostics) {
            permissionsCard
            lastCheckCard
            recipesCard
        }
        .task {
            entries = await RecipeHealth.shared.snapshot()
            loaded = true
        }
        // The window is long-lived; re-pull health whenever a check completes so
        // an open Diagnostics page doesn't show stale/empty data.
        .onChange(of: model.lastCheck) {
            Task { entries = await RecipeHealth.shared.snapshot() }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        SettingsCard(
            header: "Permissions",
            footer: "App Management lets Duo Updater replace apps updated outside the App Store (Sparkle, Homebrew, direct downloads). macOS can’t grant it programmatically — the button opens System Settings with a panel you drag DuoUpdater into.\n\nGranting through that panel doesn’t trigger the system’s usual “Quit & Reopen”, so a fresh grant may not take effect until DuoUpdater restarts. Use Relaunch below after granting."
        ) {
            // App Management has no *public* status API, but the private
            // TCCAccessPreflight SPI lets us read it — so show a real check when granted.
            SettingsField(title: "App Management") {
                if model.appManagementStatus == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Grant…") { model.presentAppManagementPermissionFlow() }
                        .settingsGlassButton()
                }
            }
            SettingsDivider()
            // Privileged helper: a one-time approval that lets App Store ("full")
            // updates run without a password each time.
            HelperStatusRow(helper: model.helperClient)
            SettingsDivider()
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
        }
    }

    // MARK: - Recipes

    private var recipesCard: some View {
        SettingsCard(
            header: "Detection recipes",
            footer: "A recipe is flagged when it fetched successfully but couldn’t read a version — often a sign the vendor changed their page. Cleared automatically on the next successful check."
        ) {
            if !loaded {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading recipe health…").foregroundStyle(.secondary)
                }
                .settingsRow()
            } else if entries.isEmpty {
                Text("No recipe-backed apps have been checked yet this session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRow()
            } else {
                // `.key`, not `.id`: the same bundle id can now appear under two
                // different `source`s (e.g. a Vendor recipe and an Electron
                // manifest read both tracking Notion) since `RecipeHealth` keys
                // its entries on `(id, source)`. `.id` alone is a display key and
                // is no longer guaranteed unique across `entries` — see
                // `RecipeHealth.Entry.key`.
                ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                    if index > 0 { SettingsDivider() }
                    recipeRow(entry)
                }
            }
        }
    }

    private func recipeRow(_ entry: RecipeHealth.Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.isHealthy ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(names[entry.id] ?? entry.id).font(.callout)
                if !entry.isHealthy, let detail = entry.lastMissDetail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(entry.source).font(.caption2).foregroundStyle(.tertiary)
        }
        .settingsRow()
    }

    /// Spawn a fresh instance, then terminate this one — the standard "restart
    /// myself" handoff. `open -n` launches a new copy that outlives our exit, so a
    /// permission granted via the drag panel takes effect without the user hunting
    /// for the app in Finder.
    private static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        do {
            try task.run()
            NSApp.terminate(nil)
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
    /// updating Duo Updater leaves the previous copy of the helper holding the
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
            if checking || answering != nil {
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
        SettingsField(title: "App Store helper") {
            if helper.isEnabled {
                // Buttons before the status, so this row's "Enabled" lines up with
                // the "Granted" directly above it: the states read down one column
                // and the actions sit to their left, instead of the status drifting
                // inward by however wide the buttons happen to be.
                //
                // "Enabled" is not the same as "answering". Updating DuoUpdater
                // replaces its bundle while the helper from the old one keeps
                // holding launchd's slot, so the record still reads enabled while
                // every App Store install times out. Re-registering cannot fix that
                // — `register()` on a live record does nothing, measured — so the
                // button offered here is the one that works: kill the stale copy so
                // launchd starts the one belonging to the app that's installed now.
                // Helpers built after this change exit on their own when idle; the
                // button is for the ones already stranded by an older build.
                checkButton
                // Disabled while the authorization panel is up: pressing again
                // would stack a second prompt on the first and kickstart twice.
                Button(restarting ? String(localized: "Restarting…") : String(localized: "Restart Helper…")) {
                    guard !restarting else { return }
                    restarting = true
                    Task {
                        let restarted = await helper.restartDaemon()
                        restarting = false
                        // Re-probe rather than assume: the point of the button is
                        // that it makes the helper answer again, so show whether it
                        // did instead of leaving a stale result on screen.
                        if restarted { answering = await HelperShellRunner().isAnswering() }
                    }
                }
                .settingsGlassButton()
                .disabled(restarting)
                .help("Restart the background helper — use this if App Store updates fail saying the helper isn’t answering. Asks for an administrator password.")
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Enable…") { helper.register() }
                    .settingsGlassButton()
            }
        }
        .onAppear { helper.refreshStatus() }
        // Probe once on arrival rather than waiting to be asked: this page exists to
        // say whether things work, and "Enabled" alone cannot. It also means the
        // result line is populated from the start, so the first press of Check
        // changes a word rather than growing the card by a row.
        .task { answering = await HelperShellRunner().isAnswering() }
    }
}
