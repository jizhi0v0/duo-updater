import SwiftUI
import AppKit
import DuoUpdaterCore

/// The Settings window — a macOS 26 sidebar layout: grouped, searchable source
/// list on the left; the selected page, built from Liquid Glass cards, on the
/// right.
///
/// It's a plain `Window` rather than the `Settings` scene (that scene injects
/// centered-title chrome that collides with a split view), and the sidebar is
/// pinned: with seven fixed pages there's nothing to gain from collapsing it, and
/// the collapse animation is janky.
///
/// Binds straight to the shared `Preferences` (an `@Observable`, so `@Bindable`
/// gives bindings) and reads live state off the model.
struct SettingsView: View {
    static let windowID = "settings"

    /// Deep-link and model compatibility: `AppListModel.requestedSettingsSection`
    /// and older call sites spell this `SettingsView.Section`.
    typealias Section = SettingsSection

    @Bindable var prefs: Preferences
    let model: AppListModel

    @State private var selection: SettingsSection = .general
    @State private var query = ""
    /// The card a deep link asked for, consumed from the model here and handed to
    /// the pages through the environment. Consumed HERE and not by the page that
    /// acts on it: a page keying its work on a value it then clears cancels itself
    /// (see `SettingsPage`), and the request has to outlive the page swap anyway.
    @State private var reveal: SettingsReveal?
    /// Advances per request, so two clicks on the same link both land instead of
    /// the second comparing equal and never re-firing.
    @State private var revealToken = 0

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, query: $query, prefs: prefs, model: model,
                            reveal: { show($0) })
                .navigationSplitViewColumnWidth(212)
        } detail: {
            detail
                .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 660, minHeight: 440)
        // A real macOS window, so route the lifecycle through the model to keep
        // focus and trust-polling consistent with the other top-level windows.
        .onAppear {
            model.windowAppeared(); model.beginTrustPolling()
            applyRequestedSection(); applyRequestedAnchor()
        }
        // Ready the Backups card while General is on screen, so its first visit
        // doesn't assemble itself (see `BackupsSettingsPage.prepareFirstVisit`).
        .task { await BackupsSettingsPage.prepareFirstVisit(model: model, prefs: prefs) }
        // Deep-link set before the window opened (onAppear) or while it's already
        // open (onChange) — e.g. onboarding asking for the GitHub page.
        .onChange(of: model.requestedSettingsSection) { applyRequestedSection() }
        .onChange(of: model.requestedSettingsAnchor) { applyRequestedAnchor() }
        // A request is spent the moment the reader navigates off the page that owns
        // it. Without this it stands for the life of the window, and `SettingsPage`
        // starts its reveal whenever a page APPEARS — so leaving General and coming
        // back would scroll and flash again for a link followed minutes ago. The
        // page-select this function performs itself does not trip it: the new
        // selection IS the anchor's section. Cleared on close too, in case the scene
        // keeps its state across a reopen.
        .onChange(of: selection) { _, now in
            if let reveal, reveal.anchor.section != now { self.reveal = nil }
        }
        .onDisappear { model.endTrustPolling(); model.windowDisappeared(); reveal = nil }
    }

    private var detail: some View {
        page(for: selection)
            .environment(\.settingsReveal, reveal)
            .background(SettingsBackdrop(section: selection))
            // Cross-fade pages rather than letting the glass cards pop: the
            // backdrop tint animates underneath at the same time.
            .animation(.smooth(duration: 0.28), value: selection)
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general:     GeneralSettingsPage(prefs: prefs, model: model)
        case .notifications: NotificationsSettingsPage(prefs: prefs)
        case .backups:     BackupsSettingsPage(prefs: prefs, model: model)
        case .storage:     StorageSettingsPage(model: model)
        case .folders:     FoldersSettingsPage(prefs: prefs, model: model)
        case .updates:     UpdatesSettingsPage()
        case .github:      GitHubSettingsPage(prefs: prefs, model: model)
        case .alcove:      AlcoveSettingsPage(prefs: prefs)
        case .xcode:       XcodeSettingsPage(prefs: prefs)
        case .ignored:     IgnoredSettingsPage(prefs: prefs, model: model)
        case .diagnostics: DiagnosticsSettingsPage(model: model)
        }
    }

    /// Honor a pending deep-link, then clear it so the selection isn't forced
    /// again on the next open. Clears the search too — a filtered sidebar that
    /// hides the page we just jumped to would be confusing.
    private func applyRequestedSection() {
        guard let requested = model.requestedSettingsSection else { return }
        query = ""
        selection = requested
        model.requestedSettingsSection = nil
    }

    /// The same for a card within that page (`SettingsAnchor`). Selects the page it
    /// lives on as well, so a link that names only the card still lands: the two
    /// requests are set together today, and a caller that forgets one should not
    /// leave the window on whatever page it was last on.
    private func applyRequestedAnchor() {
        guard let anchor = model.requestedSettingsAnchor else { return }
        query = ""
        show(anchor)
        model.requestedSettingsAnchor = nil
    }

    /// Open the page that holds `anchor` and scroll to it. The search keeps its
    /// query here — a reader picking one result often wants the next — where a
    /// deep link from elsewhere clears it first.
    private func show(_ anchor: SettingsAnchor) {
        selection = anchor.section
        revealToken += 1
        reveal = SettingsReveal(anchor: anchor, token: revealToken)
    }
}

// MARK: - Sidebar

/// Grouped source list plus a search field. Search filters pages by label,
/// subtitle, and keywords, so "token" reaches GitHub and "rollback" reaches
/// General; groups that end up empty drop out. Below the pages it lists the
/// settings and the apps a query names (`SettingsSearch`), each leading to its
/// own card or row rather than to the top of its page.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @Binding var query: String
    /// For the "new setting" dots, and for the settings search's own titles
    /// (one carries a live value) and the ignored and skipped apps it lists.
    @Bindable var prefs: Preferences
    /// Names and icons for the apps the search lists.
    let model: AppListModel
    /// Open a search result's page at its card or row.
    let reveal: (SettingsAnchor) -> Void

    /// Diagnostics' recipe list, so an app with a recipe is found by name. Read
    /// when a search starts and after each check — the same snapshot the page
    /// itself shows.
    @State private var recipes: [RecipeHealth.Entry] = []
    /// The search result last picked. Only remembered while it is on the page
    /// being shown; otherwise the list highlights the page row, as before.
    @State private var pickedHit: SettingsAnchor?

    /// One sidebar row: a page, or a result that leads into one.
    private enum Row: Hashable {
        case page(SettingsSection)
        case hit(SettingsAnchor)
    }

    private var isSearching: Bool { !SearchMatch.trimmed(query).isEmpty }

    private var groups: [(group: SettingsSection.Group, sections: [SettingsSection])] {
        SettingsSection.Group.allCases.compactMap { group in
            let matches = SettingsSection.allCases.filter { $0.group == group && $0.matches(query) }
            return matches.isEmpty ? nil : (group, matches)
        }
    }

    private var settingHits: [SettingsSearchHit] {
        SettingsSearch.settings(matching: query, prefs: prefs)
    }

    private var appHits: [SettingsSearchHit] {
        SettingsSearch.apps(matching: query, prefs: prefs, results: model.results, recipes: recipes)
    }

    /// Picking a result opens its page at its card or row; picking a page opens
    /// the page, as it always did.
    private var rowSelection: Binding<Row?> {
        Binding(
            get: {
                if isSearching, let pickedHit, pickedHit.section == selection { return .hit(pickedHit) }
                return .page(selection)
            },
            set: { row in
                switch row {
                case .page(let section)?:
                    pickedHit = nil
                    selection = section
                case .hit(let anchor)?:
                    pickedHit = anchor
                    reveal(anchor)
                case nil:
                    break
                }
            })
    }

    var body: some View {
        // Computed once per pass: each walks the catalog or the scan.
        let groups = groups
        let settingHits = settingHits
        let appHits = appHits
        VStack(spacing: 0) {
            AppSearchField(text: $query, prompt: String(localized: "Search"))
                .frame(height: 24)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if groups.isEmpty && settingHits.isEmpty && appHits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .controlSize(.small)
                Spacer()
            } else {
                List(selection: rowSelection) {
                    ForEach(groups, id: \.group.id) { entry in
                        SwiftUI.Section(entry.group.displayName) {
                            ForEach(entry.sections) { section in
                                row(section).tag(Row.page(section))
                            }
                        }
                    }
                    if !settingHits.isEmpty {
                        SwiftUI.Section(String(localized: "Settings")) {
                            ForEach(settingHits) { hit in
                                hitRow(hit).tag(Row.hit(hit.anchor))
                            }
                        }
                    }
                    if !appHits.isEmpty {
                        SwiftUI.Section(String(localized: "Apps")) {
                            ForEach(appHits) { hit in
                                hitRow(hit).tag(Row.hit(hit.anchor))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .softScrollEdges()
            }
        }
        .task(id: isSearching) {
            if isSearching { recipes = await RecipeHealth.shared.snapshot() }
        }
        .onChange(of: model.lastCheck) {
            guard isSearching else { return }
            Task { recipes = await RecipeHealth.shared.snapshot() }
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(section.label)
                if prefs.hasPendingSpotlight(in: section) { SpotlightDot(size: 5) }
            }
        } icon: {
            SettingsIconTile(section: section)
        }
        .padding(.vertical, 1)
    }

    /// A result: what it is, and under it where it lives — "Ignored → Ignored
    /// apps" — as System Settings lists its own.
    private func hitRow(_ hit: SettingsSearchHit) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .lineLimit(2)
                Text(hit.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            switch hit.icon {
            case .section(let section):
                SettingsIconTile(section: section)
            case .app(let path?):
                Image(nsImage: AppIconCache.icon(for: path))
                    .resizable()
                    .frame(width: 20, height: 20)
            case .app(nil):
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Backdrop

/// A soft wash of the selected page's tint behind the detail pane.
///
/// Liquid Glass refracts what's behind it, so over a flat window background the
/// cards all but vanish (the same reason `WelcomeView` gives its primary button
/// explicit glass rather than the `.glass` button style). This gives the glass
/// something to pick up — and it doubles as a quiet cue that the sidebar tint and
/// the page belong together. Kept at a low opacity: a tint, not a color field.
private struct SettingsBackdrop: View {
    let section: SettingsSection

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(
                colors: [section.tint.opacity(0.16), section.tint.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520)
            RadialGradient(
                colors: [section.tint.opacity(0.10), section.tint.opacity(0)],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
