import SwiftUI
import AppKit
import DuoUpdaterCore

/// Settings — a modern System-Settings-style sidebar layout. A tab-style
/// `TabView` hosts its tabs in a window titlebar; presented in a borderless sheet
/// the tabs jam against the clipped top edge, so we use a `NavigationSplitView`
/// instead: section list on the left, the selected section's form on the right.
/// Binds straight to the shared `Preferences` (an `@Observable`, so `@Bindable`
/// gives us bindings) and reaches into the model for live state (ignored-app
/// names, recipe-health diagnostics).
struct SettingsView: View {
    static let windowID = "settings"

    @Bindable var prefs: Preferences
    let model: AppListModel

    enum Section: String, CaseIterable, Identifiable {
        case general, github, ignored, diagnostics
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:     return "General"
            case .github:      return "GitHub"
            case .ignored:     return "Ignored"
            case .diagnostics: return "Diagnostics"
            }
        }
        var icon: String {
            switch self {
            case .general:     return "gearshape"
            case .github:      return "key"
            case .ignored:     return "eye.slash"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    @State private var section: Section? = .general

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { section in
                Label(section.label, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail(for: section ?? .general)
                .navigationTitle((section ?? .general).label)
                // Remove the auto sidebar-collapse button: with 4 fixed sections
                // there's no reason to hide the sidebar, and collapsing it triggers
                // the janky two-stage NavigationSplitView slide animation. Keeping
                // the sidebar pinned sidesteps it entirely.
                .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 620, minHeight: 420)
        // This is a real macOS Settings window, not a sheet. A menu-bar app is
        // .accessory by default, so the window could open behind / without focus;
        // ref-count it through the model (same as the workbench) to promote the app
        // to .regular while it's open and pull it to the front.
        .onAppear { model.windowAppeared() }
        .onDisappear { model.windowDisappeared() }
    }

    @ViewBuilder
    private func detail(for section: Section) -> some View {
        switch section {
        case .general:     GeneralSettings(prefs: prefs, model: model)
        case .github:      GitHubSettings(prefs: prefs)
        case .ignored:     IgnoredSettings(prefs: prefs, model: model)
        case .diagnostics: DiagnosticsSettings(model: model)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                Picker("Check for updates", selection: $prefs.checkFrequency) {
                    ForEach(Preferences.CheckFrequency.allCases) { freq in
                        Text(freq.label).tag(freq)
                    }
                }
                .onChange(of: prefs.checkFrequency) { _, _ in
                    // Re-arm the background loop with the new interval immediately.
                    model.reschedule()
                }
            }
            Section {
                Toggle("Notify me when updates are found", isOn: $prefs.notifyOnUpdates)
                Toggle("Keep a backup so updates can be rolled back", isOn: $prefs.keepBackups)
            } footer: {
                Text("Backups keep one previous version of each app under Application Support, so an update can be undone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper(value: $prefs.maxConcurrency, in: 1...32) {
                    Text("Check up to \(prefs.maxConcurrency) apps at once")
                }
            } footer: {
                Text("Lower this on a slow connection; raise it to check a large library faster.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("App Store updates", selection: $prefs.appStoreUpdateStrategy) {
                    ForEach(Preferences.AppStoreUpdateStrategy.allCases) { strategy in
                        Text(strategy.label).tag(strategy)
                    }
                }
                .onChange(of: prefs.appStoreUpdateStrategy) { _, new in
                    // Opting into the AX route needs Accessibility — guide the user
                    // there now instead of failing the first update silently.
                    if new == .incremental { model.guideAccessibilityForIncrementalIfNeeded() }
                }
            } footer: {
                Text("Full uses the mas tool to redownload the whole app — no extra permission. Incremental drives the App Store’s own Update button for a smaller delta download, but needs Accessibility access (you’ll be guided to grant it).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - GitHub

private struct GitHubSettings: View {
    @Bindable var prefs: Preferences

    /// nil while the `gh auth status` probe is in flight.
    @State private var cliStatus: GitHubToken.CLIStatus?
    /// Reveal the token in plain text (eye toggle).
    @State private var revealToken = false

    /// Editable copy of the token. We verify this against GitHub and only write
    /// it into `prefs.githubToken` once it's confirmed valid — so a bad paste
    /// never silently becomes the persisted token.
    @State private var draft = ""
    /// Result of the last verification of `draft`; nil before any attempt.
    @State private var verification: GitHubToken.Verification?
    @State private var verifying = false
    /// Show the editable field. When false and a token is saved, we show a
    /// compact masked summary instead of a wall of characters.
    @State private var editing = false
    @FocusState private var tokenFocused: Bool

    private static let tokenSettingsURL = URL(string: "https://github.com/settings/tokens")!

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                cliStatusRow
            }

            Section {
                if editing {
                    tokenField
                    tokenActionRow
                } else {
                    savedTokenRow
                }
            } header: {
                // "GitHub token — or paste a personal access token", where the
                // tail opens GitHub's token page. NSWorkspace rather than a
                // markdown link / SwiftUI openURL — the latter errors -50 in
                // this borderless settings window.
                HStack(spacing: 0) {
                    Text("GitHub token — or ")
                    Button("paste a personal access token") {
                        NSWorkspace.shared.open(Self.tokenSettingsURL)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .font(.callout)
                .textCase(nil)
            } footer: {
                Text("Lifts the anonymous 60-requests/hour limit to 5000/hour for apps tracked through GitHub Releases. When the `gh` CLI is signed in this is filled automatically, so the field is optional. A read-only (public-repo) token is enough.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Click anywhere outside the field to drop focus. Child controls get
        // the tap first, so buttons/field still work; only empty space resigns.
        .onTapGesture { tokenFocused = false }
        .onAppear { editing = prefs.githubToken.isEmpty }
        .task {
            // Off the main thread: `gh auth status` shells out twice.
            cliStatus = await Task.detached(priority: .userInitiated) {
                GitHubToken.cliStatus()
            }.value
        }
    }

    // MARK: actions

    /// Verify the draft against GitHub; persist only on success, then collapse
    /// back to the masked summary.
    private func verifyAndSave() async {
        verifying = true
        verification = nil
        let result = await GitHubToken.verify(trimmedDraft)
        verifying = false
        verification = result
        if case .valid(let username, _) = result {
            prefs.githubToken = trimmedDraft   // commit only when confirmed
            prefs.githubTokenAccount = username
            draft = ""
            editing = false
        }
    }

    /// Switch to the editable field to replace the saved token.
    private func startEditing() {
        draft = ""
        verification = nil
        editing = true
        tokenFocused = true
    }

    private func clearSaved() {
        draft = ""
        prefs.githubToken = ""
        prefs.githubTokenAccount = ""
        verification = nil
        editing = true
    }

    // MARK: subviews

    @ViewBuilder private var cliStatusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("GitHub CLI integration").fontWeight(.semibold)
                    // Single status slot right after the title, fixed size:
                    // loading → failed → success all live here, so the
                    // transition never shifts the title's layout.
                    statusIcon
                        .frame(width: 16, height: 16)
                }
                Text(statusHeadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if case .authenticated(let username?) = cliStatus {
                    Text("Signed in as \(username)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusIcon: some View {
        switch cliStatus {
        case .none:
            ProgressView().controlSize(.small)
        case .authenticated:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled, .notLoggedIn:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusHeadline: String {
        switch cliStatus {
        case .none:                return "Checking the gh CLI…"
        case .authenticated:       return "GitHub CLI is authenticated and ready."
        case .notLoggedIn:         return "GitHub CLI is installed but not signed in. Run `gh auth login`, or paste a token below."
        case .notInstalled:        return "GitHub CLI isn't installed. Paste a personal access token below to lift the rate limit."
        }
    }

    /// Compact summary shown once a token is saved: a key glyph, the masked
    /// token (prefix + dots + suffix, monospaced — never the full secret), the
    /// verified account, and a Change button to swap it.
    @ViewBuilder private var savedTokenRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.mask(prefs.githubToken))
                    .font(.system(.body, design: .monospaced))
                if !prefs.githubTokenAccount.isEmpty {
                    Text("Saved · belongs to \(prefs.githubTokenAccount)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Saved")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Change") { startEditing() }
            Button("Remove", role: .destructive) { clearSaved() }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if revealToken {
                    TextField("Paste token", text: $draft)
                } else {
                    SecureField("Paste token", text: $draft)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .textContentType(.password)
            .autocorrectionDisabled()
            .focused($tokenFocused)
            .onSubmit { if !trimmedDraft.isEmpty { Task { await verifyAndSave() } } }
            // A fresh edit invalidates the previous verdict.
            .onChange(of: draft) { verification = nil }

            Button {
                revealToken.toggle()
            } label: {
                Image(systemName: revealToken ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealToken ? "Hide token" : "Show token")
        }
    }

    /// Action row: the verification verdict sits on the left, the buttons on the
    /// right. Keeping the verdict on this row (rather than a separate row that
    /// appears/disappears) avoids the section growing and flickering on verify.
    @ViewBuilder private var tokenActionRow: some View {
        HStack(spacing: 10) {
            verificationInline
            Spacer(minLength: 8)
            // Keep the button mounted and show the spinner beside it (rather
            // than swapping button↔spinner), so the row height never jumps.
            ProgressView()
                .controlSize(.small)
                .opacity(verifying ? 1 : 0)
            if !prefs.githubToken.isEmpty {
                Button("Cancel") { editing = false; draft = ""; verification = nil }
                    .disabled(verifying)
            }
            Button("Verify & Save") { Task { await verifyAndSave() } }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedDraft.isEmpty || verifying)
        }
    }

    /// Mask a secret for display: keep the first 4 and last 4 chars, dots
    /// between. Short strings collapse to a fixed dot run so length doesn't leak.
    private static func mask(_ token: String) -> String {
        guard token.count > 12 else { return String(repeating: "•", count: 12) }
        return "\(token.prefix(4))\(String(repeating: "•", count: 16))\(token.suffix(4))"
    }

    /// Single-line verdict for the left of the action row: who the token belongs
    /// to, or why it failed. One line, truncating, so the row height is stable.
    @ViewBuilder private var verificationInline: some View {
        switch verification {
        case .valid(let username, _):
            Label {
                Text("Valid — belongs to **\(username)**")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.callout)
            .lineLimit(1)
        case .invalid:
            Label("Rejected by GitHub — check it's correct and not expired.",
                  systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(1)
        case .failed(let message):
            Label("Couldn't verify: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .lineLimit(1)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Ignored apps & skipped versions

private struct IgnoredSettings: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    /// key → display name, resolved from the current scan where possible.
    private var names: [String: String] {
        var map: [String: String] = [:]
        for result in model.results { map[prefs.key(for: result.app)] = result.app.name }
        return map
    }

    var body: some View {
        Form {
            Section("Ignored apps") {
                if prefs.ignoredKeys.isEmpty {
                    Text("No ignored apps. Use “Ignore this app” from an app's menu to hide it from update checks.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.ignoredKeys.sorted(), id: \.self) { key in
                        HStack {
                            Text(names[key] ?? key)
                            Spacer()
                            Button("Unignore") { prefs.removeIgnored(key: key) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            Section("Skipped versions") {
                if prefs.skippedVersions.isEmpty {
                    Text("No skipped versions.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.skippedVersions.sorted(by: { $0.key < $1.key }), id: \.key) { key, version in
                        HStack {
                            Text(names[key] ?? key)
                            Text(version).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") { prefs.clearSkip(key: key) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics (recipe health)

private struct DiagnosticsSettings: View {
    let model: AppListModel
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
        Form {
            Section {
                Button("Grant App Management…") {
                    model.presentAppManagementPermissionFlow()
                }
                Button("Relaunch DuoUpdater") { Self.relaunch() }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Replacing an installed app needs macOS App Management permission. It can't be requested programmatically — this opens System Settings and floats a panel you drag DuoUpdater into to grant it. Do this early so the first update isn't blocked.\n\nGranting it through that panel doesn't trigger the system's usual “Quit & Reopen” prompt, so a freshly granted permission may not take effect until DuoUpdater restarts. Use Relaunch above after granting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if let last = model.lastCheck {
                    LabeledContent("Last checked", value: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last checked", value: "Not yet")
                }
            }
            Section {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if entries.isEmpty {
                    Text("No recipe-backed apps have been checked yet this session.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(entry.isHealthy ? .green : .orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(names[entry.id] ?? entry.id).font(.callout)
                                if !entry.isHealthy, let detail = entry.lastMissDetail {
                                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(entry.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Detection recipes")
            } footer: {
                Text("A recipe is flagged when it fetched successfully but couldn't read a version — often a sign the vendor changed their page. Cleared automatically on the next successful check.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            entries = await RecipeHealth.shared.snapshot()
            loaded = true
        }
        // The Settings window is long-lived; re-pull health whenever a check
        // completes so an open Diagnostics tab doesn't show stale/empty data.
        .onChange(of: model.lastCheck) {
            Task { entries = await RecipeHealth.shared.snapshot() }
        }
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
