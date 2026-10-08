import Foundation

/// Junie's release notes: the GitHub Release of each build, fetched one tag at a
/// time for the builds this install's channel lists.
///
/// `JetBrains/junie` keeps one GitHub Release per build of every channel — the tag
/// is the build (`3419.26`), the name says the channel (`Junie Release 26.9.22
/// (3419.26)`, `Junie EAP …`, `Junie Nightly …`), the body is a few Markdown
/// bullets or nothing. Junie itself reads them from
/// `api.github.com/repos/JetBrains/junie/releases` (`ReleaseNotesService` in
/// 1543.24). The list is no use here: ~2,600 releases, most of them nightlies, and
/// not in version order, so a release-channel reader's few entries would be pages
/// apart. The channel's own feed (`JunieRelease`) already names its builds, so
/// those are asked for directly — `releases/tags/<build>` for the newest unseen
/// builds up to `maximumRequests`, plus enough of the reader's own to make
/// `minimum`, newest first. A release with an empty body or no release at all for
/// the tag yields no entry: no notes, not an error. The human page,
/// https://junie.jetbrains.com/whats-new, carries the release channel's last five
/// builds and no others.
///
/// The repository is addressed as `JetBrains/junie`: `jetbrains-junie/junie`, which
/// the feeds and the installer use, redirects there, and a redirect drops the
/// `Authorization` header, so a token would buy nothing. The token is
/// `ChangelogService`'s, as for bub.
public enum JunieChangelog {

    static let api = "https://api.github.com/repos/JetBrains/junie/releases/tags/"

    /// Each request costs one of 60 anonymous GitHub calls an hour (shared with
    /// every GitHub version check), so the window is capped: a reader 48 builds
    /// behind (1543.24 on release, 2026-10-02) sees the newest eight builds' notes.
    static let maximumRequests = 8

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    /// The builds to ask for, newest first: up to `maximumRequests` above
    /// `installed` and at or below `latest`, then — when that is fewer than
    /// `minimum` — the newest at or below `installed`, so an up-to-date reader
    /// still sees what their build brought.
    static func window(builds: [String], installed: String?, latest: String?, minimum: Int = 5) -> [String] {
        let sorted = builds.sorted { JunieRelease.compare($0, $1) == .orderedDescending }
        let capped = sorted.filter { latest == nil || JunieRelease.compare($0, latest!) != .orderedDescending }
        let unseen = capped.filter { installed != nil && JunieRelease.compare($0, installed!) == .orderedDescending }
        let picked = Array(unseen.prefix(maximumRequests))
        let taken = capped.dropFirst(unseen.count).prefix(max(minimum - picked.count, 0))
        return picked + taken
    }

    /// One entry per build whose release has notes, newest first. Throws only when
    /// no request came back at all: a release with no notes is an answer.
    static func fetch(
        builds: [String], installed: String?, latest: String?, force: Bool, fetch: @escaping Fetch
    ) async throws -> Changelog {
        let wanted = window(builds: builds, installed: installed, latest: latest)
        // Each child parses its own answer and the group is drained with
        // `next()`, into state of the group's own. The first shape — children
        // returning `(String, Result<(Data, Int), Error>)`, read with `for await`
        // into this function's variables — misbehaved in an optimized build:
        // the loop saw no child at all, `fetch` returned no entries, and the
        // children then completed into the finished group and aborted the app
        // in `AsyncTask::completeFuture` (`__cxa_pure_virtual`) on opening
        // Junie's pane (2026-10-02, Swift 6.4, macOS 27.2 beta; the debug build
        // was right). Measured with `swift test -c release` (now `make test-release`); why that shape is
        // miscompiled was not pinned down.
        let (entries, answered, failure) = await withTaskGroup(
            of: Answer.self, returning: ([String: Changelog.Entry], Int, Error?).self
        ) { group in
            for build in wanted {
                group.addTask { await answer(build: build, force: force, fetch: fetch) }
            }
            var entries: [String: Changelog.Entry] = [:]
            var answered = 0
            var failure: Error?
            while let next = await group.next() {
                if next.answered { answered += 1 }
                if let entry = next.entry { entries[next.build] = entry }
                if let error = next.failure { failure = error }
            }
            return (entries, answered, failure)
        }
        if answered == 0, let failure { throw failure }
        return Changelog(entries: wanted.compactMap { entries[$0] }, itemSyntax: .markdown)
    }

    /// One build's request, answered: a 200 (with its entry, when the release has
    /// notes) or a 404 is an answer; anything else is a failure.
    struct Answer: Sendable {
        let build: String
        let answered: Bool
        let entry: Changelog.Entry?
        let failure: Error?
    }

    static func answer(build: String, force: Bool, fetch: Fetch) async -> Answer {
        guard let url = URL(string: api + build) else {
            return Answer(build: build, answered: false, entry: nil, failure: URLError(.badURL))
        }
        do {
            let (data, status, remaining) = try await fetch(url, force)
            switch status {
            case 200: return Answer(build: build, answered: true, entry: parse(data, build: build), failure: nil)
            case 404: return Answer(build: build, answered: true, entry: nil, failure: nil)
            default:
                return Answer(build: build, answered: false, entry: nil,
                              failure: CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: url))
            }
        } catch {
            return Answer(build: build, answered: false, entry: nil, failure: error)
        }
    }

    /// One release object → its entry, or nil when its body has no notes or the
    /// object is not this build's release.
    static func parse(_ data: Data, build: String) -> Changelog.Entry? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["tag_name"] as? String == build,
              json["draft"] as? Bool != true,
              let body = json["body"] as? String,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let date = StructuredChangelogDecoder.isoDay(json["published_at"] as? String)
        return GitHubMarkdownParser.parse(body: body, version: build, date: date)?.entries.first
    }

    /// What the GitHub API is asked with: the headers `ChangelogService` sends, and
    /// the token when there is one.
    static func get(_ url: URL, force: Bool, session: URLSession = .updates) async throws -> (Data, Int, String?) {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if ChangelogService.isGitHubAPI(url), let token = await ChangelogService.gitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        let http = response as? HTTPURLResponse
        return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
    }
}
