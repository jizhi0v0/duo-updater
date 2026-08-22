import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DuoUpdaterCore

/// Extra folders to scan beyond the built-in roots, so apps installed outside
/// `/Applications` (a developer build folder, a third-party tool dir) get
/// version-checked too. The built-in roots are shown read-only for context —
/// that's why an app already in `/Applications` needs nothing added here.
struct FoldersSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    /// Set when the picked folder was a no-op (already covered by a built-in root
    /// or already in the list), so we can tell the user nothing changed.
    @State private var lastAddWasDuplicate = false

    private var builtInLocations: [URL] { AppScanner.defaultLocations }

    var body: some View {
        SettingsPage(section: .folders) {
            customCard
            builtInCard
        }
    }

    private var customCard: some View {
        SettingsCard(header: "Folders to scan") {
            if prefs.customScanPaths.isEmpty {
                Text("No extra folders yet.")
                    .foregroundStyle(.secondary)
                    .settingsRow()
            } else {
                ForEach(prefs.customScanPaths, id: \.self) { path in
                    folderRow(path)
                    SettingsDivider()
                }
            }
            Button { addFolder() } label: {
                Label("Add Folder…", systemImage: "plus")
            }
            .settingsGlassButton()
            .settingsRow()
        } footer: {
            if lastAddWasDuplicate {
                Label("That folder is already covered.", systemImage: "info.circle")
            } else {
                Text("Pick a folder that contains apps (or pick an app — its folder is added). Apps there are checked for updates just like the ones in your Applications folder.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var builtInCard: some View {
        SettingsCard(
            header: "Always scanned",
            footer: "Built-in locations — these are always included and can’t be removed."
        ) {
            ForEach(Array(builtInLocations.enumerated()), id: \.element) { index, url in
                if index > 0 { SettingsDivider() }
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .settingsRow()
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: 10) {
            Image(systemName: exists ? "folder.fill" : "folder.badge.questionmark")
                .foregroundStyle(exists ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !exists {
                    Text("Folder not found — it may have moved or been deleted.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Button("Remove") {
                prefs.removeScanPath(path)
                lastAddWasDuplicate = false
                Task { await model.refresh() }
            }
            .controlSize(.small)
        }
        .settingsRow()
    }

    /// Open a directory picker; on a real pick, add it and kick a rescan so the
    /// new apps surface immediately (the panel also accepts an `.app`, which the
    /// preference resolves to its parent folder).
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose a folder that contains apps to check for updates.")

        guard panel.runModal() == .OK else { return }
        var added = false
        for url in panel.urls where prefs.addScanPath(url) { added = true }
        lastAddWasDuplicate = !added
        if added { Task { await model.refresh() } }
    }
}
