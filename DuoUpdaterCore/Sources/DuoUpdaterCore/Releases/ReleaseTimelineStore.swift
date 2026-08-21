import Foundation

/// Persistent, per-app log of every release we've *seen announced*, built up over
/// time from the version checks. Where `TrafficStore` records what we downloaded,
/// this records what the vendors published — a release history that survives
/// restarts and, over time, reveals each app's release cadence and habits.
///
/// Only releases that arrive with a trustworthy vendor timestamp are recorded
/// (Sparkle `<pubDate>`, GitHub/Alcove `published_at`). Sources that can't supply
/// an honest release date (vendor probes reading a redirect URL, the App Store,
/// Homebrew) pass `publishedAt == nil` and are silently skipped — far better an
/// empty timeline than one polluted with our own polling timestamps masquerading
/// as release moments.
///
/// An `actor` so concurrent checks (many apps at once) can record without racing
/// on the in-memory map or the file write.
public actor ReleaseTimelineStore {

    /// In-memory state, keyed by `AppReleaseTimeline.appID` (the app's path).
    private var timelines: [String: AppReleaseTimeline]
    private let fileURL: URL

    /// What we last saw a detection-only source report for an app: the version and
    /// the time of that check. The baseline `observeForChange` measures against to
    /// bound an estimated release window. Persisted separately so adding it needs
    /// no migration of the releases file.
    private struct Observation: Codable, Sendable {
        var version: String
        var lastSeenAt: Date
    }
    private var observations: [String: Observation]
    private let observationsURL: URL

    /// Whether each file has unpersisted changes. Writes are **batched**: `record`
    /// and `observeForChange` are called once per app per check — dozens to hundreds
    /// of times in a burst — and each used to do a full JSON encode plus an atomic
    /// (write-temp-then-rename) write of the *entire* file. `observeForChange` was
    /// the worst: its `defer` fired even on the "nothing changed" path, so a steady-
    /// state check rewrote the observations file once per detection-only app while
    /// recording no new information at all. Callers now mark state dirty here and
    /// call ``flush()`` once when the batch is done.
    private var timelinesDirty = false
    private var observationsDirty = false

    /// - Parameter fileURL: where to persist the timeline. Defaults to
    ///   `~/Library/Application Support/com.duoupdater.app/releases.json`; the
    ///   detection baselines sit beside it as `release-observations.json`. Tests
    ///   pass a temp path so they never touch the real files.
    public init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.observationsURL = url.deletingLastPathComponent()
            .appendingPathComponent("release-observations.json")
        self.timelines = Self.load(from: url)
        self.observations = Self.loadObservations(from: observationsURL)
    }

    /// Record one observed release. No-op when `publishedAt` is nil (the source
    /// gave no trustworthy date) or when we've already recorded this version for
    /// this app — each version is logged exactly once, at first sighting, so
    /// re-checks don't pile up duplicates or drift the recorded `detectedAt`.
    /// Duplicate sightings may still refresh the timeline's display metadata.
    ///
    /// - Returns: true if this call added a new event (a release we hadn't seen).
    @discardableResult
    public func record(
        appID: String,
        appName: String,
        bundleID: String?,
        version: String?,
        sourceName: String,
        publishedAt: Date?,
        detectedAt: Date = Date()
    ) -> Bool {
        guard let publishedAt else { return false }
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return false }

        var timeline = timelines[appID] ?? AppReleaseTimeline(
            appID: appID, appName: appName, bundleID: bundleID
        )
        // Keep display fields current — the app may have been renamed since an
        // earlier event was recorded.
        let displayFieldsChanged = timeline.appName != appName || timeline.bundleID != bundleID
        timeline.appName = appName
        timeline.bundleID = bundleID

        // Already logged this version? Nothing to do — first sighting wins.
        guard !timeline.events.contains(where: { $0.version == version }) else {
            // Persist the refreshed name/bundle even when no event was added.
            timelines[appID] = timeline
            if displayFieldsChanged { timelinesDirty = true }
            return false
        }

        let event = ReleaseEvent(
            version: version,
            publishedAt: publishedAt,
            detectedAt: detectedAt,
            sourceName: sourceName
        )
        timeline.events.append(event)
        timeline.events.sort { $0.timestamp < $1.timestamp }
        timelines[appID] = timeline

        timelinesDirty = true
        Log.app.info("release-log: \(appName, privacy: .public) \(version, privacy: .public) published \(publishedAt, privacy: .public) via \(sourceName, privacy: .public)")
        return true
    }

    /// Track a detection-only source's reported version for an app and, when it
    /// *changes* from a previously-seen version, record an estimated release —
    /// dated to the window `[last time we saw the old version, now]`. The first
    /// time we ever see an app there's no baseline to measure against, so nothing
    /// is recorded; we just remember the version for next time.
    ///
    /// This is the approximate tier: use it for sources that report a version but
    /// no trustworthy date (vendor probes, Homebrew casks, the App Store). Call it
    /// every check — seeing the same version just tightens the lower bound.
    ///
    /// - Returns: true if this call recorded a new estimated release.
    @discardableResult
    public func observeForChange(
        appID: String,
        appName: String,
        bundleID: String?,
        version: String?,
        sourceName: String,
        now: Date = Date()
    ) -> Bool {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return false }

        let prior = observations[appID]
        // Display metadata can change while the reported version does not. Refresh
        // an existing timeline before the version guard so that rename-only checks
        // are still visible and persisted.
        if var timeline = timelines[appID] {
            let displayFieldsChanged = timeline.appName != appName || timeline.bundleID != bundleID
            timeline.appName = appName
            timeline.bundleID = bundleID
            timelines[appID] = timeline
            if displayFieldsChanged { timelinesDirty = true }
        }
        // Update the baseline first; we always remember the latest sighting.
        defer {
            observations[appID] = Observation(version: version, lastSeenAt: now)
            observationsDirty = true
        }

        // No baseline, or unchanged version → nothing to record (just (re)baseline
        // via the defer; an unchanged sighting tightens the lower bound for later).
        guard let prior, prior.version != version else { return false }

        // The version moved. The release happened sometime after we last confirmed
        // the old version and by the time we first saw the new one. Guard against a
        // clock skew that would invert the interval.
        let start = min(prior.lastSeenAt, now)
        let range = DateInterval(start: start, end: now)

        var timeline = timelines[appID] ?? AppReleaseTimeline(
            appID: appID, appName: appName, bundleID: bundleID
        )
        let displayFieldsChanged = timeline.appName != appName || timeline.bundleID != bundleID
        timeline.appName = appName
        timeline.bundleID = bundleID

        // Don't double-record a version already known (e.g. a trustworthy event
        // landed for it earlier, or a beta flapped back).
        guard !timeline.events.contains(where: { $0.version == version }) else {
            timelines[appID] = timeline
            if displayFieldsChanged { timelinesDirty = true }
            return false
        }

        let event = ReleaseEvent(
            version: version,
            estimatedRange: range,
            detectedAt: now,
            sourceName: sourceName
        )
        timeline.events.append(event)
        timeline.events.sort { $0.timestamp < $1.timestamp }
        timelines[appID] = timeline

        timelinesDirty = true
        Log.app.info("release-log: \(appName, privacy: .public) \(version, privacy: .public) estimated within \(range.duration, privacy: .public)s via \(sourceName, privacy: .public)")
        return true
    }

    /// Persist whatever the recording calls above marked dirty. Call once after a
    /// batch of `record`/`observeForChange` (the model does so at the end of each
    /// update check). A no-op when nothing changed, so an idle check costs no I/O.
    ///
    /// The window this opens — records held in memory until the batch ends — is
    /// bounded by one check's duration, and this is a best-effort observational log:
    /// losing a few seconds of it to a crash costs nothing a later check won't
    /// re-derive.
    public func flush() {
        if timelinesDirty {
            save()
            timelinesDirty = false
        }
        if observationsDirty {
            saveObservations()
            observationsDirty = false
        }
    }

    /// Per-app timelines, sorted by most-recent release first (apps that shipped
    /// recently float to the top); ties broken by name.
    public func snapshot() -> [AppReleaseTimeline] {
        timelines.values.sorted { a, b in
            let da = a.latest?.timestamp ?? .distantPast
            let db = b.latest?.timestamp ?? .distantPast
            if da != db { return da > db }
            return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
        }
    }

    /// Every recorded event across all apps, flattened and newest first — the
    /// global release feed, for a single chronological view.
    public func allEvents() -> [(timeline: AppReleaseTimeline, event: ReleaseEvent)] {
        timelines.values
            .flatMap { tl in tl.events.map { (tl, $0) } }
            .sorted { $0.event.timestamp > $1.event.timestamp }
    }

    /// Timeline for one app, or nil if it has never recorded a release.
    public func timeline(forAppID appID: String) -> AppReleaseTimeline? {
        timelines[appID]
    }

    /// Total number of recorded releases across every app.
    public func totalEvents() -> Int {
        timelines.values.reduce(0) { $0 + $1.events.count }
    }

    /// Clear all recorded history and remove the backing files.
    public func reset() {
        timelines = [:]
        observations = [:]
        // Drop any pending writes too — a later `flush` must not resurrect the
        // state we just deleted.
        timelinesDirty = false
        observationsDirty = false
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: observationsURL)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(timelines)
            // Atomic so a crash mid-write can't leave a truncated, unreadable file.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("release-log: failed to persist: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [String: AppReleaseTimeline] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: AppReleaseTimeline].self, from: data) else {
            Log.app.error("release-log: stored file unreadable; starting fresh")
            return [:]
        }
        return decoded
    }

    private func saveObservations() {
        do {
            let dir = observationsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(observations)
            try data.write(to: observationsURL, options: .atomic)
        } catch {
            Log.app.error("release-log: failed to persist observations: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadObservations(from url: URL) -> [String: Observation] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Observation].self, from: data)) ?? [:]
    }

    static func defaultFileURL() -> URL {   // internal: asserted by DuoStateDirectoryTests
        DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("releases.json")
    }
}
