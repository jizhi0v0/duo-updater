import Foundation

/// Release notes for one outdated Homebrew formula. A formula isn't an app, so it
/// has no Sparkle/recipe changelog — but most formulae are GitHub-hosted, and a
/// formula's `urls.stable.url` (read locally from `brew info`) names the repo and
/// the release tag. From that we fetch the GitHub release body and parse it into the
/// same structured `Changelog` the app rows render, so formula notes look native.
/// Non-GitHub formulae (Go, GNU tools) fall back to their homepage.
// `Equatable` (not `Hashable`) because that is all anything needs: the cache
// round-trip test compares two values. Nothing hashes a `FormulaRelease` — it is
// never a dictionary key or a Set member — and widening a public type further
// than its use requires is API surface nobody asked for.
public struct FormulaRelease: Sendable, Codable, Equatable {
    /// Structured notes, when a GitHub release body was found and parsed. nil falls
    /// the UI back to `pageURL` (rendered in a web view).
    public let changelog: Changelog?
    /// The GitHub release/tag page, or the formula's homepage when it's not on
    /// GitHub — somewhere to read or link the notes when there's nothing structured.
    public let pageURL: URL?

    public init(changelog: Changelog?, pageURL: URL?) {
        self.changelog = changelog
        self.pageURL = pageURL
    }

    /// Worth persisting only when it carries something the UI can show; a fully-empty
    /// result is a transient failure (e.g. `brew info` hiccup) we'd rather retry.
    var isUseful: Bool { changelog != nil || pageURL != nil }
}

/// Fetches a formula's release notes: `brew info` (local) for the repo/tag, then
/// the GitHub Releases API for the body. Lazy by design — the UI calls this only
/// when a formula is selected, so a screenful of outdated formulae never burns the
/// GitHub rate limit up front.
///
/// This is the SECOND cross-launch disk cache whose content comes from
/// `GitHubMarkdownParser` — `ChangelogDiskCache` is the other, and issue #112 was
/// filed against exactly this failure mode: a version's notes cached under an
/// older parser get served forever, because a released version's notes never
/// change but what THIS APP extracts from them can. `cached`/`persist` below stamp
/// and check `Changelog.parserGeneration` for the same reason and by the same
/// rule as `ChangelogDiskCache` — see its doc comment and `Changelog.parserGeneration`'s.
public actor BrewFormulaReleaseService {
    private let session: URLSession
    private let directory: URL

    /// `directory` defaults to `…/com.duoupdater.app/formula-releases` — the same
    /// container the changelog/image caches use. Overridable for tests.
    public init(session: URLSession = .updates, cacheDirectory: URL? = nil) {
        self.session = session
        if let cacheDirectory {
            self.directory = cacheDirectory
        } else {
            self.directory = DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("formula-releases", isDirectory: true)
        }
    }

    /// Wraps `FormulaRelease` with the parser generation that produced it, mirroring
    /// `ChangelogDiskCache.Stored` — kept OUT of `FormulaRelease` itself because that
    /// type is also what the UI holds in `FormulaReleaseStore`, and a
    /// caching concern has no business riding along on a domain value passed around
    /// the app. Non-optional and undefaulted for the same reason as
    /// `ChangelogDiskCache.Stored`: an entry written before this field existed has
    /// no honest generation to compare against, so it can't be assigned one — it can
    /// only be unknown, and decoding it here throws, which `cached` below already
    /// turns into a miss (same as any other corrupt/unreadable file). `persist`
    /// still overwrites this exact key's file on the next fetch, and the sibling
    /// prune below deletes every *other*-version file for the formula on each
    /// successful write regardless of decodability, so this doesn't accumulate
    /// unbounded undecodable files — same ~one-file-per-formula bound as before.
    private struct Stored: Codable {
        let release: FormulaRelease
        let parserGeneration: Int
    }

    /// The cross-launch disk-cached notes for a formula version, with NO `brew info`
    /// spawn and NO GitHub call. Used by the pre-warm probe and as the fast path in
    /// `release(for:…)`. A formula version's notes are immutable, so a hit is final
    /// PROVIDED it was written under the running build's `Changelog.parserGeneration`
    /// — a mismatch (or a pre-generation file with no such field at all) is treated
    /// as a miss, same as `ChangelogDiskCache.get`.
    public func cached(for name: String, version: String) -> FormulaRelease? {
        guard let data = try? Data(contentsOf: fileURL(name: name, version: version)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.parserGeneration == Changelog.parserGeneration
        else { return nil }
        return stored.release
    }

    public func release(for name: String, version: String, token: String?) async -> FormulaRelease {
        // Disk first: a version's notes never change, so a hit skips both the local
        // `brew info` Process and the (rate-limited) GitHub API call entirely.
        if let cached = cached(for: name, version: version) { return cached }

        let computed = await compute(name: name, version: version, token: token)
        if computed.isUseful { persist(computed, name: name, version: version) }
        return computed
    }

    private func compute(name: String, version: String, token: String?) async -> FormulaRelease {
        guard let info = await Self.brewInfoOffActor(name: name) else {
            return FormulaRelease(changelog: nil, pageURL: nil)
        }
        guard let gh = Self.deriveGitHub(fromStableURL: info.stableURL) else {
            // Not GitHub-hosted (Go, GNU, …): the homepage is the best we can offer.
            return FormulaRelease(changelog: nil, pageURL: info.homepage)
        }

        let tagPage = URL(string:
            "https://github.com/\(gh.owner)/\(gh.repo)/releases/tag/\(Self.encode(gh.tag))")
        if let release = try? await fetchRelease(owner: gh.owner, repo: gh.repo, tag: gh.tag, token: token) {
            let changelog = release.body.flatMap {
                $0.isEmpty ? nil : GitHubMarkdownParser.parse(body: $0, version: version, date: release.publishedAt)
            }
            return FormulaRelease(changelog: changelog, pageURL: release.htmlURL ?? tagPage)
        }
        // The git tag exists but carries no GitHub *release* (common for tarball-only
        // tags): no body to parse, but the tag page (or homepage) still works.
        return FormulaRelease(changelog: nil, pageURL: tagPage ?? info.homepage)
    }

    // MARK: - Disk cache

    private func fileURL(name: String, version: String) -> URL {
        directory.appendingPathComponent(prefix(name: name) + sanitize(version) + ".json")
    }

    /// Persist a formula version's notes, stamped with the running build's
    /// `Changelog.parserGeneration`, and prune any older-version file for the same
    /// formula (only the current version is ever shown). Best-effort.
    ///
    /// Internal, not `private`: `compute` above spawns a real `brew info` `Process`
    /// and a real GitHub request, so exercising the disk-write path (does `persist`
    /// stamp the running generation?) through the public `release(for:…)` API would
    /// make that test dependent on Homebrew being installed and reachable over the
    /// network — exactly the kind of test this codebase avoids for its cache layers.
    /// `BrewFormulaReleaseServiceTests` calls this directly instead, the same
    /// reasoning `ChangelogDiskCache.directory` documents for its own test-only
    /// internal visibility.
    func persist(_ release: FormulaRelease, name: String, version: String) {
        let keep = fileURL(name: name, version: version).lastPathComponent
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stored = Stored(release: release, parserGeneration: Changelog.parserGeneration)
            try JSONEncoder().encode(stored).write(
                to: directory.appendingPathComponent(keep), options: .atomic)
        } catch {
            Log.app.debug("formula release disk write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let pfx = prefix(name: name)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for n in names where n.hasPrefix(pfx) && n != keep {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(n))
            }
        }
    }

    private func prefix(name: String) -> String { sanitize(name) + "__" }

    /// Shared rule — see ``String/filesystemSafeToken``.
    private func sanitize(_ raw: String) -> String { raw.filesystemSafeToken }

    // MARK: - brew info (local)

    /// `Sendable` because `brewInfoOffActor` resumes a continuation with it from a
    /// Dispatch thread — it crosses a concurrency domain, it isn't decoration.
    private struct Info: Sendable { let homepage: URL?; let stableURL: String? }

    /// Runs `brewInfo` on a Dispatch thread, so the ~0.5s subprocess never occupies
    /// this actor. The hop is load-bearing: `brewInfo` is already effectively
    /// non-isolated (it's `static`), but that alone changes nothing — a *synchronous*
    /// call has no ability to switch executors (SE-0338), so it runs to completion on
    /// whatever executor calls it. Called synchronously from `compute`, that executor
    /// is this actor, and the actor stays occupied for the whole subprocess.
    ///
    /// That serialized every client behind every other. With a GitHub token configured
    /// `prewarmFormulaReleases` calls `release(...)` for each uncached outdated formula
    /// — without a token it only reads the disk cache and never spawns a subprocess at
    /// all, so the storm below is token-gated — and the interactive path
    /// (`ensureFormulaReleaseLoading`, on user select) shares this actor. So selecting
    /// a formula whose notes were ALREADY on disk still spun for N x 0.5s: its cheap
    /// `cached(...)` hop queued behind the whole blocking chain. #112's parser
    /// generation invalidates every entry once after an upgrade, which is exactly when
    /// N is largest (11 of 23 outdated formulae on the author's machine, ~7s).
    ///
    /// Dispatch, NOT `Task.detached`: a detached task still runs on the *cooperative*
    /// pool, which is width-capped near the core count and does not overcommit when one
    /// of its threads blocks. Fanning out N blocking `waitUntilExit()` calls there
    /// saturates the `.utility` band and stalls unrelated `.utility` work — this repo
    /// puts `BackupStore.pruneOrphans`, `runChannelSwitchRecheck` and the `lsappinfo`
    /// probe in that band, and they overlap the very refresh that triggers this.
    /// Measured 23-wide on a 14-core M3 Max, worst added stall for an unrelated,
    /// freshly-enqueued `.utility` task:
    ///
    ///     Task.detached          0.95 - 1.07s     fan-out wall 2.34s
    ///     DispatchQueue.global   0.02 - 0.06s     fan-out wall 2.36s
    ///
    /// Same wall clock, ~25x less collateral, because Dispatch grows its pool when a
    /// thread blocks. That is why there is no concurrency limit here: a bound would be
    /// treating a symptom of the wrong vehicle.
    ///
    /// If you re-measure, probe in the SAME QoS band as the blocked threads. Darwin
    /// pools per-QoS, so a probe on `.medium` (or any other band) reports ~0.01s and
    /// looks perfectly healthy while `.utility` is fully saturated. An earlier revision
    /// of this comment shipped that ~0.01s figure and concluded, wrongly, that the
    /// vehicle didn't matter.
    private static func brewInfoOffActor(name: String) async -> Info? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Info?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.brewInfo(name: name))
            }
        }
    }

    /// Read `homepage` + `urls.stable.url` for one formula from `brew info
    /// --json=v2` — local, no network, authoritative for the installed formula.
    private static func brewInfo(name: String) -> Info? {
        guard let brew = HomebrewInstaller.brewPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        // `--` terminates option parsing so a name can never be misread as a flag.
        process.arguments = ["info", "--json=v2", "--formula", "--", name]
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formula = (root["formulae"] as? [[String: Any]])?.first
        else { return nil }
        let homepage = (formula["homepage"] as? String).flatMap { URL(string: $0) }
        let stable = ((formula["urls"] as? [String: Any])?["stable"] as? [String: Any])?["url"] as? String
        return Info(homepage: homepage, stableURL: stable)
    }

    // MARK: - GitHub derivation

    struct GitHubRef: Equatable { let owner: String; let repo: String; let tag: String }

    /// Pull (owner, repo, tag) out of a formula's stable source URL. Handles the two
    /// GitHub forms Homebrew uses:
    ///   …/releases/download/<tag>/asset            (release asset)
    ///   …/archive/refs/tags/<tag>.tar.gz           (source tarball; also bare /archive/<tag>…)
    /// The tag is taken from the URL, NOT the formula version — some tags are
    /// prefixed (e.g. azure-cli's `azure-cli-2.87.0`).
    static func deriveGitHub(fromStableURL url: String?) -> GitHubRef? {
        guard let url else { return nil }
        let patterns = [
            #"github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/"#,
            #"github\.com/([^/]+)/([^/]+)/archive/(?:refs/tags/)?(.+?)\.(?:tar\.(?:gz|xz|bz2)|zip|tgz)$"#,
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(url.startIndex..., in: url)
            guard let m = re.firstMatch(in: url, range: range), m.numberOfRanges == 4,
                  let oR = Range(m.range(at: 1), in: url),
                  let rR = Range(m.range(at: 2), in: url),
                  let tR = Range(m.range(at: 3), in: url)
            else { continue }
            var repo = String(url[rR])
            if repo.hasSuffix(".git") { repo.removeLast(4) }
            return GitHubRef(owner: String(url[oR]), repo: repo, tag: String(url[tR]))
        }
        return nil
    }

    private static func encode(_ tag: String) -> String {
        tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
    }

    // MARK: - GitHub release fetch

    private struct Release { let body: String?; let htmlURL: URL?; let publishedAt: String? }

    private func fetchRelease(owner: String, repo: String, tag: String, token: String?) async throws -> Release? {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(Self.encode(tag))"
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.countedData(for: request, purpose: .catalog)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil  // 404 = tag has no GitHub release; treat as "no structured notes"
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Release(
            body: obj["body"] as? String,
            htmlURL: (obj["html_url"] as? String).flatMap { URL(string: $0) },
            publishedAt: obj["published_at"] as? String
        )
    }
}
