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

    private enum LoadState {
        case loading
        case loaded(Changelog)
        case failed(String)
    }
    @State private var state: LoadState = .loading

    /// The version actually running, so the list can say which entry is yours.
    private var runningVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            // Marked here rather than at the click: any route into this window —
            // the banner, the menu button, macOS restoring it after a relaunch —
            // means the notes were put in front of the user, and the banner should
            // stop nagging. Doing it at the call site would leave one of those
            // routes announcing forever.
            model.markSelfUpdateSeen()
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("What's New in Duo Updater").font(.headline)
                if let runningVersion {
                    Text("You're running \(runningVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if case .loading = state {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loaded(let changelog):
            ChangelogEntriesView(changelog: changelog)
        case .loading:
            // No spinner here — the header carries one. A second, centred spinner
            // makes a fast load flash twice.
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                state = .failed("GitHub answered HTTP \(http.statusCode).")
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            guard let changelog = SelfChangelogParser.parse(text) else {
                state = .failed("The file loaded but carried no release sections.")
                return
            }
            state = .loaded(changelog)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
