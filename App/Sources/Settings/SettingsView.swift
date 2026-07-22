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

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, query: $query)
                .navigationSplitViewColumnWidth(212)
        } detail: {
            detail
                .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 660, minHeight: 440)
        // A real macOS window, so route the lifecycle through the model to keep
        // focus and trust-polling consistent with the other top-level windows.
        .onAppear { model.windowAppeared(); model.beginTrustPolling(); applyRequestedSection() }
        // Deep-link set before the window opened (onAppear) or while it's already
        // open (onChange) — e.g. onboarding asking for the GitHub page.
        .onChange(of: model.requestedSettingsSection) { applyRequestedSection() }
        .onDisappear { model.endTrustPolling(); model.windowDisappeared() }
    }

    private var detail: some View {
        page(for: selection)
            .background(SettingsBackdrop(section: selection))
            // Cross-fade pages rather than letting the glass cards pop: the
            // backdrop tint animates underneath at the same time.
            .animation(.smooth(duration: 0.28), value: selection)
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general:     GeneralSettingsPage(prefs: prefs, model: model)
        case .folders:     FoldersSettingsPage(prefs: prefs, model: model)
        case .updates:     UpdatesSettingsPage()
        case .github:      GitHubSettingsPage(prefs: prefs)
        case .alcove:      AlcoveSettingsPage(prefs: prefs)
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
}

// MARK: - Sidebar

/// Grouped source list plus a search field. Search filters pages by label,
/// subtitle, and keywords, so "token" reaches GitHub and "rollback" reaches
/// General; groups that end up empty drop out.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @Binding var query: String

    private var groups: [(group: SettingsSection.Group, sections: [SettingsSection])] {
        SettingsSection.Group.allCases.compactMap { group in
            let matches = SettingsSection.allCases.filter { $0.group == group && $0.matches(query) }
            return matches.isEmpty ? nil : (group, matches)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSearchField(text: $query, prompt: "Search")
                .frame(height: 24)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .controlSize(.small)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(groups, id: \.group.id) { entry in
                        SwiftUI.Section(entry.group.rawValue) {
                            ForEach(entry.sections) { section in
                                row(section).tag(section)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .softScrollEdges()
            }
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        Label {
            Text(section.label)
        } icon: {
            SettingsIconTile(section: section)
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
