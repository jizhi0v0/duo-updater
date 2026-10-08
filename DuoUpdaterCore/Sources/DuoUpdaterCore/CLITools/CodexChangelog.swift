import Foundation

/// Codex's release notes: the GitHub Release of each stable version, fetched one
/// tag at a time.
///
/// `openai/codex` keeps one GitHub Release per tag, `rust-v<version>`. A stable
/// release's body is hand-written Markdown under `## New Features`, `## Bug
/// Fixes`, `## Documentation`, `## Chores`, then a `## Changelog` section listing
/// every merged PR (rust-v0.160.0: 6,274 characters, ~150 PR lines); the alphas'
/// bodies are one line ("Release 0.162.0-alpha.12"). The release list is no use
/// here: ~12 alphas a day bury the stables (11 stable in the newest 100 on
/// 2026-10-04), and each release object carries its 176 assets, so a page of 100
/// is 2.3 MB. Instead one request lists the tags
/// (`git/matching-refs/tags/rust-v`, 1,398 refs, ~42 KB gzipped, unpaginated),
/// the stable ones are kept, and `releases/tags/rust-v<version>` (~26 KB) is asked
/// for the newest unseen versions up to `maximumRequests`, plus enough of the
/// reader's own to make `minimum` — Junie's window (`JunieChangelog`). The PR list
/// is skipped: it is the commit log, not notes. The token is `ChangelogService`'s.
public enum CodexChangelog {

    static let tags = URL(string: "https://api.github.com/repos/openai/codex/git/matching-refs/tags/rust-v")!
    static let api = "https://api.github.com/repos/openai/codex/releases/tags/rust-v"
    /// The PR list under `## Changelog`.
    static let skipSections = ["Changelog"]

    /// Each request costs one of 60 anonymous GitHub calls an hour (shared with
    /// every GitHub version check), so the window is capped: a reader seventeen
    /// releases behind (0.143.0 on 2026-10-04) sees the newest eight.
    static let maximumRequests = 8

    /// The body, the status and the answer's `X-RateLimit-Remaining`.
    typealias Fetch = @Sendable (URL, Bool) async throws -> (Data, Int, String?)

    public static func fetch(installed: String?, latest: String?, force: Bool) async throws -> Changelog {
        try await fetch(installed: installed, latest: latest, force: force,
                        fetch: { try await JunieChangelog.get($0, force: $1) })
    }

    /// The seam tests use, so nothing here reaches the network.
    static func fetch(installed: String?, latest: String?, force: Bool, fetch: @escaping Fetch) async throws -> Changelog {
        let (data, status, remaining) = try await fetch(tags, force)
        guard status == 200 else {
            throw CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: tags)
        }
        let versions = await offCooperativePool { stableVersions(data) }
        guard !versions.isEmpty else { throw CLIToolReleaseNotesError.noSections }
        return try await notes(versions: versions, installed: installed, latest: latest, force: force, fetch: fetch)
    }

    /// The tags that are stable releases, as versions: `refs/tags/rust-v0.160.0`
    /// → `0.160.0`; the alphas and betas are left out.
    static func stableVersions(_ data: Data) -> [String] {
        guard let refs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return refs.compactMap { ref in
            guard let name = ref["ref"] as? String, name.hasPrefix("refs/tags/rust-v") else { return nil }
            let version = String(name.dropFirst("refs/tags/rust-v".count))
            return !version.contains("-") && CodexRelease.isVersion(version) ? version : nil
        }
    }

    /// The versions to ask for, newest first: up to `maximumRequests` above
    /// `installed` and at or below `latest`, then — when that is fewer than
    /// `minimum` — the newest at or below `installed`, so an up-to-date reader
    /// still sees what their version brought.
    static func window(versions: [String], installed: String?, latest: String?, minimum: Int = 5) -> [String] {
        let sorted = versions.sorted { CodexRelease.compare($0, $1) == .orderedDescending }
        let capped = sorted.filter { latest == nil || CodexRelease.compare($0, latest!) != .orderedDescending }
        let unseen = capped.filter { installed != nil && CodexRelease.compare($0, installed!) == .orderedDescending }
        let picked = Array(unseen.prefix(maximumRequests))
        let taken = capped.dropFirst(unseen.count).prefix(max(minimum - picked.count, 0))
        return picked + taken
    }

    /// One entry per version whose release has notes, newest first. Throws only
    /// when no request came back at all: a release with no notes is an answer.
    static func notes(
        versions: [String], installed: String?, latest: String?, force: Bool, fetch: @escaping Fetch
    ) async throws -> Changelog {
        let wanted = window(versions: versions, installed: installed, latest: latest)
        // The shape `JunieChangelog.fetch` settled on: each child parses its own
        // answer, and the group is drained with `next()` into state of its own.
        let (entries, answered, failure) = await withTaskGroup(
            of: Answer.self, returning: ([String: Changelog.Entry], Int, Error?).self
        ) { group in
            for version in wanted {
                group.addTask { await answer(version: version, force: force, fetch: fetch) }
            }
            var entries: [String: Changelog.Entry] = [:]
            var answered = 0
            var failure: Error?
            while let next = await group.next() {
                if next.answered { answered += 1 }
                if let entry = next.entry { entries[next.version] = entry }
                if let error = next.failure { failure = error }
            }
            return (entries, answered, failure)
        }
        if answered == 0, let failure { throw failure }
        return Changelog(entries: wanted.compactMap { entries[$0] }, itemSyntax: .markdown)
    }

    struct Answer: Sendable {
        let version: String
        let answered: Bool
        let entry: Changelog.Entry?
        let failure: Error?
    }

    static func answer(version: String, force: Bool, fetch: Fetch) async -> Answer {
        guard let url = URL(string: api + version) else {
            return Answer(version: version, answered: false, entry: nil, failure: URLError(.badURL))
        }
        do {
            let (data, status, remaining) = try await fetch(url, force)
            switch status {
            case 200: return Answer(version: version, answered: true, entry: parse(data, version: version), failure: nil)
            case 404: return Answer(version: version, answered: true, entry: nil, failure: nil)
            default:
                return Answer(version: version, answered: false, entry: nil,
                              failure: CLIToolReleaseNotesError.status(status, rateLimitRemaining: remaining, url: url))
            }
        } catch {
            return Answer(version: version, answered: false, entry: nil, failure: error)
        }
    }

    /// One release object → its entry, or nil when its body has no notes or the
    /// object is not this version's release.
    static func parse(_ data: Data, version: String) -> Changelog.Entry? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["tag_name"] as? String == "rust-v" + version,
              json["draft"] as? Bool != true,
              let body = json["body"] as? String,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let date = StructuredChangelogDecoder.isoDay(json["published_at"] as? String)
        return GitHubMarkdownParser.parse(body: body, version: version, date: date, skipSections: skipSections)?
            .entries.first
    }
}
