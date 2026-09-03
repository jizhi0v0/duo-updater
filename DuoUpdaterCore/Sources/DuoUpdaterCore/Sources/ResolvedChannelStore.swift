import Foundation

/// What a source PROVED about an installed copy's release channel, kept across
/// checks and restarts.
///
/// Exists for apps whose bundle cannot name its own channel — UTM being the
/// measured case: Stable and Beta share the bundle id, the app name, the Team ID,
/// plain numeric versions and the literal `UTM.dmg` asset, so
/// `ReleaseChannel.detect()` can only say "stable" and
/// `InstalledApp.channelIsAuthoritative` is false. The only discriminator lives
/// upstream, in the GitHub release record for the exact installed tag.
///
/// Two problems follow from that evidence being remote, and this store is the
/// answer to both:
///
///   * **It disappears on a bad network.** `UpdateChecker` returns
///     `remote: nil` for `.error` and `.unknown`, so a channel carried only on
///     `RemoteVersion` evaporates with it: the row's Beta badge vanishes (making
///     it read as an ordinary stable row) and `ChangelogCacheKey` flips from
///     `:beta` to `:stable`, missing the notes already cached under the right
///     key. Reading the proof from here instead keeps the row's identity stable
///     across a failed check.
///   * **Re-proving it costs a request every time.** The exact-tag lookup is an
///     extra `/releases/tags/…` call on top of the version probe, and on the
///     unauthenticated 60/hour budget that is a real cost for something that
///     changes only when the app on disk changes.
///
/// Keyed by **install path** (`InstalledApp.id`), not bundle id: two copies of
/// one app can be installed at once on different channels, and on the machine
/// this was developed against that is exactly the case — `/Applications/UTM.app`
/// at 5.0.5 (Beta) alongside `~/Applications/UTM.app` at 4.7.5 (Stable), both
/// surviving `AppScanner.dedupeIdenticalInstalls` because their versions differ.
/// A bundle-id key would let those two rows overwrite each other's channel and
/// make the badge depend on which was checked last.
///
/// An entry is only honoured while BOTH version strings still match the copy on
/// disk. Marketing alone would not do: an app that ships several builds under one
/// marketing string would keep a stale proof across an update that really did
/// change trains.
public actor ResolvedChannelStore {

    /// The instance the app and CLI share. Tests construct their own against a
    /// temp file; nothing defaults to this implicitly, so a test that forgets to
    /// inject one gets no persistence rather than a write into the real file.
    public static let shared = ResolvedChannelStore()

    struct Entry: Codable, Sendable, Equatable {
        var shortVersion: String?
        var buildVersion: String?
        var channel: String
        /// Never read — kept because this file is the only place a human can look
        /// to see what was decided about a copy and when, and a proof with no
        /// timestamp is not diagnosable. There is deliberately no expiry: the
        /// entry is scoped to an exact version, so it stops applying the moment
        /// that copy changes rather than after some interval.
        var provenAt: Date
    }

    private var entries: [String: Entry]
    private let fileURL: URL
    private var dirty = false

    /// - Parameter fileURL: defaults to
    ///   `~/Library/Application Support/com.duoupdater.app/resolved-channels.json`,
    ///   beside `releases.json` and `traffic.json`.
    public init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.entries = Self.load(from: url)
    }

    /// The proven channel for this exact copy, or nil when nothing was proven or
    /// the copy on disk has since changed version.
    public func channel(for app: InstalledApp) -> ReleaseChannel? {
        guard let entry = entries[app.id],
              entry.shortVersion == app.shortVersion,
              entry.buildVersion == app.buildVersion
        else { return nil }
        return ReleaseChannel(rawValue: entry.channel)
    }

    /// Record what a source proved. Writes are batched behind ``flush()`` the
    /// same way `ReleaseTimelineStore` batches its own: a check pass touches this
    /// once per app, and re-encoding the whole file each time would be a full
    /// write per row for information that rarely changes.
    public func record(_ channel: ReleaseChannel, for app: InstalledApp) {
        let entry = Entry(
            shortVersion: app.shortVersion, buildVersion: app.buildVersion,
            channel: channel.rawValue, provenAt: Date())
        guard entries[app.id] != entry else { return }
        entries[app.id] = entry
        dirty = true
    }

    /// Drop what we knew about a copy — used when the proof could not be
    /// re-established, so a stale channel can't outlive the evidence for it.
    public func forget(_ app: InstalledApp) {
        guard entries.removeValue(forKey: app.id) != nil else { return }
        dirty = true
    }

    /// Clears `dirty` only once the bytes are on disk: an unwritable directory
    /// or a full volume would otherwise drop the proof silently AND make the next
    /// flush a no-op, so the file would stay stale until the app was restarted.
    public func flush() {
        guard dirty else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch {
            Log.source.error(
                "resolved-channels: could not write \(self.fileURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A synchronous read of the shared file, for callers that cannot await —
    /// `duo verify`'s app scan runs on a plain `Thread` (see the comment on
    /// `installedVersions`, and why it must stay abandonable).
    ///
    /// Read-only by construction: it re-reads the file rather than touching the
    /// actor's state, so it can neither race a write nor become a second place
    /// that decides what is stored.
    public nonisolated static func provenChannelSnapshot(
        for app: InstalledApp, in snapshot: Snapshot
    ) -> ReleaseChannel? {
        guard let entry = snapshot.entries[app.id],
              entry.shortVersion == app.shortVersion,
              entry.buildVersion == app.buildVersion
        else { return nil }
        return ReleaseChannel(rawValue: entry.channel)
    }

    /// One read of the file, to be consulted for many apps — `duo verify` asks
    /// about every installed app in one pass, and re-reading per app would be a
    /// hundred-odd file reads for a dictionary that cannot change mid-scan.
    public struct Snapshot: Sendable {
        fileprivate let entries: [String: Entry]
        public init(fileURL: URL? = nil) {
            self.entries = ResolvedChannelStore.load(from: fileURL ?? defaultFileURL())
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("resolved-channels.json")
    }

    /// Drops entries whose bundle is no longer there on the way in, so a file
    /// shared by every app on the machine cannot grow without bound as copies are
    /// moved, renamed or deleted. A corrupt or hand-edited file decodes to
    /// nothing, which costs one re-proof per copy and nothing else.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded.filter { FileManager.default.fileExists(atPath: $0.key) }
    }
}
