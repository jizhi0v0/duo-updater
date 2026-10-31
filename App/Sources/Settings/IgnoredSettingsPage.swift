import SwiftUI
import DuoUpdaterCore

/// Apps hidden from update checks, and versions the user chose to skip.
struct IgnoredSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    /// Icon size for a row's app. Small, like the Settings search hits' — the
    /// page is a list of names, not a showcase.
    private static let iconSize: CGFloat = 20

    /// Both key forms → the install the current scan found.
    ///
    /// The install, not just the name: two copies of an app can be installed in
    /// different folders, and two different apps can share a display name. The
    /// path under the name is what tells those rows apart. A key the scan no
    /// longer resolves (uninstalled, or written before a migration) falls back to
    /// the raw key, no icon, and says so.
    private var installs: [String: InstalledApp] {
        var map: [String: InstalledApp] = [:]
        for result in model.results {
            map[prefs.key(for: result.app)] = result.app
            // The pre-migration key too, so a still-legacy entry shows its install.
            map[prefs.legacyKey(for: result.app)] = result.app
        }
        return map
    }

    var body: some View {
        SettingsPage(section: .ignored) {
            ignoredCard.settingsAnchor(.ignoredApps)
            skippedCard.settingsAnchor(.skippedVersions)
        }
        // Cold icons are a LaunchServices read each; `AppIconCache` has them after
        // the first look, and this reads them ahead of the first render.
        .onAppear { AppIconCache.prefetch(model.results.map(\.app.path.path)) }
    }

    private var ignoredCard: some View {
        SettingsCard(header: "Ignored apps") {
            if prefs.ignoredKeys.isEmpty {
                emptyRow("No ignored apps. Use “Ignore this app” from an app’s menu to hide it from update checks.")
            } else {
                ForEach(Array(prefs.ignoredKeys.sorted().enumerated()), id: \.element) { index, key in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 10) {
                        identity(of: key)
                        Spacer(minLength: 12)
                        Button("Unignore") { prefs.removeIgnored(key: key) }
                            .controlSize(.small)
                    }
                    .settingsRow()
                    .settingsAnchor(.ignoredApp(key))
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
                    HStack(spacing: 10) {
                        // The skipped version is part of the title line: it reads
                        // as "FlyEnv 4.21.0", not as a stray value at the row's end.
                        identity(of: entry.key, version: entry.value)
                        Spacer(minLength: 12)
                        Button("Clear") { prefs.clearSkip(key: entry.key) }
                            .controlSize(.small)
                    }
                    .settingsRow()
                    .settingsAnchor(.skippedVersion(entry.key))
                }
            }
        }
    }

    /// The app a row is about: its icon, its name (with the version beside it when
    /// there is one), and the folder that copy lives in.
    private func identity(of key: String, version: String? = nil) -> some View {
        let app = installs[key]
        return HStack(spacing: 10) {
            Group {
                if let path = app?.path.path {
                    Image(nsImage: AppIconCache.icon(for: path)).resizable()
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 16))
                }
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app?.name ?? key)
                    if let version {
                        Text(version).foregroundStyle(.secondary)
                    }
                }
                if let path = app?.path.path {
                    Text(verbatim: Self.displayPath(path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(Text(verbatim: path))
                } else {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The row's path, shortened to the part that tells two installs apart: the
    /// folder the app sits in plus its bundle name. A copy in `/Applications` or
    /// `~/Applications` is already that short — its parent is where apps live — so
    /// it keeps the full path; anything deeper elides to `…/MyApps/NestedTest.app`.
    /// The full path is the row's tooltip.
    static func displayPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        if parent == "/Applications" || parent == "/Applications/Utilities" || parent == homeApps {
            return path
        }
        return "…/\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    private func emptyRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .settingsRow()
    }
}
