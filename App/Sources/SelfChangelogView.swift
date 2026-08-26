import SwiftUI
import DuoUpdaterCore

/// Duo Updater's own release notes — the one changelog the app could show you and
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

    /// The version actually running. Marks its row in the rail — which is the only
    /// place it is stated: a line of prose saying the same thing sat above a rail
    /// that already showed it, and the window's title bar already says what this
    /// window is.
    private var runningVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        content
            .frame(minWidth: 560, minHeight: 420)
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
            // Paragraphs, not bullets: our notes are prose with a bold lead
            // sentence, and a `•` in front of ten lines reads as a list item that
            // forgot to end.
            ChangelogEntriesView(
                changelog: changelog,
                itemStyle: .paragraphs,
                runningVersion: runningVersion,
                showsDatesInline: true,
                showsLayoutPicker: false)
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
            let (data, response) = try await URLSession.updates.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                state = .failed(String(localized: "GitHub answered HTTP \(http.statusCode)."))
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            guard let changelog = SelfChangelogParser.parse(text) else {
                state = .failed(String(localized: "The file loaded but carried no release sections."))
                return
            }
            state = .loaded(await addingReleaseDates(to: changelog))
        } catch {
            state = .failed(error.localizedDescription)
        }
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

            guard let (data, response) = try? await URLSession.updates.data(for: request),
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
