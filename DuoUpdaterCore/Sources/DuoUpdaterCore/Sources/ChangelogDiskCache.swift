import CryptoKit
import Foundation

/// On-disk, cross-launch cache of parsed changelogs, keyed by app + channel +
/// version. Complements the in-memory ``ChangelogCache`` (15-min TTL, keyed by
/// page URL, cleared on every refresh): this layer **persists** and is keyed by
/// the *version* whose notes it holds.
///
/// The keying exploits an invariant the user pointed out: a released version's
/// changelog never changes. So an entry for `version` is treated as immutable —
/// once cached we can serve it instantly on the next launch, and the periodic
/// pre-warm can skip the network entirely for versions we already hold. When a new
/// version ships the *key* changes, so the new notes are fetched fresh; the prior
/// version's entry stays valid (and is pruned, since only the newest is shown).
///
/// That immutability has a precondition the keying can't check for itself: the
/// page has to have *published* the version it is being filed under. A vendor's
/// feed and their changelog page go out separately, and the feed goes first —
/// CleanShot X twice, from one appcast (5.0 on 2026-09-01, the page 6 minutes
/// behind our fetch; 5.0.1 on 2026-09-18, 9 minutes). Both timings are our
/// request time against the page's own `last-modified`, and both are written
/// down in docs/app-audits/pl-maketheweb-cleanshotx.md. Filed as immutable, such a
/// snapshot is frozen for good: the key never changes again, so no later fetch is
/// ever made for it, and the window shows the new version's number over the
/// previous version's notes with nothing logged and nothing to retry. Entries like
/// that are stored and served, but as PROVISIONAL: past ``provisionalWindow`` the
/// hit carries `needsReread`, which is a request for a fetch and never a reason to
/// withhold the notes — see ``Hit``.
///
/// `fetchedAt` is read back for one thing only: ``provisionalWindow``, the age at
/// which an entry whose page did not carry its own key version asks to be read
/// again. It is NOT a
/// freshness policy for the cache at large — an entry whose page does carry its
/// version never expires, however old, and the invalidation problem an age policy
/// would otherwise be reached for is `parserGeneration`'s job (below), which is
/// the exact-match answer rather than the approximate one; see its doc comment for
/// why a TTL was rejected there. It also remains useful the way a log line's
/// timestamp is: reading a support bundle's cache directory and seeing how old an
/// entry is says something on its own.
///
/// A released version's *notes* never change, but what THIS APP extracts from them
/// can — a parser fix. `Stored.parserGeneration` (below) is what that side of
/// invalidation runs on: not a TTL (which would either miss entries a parser
/// change never touched, or fail to catch ones it did), but an exact match against
/// `Changelog.parserGeneration`, treating any mismatch as a miss.
///
/// Thread-safe via actor isolation. Best-effort throughout: any I/O failure is
/// swallowed (a miss just falls through to the network), never thrown.
public actor ChangelogDiskCache {

    /// Shared instance — written by ``ChangelogService`` on every successful load,
    /// read by the workbench for instant first paint.
    public static let shared = ChangelogDiskCache()

    /// Identity of one cached changelog: the app, its channel, and the version the
    /// notes describe. Mirrors the workbench's in-memory `ChangelogCacheKey`.
    public struct Key: Hashable, Sendable {
        public let bundleID: String
        public let channel: String
        public let version: String
        /// The feed-resolved page the notes were parsed from, for a
        /// `ChangelogRecipe.feedPagePattern` recipe; nil for every other recipe,
        /// whose file name is unchanged by this field.
        ///
        /// Such a page depends on the reader's language as well as the version
        /// (#557). Without it here, a reader who switched language would be
        /// served the old language's notes from disk on every launch, because
        /// released notes are treated as immutable and never expire.
        public let page: URL?
        public init(bundleID: String, channel: String, version: String, page: URL? = nil) {
            self.bundleID = bundleID
            self.channel = channel
            self.version = version
            self.page = page
        }
    }

    /// Non-optional and undefaulted on purpose. An entry written before this field
    /// existed has no `parserGeneration` key at all, and there is no "generation
    /// zero" that would honestly describe what parsed it — so it can't be assigned
    /// one and compared; it can only be treated as unknown. Decoding it as `Stored`
    /// throws, `get` below already turns that throw into a miss (same as any other
    /// corrupt/unreadable file), and a miss is exactly the outcome we want for a
    /// pre-generation entry: we have no idea whether it matches current output, so
    /// don't serve it. See `ChangelogDiskCache` and `Changelog.parserGeneration`'s
    /// doc comments for why a mismatch is a miss rather than a TTL.
    ///
    /// This doesn't leak an unbounded pile of undecodable files: `set` still
    /// overwrites this exact key's file the next time this version is fetched, and
    /// `pruneSiblings` deletes every *other*-version file for the app+channel on
    /// every successful write regardless of whether it was decodable — the on-disk
    /// footprint stays bounded to ~one file per channel, same as before this field
    /// existed.
    private struct Stored: Codable {
        let changelog: Changelog
        let fetchedAt: Date
        let parserGeneration: Int
    }

    /// How long an entry whose page did NOT carry its own key version is taken at
    /// face value before a hit starts asking for a re-read.
    ///
    /// Such an entry is a snapshot of a page that had not published this version
    /// yet (see the type's doc comment). It is still the best notes we have — the
    /// previous release's, which is what the vendor's page was showing at that
    /// moment — so it is stored and painted rather than thrown away; what it must
    /// not do is outlive the vendor catching up. Past this window the entry is
    /// still returned and still painted, with ``Hit/needsReread`` set: the caller
    /// fetches *as well*, and a fetch that fails changes nothing on screen. An
    /// age that withheld the notes instead would make a cold offline launch
    /// strictly worse than no window at all, for the ~quarter of entries this
    /// applies to — most of which (a vendor who numbers notes coarsely) were never
    /// behind in the first place. A fetch that lands rewrites the entry, which
    /// either carries the version now (immutable from then on) or renews the
    /// window.
    ///
    /// Six hours is picked against the cost of being wrong in each direction. Too
    /// long and the user reads the previous release's notes under the new
    /// release's number, the failure this window exists to bound; too short and
    /// every app whose vendor numbers or publishes more slowly than they ship
    /// re-fetches on a loop. The second cost is the one that decided the number:
    /// on the cache it was sized against, about a quarter of the entries were
    /// provisional, which at four windows a day roughly doubles the app's daily
    /// changelog traffic (`duo events --purpose changelog` counts today's). Pages
    /// are tens of KB, and each of those reads is the one this layer was invented
    /// to skip rather than an extra request on top.
    ///
    /// claim-lint:allow-machine-state — "about a quarter" is a ratio over one
    /// machine's cached entries on 2026-09-18 (16 of 61 judgeable), reported as
    /// the sizing measurement itself rather than as evidence about any app. What a
    /// reader can re-derive is their own ratio, which is the point: the window is
    /// a trade against how many of THEIR apps read as behind.
    static let provisionalWindow: TimeInterval = 6 * 3600

    let directory: URL   // internal: asserted by DuoStateDirectoryTests
    /// In-memory mirror so repeated opens within a session don't re-read the file.
    private var memory: [Key: Changelog] = [:]

    /// `directory` defaults to `~/Library/Application Support/com.duoupdater.app/changelogs`
    /// — the same container the traffic and backup stores use. Overridable for tests.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = DuoStateDirectory.base
                .appendingPathComponent("com.duoupdater.app", isDirectory: true)
                .appendingPathComponent("changelogs", isDirectory: true)
        }
    }

    // MARK: - Public interface

    /// What the cache holds for one key: the notes, and whether the page they came
    /// from has anything left to prove.
    public struct Hit: Sendable, Equatable {
        public let changelog: Changelog
        /// True when this entry is provisional — its page never carried
        /// `key.version` — and older than ``provisionalWindow``.
        ///
        /// A request for a fetch, not a reason to hold the notes back. The caller
        /// paints `changelog` either way and reads the page in addition; if that
        /// read fails, what is on screen is what was already the best available.
        public let needsReread: Bool
    }

    /// The cached changelog for `key`, or nil if we've never stored this exact
    /// version's notes UNDER THE RUNNING BUILD'S PARSER GENERATION. The age of a
    /// provisional entry is reported through ``Hit/needsReread``, never by
    /// withholding it — see ``provisionalWindow``.
    ///
    /// Checks the in-memory mirror first (which — see `set` and the generation
    /// check below — can only ever hold current-generation entries that carry
    /// their own version, so it needs no check of its own), then the file, where a
    /// generation mismatch is a miss: same treatment as a missing or corrupt file,
    /// never written into `memory`. See `Changelog.parserGeneration`'s doc comment
    /// for why that exists.
    public func hit(for key: Key) -> Hit? {
        if let mirrored = memory[key] { return Hit(changelog: mirrored, needsReread: false) }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.parserGeneration == Changelog.parserGeneration
        else { return nil }
        guard stored.changelog.carries(version: key.version) else {
            // Provisional, so it answers from the file every time and never enters
            // the mirror: the mirror has no age of its own, and this app is left
            // running for days — mirrored, a provisional entry would read as fresh
            // for the rest of the session and the window would only ever pass
            // across a relaunch. Decoding one small file per pre-warm or open is
            // what that costs.
            let aged = Date().timeIntervalSince(stored.fetchedAt) >= Self.provisionalWindow
            return Hit(changelog: stored.changelog, needsReread: aged)
        }
        memory[key] = stored.changelog
        return Hit(changelog: stored.changelog, needsReread: false)
    }

    /// The notes alone, for a caller with nothing to do about a re-read.
    public func get(for key: Key) -> Changelog? { hit(for: key)?.changelog }

    /// Persist `changelog` as the notes for `key`, stamped with the running build's
    /// `Changelog.parserGeneration`, and drop any older-version files for the same
    /// app+channel (only the newest version is ever displayed, so a stale sibling
    /// is dead weight — this also bounds the on-disk footprint when it deletes a
    /// sibling written by an older, undecodable generation; see `Stored`'s doc
    /// comment). Best-effort; a write failure is logged and otherwise ignored — the
    /// network path still served the caller.
    public func set(_ changelog: Changelog, for key: Key) {
        // Mirrored only when the page carried the version — see `get` for why a
        // provisional entry must keep answering from the file.
        if changelog.carries(version: key.version) { memory[key] = changelog }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(
                Stored(changelog: changelog, fetchedAt: .now, parserGeneration: Changelog.parserGeneration))
            try data.write(to: fileURL(for: key), options: .atomic)
            pruneSiblings(of: key)
        } catch {
            Log.source.debug("changelog disk cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internals

    /// Delete on-disk entries that share `key`'s app+channel prefix but a different
    /// version, and forget them in memory. Keeps the cache to ~one file per channel.
    private func pruneSiblings(of key: Key) {
        let keep = fileURL(for: key).lastPathComponent
        let prefix = prefixToken(bundleID: key.bundleID, channel: key.channel)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) && name != keep {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        memory = memory.filter { $0.key == key
            || prefixToken(bundleID: $0.key.bundleID, channel: $0.key.channel) != prefix }
    }

    private func fileURL(for key: Key) -> URL {
        // A digest, not the sanitized URL: a URL can outrun a file name's length
        // limit, and sanitizing is lossy (`/` and `?` both become `_`), so two
        // pages could share a name.
        let page = key.page.map {
            "__" + SHA256.hash(data: Data($0.absoluteString.utf8))
                .prefix(8).map { String(format: "%02x", $0) }.joined()
        } ?? ""
        let name = prefixToken(bundleID: key.bundleID, channel: key.channel)
            + sanitize(key.version) + page + ".json"
        return directory.appendingPathComponent(name)
    }

    /// The filename prefix shared by every version of one app+channel: used both to
    /// build a key's filename and to find its siblings for pruning.
    private func prefixToken(bundleID: String, channel: String) -> String {
        sanitize(bundleID) + "__" + sanitize(channel) + "__"
    }

    /// Map an arbitrary string to a filesystem-safe token (shared rule — see
    /// ``String/filesystemSafeToken``).
    private func sanitize(_ raw: String) -> String { raw.filesystemSafeToken }
}
