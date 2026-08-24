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

    @State private var outboxBytes: Int64?
    @State private var destinationBytes: Int64?
    @State private var pendingCount = 0
    @State private var transferState: BackupTransferQueue.State = .idle
    @State private var availability: BackupStore.Availability = .localOnly(BackupStore.outboxRoot)
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
            rollbackCard
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
            Picker("Where backups are kept", selection: locationBinding) {
                Text("On this Mac").tag(false)
                Text("On another disk").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .settingsRow()

            if prefs.backupDestination.kind == .external {
                SettingsDivider()
                diskRow.settingsRow()
            }
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

    private var diskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                if let path = prefs.backupDestination.path {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 12)
            Button("Change…") { chooseDisk() }
                .controlSize(.small)
                .disabled(isWorking)
        }
    }

    private var storageCard: some View {
        SettingsCard(header: "Storage") {
            HStack {
                Text("On this Mac")
                Spacer()
                Text(format(outboxBytes)).foregroundStyle(.secondary)
            }
            .settingsRow()

            if prefs.backupDestination.kind == .external {
                SettingsDivider()
                HStack {
                    Text(prefs.backupDestination.volumeName.map { "On “\($0)”" } ?? "On the backup disk")
                    Spacer()
                    Text(format(destinationBytes)).foregroundStyle(.secondary)
                }
                .settingsRow()

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

    // MARK: - Status wording

    private var statusIcon: String {
        if isOnThisMacsDisk { return "internaldrive.fill" }
        switch availability {
        case .ready:             return "externaldrive.fill.badge.checkmark"
        case .volumeNotMounted:  return "externaldrive.badge.xmark"
        case .identityMismatch:  return "externaldrive.badge.questionmark"
        case .notWritable:       return "lock.fill"
        case .localOnly:         return "internaldrive.fill"
        }
    }

    private var statusTint: Color {
        if isOnThisMacsDisk { return .orange }
        if case .ready = availability { return .accentColor }
        if case .localOnly = availability { return .secondary }
        return .orange
    }

    private var statusTitle: String {
        let name = prefs.backupDestination.volumeName
        switch availability {
        case .ready:
            if isOnThisMacsDisk { return String(localized: "This folder is on this Mac’s disk") }
            return name.map { String(localized: "“\($0)” is connected") }
                ?? String(localized: "Connected")
        case .volumeNotMounted:
            return name.map { String(localized: "“\($0)” isn’t connected") }
                ?? String(localized: "The backup disk isn’t connected")
        case .identityMismatch:
            return String(localized: "A different disk is mounted here")
        case .notWritable:
            return String(localized: "This folder can’t be written to")
        case .localOnly:
            return String(localized: "Backups are kept on this Mac")
        }
    }

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

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { prefs.backupDestination.kind == .external },
            set: { wantsExternal in
                guard wantsExternal else {
                    Task { await work { await model.useLocalBackups() } }
                    return
                }
                // Turning the disk back on is a switch, not a decision to make
                // again. Only ask for a folder when there is none to return to —
                // and note that "remembered but not plugged in right now" is not
                // one of those cases: the status row says so, and backups wait on
                // this Mac until it is back, which is the designed behaviour.
                if let remembered = prefs.rememberedBackupDisk {
                    Task { await work { await model.useBackupDisk(remembered) } }
                } else {
                    chooseDisk()
                }
            })
    }

    private func chooseDisk() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use This Folder")
        panel.message = String(localized: "Choose a folder on an external disk or a network share. Backups are kept inside it, and moving them there is what frees space on this Mac.")

        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        let sizes = await model.backupStoreSizes()
        outboxBytes = sizes.outbox
        destinationBytes = sizes.destination
        pendingCount = await model.pendingBackupTransfers()
        transferState = await model.backupTransferState()
        isOnThisMacsDisk = prefs.backupDestination.directory.map {
            BackupDestinationProbe.isOnSameVolume($0, as: BackupStore.outboxRoot)
        } ?? false
    }

    private func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
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
