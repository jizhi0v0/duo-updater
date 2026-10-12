import SwiftUI
import AppKit
import WebKit
import DuoUpdaterCore

/// Where DuoUpdater keeps things on this Mac and how big each part is, with the
/// caches — and only the caches — clearable.
///
/// A Homebrew install is told these paths by the cask's `zap` stanza; a GitHub
/// download is told nothing, so this page is that list for everyone. The map
/// itself (which path is which item, which items may be emptied) lives in
/// `StorageInventory` in Core; this page only names and lays out the items.
///
/// One colour per group runs through the page: the segment in the usage bar,
/// the legend under it, and the icon tile of every row in that group. A row is
/// found from the bar by colour alone.
struct StorageSettingsPage: View {
    let model: AppListModel

    @State private var measurements: [StorageInventory.Item: StorageInventory.Measurement]?
    @State private var measuring = false
    @State private var clearing = false
    /// What the last clear freed, shown in place of the button's caption for a
    /// few seconds so the click visibly landed.
    @State private var freedNote: String?
    @State private var clearError: String?
    @State private var noteReset: Task<Void, Never>?

    var body: some View {
        SettingsPage(section: .storage) {
            SettingsCard {
                overview
            }

            SettingsCard(
                header: "Caches",
                footer: "Caches are downloaded again the next time they are needed. Clearing them doesn’t touch your settings, history, release notes or backups."
            ) {
                rows(StorageGroup.caches.items)
                SettingsDivider()
                clearRow
            }

            SettingsCard(
                header: "App data",
                footer: "DuoUpdater needs these to undo updates, keep its history, show release notes it has already read, and stay within GitHub’s rate limit, so they can’t be cleared here."
            ) {
                rows(StorageGroup.backups.items + StorageGroup.appData.items)
            }

            SettingsCard(
                header: "Kept by macOS for DuoUpdater",
                footer: "To remove everything, quit DuoUpdater and move these folders and files to the Trash, along with the app."
            ) {
                rows(StorageGroup.system.items)
            }
        }
        .task { await measure() }
        .onDisappear { noteReset?.cancel() }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Used by DuoUpdater")
                        .foregroundStyle(.secondary)
                    Group {
                        if let measurements {
                            Text(Self.format(measurements.values.reduce(0) { $0 + $1.bytes }))
                                .contentTransition(.numericText())
                        } else {
                            Text(verbatim: "—")
                        }
                    }
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                }
                Spacer(minLength: 8)
                Button { Task { await measure() } } label: {
                    if measuring {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)
                .help(String(localized: "Refresh"))
                .disabled(measuring || clearing)
            }

            StorageUsageBar(segments: StorageGroup.allCases.map { ($0, groupBytes($0)) })
                .frame(height: 14)
                .opacity(measurements == nil ? 0.35 : 1)

            HStack(spacing: 18) {
                ForEach(StorageGroup.allCases) { group in
                    HStack(spacing: 6) {
                        Circle().fill(group.color.gradient).frame(width: 8, height: 8)
                        Text(group.label)
                            .foregroundStyle(.secondary)
                        Text(verbatim: measurements == nil ? "—" : Self.format(groupBytes(group)))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.caption)
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .animation(.smooth(duration: 0.45), value: measurements)
    }

    private func groupBytes(_ group: StorageGroup) -> Int64 {
        group.items.reduce(0) { $0 + (measurements?[$1]?.bytes ?? 0) }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rows(_ items: [StorageInventory.Item]) -> some View {
        let shown = items.filter { $0 != .otherData || (measurements?[$0]?.bytes ?? 0) > 0 }
        ForEach(Array(shown.enumerated()), id: \.element) { index, item in
            if index > 0 { SettingsDivider() }
            row(item)
        }
    }

    private func row(_ item: StorageInventory.Item) -> some View {
        let measurement = measurements?[item]
        let paths = measurement?.paths ?? []
        let group = StorageGroup.of(item)
        let groupTotal = groupBytes(group)
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(group.color.gradient)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: Self.symbol(item))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.title(item))
                    Spacer(minLength: 8)
                    if let measurement {
                        Text(measurement.paths.isEmpty ? String(localized: "None") : Self.format(measurement.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(Self.detail(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let location = Self.location(of: paths) {
                        StoragePathLink(path: location) { Self.reveal(paths) }
                    }
                    Spacer(minLength: 8)
                    if item == .backups {
                        Button("Manage…") { model.requestedSettingsSection = .backups }
                            .controlSize(.small)
                            .settingsGlassButton()
                    } else if let measurement, groupTotal > 0, group.items.count > 1 {
                        // The row's share of its own group: against the page total
                        // every row but Backups would be an empty bar.
                        StorageShareMeter(
                            fraction: Double(measurement.bytes) / Double(groupTotal),
                            color: group.color)
                    }
                }
                .padding(.top, 1)
            }
        }
        .settingsRow()
        .animation(.smooth(duration: 0.45), value: measurement)
    }

    private var clearRow: some View {
        HStack(spacing: 12) {
            Group {
                if let clearError {
                    Label(clearError, systemImage: "exclamationmark.triangle")
                } else if let freedNote {
                    Label(freedNote, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if measurements != nil {
                    Text("\(Self.format(groupBytes(.caches))) can be cleared")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .contentTransition(.opacity)
            Spacer(minLength: 8)
            if clearing { ProgressView().controlSize(.small) }
            Button("Clear Caches") { Task { await clearCaches() } }
                .settingsGlassButton(prominent: true)
                .disabled(clearing || measurements == nil || groupBytes(.caches) == 0)
        }
        .settingsRow()
        .animation(.smooth(duration: 0.3), value: freedNote)
    }

    // MARK: - Work

    private func measure() async {
        measuring = true
        let result = await Task.detached(priority: .userInitiated) {
            StorageInventory.measure()
        }.value
        measurements = Dictionary(uniqueKeysWithValues: result.map { ($0.item, $0) })
        measuring = false
    }

    private func clearCaches() async {
        guard measurements != nil else { return }
        let before = groupBytes(.caches)
        noteReset?.cancel()
        clearing = true
        freedNote = nil
        clearError = nil

        // Each cache is emptied by whoever holds it open: the image store resets
        // its running size with the files, `URLCache` and WebKit keep databases
        // open in this process. Only the two nobody here holds are plain file
        // removals.
        await ImageStore.shared.removeAll()
        URLCache.shared.removeAllCachedResponses()
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
            modifiedSince: .distantPast)
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try StorageInventory.removeContents(of: .formulaIcons)
                try StorageInventory.removeContents(of: .cliCache)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        await measure()
        clearing = false
        clearError = failure
        if failure == nil {
            let freed = max(0, before - groupBytes(.caches))
            freedNote = String(localized: "Cleared \(Self.format(freed))")
            noteReset = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                freedNote = nil
            }
        }
    }

    /// Finder shows a directory named `*.app` as an application — and every
    /// directory macOS makes for this bundle id is named `com.duoupdater.app`
    /// (Launch Services types all four as `com.apple.application-bundle`), so
    /// revealing one selected what Finder drew as a broken app. Selecting what
    /// is inside it opens the folder instead. Empty, there is nothing to
    /// select, and the folder itself is the only thing left to show.
    private static func reveal(_ paths: [URL]) {
        let fm = FileManager.default
        let targets = paths.flatMap { url -> [URL] in
            guard url.pathExtension == "app",
                  let children = try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
                  !children.isEmpty
            else { return [url] }
            return children
        }
        NSWorkspace.shared.activateFileViewerSelecting(targets)
    }

    // MARK: - Presentation

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// The folder to print under a row: the path itself when there is one, the
    /// directory they share when there are several. `~` for the home folder,
    /// which is how anyone would type it into Finder's Go to Folder.
    private static func location(of paths: [URL]) -> String? {
        guard let first = paths.first else { return nil }
        let path: String
        if paths.count == 1 {
            path = first.path
        } else {
            var common = first.deletingLastPathComponent().pathComponents
            for url in paths.dropFirst() {
                let parts = url.deletingLastPathComponent().pathComponents
                common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
            }
            path = NSString.path(withComponents: common)
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private static func symbol(_ item: StorageInventory.Item) -> String {
        switch item {
        case .changelogImages: "photo.on.rectangle"
        case .networkCache: "network"
        case .formulaIcons: "mug.fill"
        case .cliCache: "terminal.fill"
        case .backups: "clock.arrow.circlepath"
        case .backupIndex: "list.bullet.rectangle"
        case .history: "chart.bar.doc.horizontal"
        case .releaseNotes: "doc.text"
        case .checkState: "checkmark.seal"
        case .appleDeveloperSession: "person.badge.key.fill"
        case .httpStorage: "globe"
        case .preferences: "slider.horizontal.3"
        case .otherData: "ellipsis"
        }
    }

    private static func title(_ item: StorageInventory.Item) -> String {
        switch item {
        case .changelogImages: String(localized: "Release note images")
        case .networkCache: String(localized: "Web and download cache")
        case .formulaIcons: String(localized: "Homebrew formula icons")
        case .cliCache: String(localized: "duo command-line cache")
        case .backups: String(localized: "Backups on this Mac")
        case .backupIndex: String(localized: "Backup index")
        case .history: String(localized: "History and network log")
        case .releaseNotes: String(localized: "Release notes")
        case .checkState: String(localized: "Update check state")
        case .appleDeveloperSession: String(localized: "Apple Developer sign-in")
        case .httpStorage: String(localized: "Cookies")
        case .preferences: String(localized: "Settings")
        case .otherData: String(localized: "Other")
        }
    }

    private static func detail(_ item: StorageInventory.Item) -> String {
        switch item {
        case .changelogImages:
            String(localized: "Screenshots from vendors’ release notes.")
        case .networkCache:
            String(localized: "Responses kept by macOS’s networking and web views.")
        case .formulaIcons:
            String(localized: "Icons fetched from each formula’s homepage.")
        case .cliCache:
            String(localized: "Responses kept for the duo command.")
        case .backups:
            String(localized: "The previous version of each updated app, for undoing an update. Backups on another disk are not counted here.")
        case .backupIndex:
            String(localized: "Sizes and details of each backup, so the backup list opens quickly.")
        case .history:
            String(localized: "What DuoUpdater did, the versions it has seen, and the requests it made.")
        case .releaseNotes:
            String(localized: "Notes as each vendor published them when DuoUpdater read them.")
        case .checkState:
            String(localized: "What GitHub and other sources last answered, chosen channels, and verified checksums.")
        case .appleDeveloperSession:
            String(localized: "Signing out on the Xcode page removes it.")
        case .httpStorage:
            String(localized: "Cookies and connection details macOS remembers for the sites DuoUpdater checks.")
        case .preferences:
            String(localized: "Your settings.")
        case .otherData:
            String(localized: "Self-update downloads, window state and anything not listed above.")
        }
    }
}

/// The four colours of the page. Backups get their own although they sit in the
/// App data card: they are nearly all of the total, and folded into App data
/// the bar would say nothing about the rest of it.
private enum StorageGroup: CaseIterable, Identifiable {
    case backups, appData, caches, system

    var id: Self { self }

    var items: [StorageInventory.Item] {
        switch self {
        case .backups: [.backups]
        case .appData: [.backupIndex, .history, .releaseNotes, .checkState, .otherData]
        case .caches: [.changelogImages, .networkCache, .formulaIcons, .cliCache]
        case .system: [.appleDeveloperSession, .httpStorage, .preferences]
        }
    }

    static func of(_ item: StorageInventory.Item) -> StorageGroup {
        allCases.first { $0.items.contains(item) } ?? .appData
    }

    /// The Backups page's own tint for backups, so the two pages agree.
    var color: Color {
        switch self {
        case .backups: .indigo
        case .appData: .teal
        case .caches: .orange
        case .system: .gray
        }
    }

    var label: String {
        switch self {
        case .backups: String(localized: "Backups")
        case .appData: String(localized: "App data")
        case .caches: String(localized: "Caches")
        case .system: String(localized: "Kept by macOS")
        }
    }
}

/// One capsule split by group. A group that holds anything gets a sliver at
/// least, however small its share: backups are routinely 97% of the total,
/// and drawn to scale the other three would not be there at all.
private struct StorageUsageBar: View {
    let segments: [(group: StorageGroup, bytes: Int64)]

    private static let minimumWidth: CGFloat = 6
    private static let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let visible = segments.filter { $0.bytes > 0 }
            let widths = Self.widths(
                visible.map(\.bytes),
                in: geometry.size.width - Self.gap * CGFloat(max(0, visible.count - 1)))
            HStack(spacing: Self.gap) {
                if visible.isEmpty {
                    Capsule().fill(.quaternary)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.group) { index, segment in
                        Rectangle()
                            .fill(segment.group.color.gradient)
                            .frame(width: widths[index])
                    }
                }
            }
            .clipShape(Capsule())
        }
    }

    /// Proportional widths, each at least ``minimumWidth``; what the slivers
    /// borrow comes out of the widest segment.
    static func widths(_ bytes: [Int64], in width: CGFloat) -> [CGFloat] {
        let total = CGFloat(bytes.reduce(0, +))
        guard total > 0, width > 0 else { return bytes.map { _ in 0 } }
        var widths = bytes.map { max(minimumWidth, CGFloat($0) / total * width) }
        let excess = widths.reduce(0, +) - width
        if excess > 0, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[widest] = max(minimumWidth, widths[widest] - excess)
        }
        return widths
    }
}

/// A row's share of its group, as a short bar.
private struct StorageShareMeter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 64, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(fraction > 0 ? 3 : 0, 64 * min(1, fraction)), height: 4)
            }
    }
}

/// The path, as the control that shows it in Finder. Brightens under the
/// pointer so it reads as clickable without looking like a link in a document.
private struct StoragePathLink: View {
    let path: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(verbatim: path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.up.forward.square")
                    .imageScale(.small)
            }
            .font(.caption.monospaced())
            .foregroundStyle(hovering ? .secondary : .tertiary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Show in Finder"))
    }
}
