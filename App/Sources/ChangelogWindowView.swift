import SwiftUI
import AppKit
import WebKit
import DuoUpdaterCore

/// The "工作台" window — a roomier home than the menu-bar popover for content the
/// popover can't hold. First tenant: per-app changelogs. The popover stays the
/// quick-glance remote; this is where you sit and read.
///
/// Master–detail: left column lists apps (updates first), right pane shows the
/// selected app's release notes. Notes come from one of two places, in order:
///   1. `releaseNotesHTML` — inline text we already parsed (Sparkle, GitHub).
///   2. `changelogURL` — the vendor's own page, embedded in a web view.
/// When neither exists we say so plainly and offer the download page.
struct ChangelogWindowView: View {
    static let windowID = "changelog"

    @Bindable var model: AppListModel
    @State private var selection: String?
    @Environment(\.scenePhase) private var scenePhase

    /// While the window stays open, re-read on-disk versions every 15s so an app
    /// that self-updates in the background surfaces even if you never close/refocus
    /// the window. `refreshLocal()` is network-free and `!isChecking`-guarded, so
    /// each tick is cheap (just re-reads each app's Info.plist).
    private let refreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    /// Apps with an update float to the top; everything else stays visible so the
    /// window doubles as a full inventory, not just a pending-updates list.
    private var apps: [UpdateResult] {
        model.results.sorted { lhs, rhs in
            if lhs.hasUpdate != rhs.hasUpdate { return lhs.hasUpdate }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }

    private var selected: UpdateResult? {
        apps.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(apps, selection: $selection) { result in
                ChangelogSidebarRow(result: result).tag(result.id)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            if let selected {
                ChangelogDetail(result: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView(
                    "Select an app",
                    systemImage: "sidebar.left",
                    description: Text("Pick an app to read its changelog.")
                )
            }
        }
        .navigationTitle("Changelog")
        .task {
            // First open with no data: full (networked) check. Otherwise a cheap,
            // network-free rescan that re-reads each app's on-disk version — so an
            // app that self-updated in the background (its own Sparkle/Squirrel/
            // Keystone updater) shows its new version here, not the stale one the
            // popover cached. Mirrors MenuContentView's refreshLocal() on open.
            if model.results.isEmpty { await model.refresh() }
            else { await model.refreshLocal() }
            if selection == nil { selection = apps.first?.id }
        }
        // Refocus the window (⌘-Tab back, click in) → re-read on-disk versions.
        // App-scoped notification, so only our own windows trigger it; refreshLocal
        // is cheap and idempotent, so an extra fire costs nothing.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refreshLocal() }
        }
        // Stationary stay (never lose focus) → the 15s timer keeps versions fresh.
        // Skip ticks while the window is hidden/minimized (scenePhase .background):
        // refreshing on-disk versions for a window no one is looking at is wasted
        // work and battery.
        .onReceive(refreshTimer) { _ in
            guard scenePhase != .background else { return }
            Task { await model.refreshLocal() }
        }
        // This is a menu-bar (LSUIElement/.accessory) app, so its windows have no
        // Dock icon and don't behave like real top-level windows. Promote the app
        // to .regular while the changelog window is open — Dock icon, app menu,
        // ⌘-Tab — then drop back to .accessory when it closes.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct ChangelogSidebarRow: View {
    let result: UpdateResult

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.app.name).font(.body).lineLimit(1)
                if case .updateAvailable(let latest) = result.status {
                    Text("\(result.app.shortVersion ?? "?") → \(latest)")
                        .font(.caption).foregroundStyle(.tint).lineLimit(1)
                } else {
                    Text("v\(result.app.shortVersion ?? "?")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

private struct ChangelogDetail: View {
    let result: UpdateResult

    /// The page to embed/link to: the source's own `changelogURL` first, then our
    /// hand-curated catalog (covers apps whose source ships no URL — a plain
    /// Homebrew cask like CodexBar — and apps with no source at all — auto_updates
    /// casks like Ghostty/Ollama that defer out of Homebrew yet still have notes).
    private var changelogURL: URL? {
        result.remote?.changelogURL ?? ChangelogCatalog.url(forBundleID: result.app.bundleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            notes
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                .resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.app.name).font(.title2).bold()
                versionLine
            }
            Spacer()
            if let url = changelogURL {
                Link(destination: url) {
                    Label("Open page", systemImage: "safari")
                }
                .font(.callout)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var versionLine: some View {
        if case .updateAvailable(let latest) = result.status {
            Text("\(result.app.shortVersion ?? "?")  →  \(latest)")
                .font(.callout).foregroundStyle(.tint)
        } else {
            Text("v\(result.app.shortVersion ?? "?") · up to date")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let recipe = ChangelogRecipeRegistry.recipe(forBundleID: result.app.bundleID) {
            // A hand-authored recipe beats inline Sparkle/GitHub HTML: it gives the
            // full changelog history, not just the 1-2 builds the appcast embeds.
            // Falls back to the embedded page (or inline HTML) if fetch/parse fails.
            StructuredChangelogView(
                recipe: recipe,
                fallbackURL: changelogURL,
                fallbackHTML: result.remote?.releaseNotesHTML,
                fallbackSource: result.remote?.sourceName)
                .id(recipe.bundleID)
                .onAppear {
                    Log.changelog.debug(
                        "detail app=\(result.app.name, privacy: .public) bundle=\(result.app.bundleID ?? "nil", privacy: .public) source=\(result.remote?.sourceName ?? "nil", privacy: .public) recipe=\(recipe.source.absoluteString, privacy: .public) fallbackURL=\(changelogURL?.absoluteString ?? "nil", privacy: .public) hasInlineHTML=\(result.remote?.releaseNotesHTML != nil, privacy: .public)")
                }
        } else if let changelog = result.remote?.structuredChangelog {
            // GitHub release body parsed into native entries — renders the same way
            // as a recipe-based changelog: version header + bulleted item list.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                        ChangelogEntryView(entry: entry)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let html = result.remote?.releaseNotesHTML {
            ScrollView {
                ReleaseNotesText(text: html, format: .forSource(result.remote?.sourceName))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let url = changelogURL {
            WebView(url: url)
        } else {
            ContentUnavailableView {
                Label("No release notes", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("\(result.remote?.sourceName ?? "This source") doesn’t publish a changelog we can read.")
            } actions: {
                if let dl = result.remote?.downloadURL {
                    Link("Open download page", destination: dl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Renders inline notes. The wire format differs by source: GitHub bodies are
/// GitHub-flavored markdown, Sparkle `<description>` blocks are HTML, and the App
/// Store's `releaseNotes` is plain text whose newlines carry the layout. We pick
/// the parser by source and fall back to plain text if it fails.
private struct ReleaseNotesText: View {
    enum Format {
        case markdown   // GitHub release body
        case html       // Sparkle <description>
        case plainText  // App Store releaseNotes — newline-delimited, no markup

        /// HTML is the safe default for an unknown/Sparkle-like source; plain text
        /// would also survive the HTML parser but lose its newlines.
        static func forSource(_ name: String?) -> Format {
            switch name {
            case "GitHub": return .markdown
            case "App Store": return .plainText
            default: return .html
            }
        }
    }

    let text: String
    let format: Format

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .tint(.accentColor)
    }

    private var attributed: AttributedString {
        switch format {
        case .markdown:
            if let a = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) { return a }
        case .html:
            if let data = text.data(using: .utf8),
               let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil),
               let a = try? AttributedString(ns, including: \.appKit) {
                return a
            }
        case .plainText:
            break  // fall through to the plain-text path, which preserves newlines
        }
        return AttributedString(text)
    }
}

/// Renders a `ChangelogRecipe`'s output natively. Fetches the vendor's changelog
/// page on appear (lazily — only when the user actually opens this app), runs the
/// recipe through `ChangelogExtractor`, and lays out the parsed entries as version
/// headers + bulleted lists. On any failure it falls through to the embedded web
/// page, so a stale recipe never leaves the user with nothing.
private struct StructuredChangelogView: View {
    let recipe: ChangelogRecipe
    let fallbackURL: URL?
    var fallbackHTML: String? = nil
    var fallbackSource: String? = nil

    @State private var phase: Phase = .loading
    private enum Phase { case loading, loaded(Changelog), failed }

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await load() }
        case .loaded(let changelog):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(changelog.entries.enumerated()), id: \.offset) { _, entry in
                        ChangelogEntryView(entry: entry)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .failed:
            if let url = fallbackURL {
                WebView(url: url)
            } else if let html = fallbackHTML {
                ScrollView {
                    ReleaseNotesText(text: html, format: .forSource(fallbackSource))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ContentUnavailableView {
                    Label("No release notes", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }

    private func load() async {
        let changelog = await ChangelogService.load(recipe)
        if let changelog {
            let first = changelog.entries.first
            Log.changelog.debug(
                "loaded bundle=\(recipe.bundleID, privacy: .public) entries=\(changelog.entries.count, privacy: .public) firstTitle=\(first?.title ?? "nil", privacy: .public) firstVersion=\(first?.version ?? "nil", privacy: .public) firstDate=\(first?.date ?? "nil", privacy: .public)")
            phase = .loaded(changelog)
        } else {
            Log.changelog.debug(
                "failed bundle=\(recipe.bundleID, privacy: .public) source=\(recipe.source.absoluteString, privacy: .public) fallbackURL=\(fallbackURL?.absoluteString ?? "nil", privacy: .public) hasFallbackHTML=\(fallbackHTML != nil, privacy: .public)")
            phase = .failed
        }
    }
}

/// One changelog block: either a classic version heading, or a post-style title
/// with date/build metadata underneath.
private struct ChangelogEntryView: View {
    let entry: Changelog.Entry

    private var displayDate: String? {
        guard let date = entry.date else { return nil }
        return Self.displayDate(for: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = entry.title {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title)
                            .font(.title3)
                            .bold()
                        if !entry.version.isEmpty {
                            Text(entry.version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let date = displayDate {
                        Text(date)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.version).font(.title3).bold()
                    if let date = displayDate {
                        Text(date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private static func displayDate(for raw: String) -> String {
        if let parsed = iso8601Fractional.date(from: raw) ?? iso8601.date(from: raw) {
            return ymd.string(from: parsed)
        }
        return raw
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// A minimal WKWebView wrapper. Navigation is allowed to follow links the user
/// clicks (changelogs link out to blog posts, etc.); this is a viewer, not a
/// locked-down frame — but it's read-only content we never submit to.
private struct WebView: NSViewRepresentable {
    let url: URL

    /// Tracks the URL we last *requested* (not `view.url`, which becomes the
    /// post-redirect URL). Comparing against the requested URL stops a changelog
    /// page that 301-redirects from reloading on every `updateNSView` — `view.url`
    /// would never equal the original `url`, so it would loop indefinitely.
    final class Coordinator { var requested: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        context.coordinator.requested = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.requested != url else { return }
        context.coordinator.requested = url
        view.load(URLRequest(url: url))
    }
}
