import SwiftUI
import AppKit
import DuoUpdaterCore

/// DuoUpdater's own release notes — the one changelog the app could show you and
/// didn't. Every other app in the list has a Release Notes pane; this one is ours.
///
/// The notes are the repository's `CHANGELOG.md`, fetched rather than bundled.
/// Bundling would freeze them at build time, so the copy on your Mac would
/// describe its own version and nothing after it — leaving out the one release you
/// most want to read about, the one you haven't taken yet. The appcast isn't the
/// source either: it keeps a rolling window of the last few releases, while that
/// file has all of them. And it is the same text the update prompt shows, because
/// `publish-release.sh` lifts each version's section straight out of it.
struct SelfChangelogView: View {
    static let windowID = "self-changelog"

    @Bindable var model: AppListModel

    /// Raw file rather than the API: no token, no rate budget shared with the
    /// version checks, and it is the same host the app already reads its appcast
    /// from. (Note that this host is CDN-cached for a few minutes, so a release
    /// published seconds ago may take a moment to appear here.)
    private static let source = URL(
        string: "https://raw.githubusercontent.com/jizhi0v0/duo-updater/main/CHANGELOG.md")!
    /// The same notes in the language the app is running in, when we have them.
    ///
    /// A separate file rather than one multilingual `CHANGELOG.md`, because that
    /// file is also what `publish-release.sh` lifts a release's section out of and
    /// what the update prompt shows — the release path reads it as English and must
    /// keep doing so. Fetched only when the app is not running in English, and only
    /// ever as an addition: see `SelfChangelogLocalization` for what happens when
    /// it 404s, is behind, or has drifted (in every case, English stands).
    private static func translatedSource(_ basename: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/jizhi0v0/duo-updater/main/changelog/"
            + basename + ".md")
    }

    /// CHANGELOG.md deliberately contains only prose. GitHub Releases is the
    /// authoritative clock for when each of those versions became available.
    ///
    /// Paged, because the changelog outlives one page. At this repo's cadence
    /// (twenty releases in the six days to 0.3.63) the list passes 100 within
    /// weeks, and a single-page read would then quietly drop the date off every
    /// older entry — a rail half dated and half not, sized off the mixture.
    private static func releasesSource(page: Int) -> URL {
        URL(string: "https://api.github.com/repos/jizhi0v0/duo-updater/releases"
            + "?per_page=\(releasesPerPage)&page=\(page)")!
    }

    private static let releasesPerPage = 100

    /// Stop after this many pages whatever happens. Dates are an enrichment, not
    /// a reason to spend an unbounded slice of the unauthenticated 60/hour
    /// budget — and every version the notes can show is inside the first few.
    private static let maxReleasePages = 3

    private struct PublishedRelease: Decodable {
        let tagName: String
        let publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case publishedAt = "published_at"
        }
    }

    private enum LoadState {
        case loading
        case loaded(Changelog)
        case failed(String)
    }
    @State private var state: LoadState = .loading

    /// The version actually running, marked in the history and selected header.
    private var runningVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        content
            .frame(minWidth: 720, minHeight: 480)
            .task {
            // Marked here rather than at the click: any route into this window —
            // the menu sparkles, macOS restoring it after a relaunch — means the
            // notes were put in front of the user, and the bright unread state should
            // clear. Doing it at the call site would leave one of those routes
            // announcing forever.
            model.markSelfUpdateSeen()
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loaded(let changelog):
            SelfChangelogHistoryView(changelog: changelog, runningVersion: runningVersion)
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Couldn't load the release notes")
                    .font(.callout)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                HStack(spacing: 10) {
                    Button("Try Again") { Task { await load(force: true) } }
                    Link("Open on GitHub", destination: Self.source)
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Fetch and parse. Failure states are distinguished on purpose: "the request
    /// failed" and "the file came back but no longer looks like a changelog" want
    /// different things from whoever reads them, and collapsing both into one
    /// message is how a format drift gets mistaken for a network blip.
    private func load(force: Bool = false) async {
        if force { state = .loading }
        var request = URLRequest(url: Self.source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        do {
            let (data, response) = try await RequestAttribution.withApp(Bundle.main.bundlePath) {
                try await URLSession.updates.countedData(
                    for: request, purpose: .selfUpdate)
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                state = .failed(String(localized: "GitHub answered HTTP \(http.statusCode)."))
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            guard let changelog = SelfChangelogParser.parse(text) else {
                state = .failed(String(localized: "The file loaded but carried no release sections."))
                return
            }
            let localized = SelfChangelogLocalization.merge(
                english: changelog, translated: await translatedNotes(force: force))
            state = .loaded(await addingReleaseDates(to: localized))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The translated notes, or nil to stay in English.
    ///
    /// Every failure returns nil and none of them is surfaced. A missing or
    /// unreachable translation is not a broken window — it is a window in English,
    /// which is what this file was until translations existed. The one thing that
    /// would be worse than untranslated notes is no notes, so nothing in here can
    /// reach the failure state.
    private func translatedNotes(force: Bool) async -> Changelog? {
        guard let basename = SelfChangelogLocalization.translatedNotesBasename(
                preferredLocalizations: Bundle.main.preferredLocalizations),
              let url = Self.translatedSource(basename)
        else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        guard let (data, response) = try? await RequestAttribution.withApp(Bundle.main.bundlePath, operation: {
            try await URLSession.updates.countedData(
                for: request, purpose: .selfUpdate)
        }),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return SelfChangelogParser.parse(String(decoding: data, as: UTF8.self))
    }

    /// Date lookup is enrichment, not a second requirement for opening the
    /// notes. A rate limit or transient GitHub API failure leaves the changelog
    /// usable, just without dates — and a page that fails mid-walk keeps the
    /// dates the earlier pages already produced.
    private func addingReleaseDates(to changelog: Changelog) async -> Changelog {
        var dates: [String: String] = [:]
        // Stop as soon as every version the notes can show has an answer, so the
        // common case stays one request.
        var wanted = Set(changelog.entries.map(\.version))

        for page in 1...Self.maxReleasePages where !wanted.isEmpty {
            var request = URLRequest(url: Self.releasesSource(page: page))
            // Revalidate rather than serve whatever is cached. The version a
            // reader most wants a date for is the one that just landed on their
            // Mac, and `returnCacheDataElseLoad` answers from a copy taken before
            // that release existed — the one entry guaranteed to be missing is the
            // one they opened the window for. A 304 costs nothing against the
            // rate limit.
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await RequestAttribution.withApp(Bundle.main.bundlePath, operation: {
                    try await URLSession.updates.countedData(
                        for: request, purpose: .selfUpdate)
                }),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let releases = try? JSONDecoder().decode([PublishedRelease].self, from: data),
                  !releases.isEmpty
            else { break }

            for release in releases {
                guard let timestamp = release.publishedAt, timestamp.count >= 10 else { continue }
                let version = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst()) : release.tagName
                // Newest-first, first writer wins — so a version that was tagged
                // twice keeps its latest publication. Deliberately not
                // `Dictionary(uniqueKeysWithValues:)`, which TRAPS on a duplicate
                // key: `v0.3.63` and `0.3.63` are two legal tags that collide the
                // moment the "v" is stripped, and the notes window would crash
                // rather than show a date it wasn't sure about.
                if dates[version] == nil { dates[version] = String(timestamp.prefix(10)) }
                wanted.remove(version)
            }
            // A short page is the last page.
            if releases.count < Self.releasesPerPage { break }
        }

        guard !dates.isEmpty else { return changelog }

        let entries = changelog.entries.map { entry in
            Changelog.Entry(
                title: entry.title,
                version: entry.version,
                date: dates[entry.version] ?? entry.date,
                items: entry.items,
                content: entry.content)
        }
        return Changelog(entries: entries, itemSyntax: changelog.itemSyntax)
    }
}

/// DuoUpdater's own history shares the note renderer and sidebar interactions
/// with the workbench, with a quieter two-line rail and a bounded reading column.
struct SelfChangelogHistoryView: View {
    let changelog: Changelog
    var runningVersion: String?

    @State private var selection: String?
    @FocusState private var focusedHistory: Bool?

    private static let readingWidth: CGFloat = 640
    private static let scrollTop = "self-changelog-top"

    private var selectedIndex: Int? {
        guard !changelog.entries.isEmpty else { return nil }
        return selection.flatMap(Int.init).flatMap { changelog.entries.indices.contains($0) ? $0 : nil } ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            history
                .frame(width: 224)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if let index = selectedIndex {
                readingPane(index)
            } else {
                ContentUnavailableView("Release Notes", systemImage: "text.alignleft")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .releaseNoteLinks()
        .onChange(of: changelog) { selection = nil }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Releases")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 14)

            SidebarList(selection: historySelection,
                        order: changelog.entries.indices.map(String.init),
                        label: String(localized: "Releases"),
                        focus: $focusedHistory, focusValue: true) {
                ForEach(changelog.entries.indices, id: \.self) { index in
                    let entry = changelog.entries[index]
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(entry.version)
                                .font(.system(size: 13, weight: selectedIndex == index ? .semibold : .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if isRunning(entry) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .help("The version you're running")
                                    .accessibilityLabel("The version you're running")
                            }
                        }
                        if let date = entry.date, !date.isEmpty {
                            Text(ChangelogEntryView.displayDate(for: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: SidebarRowMetrics.height - 2 * SidebarRowMetrics.verticalPadding)
                    .sidebarRow(String(index), selection: historySelection)
                }
            }
        }
    }

    /// The first release is selected immediately, including its accessibility
    /// state and the starting point for the sidebar's arrow-key navigation.
    private var historySelection: Binding<String?> {
        Binding(get: { selectedIndex.map(String.init) }, set: { selection = $0 })
    }

    private func readingPane(_ index: Int) -> some View {
        let entry = changelog.entries[index]
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.version)
                        .font(.system(size: 28, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        if let date = entry.date, !date.isEmpty {
                            Text(ChangelogEntryView.displayDate(for: date))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if isRunning(entry) {
                            Label("Installed", systemImage: "checkmark.circle")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .help("The version you're running")
                        }
                    }
                }
                Spacer(minLength: 0)
                ChangelogEntryView.CopyNotesButton(entry: entry)
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: Self.readingWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)

            Divider()
                .frame(maxWidth: Self.readingWidth)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(0..<ChangelogEntryView.rowCount(of: entry), id: \.self) { row in
                            ChangelogEntryView(entry: entry, itemStyle: .paragraphs,
                                               syntax: changelog.itemSyntax, part: .row(row))
                                .font(.system(size: 14))
                                .lineSpacing(4)
                        }
                    }
                    .frame(maxWidth: Self.readingWidth, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .id(Self.scrollTop)
                }
                .onChange(of: index) { proxy.scrollTo(Self.scrollTop, anchor: .top) }
                .onChange(of: changelog) { proxy.scrollTo(Self.scrollTop, anchor: .top) }
            }
        }
    }

    private func isRunning(_ entry: Changelog.Entry) -> Bool {
        guard let runningVersion, !runningVersion.isEmpty else { return false }
        return entry.version == runningVersion
    }
}
