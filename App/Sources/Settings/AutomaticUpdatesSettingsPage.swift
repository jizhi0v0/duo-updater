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
                "Automatically update closed apps",
                detail: "Installs eligible updates after each scheduled check. With backups on, each app is backed up first, and its update waits if that fails. App data is not backed up.",
                info: "Runs only after scheduled checks, on a network that is not restricted. An app is skipped while it or one of its helpers is running, and updates that need an installer or an authorization prompt are left for you. After a failed update, nothing is tried for that app for a day, and after three failures not until a newer version. Each attempt, and why one was deferred, is listed in the Network window under Events.",
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
                    detail: "Quits an allowed app only when it and the Mac have both been idle, installs the update, and reopens it. Choose the apps below.",
                    info: "An app is quit only if: you allowed it; it has been out of date for the wait chosen below, counted again from its last quit for an update; it has not been in front for an hour; the Mac has had no input for 15 minutes or is locked; it is not keeping the Mac awake (calls, playback, recording, downloads); it has no shell or other program running; and none of its helpers keeps running once it quits. It is quit only after its update has downloaded and been verified, if all of this still holds, and is reopened in the background. When the wait is over, the newest version is installed, even if it came out moments ago. It is asked to quit normally; if it does not quit, it is not asked again for that version. These conditions are checked at each scheduled check, so the wait can run longer.",
                    channel: .beta,
                    isOn: $prefs.automaticUpdatesRunningApps)
                if prefs.automaticUpdatesRunningApps {
                    SettingsDivider()
                    Picker("Wait before quitting a running app", selection: $prefs.runningAppUpdateDelayMinutes) {
                        ForEach(RunningAppAutoUpdate.delayChoices, id: \.self) { minutes in
                            Text(Self.delayLabel(minutes)).tag(minutes)
                        }
                    }
                    .settingsRow()
                }
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

    /// Spelled out per choice so each is its own catalog key.
    private static func delayLabel(_ minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 15: "15 minutes"
        case 30: "30 minutes"
        default: "1 hour"
        }
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
            .map { (result: $0, customized: prefs.automaticUpdateMode($0.app) != .whenClosed) }
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
                Button("Choose with Suggestions…") { showingSetup = true }
                    // The guide picks apps to quit while running; it has no
                    // job while that switch is off.
                    .disabled(!prefs.automaticUpdatesRunningApps)
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
            Picker("Automatic updates for \(result.app.name)", selection: Binding(
                get: { prefs.automaticUpdateMode(result.app) },
                set: { prefs.setAutomaticUpdateMode($0, result.app) })) {
                Text("When Closed").tag(Preferences.AutomaticUpdateMode.whenClosed)
                Text("Also While Running").tag(Preferences.AutomaticUpdateMode.alsoWhenRunning)
                    // Means nothing while running apps are not updated; a choice
                    // already made stays, shown as paused (`caption`).
                    .selectionDisabled(!prefs.automaticUpdatesRunningApps)
                Text("Never").tag(Preferences.AutomaticUpdateMode.never)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            // Nothing to choose for an app automatic updates never install.
            .disabled(model.installsAutomatically(result) == false)
        }
    }

    /// Where the copy lives, or — when its updates come by a route automatic
    /// updates never take — that, so a choice here is not mistaken for a promise.
    private var caption: String {
        guard model.installsAutomatically(result) == false else {
            if !prefs.automaticUpdatesRunningApps, prefs.automaticUpdateMode(result.app) == .alsoWhenRunning {
                return String(localized: "Paused while “Also update running apps” is off; updated when closed")
            }
            return IgnoredSettingsPage.displayPath(result.app.path.path)
        }
        if result.app.bundleID == AppScanner.xcodeBundleID {
            return String(localized: "Xcode is not updated automatically")
        }
        // Setapp installs its own apps, all at once, when DuoUpdater starts it
        // in the background (Updates settings); a choice here cannot hold one back.
        if result.remote?.sourceName == "Setapp" {
            return setappBackgroundUpdateEnabled()
                ? String(localized: "Updated by Setapp in the background, not here")
                : String(localized: "Updated through Setapp, so not automatically")
        }
        switch model.automaticUpdateRoute(result) {
        case .homebrew?:
            return String(localized: "Updated through Homebrew, so not automatically")
        case .appStore?:
            return String(localized: "Updated through the App Store, so not automatically")
        case .installer?:
            return String(localized: "Needs an installer, so not automatically")
        default:
            return String(localized: "Its update needs you, so not automatically")
        }
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
            choice("When Closed", .whenClosed, current: mode)
            choice("Also While Running", .alsoWhenRunning, current: mode)
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
    @State private var filter = ""
    @State private var loaded = false
    @State private var showUnsupported = false
    @State private var selection: Set<String> = []
    /// Where a ⇧-click range starts: the last plain or ⌘-click.
    @State private var anchor: String?
    /// The apps being dragged, the tile under the pointer, and where it is.
    @State private var dragging: Set<String> = []
    @State private var grabbed: Candidate?
    @State private var dragLocation: CGPoint?
    @State private var columnFrames: [Mode: CGRect] = [:]

    private static let columns: [Mode] = [.alsoWhenRunning, .whenClosed, .never]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose apps that may be quit for an update")
                .font(.title3.weight(.semibold))
            Text("Apps in the first column are quit only while they and the Mac are idle, then updated and reopened. They still ask before discarding unsaved work. Drag an app to another column, or right-click it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Filter apps", text: $filter)
                .textFieldStyle(.roundedBorder)
            if loaded {
                board
                if !unsupported.isEmpty { unsupportedStrip }
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
        .frame(width: 820, height: 640)
        .task { await load() }
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Self.columns, id: \.self) { mode in column(mode) }
        }
        .frame(maxHeight: .infinity)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(ColumnFrames.self) { columnFrames = $0 }
        .overlay(alignment: .topLeading) { floatingTile }
    }

    private static let space = "automatic-update-board"

    private func column(_ mode: Mode) -> some View {
        let items = items(in: mode)
        let targeted = dragLocation.map { columnFrames[mode]?.contains($0) == true } ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(mode)).font(.headline)
                Spacer()
                Text(verbatim: "\(count(in: mode))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                    Text("Drag apps here")
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
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .opacity(dragging.contains(item.id) ? 0.3 : 1)
        .contentShape(Rectangle())
        .help(Self.reason(item.suggestion))
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
            for id in ids { placement[id] = target }
        }
    }

    private var unsupportedStrip: some View {
        DisclosureGroup(isExpanded: $showUnsupported) {
            Text(unsupported.map(\.app.name).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("Not updated automatically (\(unsupported.count))")
                Text("These update through Homebrew, the App Store, an installer or a prompt, which automatic updates never use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func title(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .alsoWhenRunning: "Also While Running"
        case .whenClosed: "When Closed"
        case .never: "Never"
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

    static func reason(_ suggestion: AutomaticUpdateSuggestion) -> String {
        switch suggestion {
        case .suggested(.menuBarApp), .notSuggested(.menuBarApp):
            return String(localized: "Menu bar app")
        case .suggested(.declaresSafeTermination), .notSuggested(.declaresSafeTermination):
            return String(localized: "Tells macOS it can be quit safely")
        case .suggested(.networkExtension), .notSuggested(.networkExtension):
            return String(localized: "Runs a VPN, proxy or network filter")
        case .suggested(.fileSync), .notSuggested(.fileSync):
            return String(localized: "Syncs files")
        case .suggested(.systemExtension), .notSuggested(.systemExtension):
            return String(localized: "Installs a system extension")
        case .suggested(.inputMethod), .notSuggested(.inputMethod):
            return String(localized: "Input method: quitting it interrupts typing")
        case .suggested(.windowedApp), .notSuggested(.windowedApp):
            return String(localized: "Has windows that may hold your work")
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
        let supported = results.filter { model.installsAutomatically($0) != false }
        unsupported = results.filter { model.installsAutomatically($0) == false }
        let paths = supported.map(\.app.path)
        let suggestions = await Task.detached { paths.map { AutomaticUpdateSuggestion.classify(bundle: $0) } }.value
        candidates = zip(supported, suggestions).map { Candidate(result: $0, suggestion: $1) }
        // An explicit choice stays where it is; an app on the default starts in
        // the first column only when it is a suggestion.
        for item in candidates {
            let mode = prefs.automaticUpdateMode(item.result.app)
            placement[item.id] = mode == .whenClosed && item.suggestion.isSuggested ? .alsoWhenRunning : mode
        }
        loaded = true
    }

    private func apply() {
        for item in candidates {
            if let mode = placement[item.id], mode != prefs.automaticUpdateMode(item.result.app) {
                prefs.setAutomaticUpdateMode(mode, item.result.app)
            }
        }
        if placement.values.contains(.alsoWhenRunning) { prefs.automaticUpdatesRunningApps = true }
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
