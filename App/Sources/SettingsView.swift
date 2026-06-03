import SwiftUI
import DuoUpdaterCore

/// The Settings window — standard macOS multi-tab layout. Binds straight to the
/// shared `Preferences` (an `@Observable`, so `@Bindable` gives us bindings) and
/// reaches into the model for the things that need live state: the names behind
/// ignored-app keys, and the recipe-health diagnostics.
struct SettingsView: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    var body: some View {
        TabView {
            GeneralSettings(prefs: prefs, model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            GitHubSettings(prefs: prefs)
                .tabItem { Label("GitHub", systemImage: "key") }
            IgnoredSettings(prefs: prefs, model: model)
                .tabItem { Label("Ignored", systemImage: "eye.slash") }
            DiagnosticsSettings(model: model)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 460, height: 360)
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - GitHub

private struct GitHubSettings: View {
    @Bindable var prefs: Preferences

    var body: some View {
        Form {
            Section {
                SecureField("Personal access token", text: $prefs.githubToken)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("GitHub API token")
            } footer: {
                Text("Optional. Lifts the anonymous 60-requests/hour limit to 5000/hour for apps tracked through GitHub Releases. Leave empty to fall back to the `GITHUB_TOKEN` / `GH_TOKEN` environment variables or the `gh` CLI login. A read-only (public-repo) token is enough.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
}
