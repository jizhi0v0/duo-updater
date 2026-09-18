import AppKit
import DuoUpdaterCore
import SwiftUI

/// Rollback points: whether to keep them, where they live, and what they cost.
///
/// Split out of General once "where" became a real question. A backup is a full
/// second copy of an app, so on a machine that is short of space the usual
/// response is to turn the safety net off — and pointing the store at an
/// external disk is the way to keep both.
struct BackupsSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    @State private var storeSizes: [(store: BackupStore.Store, bytes: Int64)] = []
    @State private var pendingCount = 0
    @State private var transferState: BackupTransferQueue.State = .idle
    @State private var availability: BackupStore.Availability = .localOnly(BackupStore.outboxRoot)
    /// Each known disk's own reachability, keyed by `destinationKey(_:)`.
    /// Recomputed on every `refresh()`, not on every render — walking a marker
    /// file on a network share is a filesystem call, and this can run it for up
    /// to eight disks.
    @State private var knownAvailability: [String: BackupStore.Availability] = [:]
    /// Disks plugged in right now that already carry a store, whether or not
    /// this Mac was ever configured for them. Populated once, off the main
    /// thread — `BackupStoreDiscovery` reads mounted volumes.
    @State private var discoveredStores: [BackupStoreDiscovery.Found] = []
    @State private var lastReport: BackupDestinationProbe.Report?
    @State private var pickError: String?
    @State private var isWorking = false
    /// True when the chosen folder lives on the same volume as the local
    /// store, which makes every word of the "another disk" promise untrue.
    @State private var isOnThisMacsDisk = false

    @State private var showingBackups = false
    @State private var backupListing: [BackupStore.Listing] = []
    @State private var isCleaningBackups = false

    var body: some View {
        SettingsPage(section: .backups) {
            rollbackCard.settingsAnchor(.backups)
            locationCard
            storageCard
        }
        .task {
            await refresh()
            // The page would otherwise show whatever was true when it opened: a
            // transfer finishing in the background is exactly the thing someone
            // has this page open to watch, and it reported "Zero KB" for a
            // backup that had already landed. Sizes walk both stores, so they
            // are re-read only when the amount of owed work actually changes.
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                // Two cadences on purpose. The queue's state lives in memory and
                // is free to read, so the progress line stays live; counting what
                // is owed reads a sidecar per backup and re-measuring sizes walks
                // both stores, so those happen half as often and only when the
                // amount of owed work has actually moved.
                transferState = await model.backupTransferState()
                tick += 1
                if tick % 2 == 0 {
                    let owed = await model.pendingBackupTransfers()
                    if owed != pendingCount { await refresh() }
                }
            }
        }
        .task {
            // A separate, one-shot task: this walks every mounted volume, which
            // touches the filesystem and would block the render pass if it ran
            // inline in `body`.
            discoveredStores = await model.discoverBackupStores()
        }
        .sheet(isPresented: $showingBackups) {
            BackupsSheet(backups: backupListing) { keys in
                Task {
                    await model.deleteBackups(keys: keys)
                    await refresh()
                }
            }
        }
    }

    // MARK: - Cards

    private var rollbackCard: some View {
        SettingsCard(
            header: "Rollback points",
            footer: "Backups keep one previous version of each app, so an update can be undone. Retention is one per app — the previous version is replaced, not accumulated."
        ) {
            Toggle("Keep a backup so updates can be rolled back", isOn: $prefs.keepBackups)
                .settingsRow()
            SettingsDivider()
            Toggle("Delete a backup once its app is uninstalled", isOn: $prefs.pruneOrphanBackups)
                .settingsRow()
        }
    }

    private var locationCard: some View {
        SettingsCard(header: "Where backups are kept") {
            ForEach(Array(destinationOptions.enumerated()), id: \.element.id) { index, option in
                if index > 0 { SettingsDivider() }
                destinationRow(option)
            }
            SettingsDivider()
            chooseAnotherRow
        } footer: {
            if let pickError {
                // Named as the folder that was *rejected*, because the row above
                // still shows the destination in use — without this the warning
                // reads as being about that one.
                Label(pickError, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            } else if prefs.backupDestination.kind == .external {
                Text(destinationFooter)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Backups are copies of whole apps, so they are large. Keeping them on an external disk or a network share frees that space on this Mac without giving up the ability to undo an update.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One row per disk the picker can write to: this Mac, then every disk ever
    /// adopted, then any disk plugged in right now that already carries a store
    /// this Mac was never configured for.
    private var destinationOptions: [DestinationOption] {
        let known = prefs.knownBackupDestinations
        var out: [DestinationOption] = [.local] + known.map(DestinationOption.known)
        let knownIdentities = Set(known.compactMap(\.identity))
        for found in discoveredStores where !knownIdentities.contains(found.marker.identity) {
            out.append(.discovered(found))
        }
        return out
    }

    private func destinationRow(_ option: DestinationOption) -> some View {
        let selected = isSelected(option)
        return Button {
            select(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: option))
                    .foregroundStyle(tint(for: option))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: option))
                    if let subtitle = subtitle(for: option) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // The exact folder, not just the disk, only for the one
                    // currently in use — the other rows are a name and a state,
                    // not a path to double-check.
                    if selected, case .known(let destination) = option, let path = destination.path {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 12)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .settingsRow()
    }

    private var chooseAnotherRow: some View {
        Button {
            chooseDisk()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("Choose another folder…")
                Spacer(minLength: 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .settingsRow()
    }

    private var storageCard: some View {
        SettingsCard(header: "Storage") {
            ForEach(Array(storeSizes.enumerated()), id: \.element.store.id) { index, entry in
                if index > 0 { SettingsDivider() }
                HStack {
                    Text(storeSizeLabel(entry.store))
                    Spacer()
                    Text(format(entry.bytes)).foregroundStyle(.secondary)
                }
                .settingsRow()
            }

            if prefs.backupDestination.kind == .external {
                if case .copying(let name, let completed, let total) = transferState {
                    SettingsDivider()
                    // A bare count reads as stalled on a slow disk — a single
                    // large app can hold the number still for a minute. Naming
                    // what is moving, and how far along the run is, is the
                    // difference between "working" and "stuck".
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Copying \(name)…")
                            Spacer()
                            Text("\(completed + 1)/\(max(total, completed + 1))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        ProgressView(
                            value: Double(completed),
                            total: Double(max(total, completed + 1)))
                    }
                    .settingsRow()
                } else if pendingCount > 0 {
                    SettingsDivider()
                    HStack {
                        // Colon form rather than "%lld backups waiting": it needs no
                        // plural agreement in any language, which keeps this out of
                        // four-way Russian plural variations for a settings row.
                        Text("Waiting to be copied: \(pendingCount)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy Now") { Task { await work { await model.syncBackupsNow() } } }
                            .controlSize(.small)
                            .disabled(isWorking)
                    }
                    .settingsRow()
                } else if case .ready = availability {
                    SettingsDivider()
                    // Say "finished" rather than letting the row disappear. A
                    // control that vanishes when its work is done reads the same
                    // as one that broke: there is nothing left to tell you
                    // whether everything moved or the feature stopped trying.
                    Label("Everything is on the backup disk", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .settingsRow()
                }
            }

            SettingsDivider()
            AdaptiveCompressionRow(selection: $prefs.backupCompression)
                .settingsRow()

            SettingsDivider()
            HStack {
                Spacer()
                Button("Clean Up…") {
                    guard !isCleaningBackups else { return }
                    isCleaningBackups = true
                    Task {
                        backupListing = await model.backupListing()
                        isCleaningBackups = false
                        showingBackups = !backupListing.isEmpty
                    }
                }
                .disabled(isCleaningBackups)
            }
            .settingsRow()
        } footer: {
            Text("Backups on another disk are stored as a single compressed archive. That is what lets a disk formatted for Windows, or a network share, hold one at all — and it is usually less than half the size of the app.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Destination rows

    /// One entry the disk picker can show. `known` disks are offered whether or
    /// not they are plugged in right now — the picker has to name a disk in
    /// order to say it isn't connected — and `discovered` disks are ones found
    /// on a volume that is mounted right now but was never adopted here.
    private enum DestinationOption: Identifiable {
        case local
        case known(BackupDestination)
        case discovered(BackupStoreDiscovery.Found)

        var id: String {
            switch self {
            case .local: return "local"
            case .known(let destination): return "known:\(destinationKey(destination))"
            case .discovered(let found): return "discovered:\(found.marker.identity)"
            }
        }
    }

    private func isSelected(_ option: DestinationOption) -> Bool {
        switch option {
        case .local:
            return prefs.backupDestination.kind == .local
        case .known(let destination):
            return prefs.backupDestination.kind == .external
                && destinationKey(destination) == destinationKey(prefs.backupDestination)
        case .discovered:
            // Never the active choice: a discovered disk is, by construction,
            // one whose identity isn't among the known destinations, and the
            // active destination is always one of those.
            return false
        }
    }

    private func select(_ option: DestinationOption) {
        guard !isWorking else { return }
        switch option {
        case .local:
            Task { await work { await model.useLocalBackups() } }
        case .known(let destination):
            Task { await work { await model.useBackupDisk(destination) } }
        case .discovered(let found):
            adopt(at: found.root)
        }
    }

    private func icon(for option: DestinationOption) -> String {
        switch option {
        case .local:
            return "internaldrive.fill"
        case .known(let destination):
            switch availability(for: destination) {
            case .ready:            return "externaldrive.fill.badge.checkmark"
            case .volumeNotMounted: return "externaldrive.badge.xmark"
            case .identityMismatch: return "externaldrive.badge.questionmark"
            case .notWritable:      return "lock.fill"
            case .localOnly:        return "externaldrive"
            }
        case .discovered:
            return "externaldrive.badge.plus"
        }
    }

    private func tint(for option: DestinationOption) -> Color {
        switch option {
        case .local:
            return .secondary
        case .known(let destination):
            switch availability(for: destination) {
            case .ready:     return .accentColor
            case .localOnly: return .secondary
            default:         return .orange
            }
        case .discovered:
            return .blue
        }
    }

    private func title(for option: DestinationOption) -> String {
        switch option {
        case .local:
            return String(localized: "On this Mac")
        case .known(let destination):
            return destination.volumeName ?? String(localized: "Backup disk")
        case .discovered(let found):
            return found.volumeName ?? String(localized: "Backup disk")
        }
    }

    private func subtitle(for option: DestinationOption) -> String? {
        switch option {
        case .local:
            return nil
        case .known(let destination):
            // What the disk is doing beats what it is. Choosing a disk starts a
            // transfer that can run for minutes, and a row that only ever said
            // "Connected" gave the press no visible consequence at all — the one
            // thing this page is not allowed to do.
            if isSelected(option) {
                if case .copying(let name, _, _) = transferState {
                    return String(localized: "Copying \(name)…")
                }
                if pendingCount > 0 {
                    return String(localized: "Waiting to be copied: \(pendingCount)")
                }
            }
            switch availability(for: destination) {
            case .ready:             return String(localized: "Connected")
            case .volumeNotMounted:  return String(localized: "Isn’t connected")
            case .identityMismatch:  return String(localized: "A different disk is mounted here")
            case .notWritable:       return String(localized: "Can’t be written to")
            case .localOnly:         return nil
            }
        case .discovered:
            return String(localized: "Has a backup store, but isn’t set up on this Mac.")
        }
    }

    /// A known disk's own reachability, from the cache `refresh()` fills. A disk
    /// that has never been checked (should not happen — every known disk is
    /// checked on every refresh) reads as not mounted rather than crashing on a
    /// missing key.
    private func availability(for destination: BackupDestination) -> BackupStore.Availability {
        knownAvailability[destinationKey(destination)]
            ?? .volumeNotMounted(volumeName: destination.volumeName, path: destination.path ?? "")
    }

    // MARK: - Storage wording

    private func storeSizeLabel(_ store: BackupStore.Store) -> String {
        if let name = store.volumeName { return String(localized: "On “\(name)”") }
        return store.location == .outbox
            ? String(localized: "On this Mac")
            : String(localized: "On the backup disk")
    }

    // MARK: - Status wording

    private var destinationFooter: String {
        if isOnThisMacsDisk {
            return String(localized: "This folder is on the same disk as this Mac, so it frees no space. Backups there are only stored compressed, at roughly half the size. To move them off this Mac, choose a folder on an external disk or a network share.")
        }
        switch availability {
        case .ready:
            if let report = lastReport, let speed = report.writeBytesPerSecond {
                let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
                return String(localized: "Measured at about \(rate)/s. Backups are copied here in the background, after an update is installed, so nothing waits on the disk.")
            }
            return String(localized: "Backups are copied here in the background, after an update is installed, so nothing waits on the disk.")
        case .volumeNotMounted, .notWritable:
            return String(localized: "New backups stay on this Mac until the disk is back, then move on their own. If this Mac runs low on space while the disk is away, updates are installed without a rollback point rather than filling the startup disk.")
        case .identityMismatch:
            return String(localized: "The disk mounted at this path isn’t the one the backups were set up on. Nothing has been written to it. Reconnect the original disk, or choose this one to start using it instead.")
        case .localOnly:
            return ""
        }
    }

    /// Warns only when the ceiling is one a backup could plausibly hit — FAT32's
    /// 4 GB cap. Reported by the filesystem, not guessed from its name.
    private var sizeCeilingWarning: String? {
        guard let max = lastReport?.maxFileBytes, max < (8 << 30) else { return nil }
        let limit = ByteCountFormatter.string(fromByteCount: max, countStyle: .file)
        return String(localized: "This disk’s format caps a single file at \(limit), so a very large app may not fit. Reformatting it as APFS or Mac OS Extended removes that limit.")
    }

    // MARK: - Actions

    private func chooseDisk() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use This Folder")
        panel.message = String(localized: "Choose a folder on an external disk or a network share. Backups are kept inside it, and moving them there is what frees space on this Mac.")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(at: url)
    }

    /// Probe and adopt `url`, whether it came from the folder panel or from
    /// picking a disk the scan already found holding a store.
    private func adopt(at url: URL) {
        Task {
            await work {
                do {
                    lastReport = try await model.useBackupDisk(at: url)
                    pickError = sizeCeilingWarning
                } catch {
                    pickError = String(
                        localized: "That folder wasn’t used: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Runs `body` with the busy flag held and the page refreshed afterwards, so
    /// every button that changes something leaves the numbers honest.
    private func work(_ body: () async -> Void) async {
        isWorking = true
        await body()
        isWorking = false
        await refresh()
    }

    private func refresh() async {
        availability = model.backupAvailability()
        storeSizes = await model.backupSizesByStore()
        pendingCount = await model.pendingBackupTransfers()
        transferState = await model.backupTransferState()
        isOnThisMacsDisk = prefs.backupDestination.directory.map {
            BackupDestinationProbe.isOnSameVolume($0, as: BackupStore.outboxRoot)
        } ?? false
        var avail: [String: BackupStore.Availability] = [:]
        for destination in prefs.knownBackupDestinations {
            avail[destinationKey(destination)] = model.backupAvailability(for: destination)
        }
        knownAvailability = avail
    }

    private func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Groups a destination by identity where there is one, else by path — the same
/// rule `BackupDestination.known(from:)` uses to dedupe the remembered list.
private func destinationKey(_ destination: BackupDestination) -> String {
    destination.identity ?? destination.path ?? ""
}

/// The compression choice, laid out the way the other settings pickers are.
private struct AdaptiveCompressionRow: View {
    @Binding var selection: BundleArchive.Compression

    var body: some View {
        HStack(spacing: 12) {
            Text("Compression").font(.callout)
            Spacer(minLength: 12)
            Picker("Compression", selection: $selection) {
                Text("Faster").tag(BundleArchive.Compression.fast)
                Text("Smaller").tag(BundleArchive.Compression.smallest)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
