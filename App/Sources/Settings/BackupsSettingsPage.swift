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

    /// Which stores to draw a row for. Answered in milliseconds, and kept
    /// apart from `storeBytes` on purpose: a row's existence is not a
    /// measurement, and deriving the rows from the measurement left the whole
    /// card empty for the five seconds it takes to walk a 49 GB store on USB.
    @State private var stores: [BackupStore.Store] = []
    /// Bytes per store id, filled in as the walk finishes. A store missing from
    /// here renders "…", not a missing row.
    @State private var storeBytes: [String: Int64] = [:]
    /// Room on each store's volume, by store id. A stat rather than a walk, so
    /// it lands with the rows rather than behind them.
    @State private var volumeSpace: [String: BackupVolumeSpace] = [:]
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
    /// Disks and shares plugged in right now that could take a store but carry
    /// none. Offered inside the "somewhere else" row rather than as rows of
    /// their own — see `chooseAnotherRow`.
    @State private var candidateVolumes: [BackupStoreDiscovery.Candidate] = []
    /// Whether each candidate will actually take a file, by candidate id. Filled
    /// in behind the rows the way `storeBytes` is: the answer costs a write, and
    /// a row that waited for it would be a row that was not there yet.
    @State private var candidateWritable: [String: Bool] = [:]
    /// What was mounted when the disks were last looked at. Everything about a
    /// disk — whether it holds a store, whether it can be written to, what its
    /// icon is — changes only when a disk is plugged in or pulled out, and this
    /// is how that is noticed without asking the disks themselves.
    @State private var mountedVolumes: [String] = []
    /// Whether the disks that cannot take a backup are shown. Folded away by
    /// default: a Mac can have a dozen things mounted — installer images,
    /// shares, a Time Machine disk — and a list mostly made of disks you cannot
    /// choose is harder to read than one that names them and steps aside.
    @State private var showsUnusableDisks = false
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
    /// A disk pick waiting on a decision about backups already on this Mac. By
    /// the time this is set, the switch has already happened — see
    /// `beginSwitch(to:diskLabel:)` — so "Cancel" has to put `previous` back
    /// rather than merely dismissing.
    @State private var pendingMove: PendingBackupMove?

    @State private var showingBackups = false
    @State private var backupListing: [BackupStore.Listing] = []
    @State private var isCleaningBackups = false
    /// The size walk in flight, so a refresh can replace it rather than race it.
    @State private var sizeTask: Task<Void, Never>?

    init(prefs: Preferences, model: AppListModel) {
        _prefs = Bindable(wrappedValue: prefs)
        self.model = model
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
                    // Plugging a disk in changes neither of those, and it is the
                    // one thing someone with this page open is most likely to do.
                    // Gated on the mount table rather than run each time: the
                    // scan behind it opens marker files and reads attributes on
                    // every attached volume, and a network share is somewhere
                    // that costs a round trip to answer — polling one every two
                    // seconds for an answer that changes when a cable moves is
                    // not a price this page should make anyone pay.
                    let mounted = await model.mountedVolumePaths()
                    if mounted != mountedVolumes {
                        mountedVolumes = mounted
                        await refreshAttachedDisks()
                    }
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
            mountedVolumes = await model.mountedVolumePaths()
            await refreshAttachedDisks()
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
            ForEach(Array(usableOptions.enumerated()), id: \.element.id) { index, option in
                if index > 0 { SettingsDivider() }
                destinationRow(option)
            }
            if !unusableOptions.isEmpty {
                SettingsDivider()
                unusableGroupRow
                if showsUnusableDisks {
                    ForEach(unusableOptions, id: \.id) { option in
                        SettingsDivider()
                        destinationRow(option)
                    }
                }
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

    /// One row per disk this Mac knows about, followed by any disk plugged in
    /// right now that already carries a store this Mac was never configured
    /// for, and this Mac at the head of them.
    private var destinationOptions: [DestinationOption] {
        let known = prefs.knownBackupDestinations
        var out: [DestinationOption] = [.thisMac] + known.map(DestinationOption.known)
        let knownIdentities = Set(known.compactMap(\.identity))
        for found in discoveredStores where !knownIdentities.contains(found.marker.identity) {
            out.append(.discovered(found))
        }
        out.append(contentsOf: candidateVolumes.map(DestinationOption.candidate))
        return out
    }

    /// The disks worth putting first: everywhere backups are or could go.
    private var usableOptions: [DestinationOption] {
        destinationOptions.filter { !isUnusable($0) }
    }

    /// Attached, named, and not a choice — a Time Machine volume, or a share that
    /// will not take a file. They stay in the list rather than disappearing from
    /// it, because a disk you can see on your desk and not in this list reads as
    /// a list that is broken; they are just folded.
    ///
    /// Not everything mounted lands here. A read-only disk image never becomes a
    /// candidate at all (`BackupStoreDiscovery.isWorthOffering`), so the two
    /// installer images mounted on the Mac this was written on appear in neither
    /// list — they are not disks anyone is choosing between.
    private var unusableOptions: [DestinationOption] {
        destinationOptions.filter { isUnusable($0) }
    }

    private var unusableGroupRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showsUnusableDisks.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsUnusableDisks ? 90 : 0))
                    .frame(width: 18)
                // Colon form rather than "%lld disks can't", for the reason the
                // storage rows give: no plural agreement to get wrong in any
                // language, in a row that is only ever a count.
                Text("Attached, but can’t take backups: \(unusableOptions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsRow()
    }

    private func destinationRow(_ option: DestinationOption) -> some View {
        let selected = isSelected(option)
        return Button {
            select(option)
        } label: {
            HStack(spacing: 10) {
                diskIconView(for: option)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: option))
                    // The bar carries "is this disk here" better than a word
                    // does — it is either drawn against real numbers or it is
                    // not there at all — and answers the two questions the
                    // word never did: how much is free, and how much of what
                    // is used is ours.
                    if let space = space(for: option) {
                        let id = storeID(for: option)
                        CapacityBar(
                            backups: id.flatMap { storeBytes[$0] } ?? 0,
                            used: space.used, total: space.total)
                        // The two numbers worth comparing, at opposite ends of
                        // the bar that shows their proportion. Run together on
                        // one line they had to be read as a sentence before
                        // they could be compared. The left one takes the bar's
                        // own colour, which saves the bar needing a legend.
                        HStack(spacing: 12) {
                            // Left blank on a disk with no store: "Backups: Zero
                            // KB" would be a measurement of something that does
                            // not exist, and "…" would promise one is coming.
                            if let id {
                                Text("Backups: \(format(storeBytes[id]))")
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer(minLength: 8)
                            Text("\(bytes(space.free)) free of \(bytes(space.total))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
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
                // The slot is kept whether this row is chosen or not, for the
                // same reason the path is on every row: when the checkmark
                // existed only on the chosen one, everything to its left — the
                // bar, and the figure pinned to the bar's right end — slid
                // sideways each time the choice moved.
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(!selected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking || isUnusable(option))
        .settingsRow()
    }

    /// A row that cannot be pressed because the disk behind it will not take a
    /// backup whatever folder is chosen on it.
    private func isUnusable(_ option: DestinationOption) -> Bool {
        guard case .candidate(let candidate) = option else { return false }
        // Until the write test lands the row is pressable: an unanswered question
        // is not a no, and the panel it opens costs nothing if the answer turns
        // out to be no.
        return candidate.isReservedForTimeMachine || candidateWritable[candidate.id] == false
    }

    /// The places the rows above cannot reach. Every attached disk and share now
    /// has a row of its own, and pressing one opens this same panel on that disk
    /// — so what is left for this row is narrower than it was, and still real:
    ///
    ///   * a second *internal* volume, which is deliberately never offered as a
    ///     row (on most Macs it shares the boot container's free space, so moving
    ///     backups there frees nothing) but is a genuine choice on a Mac that has
    ///     a real second drive;
    ///   * a folder on this Mac's own disk, which frees no space and says so, but
    ///     is the only option on a Mac with nothing attached;
    ///   * a volume mounted `nobrowse`, which the scan skips along with every
    ///     system volume.
    private var chooseAnotherRow: some View {
        Button { chooseDisk() } label: {
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

    /// Everything that depends on which disks are attached. Run when the page
    /// opens and when the mount table moves, never on the plain tick.
    private func refreshAttachedDisks() async {
        discoveredStores = await model.discoverBackupStores()
        await refreshCandidateVolumes()
        await refreshDiskAppearances()
    }

    private func refreshCandidateVolumes() async {
        let configured = prefs.knownBackupDestinations.compactMap(\.path)
        let fresh = await model.candidateBackupVolumes(excluding: configured)
        // Assigning an equal array still invalidates the view, and this runs on
        // a timer.
        guard fresh != candidateVolumes else { return }
        candidateVolumes = fresh
        // Only for disks whose answer is not already known, so replugging one
        // disk does not re-test the rest — and never for a Time Machine disk,
        // which `canWrite` refuses without touching it.
        for candidate in fresh where candidateWritable[candidate.id] == nil {
            candidateWritable[candidate.id] =
                await model.backupVolumeIsWritable(candidate.volume)
        }
    }

    private var storageCard: some View {
        SettingsCard(header: "Storage") {
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
    /// One place backups can be kept. This Mac is one of them rather than a
    /// category above them: its store is a directory on a disk like any other,
    /// and giving it its own radio tier meant every row below it was answering
    /// a different question than the row above.
    private enum DestinationOption: Identifiable {
        case thisMac
        case known(BackupDestination)
        case discovered(BackupStoreDiscovery.Found)
        /// A disk or share plugged in right now with no backups on it. A row
        /// like the rest, rather than something to be found inside a menu: a
        /// disk someone can see attached to their Mac and cannot see in this
        /// list reads as a list that is broken.
        case candidate(BackupStoreDiscovery.Candidate)

        var id: String {
            switch self {
            case .thisMac: return "this-mac"
            case .known(let destination): return "known:\(destinationKey(destination))"
            case .discovered(let found): return "discovered:\(found.marker.identity)"
            case .candidate(let candidate): return "candidate:\(candidate.id)"
            }
        }
    }

    private func isSelected(_ option: DestinationOption) -> Bool {
        switch option {
        case .thisMac:
            return prefs.backupDestination.kind == .local
        case .known(let destination):
            return prefs.backupDestination.kind == .external
                && destinationKey(destination) == destinationKey(prefs.backupDestination)
        case .discovered, .candidate:
            // Never the active choice: a discovered disk is, by construction,
            // one whose identity isn't among the known destinations, and the
            // active destination is always one of those. A candidate has no
            // store at all yet.
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
        case .thisMac:
            // Nothing to confirm in this direction: the pointer moves, nothing
            // is copied, and whatever is already on a disk stays exactly there
            // (see `useLocalBackups`'s own doc comment).
            Task { await work { await model.useLocalBackups() } }
        case .known(let destination):
            beginSwitch(to: destination, diskLabel: title(for: option))
        case .discovered(let found):
            adopt(at: found.root)
        case .candidate(let candidate):
            // The one row that asks something back. A disk with no store on it
            // has no folder yet, and which folder is not ours to assume: some
            // disks are only writable in part, and a share is usually somebody's
            // whole filing system. The panel opens *on* the disk, so saying "the
            // top of it" is one press.
            chooseDisk(startingAt: candidate.volume)
        }
    }

    private func path(for option: DestinationOption) -> String? {
        switch option {
        case .thisMac: return (BackupStore.outboxRoot.path as NSString).abbreviatingWithTildeInPath
        case .known(let destination): return destination.path
        case .discovered(let found): return found.root.path
        case .candidate(let candidate): return candidate.volume.path
        }
    }

    private func icon(for option: DestinationOption) -> String {
        switch option {
        case .thisMac:
            return "internaldrive.fill"
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
        case .candidate(let candidate):
            if isUnusable(option) { return "lock.fill" }
            return candidate.isNetwork
                ? "externaldrive.connected.to.line.below"
                : "externaldrive.badge.plus"
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
        case .thisMac:
            return isSelected(option) ? .accentColor : .secondary
        case .known(let destination):
            switch availability(for: destination) {
            case .ready:     return .accentColor
            case .localOnly: return .secondary
            default:         return .orange
            }
        case .discovered:
            return .blue
        case .candidate:
            return isUnusable(option) ? .secondary : .blue
        }
    }

    private func title(for option: DestinationOption) -> String {
        switch option {
        case .thisMac:
            return String(localized: "This Mac")
        case .known(let destination):
            return destination.volumeName ?? String(localized: "Backup disk")
        case .discovered(let found):
            return found.volumeName ?? String(localized: "Backup disk")
        case .candidate(let candidate):
            return candidate.name ?? candidate.volume.lastPathComponent
        }
    }

    private func subtitle(for option: DestinationOption) -> String? {
        switch option {
        case .thisMac:
            // Only when the startup disk cannot be measured at all, which means
            // something is very wrong; otherwise its numbers say it better.
            return showsCapacity(option) ? nil : String(localized: "Always connected")
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
            case .ready:             return showsCapacity(option) ? nil : String(localized: "Connected")
            case .volumeNotMounted:  return String(localized: "Isn’t connected")
            case .identityMismatch:  return String(localized: "A different disk is mounted here")
            case .notWritable:       return String(localized: "Can’t be written to")
            case .localOnly:         return nil
            }
        case .discovered:
            return String(localized: "Has a backup store, but isn’t set up on this Mac.")
        case .candidate(let candidate):
            // Says what pressing it will do, because this is the only row whose
            // press opens something rather than deciding something.
            if candidate.isReservedForTimeMachine {
                return String(localized: "Reserved for Time Machine — nothing else can be written here")
            }
            if candidateWritable[candidate.id] == false {
                return String(localized: "Can’t be written to")
            }
            return String(localized: "No backups here yet — choose a folder on it")
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
        case .thisMac: return DestinationOption.thisMac.id
        case .known(let destination): return destination.identity ?? destination.path ?? "unknown"
        case .discovered(let found): return found.marker.identity
        case .candidate(let candidate): return candidate.id
        }
    }

    private func volumeKind(for option: DestinationOption) -> BackupVolumeKind {
        diskAppearances[iconCacheKey(for: option)]?.kind ?? .external
    }

    private func isDimmed(_ option: DestinationOption) -> Bool {
        switch option {
        case .thisMac:
            return false
        case .known(let destination):
            if case .ready = availability(for: destination) { return false }
            return true
        case .discovered:
            // Discovered rows are, by construction, on a volume mounted right
            // now — there is nothing to dim.
            return false
        case .candidate:
            // The disk is attached and healthy; what is dimmed is the fact that
            // nothing here can put anything on it.
            return isUnusable(option)
        }
    }

    private func refreshDiskAppearances() async {
        // The startup disk first, and asked for by the volume rather than by
        // the store inside it — `icon(forFile:)` on a folder answers with a
        // folder.
        var entries: [(cacheKey: String, path: String?)] = [(DestinationOption.thisMac.id, "/")]
        for destination in prefs.knownBackupDestinations {
            entries.append((destination.identity ?? destination.path ?? "unknown", destination.path))
        }
        for found in discoveredStores {
            entries.append((found.marker.identity, found.root.path))
        }
        for candidate in candidateVolumes {
            entries.append((candidate.id, candidate.volume.path))
        }
        let appearances = await model.backupDiskAppearances(for: entries)
        // Merged, not replaced: a disk that just went offline keeps whatever
        // it last looked like rather than losing its icon the moment it can no
        // longer be asked for one.
        diskAppearances.merge(appearances) { _, new in new }
    }

    // MARK: - Storage wording

    /// The reachable store this row stands for, or nil when there is none —
    /// which is what a disk that is not plugged in looks like from here.
    private func storeID(for option: DestinationOption) -> String? {
        stores.first { store in
            switch option {
            case .thisMac:                return store.location == .outbox
            case .known(let destination): return store.identity == destination.identity
            case .discovered(let found):  return store.identity == found.marker.identity
            // A candidate is a volume with no store on it — that is what makes
            // it a candidate rather than a discovered disk.
            case .candidate:              return false
            }
        }?.id
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// Whether the row is already saying its numbers, in which case the caption
    /// beneath has nothing left to add.
    private func showsCapacity(_ option: DestinationOption) -> Bool {
        space(for: option) != nil
    }

    /// Room on the volume this row stands for. A store's measurement where there
    /// is a store, and the volume's own figures where there is not — a disk with
    /// nothing on it still has to say how big it is, or choosing it is a guess.
    private func space(for option: DestinationOption) -> BackupVolumeSpace? {
        if let id = storeID(for: option) { return volumeSpace[id] }
        guard case .candidate(let candidate) = option,
              let free = candidate.freeBytes, let total = candidate.totalBytes, total > 0
        else { return nil }
        return BackupVolumeSpace(free: free, total: total)
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

    private func chooseDisk(startingAt volume: URL? = nil) {
        let panel = NSOpenPanel()
        // Opening on the disk that was pressed, so choosing its top level is one
        // press rather than a navigation.
        panel.directoryURL = volume
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
        stores = await model.backupStores()
        var space: [String: BackupVolumeSpace] = [:]
        for store in stores { space[store.id] = await model.backupVolumeSpace(of: store) }
        volumeSpace = space
        // Not awaited. Everything above is a stat or two; this walks every
        // backup in every store, and holding the card's other numbers back for
        // it is what made opening the page look broken.
        measureStores()
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

    /// Walk the stores for their sizes, replacing any walk still in flight —
    /// a refresh that lands mid-walk wants the newer answer, and two walks of
    /// the same USB disk at once are slower than one.
    private func measureStores() {
        sizeTask?.cancel()
        let wanted = stores
        sizeTask = Task {
            // In the order `reachableStores()` gives them, which puts this Mac
            // first — so the row that measures in milliseconds is filled in
            // while a USB disk is still being walked, instead of after.
            for store in wanted {
                let bytes = await model.backupStoreBytes(of: store)
                guard !Task.isCancelled else { return }
                storeBytes[store.id] = bytes
            }
        }
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
/// How full the volume a store sits on is, and how much of that is ours.
///
/// Three segments rather than one: "49.58 GB of backups" means something
/// different on a disk with 60 GB free than on one with 600 MB, and deciding
/// whether to keep going is the reason someone opens this page. The backups'
/// share is drawn in the accent colour because it is the only part this app
/// can do anything about.
///
/// Hidden from accessibility: the line beneath it says the same thing in
/// words, and a bar read aloud as three unnamed rectangles says nothing.
private struct CapacityBar: View {
    let backups: Int64
    let used: Int64
    let total: Int64

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Clamped against each other: the store walk and the volume's own
            // accounting are taken moments apart and need not agree, and a
            // segment wider than the bar draws outside it.
            let ours = min(max(backups, 0), used)
            HStack(spacing: 0) {
                Rectangle().fill(Color.accentColor)
                    .frame(width: width * fraction(ours))
                Rectangle().fill(Color.secondary.opacity(0.55))
                    .frame(width: width * fraction(used - ours))
                Rectangle().fill(Color.secondary.opacity(0.18))
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func fraction(_ bytes: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(bytes) / Double(total), 0), 1)
    }
}

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
