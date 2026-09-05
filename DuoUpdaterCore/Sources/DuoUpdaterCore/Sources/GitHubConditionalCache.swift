import Foundation
import CryptoKit

/// Persisted validators (`Last-Modified`, `ETag`) + raw response body for
/// `GitHubReleasesSource`'s two registry-driven endpoints (`/releases/latest`
/// and `/releases?per_page=<listPageSize>`), and the conditional GET built
/// from them.
///
/// ## Why this exists, and why `Last-Modified` comes first
///
/// `URLSession.updates`' own `URLCache` was measured (not assumed) to almost
/// never get a 304 for these endpoints: over 36 five-minute rounds on
/// 2026-09-05, 1348 full 200s against 347 304s across `/releases/latest` for
/// 49 repos, and 197 against 12 for the 7 `/releases?per_page=N` repos. Per
/// repo it tracks popularity — VSCodium 34 × 200 / 0 × 304, an obscure repo
/// 14 / 20 — and the reason is in the body: **GitHub's `ETag` is a hash of the
/// response, and the response carries `assets[].download_count`.** Two fetches
/// of VSCodium's `/latest` 240 s apart differed in exactly four
/// `download_count` values and nothing else, and had different `ETag`s. Any
/// repo people actually download from mints a new `ETag` every few minutes, so
/// `If-None-Match` is worthless precisely where the bytes are.
///
/// `Last-Modified` is the release's own timestamp (it matched `updated_at`,
/// not the download counters) and `/releases/latest` honours
/// `If-Modified-Since` against it — measured the same minute the `ETag` had
/// just rotated:
///
///     If-None-Match: <ETag from 4 min ago>                 → 200, full body
///     If-Modified-Since: <Last-Modified as served>         → 304
///     If-None-Match: <stale> + If-Modified-Since: <valid>  → 200, full body
///     If-Modified-Since: <Last-Modified minus 1 s>         → 200
///
/// The third line is why this type exists instead of trusting `URLCache`:
/// RFC 7232 §6 says a server evaluates `If-None-Match` first and ignores
/// `If-Modified-Since` when both are present, GitHub does exactly that, and
/// `URLCache` revalidation sends both whenever it holds both. So the rule
/// `Validator.conditionalHeaders` encodes is: **when the stored response had a
/// `Last-Modified`, send `If-Modified-Since` and nothing else; only a response
/// that had no `Last-Modified` at all is revalidated by `ETag`.** The list
/// endpoint is the second case — it sends no `Last-Modified` and answers
/// `If-Modified-Since` with 200 for any date (measured) — so its `ETag` is
/// kept as the only validator it has, which still buys a 304 for repos whose
/// counters sit still. The request that carries one of these validators also
/// bypasses `URLCache` (`.reloadIgnoringLocalCacheData`) so the cache cannot
/// add its own `If-None-Match` back on top. Issue #357 has the full
/// measurement.
///
/// GitHub confirms a 304 from a *correctly authenticated* conditional request
/// does not spend the primary rate limit:
/// <https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api>
/// ("Making a conditional request does not count against your primary rate
/// limit if a `304` response is returned and the request was made while
/// correctly authorized with an `Authorization` header. […] each `304 Not
/// Modified` response is fast and does not use your rate limit, making
/// conditional requests especially useful when polling an endpoint.") — matches
/// what was measured locally (`x-ratelimit-used` did not advance across a 304).
///
/// ## What is deliberately NOT here
///
/// - **The `/releases/tags/<tag>` channel-discovery lookup.** That endpoint is
///   minted per *installed version* (`GitHubReleasesSource.ruleFromInstalledRelease`),
///   not per registry rule — there is no fixed, enumerable set of tag URLs to
///   prune against the way there is for `/latest` and the list endpoint, so
///   caching it would accumulate one-off entries forever instead of staying
///   bounded. It is also not the endpoint the measurement above is about: a
///   proven channel is already remembered by `ResolvedChannelStore` and the tag
///   lookup runs at most once per version change, not once per check round. See
///   `GitHubReleasesSource.fetchReleases` for where this is enforced (the
///   conditional path is skipped whenever `tag != nil`).
/// - **Parsed results.** Only the raw HTTP body is stored — see `Entry.body`.
public actor GitHubConditionalCache {

    /// The instance the app and CLI share. Like `ResolvedChannelStore.shared`,
    /// nothing defaults to this implicitly — `GitHubReleasesSource`'s own
    /// `validatorCache` parameter defaults to nil, so a test that constructs a
    /// source directly (the overwhelming majority of them) writes nothing to the
    /// real file. Only `SourceStack.make` and `duo verify`'s GitHub sweep wire
    /// this in.
    public static var shared: GitHubConditionalCache {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if let existing = sharedInstance { return existing }
        let created = GitHubConditionalCache()
        sharedInstance = created
        return created
    }
    /// Whether anything has touched `shared` in this process — so a CLI exit
    /// path can flush it without first loading a multi-megabyte file for a
    /// command that never made a GitHub request (`duo list`). Same shape as
    /// `EventStore.hasRecorded`, for the same reason.
    public static var hasShared: Bool {
        sharedLock.lock(); defer { sharedLock.unlock() }
        return sharedInstance != nil
    }
    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var sharedInstance: GitHubConditionalCache?

    /// One endpoint's cached validator, keyed by the endpoint URL string.
    ///
    /// ⚠️ `body` is the RAW HTTP response body — never a parsed `[Release]` or
    /// any other derived conclusion. Storing a conclusion would mean a rule
    /// whose `versionPattern`/`installAssetPattern` changed keeps answering with
    /// the OLD verdict for as long as GitHub's `ETag` stays unchanged (which can
    /// be weeks) — recipe fixes would look like they "didn't take". Re-parsing
    /// the stored body on every 304 is what `GitHubReleasesSource.fetchReleases`
    /// does, and it is the entire reason this file exists in this shape.
    struct Entry: Codable, Sendable {
        /// Both optional so a file written before `lastModified` existed (and
        /// a response missing either header) still decodes; `store` refuses an
        /// entry that has neither, so a decoded entry always has at least one.
        var etag: String?
        var lastModified: String?
        var body: Data
        /// A stable, non-reversible fingerprint of the credential this entry was
        /// fetched with — see `authFingerprint(_:)`. NEVER the token itself:
        /// this file lives on disk indefinitely, unlike the in-memory-only
        /// `URLCache` this replaces. GitHub hands out a different `ETag` to an
        /// authenticated vs. an anonymous request for the same resource
        /// (measured), so an entry fetched under one credential is simply wrong
        /// evidence for another — `validator(for:authFingerprint:)` refuses to
        /// return it across a mismatch rather than risk serving a body scoped to
        /// someone else's rate limit or visibility.
        var authFingerprint: String
        /// When the 200 this entry holds was received. Load-bearing, not
        /// diagnostics: `validator(for:authFingerprint:)` refuses an entry older
        /// than `maxAge`, and a 304 does NOT refresh it — see `maxAge`.
        var storedAt: Date
    }

    /// How long a stored 200 may go on being revalidated before one full,
    /// unconditional fetch is forced.
    ///
    /// `If-Modified-Since` asks "has this changed since <date>", and GitHub
    /// answers it the RFC 7232 §3.3 way — measured 2026-09-05: a date one DAY
    /// after the release's `Last-Modified` is still a 304. So a
    /// `/releases/latest` that comes to point at an OLDER release (the newest
    /// one deleted, or re-marked prerelease) is "not modified since" our date
    /// too, and the stored body would keep offering the yanked release until
    /// something newer appeared. `URLCache`'s `If-None-Match` used to catch that
    /// case by accident, in the rounds it happened to 304 at all. A day bounds
    /// the staleness at ~one full body per endpoint per day — 59 endpoints,
    /// ~500 KB — against the ~50 full bodies a round this store removes.
    static let maxAge: TimeInterval = 24 * 60 * 60

    /// What `fetchReleases` needs to build a conditional request and to recover
    /// if the server actually answers 304.
    public struct Validator: Sendable {
        public let etag: String?
        public let lastModified: String?
        public let body: Data

        /// Every conditional header a request built from this validator sends
        /// — one, never both. See the type's doc comment for the measurement
        /// behind the order: a `Last-Modified` wins outright because sending
        /// the `ETag` alongside it makes GitHub ignore the date and compare the
        /// (download-count-churned) `ETag` instead.
        public var conditionalHeaders: [String: String] {
            if let lastModified { return ["If-Modified-Since": lastModified] }
            if let etag { return ["If-None-Match": etag] }
            return [:]
        }

        /// The header names this layer owns on a request, so the unconditional
        /// retry can strip exactly these and nothing else.
        public static let headerNames = ["If-Modified-Since", "If-None-Match"]
    }

    private var entries: [String: Entry]
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var dirty = false
    /// The pending coalesced write, if any — see `scheduleFlush()`.
    private var flushTask: Task<Void, Never>?

    /// - Parameter fileURL: defaults to
    ///   `DuoStateDirectory.base/com.duoupdater.app/github-conditional-cache.json`
    ///   — the same container `ChangelogDiskCache` and the traffic store use.
    ///   `DUO_STATE_DIR` redirects it like every other store, but nothing in
    ///   this repository sets that variable outside the tests: a `duo verify`
    ///   run from a terminal reads and writes the running app's copy. That is
    ///   acceptable here (both hold public release bodies under the same
    ///   credential; a mismatched fingerprint just costs one unconditional
    ///   round) and is stated rather than pretended away.
    /// - Parameter now: injectable clock so tests can age an entry past
    ///   `maxAge` without sleeping.
    public init(fileURL: URL? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.now = now
        self.entries = Self.load(from: url)
    }

    /// A stable, non-reversible identifier of "which credential" — never the
    /// token itself. Two tokens (or a token vs. no token) must never be treated
    /// as interchangeable: GitHub hands out a different `ETag` to an
    /// authenticated vs. an anonymous request for the same URL (measured), so a
    /// validator minted under one credential is not valid evidence under
    /// another — sending it as `If-None-Match` risks a 304 that silently
    /// resurrects a body fetched under a DIFFERENT identity (e.g. before a token
    /// was revoked and replaced, or when running without one at all).
    public static func authFingerprint(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "anonymous" }
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The validator to revalidate `endpoint` with, or nil when nothing is
    /// cached for this exact endpoint under this exact credential. Validators
    /// and body are read together as one `Entry` so a caller can never see a
    /// validator whose matching body has since been evicted or overwritten by
    /// a concurrent write — they are stored, and read, as one unit.
    public func validator(for endpoint: String, authFingerprint: String) -> Validator? {
        guard let entry = entries[endpoint], entry.authFingerprint == authFingerprint else {
            return nil
        }
        // Older than a day → no validator → the caller fetches unconditionally
        // and `store` restamps it. See `maxAge` for the yanked-release case this
        // bounds.
        guard now().timeIntervalSince(entry.storedAt) < Self.maxAge else { return nil }
        return Validator(etag: entry.etag, lastModified: entry.lastModified, body: entry.body)
    }

    /// Persist a fresh 200's validators + raw body for `endpoint` under this
    /// credential, replacing whatever (if anything) was there — including an
    /// entry stored under a different credential, which this simply overwrites
    /// rather than trying to keep both around. A response with neither
    /// validator is not stored: there would be nothing to revalidate with, and
    /// an entry that can only ever miss is a body kept on disk for no reason.
    public func store(
        endpoint: String, authFingerprint: String,
        etag: String?, lastModified: String?, body: Data
    ) {
        guard etag != nil || lastModified != nil else { return }
        entries[endpoint] = Entry(
            etag: etag, lastModified: lastModified, body: body,
            authFingerprint: authFingerprint, storedAt: now())
        dirty = true
        scheduleFlush()
    }

    /// Coalesce a round's writes into one. Every 2xx used to `flush()` on the
    /// spot, and a flush re-encodes the whole dictionary (3.4 MB of raw bodies
    /// → base64) and atomically rewrites the ~4.6 MB file — measured on this
    /// machine's store, 59 entries. Steady state is 4–6 × 200 a round (the
    /// list endpoints, whose `ETag` churns), i.e. ~25 MB of writes every five
    /// minutes; a cold round did it 59 times. `ReleaseTimelineStore` batched
    /// exactly this pattern for exactly this reason. Two seconds is longer
    /// than the gap between one round's fetches and shorter than anything a
    /// user waits for; a process that exits inside the window loses at most
    /// that round's memos, which cost one unconditional fetch each next time —
    /// the `duo` CLI, which exits after one run, flushes explicitly before it
    /// does (`duo verify` at the end of its sweep, every other subcommand at
    /// exit beside the event store's flush).
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flushScheduled()
        }
    }

    private func flushScheduled() {
        // `flush()` cancels a pending task, but `try? await Task.sleep` returns
        // early on cancellation instead of throwing out of the task, so a
        // cancelled task still reaches this line. It must not touch the handle
        // of whatever task was scheduled after it, nor write again.
        guard !Task.isCancelled else { return }
        flushTask = nil
        flush()
    }

    /// Drop every entry whose endpoint is not in `validEndpoints` — the set of
    /// `/latest` and `/releases?per_page=<listPageSize>` URLs the CURRENT registry can
    /// still ask for. Without this, a repo whose rule is deleted (renamed app,
    /// retired recipe) leaves its entry behind forever, since nothing else ever
    /// revisits that URL to notice it's dead. Bounded by construction: the set
    /// this is pruned against has two entries per registered rule, three for a
    /// rule that probes (`GitHubReleasesSource.validNonTagEndpoints`).
    public func prune(keeping validEndpoints: Set<String>) {
        let before = entries.count
        entries = entries.filter { validEndpoints.contains($0.key) }
        if entries.count != before { dirty = true; scheduleFlush() }
    }

    /// Write now. Clears `dirty` only once the bytes are actually on disk —
    /// same reasoning as `ResolvedChannelStore.flush()`: an unwritable
    /// directory or full volume must not silently drop the write AND make the
    /// next flush a no-op. Writes are normally coalesced by `scheduleFlush()`;
    /// call this directly when the process is about to exit.
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard dirty else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch {
            Log.source.error(
                "github-conditional-cache: could not write \(self.fileURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    static func defaultFileURL() -> URL {
        DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("github-conditional-cache.json")
    }

    /// A corrupt or hand-edited file decodes to nothing — costs one full,
    /// unconditional fetch per affected endpoint and nothing else. Never thrown.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }
}
