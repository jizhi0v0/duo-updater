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
struct StorageSettingsPage: View {
    let model: AppListModel

    /// Seeded from the last measurement this session, so coming back to the page
    /// paints the numbers it showed last time while a fresh walk runs, instead of
    /// a column of spinners that turn into text a second later.
    @State private var measurements = StorageMeasurementMemo.last
    @State private var clearing = false
    @State private var refreshing = false
    /// The busy look, shown only once the work has run past ``busyThreshold``.
    /// Shown at once, a clear or a measurement that finishes in one or two frames
    /// — the usual case — flashed a spinner and a dimmed button for a single
    /// frame, which read as a flicker rather than as progress (recorded
    /// 2026-10-12: the spinner and the dim lasted exactly one frame at 30 fps).
    @State private var showsRefreshSpinner = false
    @State private var showsClearSpinner = false
    /// Set for a moment after a Refresh the user asked for, so the button says
    /// it worked even when nothing changed — which is the usual answer, and the
    /// one a silent button can't be told apart from a click that missed.
    @State private var refreshed = false
    @State private var refreshedReset: Task<Void, Never>?
    /// What the last clear freed, shown in place of the button's caption for a
    /// few seconds so the click visibly landed.
    @State private var freedNote: String?
    @State private var clearError: String?
    @State private var noteReset: Task<Void, Never>?

    private static let caches = StorageInventory.Group.caches.items
    private static let appData = StorageInventory.Group.appData.items
    private static let system = StorageInventory.Group.system.items

    var body: some View {
        SettingsPage(section: .storage) {
            SettingsCard {
                totalRow
            }

            SettingsCard(
                header: "Caches",
                footer: "Caches are downloaded again the next time they are needed. Clearing them doesn’t touch your settings, history, release notes or backups."
            ) {
                rows(Self.caches)
                SettingsDivider()
                clearRow
            }

            SettingsCard(
                header: "App data",
                footer: "DuoUpdater needs these to undo updates, keep its history, show release notes it has already read, and stay within GitHub’s rate limit, so they can’t be cleared here."
            ) {
                rows(Self.appData)
            }

            SettingsCard(
                header: "Kept by macOS for DuoUpdater",
                footer: "To remove everything, quit DuoUpdater and move these folders and files to the Trash, along with the app."
            ) {
                rows(Self.system)
            }
        }
        .task { await measure() }
        .onDisappear { noteReset?.cancel(); refreshedReset?.cancel() }
    }

    // MARK: - Rows

    private var totalRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Used by DuoUpdater")
                // A placeholder in the same font while the first walk runs, so
                // the card is the height it will be and nothing below it moves.
                Text(measurements.map { Self.format($0.values.reduce(0) { $0 + $1.bytes }) } ?? "00.0 GB")
                    .font(.system(.title2, weight: .semibold))
                    .monospacedDigit()
                    .redacted(reason: measurements == nil ? .placeholder : [])
            }
            Spacer(minLength: 8)
            Button { Task { await refresh() } } label: {
                // All three laid out, one shown, so the button keeps its width.
                ZStack {
                    Text("Refresh").opacity(!showsRefreshSpinner && !refreshed ? 1 : 0)
                    ProgressView().controlSize(.small).opacity(showsRefreshSpinner ? 1 : 0)
                    Label("Refreshed", systemImage: "checkmark").opacity(refreshed && !showsRefreshSpinner ? 1 : 0)
                }
            }
            .settingsGlassButton()
        }
        .settingsRow()
    }

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
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(item))
                Text(Self.detail(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let location = Self.location(of: paths) ?? (measurement == nil ? "~/Library/Application Support" : nil) {
                    Text(location)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .redacted(reason: measurement == nil ? .placeholder : [])
                }
                // Under the text rather than beside the size: there it pushed this
                // one size left of the column every other row's size lines up in.
                if item == .backups {
                    Button("Manage…") { model.requestedSettingsSection = .backups }
                        .controlSize(.small)
                        .settingsGlassButton()
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            Text(measurement.map { $0.paths.isEmpty ? String(localized: "None") : Self.format($0.bytes) } ?? "00.0 MB")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .redacted(reason: measurement == nil ? .placeholder : [])
            Button {
                Self.reveal(paths)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Show in Finder"))
            .disabled(paths.isEmpty)
        }
        .settingsRow()
    }

    private var clearRow: some View {
        HStack(spacing: 12) {
            Group {
                if let clearError {
                    Label(clearError, systemImage: "exclamationmark.triangle")
                } else if let freedNote {
                    Label(freedNote, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let clearable {
                    Group {
                        if clearable == 0 {
                            Text("Nothing to clear")
                        } else {
                            Text("\(Self.format(clearable)) can be cleared")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer(minLength: 8)
            if showsClearSpinner { ProgressView().controlSize(.small) }
            Button("Clear Caches") { Task { await clearCaches() } }
                .settingsGlassButton(prominent: true)
                .disabled(measurements == nil || clearable == 0)
        }
        .settingsRow()
    }

    /// What Clear Caches would remove — not the caches' whole size, which
    /// includes what a clear leaves behind (see
    /// `StorageInventory.networkCacheClearableBytes`).
    private var clearable: Int64? {
        measurements.map { m in Self.caches.reduce(0) { $0 + (m[$1]?.clearableBytes ?? 0) } }
    }

    // MARK: - Work

    private static let busyThreshold: Duration = .milliseconds(300)

    /// Sets a busy flag once ``busyThreshold`` has passed, unless cancelled
    /// first by the work finishing.
    private func busyAfterThreshold(_ set: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: Self.busyThreshold)
            guard !Task.isCancelled else { return }
            set()
        }
    }

    /// A second click while one runs is ignored here rather than by disabling
    /// the button: a button that greys out for one frame is the flicker this
    /// page is avoiding.
    private func refresh() async {
        guard !refreshing, !clearing else { return }
        refreshing = true
        refreshedReset?.cancel()
        let busy = busyAfterThreshold { showsRefreshSpinner = true }
        await measure()
        busy.cancel()
        showsRefreshSpinner = false
        refreshing = false
        // Left on if it already was: flipping it off and on again is one more
        // frame of the plain label between two of the checkmark.
        refreshed = true
        refreshedReset = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            refreshed = false
        }
    }

    private func measure() async {
        let result = await Task.detached(priority: .userInitiated) {
            StorageInventory.measure()
        }.value
        let fresh = Dictionary(uniqueKeysWithValues: result.map { ($0.item, $0) })
        measurements = fresh
        StorageMeasurementMemo.last = fresh
    }

    private func clearCaches() async {
        guard !clearing, !refreshing, let before = clearable else { return }
        noteReset?.cancel()
        clearing = true
        // The previous result stays up until this one replaces it. Cleared first,
        // it gave way to "… can be cleared" for a frame before the new result.
        let busy = busyAfterThreshold { showsClearSpinner = true }

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
        busy.cancel()
        showsClearSpinner = false
        clearing = false
        clearError = failure
        if failure == nil {
            let freed = max(0, before - (clearable ?? 0))
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

    /// "0 KB" rather than the formatter's default "Zero KB", which is what every
    /// cache row reads right after a clear.
    private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
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

/// The page's last measurement, kept for as long as the app runs. The page is
/// rebuilt every time it is selected, and its `@State` with it.
@MainActor
private enum StorageMeasurementMemo {
    static var last: [StorageInventory.Item: StorageInventory.Measurement]?
}
