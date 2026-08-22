import SwiftUI
import DuoUpdaterCore

/// Apps hidden from update checks, and versions the user chose to skip.
struct IgnoredSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    /// key → display name, resolved from the current scan where possible.
    private var names: [String: String] {
        var map: [String: String] = [:]
        for result in model.results {
            map[prefs.key(for: result.app)] = result.app.name
            // Also map the pre-migration key so a still-legacy entry shows its name.
            map[prefs.legacyKey(for: result.app)] = result.app.name
        }
        return map
    }

    var body: some View {
        SettingsPage(section: .ignored) {
            ignoredCard
            skippedCard
        }
    }

    private var ignoredCard: some View {
        SettingsCard(header: "Ignored apps") {
            if prefs.ignoredKeys.isEmpty {
                emptyRow("No ignored apps. Use “Ignore this app” from an app’s menu to hide it from update checks.")
            } else {
                ForEach(Array(prefs.ignoredKeys.sorted().enumerated()), id: \.element) { index, key in
                    if index > 0 { SettingsDivider() }
                    HStack {
                        Text(names[key] ?? key)
                        Spacer(minLength: 12)
                        Button("Unignore") { prefs.removeIgnored(key: key) }
                            .controlSize(.small)
                    }
                    .settingsRow()
                }
            }
        }
    }

    private var skippedCard: some View {
        SettingsCard(header: "Skipped versions") {
            if prefs.skippedVersions.isEmpty {
                emptyRow("No skipped versions.")
            } else {
                ForEach(Array(prefs.skippedVersions.sorted(by: { $0.key < $1.key }).enumerated()),
                        id: \.element.key) { index, entry in
                    if index > 0 { SettingsDivider() }
                    HStack {
                        Text(names[entry.key] ?? entry.key)
                        Text(entry.value).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button("Clear") { prefs.clearSkip(key: entry.key) }
                            .controlSize(.small)
                    }
                    .settingsRow()
                }
            }
        }
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .settingsRow()
    }
}
