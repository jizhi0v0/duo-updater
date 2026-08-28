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
/// `fetchedAt` is recorded for diagnostics / future age-based policy; freshness of
/// the "open window" stale-while-revalidate path is driven by the model + the
/// in-memory cache, not by a TTL here.
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
        public init(bundleID: String, channel: String, version: String) {
            self.bundleID = bundleID
            self.channel = channel
            self.version = version
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

    /// The cached changelog for `key`, or nil if we've never stored this exact
    /// version's notes UNDER THE RUNNING BUILD'S PARSER GENERATION. Checks the
    /// in-memory mirror first (which — see `set` and the generation check below —
    /// can only ever hold current-generation entries, so it needs no check of its
    /// own), then the file, where a generation mismatch is a miss: same treatment
    /// as a missing or corrupt file, never written into `memory`. See
    /// `Changelog.parserGeneration`'s doc comment for why this exists.
    public func get(for key: Key) -> Changelog? {
        if let hit = memory[key] { return hit }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.parserGeneration == Changelog.parserGeneration
        else { return nil }
        memory[key] = stored.changelog
        return stored.changelog
    }

    /// Persist `changelog` as the notes for `key`, stamped with the running build's
    /// `Changelog.parserGeneration`, and drop any older-version files for the same
    /// app+channel (only the newest version is ever displayed, so a stale sibling
    /// is dead weight — this also bounds the on-disk footprint when it deletes a
    /// sibling written by an older, undecodable generation; see `Stored`'s doc
    /// comment). Best-effort; a write failure is logged and otherwise ignored — the
    /// network path still served the caller.
    public func set(_ changelog: Changelog, for key: Key) {
        memory[key] = changelog
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
        let name = prefixToken(bundleID: key.bundleID, channel: key.channel)
            + sanitize(key.version) + ".json"
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
