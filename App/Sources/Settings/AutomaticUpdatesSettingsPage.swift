import SwiftUI
import DuoUpdaterCore

/// What automatic updates do, and the choice for each app. A Beta feature in
/// every build (its switches carry the Beta tag); off until the user turns it on.
///
/// Every installed app is listed with its own choice, rather than only the ones
/// already changed: a switch that names "apps you allow" has to show where they
/// are allowed.
struct AutomaticUpdatesSettingsPage: View {
    @Bindable var prefs: Preferences
    let model: AppListModel

    @State private var showingSetup = false

    var body: some View {
        SettingsPage(section: .automaticUpdates) {
            switchesCard
            // Every choice below is about automatic updates, so with them off
            // there is nothing to choose.
            AutomaticUpdateAppsCard(prefs: prefs, model: model, showingSetup: $showingSetup)
                .disabled(!prefs.automaticUpdates)
                .opacity(prefs.automaticUpdates ? 1 : 0.5)
        }
        .onAppear { AppIconCache.prefetch(model.results.map(\.app.path.path)) }
        // The guide opens by itself the first time the switch goes on with no app
        // allowed: otherwise the switch does nothing and says nothing.
        .onChange(of: prefs.automaticUpdatesRunningApps) { _, on in
            if on && prefs.automaticRelaunchKeys.isEmpty { showingSetup = true }
        }
        .sheet(isPresented: $showingSetup) {
            AutomaticUpdateSetupSheet(prefs: prefs, model: model)
        }
    }

    /// The card that decides WHETHER an update is installed unattended. It runs
    /// on the schedule in General, and the footer says so when that schedule is
    /// Manual — the one setting that silently turns it off.
    private var switchesCard: some View {
        SettingsCard {
            SettingsToggle(
                "Automatically update apps",
                detail: "Installs eligible updates after each scheduled check. With backups on, each app is backed up first, and its update waits if that fails. App data is not backed up.",
                info: "Runs only after scheduled checks, on a network that is not restricted. By default, an app is skipped while its main app is running; apps you allow below may be quit and reopened, and updates that need an installer or an authorization prompt are left for you. After a failed update, nothing is tried for that app for a day, and after three failures not until a newer version. Each attempt, and why one was deferred, is listed in the Network window under Events.",
                channel: .beta,
                isOn: $prefs.automaticUpdates)
                .settingsAnchor(.automaticUpdates)
            // Backups are opt-in, and with them off an unattended update leaves
            // no way back (vendor and Sparkle take no install rollback point).
            if prefs.automaticUpdates && !prefs.keepBackups {
                SettingsDivider()
                noBackupsWarning
            }
            if prefs.automaticUpdates {
                SettingsDivider()
                SettingsToggle(
                    "Also update running apps you allow",
                    detail: "Keeps allowed apps up to date, even while you use them. Downloads and verifies each update before quitting and reopening the app.",
                    info: "Apps you allow may restart while in front, playing media or doing work. There is no idle-time or update delay. If normal quit is refused, that version waits. Installer prompts and safety checks can still defer an update.",
                    channel: .beta,
                    isOn: $prefs.automaticUpdatesRunningApps)
            }
        } footer: {
            if prefs.automaticUpdates && prefs.checkFrequency.interval == nil {
                Label(
                    "Scheduled checks are off, so nothing is updated automatically. Choose how often to check for updates in General.",
                    systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noBackupsWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(
                "Backups are off, so an automatic update can’t be undone. Turn them on to keep the previous version of each app.",
                systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Turn On Backups") { prefs.keepBackups = true }
        }
        .settingsRow()
    }

}

/// Keep list observation separate from the switches above it: changing the
/// backup preference must not rebuild every app's picker.
private struct AutomaticUpdateAppsCard: View {
    let prefs: Preferences
    let model: AppListModel
    @Binding var showingSetup: Bool
    @State private var filter = ""

    /// One row per installed copy, the ones with a choice of their own first.
    private var rows: [UpdateResult] {
        var seen = Set<String>()
        return model.results
            .filter { seen.insert(prefs.key(for: $0.app)).inserted }
            .filter { filter.isEmpty || SearchMatch.matches(filter, in: [$0.app.name, $0.app.path.path]) }
            .map { (result: $0, customized: prefs.explicitAutomaticUpdateMode($0.app) != nil) }
            .sorted { lhs, rhs in
                if lhs.customized != rhs.customized { return lhs.customized }
                return lhs.result.app.name.localizedStandardCompare(rhs.result.app.name) == .orderedAscending
            }
            .map(\.result)
    }

    var body: some View {
        SettingsCard(header: "Apps") {
            HStack {
                TextField("Filter apps", text: $filter)
                    .textFieldStyle(.roundedBorder)
                // Choices can be prepared while running-app updates are paused.
                Button("Choose with Suggestions…") { showingSetup = true }
            }
            .settingsRow()
            let rows = rows
            if rows.isEmpty {
                Text(model.results.isEmpty ? "No apps found yet." : "No apps match.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .settingsRow()
            }
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.id) { result in
                    VStack(spacing: 0) {
                        SettingsDivider()
                        AutomaticUpdateAppRow(prefs: prefs, model: model, result: result)
                            .settingsRow()
                    }
                }
            }
        }
    }
}

private struct AutomaticUpdateAppRow: View {
    let prefs: Preferences
    let model: AppListModel
    let result: UpdateResult

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.app.name)
                let text = caption
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // A path stays on one line; a reason may wrap, since in
                    // German or French it does not fit beside the menu.
                    .lineLimit(text == IgnoredSettingsPage.displayPath(result.app.path.path) ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(Text(verbatim: result.app.path.path))
            }
            Spacer(minLength: 12)
            if model.canConfigureAutomaticUpdates(result) {
            AutomaticUpdateExplanationButton(prefs: prefs, app: result.app,
                mode: prefs.automaticUpdateMode(result.app),
                source: prefs.explicitAutomaticUpdateMode(result.app) == nil ? .defaultChoice : .userChoice,
                updateHold: model.automaticUpdateSetupHold(result))
            } else {
                ManualAutomaticUpdateExplanationButton(result: result,
                    reason: model.manualAutomaticUpdateReason(result))
            }
            Picker("Automatic updates for \(result.app.name)", selection: Binding(
                get: { prefs.automaticUpdateMode(result.app) },
                set: { prefs.setAutomaticUpdateMode($0, result.app) })) {
                Text("Only When Not Running").tag(Preferences.AutomaticUpdateMode.whenClosed)
                Text("Keep Up to Date").tag(Preferences.AutomaticUpdateMode.alsoWhenRunning)
                    // Means nothing while running apps are not updated; a choice
                    // already made stays, shown as paused (`caption`).
                    .selectionDisabled(!prefs.automaticUpdatesRunningApps)
                Text("Never").tag(Preferences.AutomaticUpdateMode.never)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            // Nothing to choose for an app automatic updates never install.
            .disabled(!model.canConfigureAutomaticUpdates(result))
        }
    }

    /// Where the copy lives, or — when its updates come by a route automatic
    /// updates never take — that, so a choice here is not mistaken for a promise.
    private var caption: String {
        if let hold = model.automaticUpdateSetupHold(result) { return hold }
        guard model.installsAutomatically(result) == false else {
            if !prefs.automaticUpdatesRunningApps, prefs.automaticUpdateMode(result.app) == .alsoWhenRunning {
                return String(localized: "Paused while “Also update running apps” is off; updated only when not running")
            }
            return IgnoredSettingsPage.displayPath(result.app.path.path)
        }
        return model.manualAutomaticUpdateReason(result)
    }
}

/// The row-menu choice of how automatic updates treat one app — the same
/// choice the Automatic Updates page lists for every app.
struct AutomaticUpdateModeMenu: View {
    let prefs: Preferences
    let app: InstalledApp

    var body: some View {
        let mode = prefs.automaticUpdateMode(app)
        Menu("Automatic Updates") {
            choice("Only When Not Running", .whenClosed, current: mode)
            choice("Keep Up to Date", .alsoWhenRunning, current: mode)
            choice("Never", .never, current: mode)
        }
    }

    private func choice(_ title: LocalizedStringKey, _ value: Preferences.AutomaticUpdateMode,
                        current: Preferences.AutomaticUpdateMode) -> some View {
        Toggle(title, isOn: Binding(
            get: { current == value },
            set: { if $0 { prefs.setAutomaticUpdateMode(value, app) } }))
    }
}

/// The guide for a library of hundreds of apps: a board with one column per
/// choice, so the whole library's split is visible at once. Apps start where
/// `AutomaticUpdateSuggestion` and their current choice put them, and nothing
/// changes until Apply.
///
/// Dragging is the board's own gesture, not a system drag session: a session
/// ends with the system's drop animation and an asynchronous hand-over of the
/// payload, so the tile lingered after the release. Here the tile follows the
/// pointer and lands on release. Click selects, ⌘-click adds; dragging or moving
/// a selected app takes the whole selection with it.
struct AutomaticUpdateSetupSheet: View {
    typealias Mode = Preferences.AutomaticUpdateMode
    let prefs: Preferences
    let model: AppListModel
    @Environment(\.dismiss) private var dismiss

    struct Candidate: Identifiable {
        let result: UpdateResult
        let suggestion: AutomaticUpdateSuggestion
        var id: String { result.id }
    }

    @State private var candidates: [Candidate] = []
    @State private var unsupported: [UpdateResult] = []
    @State private var placement: [String: Mode] = [:]
    @State private var edited: Set<String> = []
    @State private var filter = ""
    @State private var loaded = false
    @State private var selection: Set<String> = []
    /// Where a ⇧-click range starts: the last plain or ⌘-click.
    @State private var anchor: String?
    /// The apps being dragged, the tile under the pointer, and where it is.
    @State private var dragging: Set<String> = []
    @State private var grabbed: Candidate?
    @State private var dragLocation: CGPoint?
    @State private var columnFrames: [Mode: CGRect] = [:]
    @State private var columnHeaderHeight: CGFloat = 0

    private static let columns: [Mode] = [.alsoWhenRunning, .whenClosed, .never]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose apps that may be quit for an update")
                .font(.title3.weight(.semibold))
            Text("Drag apps between columns, or right-click to move them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Filter apps", text: $filter)
                .textFieldStyle(.roundedBorder)
            if loaded {
                board
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!loaded)
            }
        }
        .padding(20)
        .frame(width: 1080, height: 640)
        .task { await load() }
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Self.columns, id: \.self) { mode in column(mode) }
            unsupportedColumn
        }
        .frame(maxHeight: .infinity)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(ColumnFrames.self) { columnFrames = $0 }
        .onPreferenceChange(ColumnHeaderHeights.self) { columnHeaderHeight = $0.values.max() ?? 0 }
        .overlay(alignment: .topLeading) { floatingTile }
    }

    private static let space = "automatic-update-board"

    private func column(_ mode: Mode) -> some View {
        let items = items(in: mode)
        let targeted = dragLocation.map { columnFrames[mode]?.contains($0) == true } ?? false
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.title(mode)).font(.headline)
                    Spacer()
                    Text(verbatim: "\(count(in: mode))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(Self.explanation(mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ColumnHeaderHeights.self, value: [mode.rawValue: proxy.size.height])
            })
            .frame(minHeight: columnHeaderHeight, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in tile(item, in: mode) }
                }
                .padding(6)
            }
            .overlay {
                if items.isEmpty {
                    Text(filter.isEmpty ? "Drag apps here" : "No matching apps")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(targeted ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0))
        .contentShape(Rectangle())
        // A click on the column's empty space clears the selection, as in Finder.
        .onTapGesture { selection.removeAll() }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ColumnFrames.self,
                                   value: [mode: proxy.frame(in: .named(Self.space))])
        })
    }

    private func tile(_ item: Candidate, in mode: Mode) -> some View {
        let selected = selection.contains(item.id)
        return HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: item.result.app.path.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(item.result.app.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer(minLength: 0)
            AutomaticUpdateExplanationButton(prefs: prefs, app: item.result.app, mode: mode,
                source: edited.contains(item.id) ? .pendingChoice
                    : prefs.explicitAutomaticUpdateMode(item.result.app) != nil ? .userChoice
                    : item.suggestion.isSuggested ? .suggestion : .defaultChoice,
                prepared: item.suggestion,
                updateHold: model.automaticUpdateSetupHold(item.result))
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .opacity(dragging.contains(item.id) ? 0.3 : 1)
        .contentShape(Rectangle())
        .help("Why this category?")
        // Modifier taps first: a plain tap also fires with a modifier held.
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded { toggle(item.id) })
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { extend(to: item.id, in: mode) })
        .onTapGesture { selection = [item.id]; anchor = item.id }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragging.isEmpty {
                    if !selection.contains(item.id) { selection = [item.id] }
                    dragging = selection
                    grabbed = item
                }
                dragLocation = value.location
            }
            .onEnded { value in
                if let target = columnFrames.first(where: { $0.value.contains(value.location) })?.key {
                    move(dragging, to: target)
                }
                dragging = []
                grabbed = nil
                dragLocation = nil
            })
        .contextMenu {
            let ids = selection.contains(item.id) ? selection : [item.id]
            ForEach(Self.columns.filter { $0 != mode }, id: \.self) { target in
                Button {
                    move(ids, to: target)
                } label: {
                    Text("Move to \(Text(Self.title(target)))")
                }
            }
        }
    }

    /// The tile under the pointer while dragging, with a count when it carries more.
    @ViewBuilder
    private var floatingTile: some View {
        if let grabbed, let point = dragLocation {
            HStack(spacing: 8) {
                Image(nsImage: AppIconCache.icon(for: grabbed.result.app.path.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(grabbed.result.app.name).lineLimit(1)
                if dragging.count > 1 {
                    Text(verbatim: "\(dragging.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 6, y: 2)
            .fixedSize()
            .position(x: point.x + 40, y: point.y)
            .allowsHitTesting(false)
        }
    }

    private func toggle(_ id: String) {
        if selection.remove(id) == nil { selection.insert(id) }
        anchor = id
    }

    /// Select from the anchor to `id` within one column, as a list does. An
    /// anchor in another column starts the range afresh at `id`.
    private func extend(to id: String, in mode: Mode) {
        let ids = items(in: mode).map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        guard let anchor, let start = ids.firstIndex(of: anchor) else {
            selection = [id]; self.anchor = id; return
        }
        selection.formUnion(ids[min(start, end)...max(start, end)])
    }

    private func move(_ ids: Set<String>, to target: Mode) {
        withAnimation(.snappy(duration: 0.2)) {
            for id in ids { placement[id] = target; edited.insert(id) }
        }
    }

    private var unsupportedColumn: some View {
        let items = unsupported.filter { filter.isEmpty || SearchMatch.matches(filter, in: [$0.app.name]) }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Manual Updates").font(.headline)
                    Spacer()
                    Text(verbatim: "\(unsupported.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Requires a manual update action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ColumnHeaderHeights.self, value: ["manual": proxy.size.height])
            })
            .frame(minHeight: columnHeaderHeight, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { result in
                        HStack(spacing: 8) {
                            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                                .resizable().frame(width: 18, height: 18)
                            Text(result.app.name).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                            ManualAutomaticUpdateExplanationButton(result: result,
                                reason: model.manualAutomaticUpdateReason(result))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .help("Why this category?")
                    }
                }
                .padding(6)
            }
            .overlay {
                if items.isEmpty {
                    Text("No matching apps")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    static func title(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .alsoWhenRunning: "Keep Up to Date"
        case .whenClosed: "Only When Not Running"
        case .never: "Never"
        }
    }

    private static func explanation(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .alsoWhenRunning: "May quit and reopen apps to install updates."
        case .whenClosed: "Waits until the app has quit."
        case .never: "Updates only when you choose."
        }
    }

    private func count(in mode: Mode) -> Int {
        candidates.filter { placement[$0.id] == mode }.count
    }

    private func items(in mode: Mode) -> [Candidate] {
        candidates.filter {
            placement[$0.id] == mode
                && (filter.isEmpty || SearchMatch.matches(filter, in: [$0.result.app.name]))
        }
    }

    /// Sort the library once, reading each bundle off the main actor. One tile
    /// per installed copy; DuoUpdater itself and ignored apps are left out.
    private func load() async {
        var seen = Set<String>()
        let results = model.results.filter {
            seen.insert(prefs.key(for: $0.app)).inserted
                && $0.app.bundleID != Bundle.main.bundleIdentifier
                && !prefs.isIgnored($0.app)
        }.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        let supported = results.filter {
            model.canConfigureAutomaticUpdates($0)
        }
        let supportedIDs = Set(supported.map(\.id))
        unsupported = results.filter { !supportedIDs.contains($0.id) }
        let inputs = supported.map { (path: $0.app.path, observation: prefs.automaticUpdateObservation($0.app)) }
        let suggestions = await Task.detached {
            inputs.map { AutomaticUpdateSuggestion.classify(bundle: $0.path, observation: $0.observation) }
        }.value
        candidates = zip(supported, suggestions).map { Candidate(result: $0, suggestion: $1) }
        // A saved choice (including whenClosed) stays put. Only an unset copy
        // may start in the running-updates column from matching evidence.
        for item in candidates {
            placement[item.id] = prefs.suggestedAutomaticUpdateMode(item.result.app, suggested: item.suggestion.isSuggested)
        }
        loaded = true
    }

    private func apply() {
        for item in candidates {
            if let mode = placement[item.id] {
                prefs.setAutomaticUpdateMode(mode, item.result.app)
            }
        }
        // Applying confirms every displayed placement, even an unchanged default.
        // Only the explicit switch enables quitting running apps. Saving this
        // board must preserve the user's paused state.
    }
}

/// Align lists to the tallest translated header without reserving empty lines.
private struct ColumnHeaderHeights: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat],
                       nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Each column's frame in the board's coordinate space, for the drop target.
private struct ColumnFrames: PreferenceKey {
    static let defaultValue: [Preferences.AutomaticUpdateMode: CGRect] = [:]
    static func reduce(value: inout [Preferences.AutomaticUpdateMode: CGRect],
                       nextValue: () -> [Preferences.AutomaticUpdateMode: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct AutomaticUpdateExplanationButton: View {
    let prefs: Preferences
    let app: InstalledApp
    let mode: Preferences.AutomaticUpdateMode
    let source: AutomaticUpdateCategorySource
    var prepared: AutomaticUpdateSuggestion? = nil
    var updateHold: String? = nil
    @State private var showing = false
    @State private var showingDetails = false
    @State private var loaded: AutomaticUpdateSuggestion?

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Why this category?")
        .help("Why this category?")
        .popover(isPresented: $showing) {
            AutomaticUpdateExplanationView(
                appName: app.name,
                icon: AppIconCache.icon(for: app.path.path),
                mode: mode,
                source: source,
                suggestion: prepared ?? loaded,
                expanded: $showingDetails, updateHold: updateHold)
            .task {
                guard prepared == nil else { return }
                let path = app.path
                let observation = prefs.automaticUpdateObservation(app)
                loaded = await Task.detached {
                    AutomaticUpdateSuggestion.classify(bundle: path, observation: observation)
                }.value
            }
        }
    }

}
