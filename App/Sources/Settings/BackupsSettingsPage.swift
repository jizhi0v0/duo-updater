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
    @State private var heldCount = 0
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
    /// Each disk's real icon (or, absent that, the measured volume kind for a
    /// symbol fallback), keyed the same way a row identifies itself. See
    /// `AppListModel.backupDiskAppearances(for:)` for why this is fetched off
    /// the main thread and cached rather than asked fresh on every render.
    @State private var diskAppearances: [String: BackupDiskAppearance] = [:]
    @State private var lastReport: BackupDestinationProbe.Report?
    @State private var pickError: String?
    @State private var isWorking = false
    /// True when the chosen folder lives on the same volume as the local
    /// store, which makes every word of the "another disk" promise untrue.
    @State private var isOnThisMacsDisk = false
    /// Whether the "On another disk" list is expanded. Deliberately independent
    /// of `prefs.backupDestination.kind`: picking that radio option only
    /// reveals the disks to choose from, it does not itself point backups
    /// anywhere — that only happens once a specific disk row is tapped, and
    /// only after anything owed to it has been accounted for.
    @State private var showsDiskList: Bool
    /// A disk pick waiting on a decision about backups already on this Mac. By
    /// the time this is set, the switch has already happened — see
    /// `beginSwitch(to:diskLabel:)` — so "Cancel" has to put `previous` back
    /// rather than merely dismissing.
    @State private var pendingMove: PendingBackupMove?

    @State private var showingBackups = false
    @State private var backupListing: [BackupStore.Listing] = []
    @State private var isCleaningBackups = false

    init(prefs: Preferences, model: AppListModel) {
        _prefs = Bindable(wrappedValue: prefs)
        self.model = model
        _showsDiskList = State(initialValue: prefs.backupDestination.kind == .external)
    }

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
            // backup that had already landed. Sizes walk every store, so they
            // are re-read only when something has actually changed.
            var tick = 0
            var storeCount = await model.backupStoreChangeCount()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                // Two cadences on purpose. The queue's state lives in memory and
                // is free to read, so the progress line stays live; the change
                // signal is a directory listing per store, so it runs half as
                // often and only re-measures sizes when it moves.
                transferState = await model.backupTransferState()
                tick += 1
                if tick % 2 == 0 {
                    // Both signals, because neither covers the other. What is
                    // owed moves during a transfer while the number of stored
                    // backups does not; the count moves when a backup is taken
                    // or deleted, including while backups are kept on this Mac,
                    // where nothing is ever owed and the owed count is frozen
                    // at zero.
                    let owed = await model.pendingBackupTransfers()
                    let count = await model.backupStoreChangeCount()
                    if owed != pendingCount || count != storeCount {
                        storeCount = count
                        await refresh()
                    }
                }
            }
        }
        .task {
            // A separate, one-shot task: this walks every mounted volume, which
            // touches the filesystem and would block the render pass if it ran
            // inline in `body`.
            discoveredStores = await model.discoverBackupStores()
            await refreshDiskAppearances()
        }
        .sheet(isPresented: $showingBackups) {
            BackupsSheet(backups: backupListing) { keys in
                Task {
                    await model.deleteBackups(keys: keys)
                    await refresh()
                }
            }
        }
        .confirmationDialog(
            moveDialogTitle,
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { presented in if !presented { resolvePendingMove(.cancel) } }),
            titleVisibility: .visible
        ) {
            Button("Copy Them Over") { resolvePendingMove(.copyOver) }
            Button("Leave Them on This Mac") { resolvePendingMove(.leaveOnThisMac) }
            Button("Cancel", role: .cancel) { resolvePendingMove(.cancel) }
        } message: {
            Text(moveDialogMessage)
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
            .disabled(isWorking)
            .settingsRow()

            if showsDiskList {
                ForEach(destinationOptions) { option in
                    SettingsDivider()
                    destinationRow(option)
                }
                SettingsDivider()
                chooseAnotherRow
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

    /// One row per disk this Mac knows about, followed by any disk plugged in
    /// right now that already carries a store this Mac was never configured
    /// for. Shown only once "On another disk" is expanded — see `showsDiskList`.
    private var destinationOptions: [DestinationOption] {
        let known = prefs.knownBackupDestinations
        var out: [DestinationOption] = known.map(DestinationOption.known)
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
                diskIconView(for: option)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: option))
                    if let subtitle = subtitle(for: option) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Shown on every row, selected or not — not just this one.
                    // A row's height used to depend on selection (only the
                    // active disk grew this line), which made the whole card
                    // jump every time the choice moved. It also isn't optional:
                    // a volume's name is not its identity (see
                    // `BackupDestination.volumeName`'s own doc comment —
                    // "Never a matching criterion, volumes get renamed"), so two
                    // disks both named "Backup" are indistinguishable without it.
                    if let path = path(for: option) {
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
                } else {
                    if pendingCount > 0 {
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
                    }
                    if heldCount > 0 {
                        SettingsDivider()
                        HStack {
                            // Says "on purpose", not just a count: these are not
                            // stuck or forgotten — someone pressed "Leave Them
                            // on This Mac" when the disk changed, and this is
                            // where they can undo that.
                            Text("Staying on this Mac on purpose: \(heldCount)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy Now") {
                                Task { await work { await model.releaseHeldBackupsAndSync() } }
                            }
                            .controlSize(.small)
                            .disabled(isWorking)
                        }
                        .settingsRow()
                    }
                    if pendingCount == 0, heldCount == 0, case .ready = availability {
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

    /// One disk the picker can show underneath "On another disk". `known`
    /// disks are offered whether or not they are plugged in right now — the
    /// picker has to name a disk in order to say it isn't connected — and
    /// `discovered` disks are ones found on a volume that is mounted right now
    /// but was never adopted here.
    private enum DestinationOption: Identifiable {
        case known(BackupDestination)
        case discovered(BackupStoreDiscovery.Found)

        var id: String {
            switch self {
            case .known(let destination): return "known:\(destinationKey(destination))"
            case .discovered(let found): return "discovered:\(found.marker.identity)"
            }
        }
    }

    private func isSelected(_ option: DestinationOption) -> Bool {
        switch option {
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
        // Pressing the disk already in use changes nothing, and running the
        // switch anyway disabled every row for the round trip — a flash of grey
        // that said something was happening when nothing was.
        guard !isSelected(option) else { return }
        switch option {
        case .known(let destination):
            beginSwitch(to: destination, diskLabel: title(for: option))
        case .discovered(let found):
            adopt(at: found.root)
        }
    }

    private func path(for option: DestinationOption) -> String? {
        switch option {
        case .known(let destination): return destination.path
        case .discovered(let found): return found.root.path
        }
    }

    private func icon(for option: DestinationOption) -> String {
        switch option {
        case .known(let destination):
            switch availability(for: destination) {
            case .volumeNotMounted: return "externaldrive.badge.xmark"
            case .identityMismatch: return "externaldrive.badge.questionmark"
            case .notWritable:      return "lock.fill"
            case .localOnly:        return baseSymbol(for: volumeKind(for: option))
            case .ready:
                switch volumeKind(for: option) {
                case .internalDisk: return "internaldrive.fill"
                case .external:     return "externaldrive.fill.badge.checkmark"
                case .network:      return "externaldrive.connected.to.line.below"
                }
            }
        case .discovered:
            return "externaldrive.badge.plus"
        }
    }

    private func baseSymbol(for kind: BackupVolumeKind) -> String {
        switch kind {
        case .internalDisk: return "internaldrive"
        case .external:      return "externaldrive"
        case .network:        return "externaldrive.connected.to.line.below"
        }
    }

    private func tint(for option: DestinationOption) -> Color {
        switch option {
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
        case .known(let destination):
            return destination.volumeName ?? String(localized: "Backup disk")
        case .discovered(let found):
            return found.volumeName ?? String(localized: "Backup disk")
        }
    }

    private func subtitle(for option: DestinationOption) -> String? {
        switch option {
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

    // MARK: - Disk icons

    /// The disk's own icon when one could be resolved — live or cached from a
    /// previous session — else the symbol `icon(for:)`/`tint(for:)` already
    /// pick for its state. A real icon is never recoloured (that would defeat
    /// the point of using one); reachability is instead conveyed by dimming
    /// it, the same signal a person already reads on a disconnected drive in
    /// Finder, so it never has to fight the status caption for the same job.
    @ViewBuilder
    private func diskIconView(for option: DestinationOption) -> some View {
        if let image = diskAppearances[iconCacheKey(for: option)]?.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .opacity(isDimmed(option) ? 0.4 : 1.0)
        } else {
            Image(systemName: icon(for: option))
                .foregroundStyle(tint(for: option))
                .frame(width: 18)
        }
    }

    private func iconCacheKey(for option: DestinationOption) -> String {
        switch option {
        case .known(let destination): return destination.identity ?? destination.path ?? "unknown"
        case .discovered(let found): return found.marker.identity
        }
    }

    private func volumeKind(for option: DestinationOption) -> BackupVolumeKind {
        diskAppearances[iconCacheKey(for: option)]?.kind ?? .external
    }

    private func isDimmed(_ option: DestinationOption) -> Bool {
        switch option {
        case .known(let destination):
            if case .ready = availability(for: destination) { return false }
            return true
        case .discovered:
            // Discovered rows are, by construction, on a volume mounted right
            // now — there is nothing to dim.
            return false
        }
    }

    private func refreshDiskAppearances() async {
        var entries: [(cacheKey: String, path: String?)] = []
        for destination in prefs.knownBackupDestinations {
            entries.append((destination.identity ?? destination.path ?? "unknown", destination.path))
        }
        for found in discoveredStores {
            entries.append((found.marker.identity, found.root.path))
        }
        let appearances = await model.backupDiskAppearances(for: entries)
        // Merged, not replaced: a disk that just went offline keeps whatever
        // it last looked like rather than losing its icon the moment it can no
        // longer be asked for one.
        diskAppearances.merge(appearances) { _, new in new }
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

    // MARK: - Moving existing backups

    /// A disk pick this page put up a confirmation for. Everything needed to
    /// either finish the switch or undo it is captured here, at the moment the
    /// sheet is built — see `holdBackupsOnThisMac`'s own doc comment for why
    /// `keys` in particular must not be re-read later.
    private struct PendingBackupMove {
        let previous: BackupDestination
        let diskLabel: String
        /// Whether the disk is connected right now, which changes only what the
        /// message says about *when* — never which answers are on offer.
        let reachable: Bool
        let keys: [String]
        let bytes: Int64
    }

    private enum PendingMoveAction {
        case copyOver, leaveOnThisMac, cancel
    }

    private var moveDialogTitle: String {
        guard let pendingMove else { return "" }
        return String(localized: "Move existing backups to “\(pendingMove.diskLabel)”?")
    }

    private var moveDialogMessage: String {
        guard let pendingMove else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: pendingMove.bytes, countStyle: .file)
        if !pendingMove.reachable {
            return String(localized: "There are \(pendingMove.keys.count) backups on this Mac, \(size). The disk isn’t connected, so they would move as soon as it is. New backups will be kept on the disk either way.")
        }
        return String(localized: "There are \(pendingMove.keys.count) backups on this Mac, \(size). New backups will be kept on the disk either way.")
    }

    private func resolvePendingMove(_ action: PendingMoveAction) {
        guard let pending = pendingMove else { return }
        pendingMove = nil
        Task {
            await work {
                switch action {
                case .copyOver:
                    model.beginDrainingBackups()
                case .leaveOnThisMac:
                    await model.holdBackupsOnThisMac(keys: pending.keys)
                case .cancel:
                    await model.revertBackupDestination(to: pending.previous)
                }
            }
        }
    }

    /// Point new backups at `destination`, then decide whether that is the
    /// whole story or a decision belongs in front of the user first.
    ///
    /// The switch itself is instantaneous and, on its own, reversible — a
    /// preference and a reconfigured store, nothing copied or queued. That is
    /// what makes it safe to do before asking what is owed:
    /// `pendingOutboxSnapshot()` only means anything once the destination is
    /// external, so the switch has to happen first for the answer to be
    /// accurate. What must not happen automatically is the drain — seeing that
    /// start, unannounced, on every backup already on this Mac is the bug this
    /// whole flow exists to fix.
    private func beginSwitch(to destination: BackupDestination, diskLabel: String) {
        guard !isWorking else { return }
        let previous = prefs.backupDestination
        let reachable: Bool = {
            if case .ready = availability(for: destination) { return true }
            return false
        }()
        Task {
            await work {
                await model.useBackupDisk(destination)
                await afterSwitch(reachable: reachable, previous: previous, diskLabel: diskLabel)
            }
        }
    }

    /// After the destination has already been switched — and only switched —
    /// decide whether there is anything to ask about. A disk that cannot be
    /// written to right now cannot receive anything either, so nothing is
    /// about to move regardless of what is owed; a reachable one with nothing
    /// owed is just as uneventful. Only a reachable disk with backups actually
    /// sitting in the outbox is worth putting a decision in front of someone.
    private func afterSwitch(reachable: Bool, previous: BackupDestination, diskLabel: String) async {
        let snapshot = await model.pendingOutboxSnapshot()
        guard !snapshot.keys.isEmpty else {
            model.beginDrainingBackups()
            return
        }
        // Asked whether the disk is here or not. An unreachable disk does not
        // make the question go away, it only defers the answer: the queue moves
        // everything the moment the disk is plugged in, so skipping the
        // confirmation here bought exactly the silent multi-gigabyte move it was
        // added to prevent, with a delay in front of it. The counts come from
        // this Mac, which can be read either way.
        pendingMove = PendingBackupMove(
            previous: previous, diskLabel: diskLabel, reachable: reachable,
            keys: snapshot.keys, bytes: snapshot.bytes)
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
    /// picking a disk the scan already found holding a store. A folder just
    /// probed is, by construction, reachable right now — the probe itself
    /// would have thrown otherwise — so there is no availability check to make
    /// before deciding whether a confirmation is needed.
    private func adopt(at url: URL) {
        guard !isWorking else { return }
        let previous = prefs.backupDestination
        Task {
            await work {
                do {
                    let report = try await model.useBackupDisk(at: url)
                    lastReport = report
                    pickError = sizeCeilingWarning
                    let diskLabel = prefs.backupDestination.volumeName ?? String(localized: "Backup disk")
                    await refreshDiskAppearances()
                    await afterSwitch(reachable: true, previous: previous, diskLabel: diskLabel)
                } catch {
                    pickError = String(
                        localized: "That folder wasn’t used: \(error.localizedDescription)")
                }
            }
        }
    }

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { showsDiskList },
            set: { external in
                showsDiskList = external
                if external {
                    // Expanding the list is not a choice, and leaving it at
                    // that put the card in a state it could not describe: the
                    // radio says backups go to a disk while the destination is
                    // still this Mac, for as long as nobody picks a row. With
                    // several disks listed that is easy to walk away from.
                    // Landing on the first makes the radio true the moment it
                    // is set, and picking a different row afterwards is one
                    // press. First is the disk used most recently, and by
                    // construction rather than by luck: `BackupDestination.save`
                    // re-inserts a disk at the head of the remembered list every
                    // time it is chosen, and `known(from:)` reads that order.
                    guard prefs.backupDestination.kind != .external else { return }
                    if let first = destinationOptions.first {
                        select(first)
                    } else {
                        chooseDisk()
                    }
                    return
                }
                guard prefs.backupDestination.kind == .external else { return }
                // Choosing "On this Mac" is itself an action, not just
                // collapsing the list: if backups were going to a disk, new
                // ones come back here. Nothing to confirm going this
                // direction — the pointer moves, nothing is copied, and
                // whatever is already on the disk stays exactly there (see
                // `useLocalBackups`'s own doc comment).
                Task { await work { await model.useLocalBackups() } }
            })
    }

    /// Runs `body` with the busy flag held and the page refreshed afterwards, so
    /// every button that changes something leaves the numbers honest.
    ///
    /// Deliberately narrow: this covers a switch, a hold, or a revert — never a
    /// transfer. `syncBackupsNow()`/`beginDrainingBackups()` are fire-and-forget
    /// on purpose (see the latter's doc comment), so a drain that takes minutes
    /// never holds this flag and never greys out the card while it runs.
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
        heldCount = await model.heldBackupCount()
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
