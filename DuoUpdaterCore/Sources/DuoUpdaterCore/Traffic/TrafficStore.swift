import Foundation

/// Persistent, per-app record of update download traffic, tracked to the byte.
///
/// Every install that downloads through our own `Downloader` (Sparkle, Vendor,
/// GitHub, and pkg installers) reports the exact byte count it transferred; this
/// store accumulates those into a per-app total and an event history, and writes
/// the whole thing to a JSON file so the numbers survive app restarts.
///
/// Homebrew updates are deliberately *not* counted: `brew` performs that download
/// itself, so we never see those bytes and would only be able to guess. Counting
/// only what we actually measured keeps every recorded number exact.
///
/// An `actor` so concurrent installs (several apps updating at once) can record
/// without racing on the in-memory map or the file write.
public actor TrafficStore {

    /// In-memory state, keyed by `AppTrafficStat.appID` (the app's on-disk path).
    private var stats: [String: AppTrafficStat]
    private let fileURL: URL

    /// - Parameter fileURL: where to persist. Defaults to
    ///   `~/Library/Application Support/com.duoupdater.app/traffic.json`. Tests
    ///   pass a temp path so they never touch the real file.
    public init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.stats = Self.load(from: url)
    }

    /// Record the bytes downloaded for one app's update. Adds to the running
    /// total and appends an event. Persisted immediately so a crash mid-session
    /// can't lose a completed download's count.
    ///
    /// A non-positive `bytes` is ignored — we only ever record a real, measured
    /// transfer, never a zero placeholder that would inflate the update count.
    public func record(
        appID: String,
        appName: String,
        bundleID: String?,
        fromVersion: String?,
        toVersion: String?,
        sourceName: String?,
        bytes: Int64,
        date: Date = Date()
    ) {
        guard bytes > 0 else { return }

        let event = TrafficEvent(
            date: date,
            fromVersion: fromVersion,
            toVersion: toVersion,
            sourceName: sourceName,
            bytes: bytes
        )

        var stat = stats[appID] ?? AppTrafficStat(
            appID: appID, appName: appName, bundleID: bundleID
        )
        // Keep the display fields current — the app may have been renamed since
        // an earlier event was recorded.
        stat.appName = appName
        stat.bundleID = bundleID
        stat.totalBytes += bytes
        stat.lastUpdated = date
        stat.events.append(event)
        stats[appID] = stat

        save()
        Log.install.info("traffic: \(appName, privacy: .public) +\(bytes, privacy: .public) bytes (total \(stat.totalBytes, privacy: .public))")
    }

    /// Per-app stats, sorted by total bytes descending (heaviest app first).
    public func snapshot() -> [AppTrafficStat] {
        stats.values.sorted { a, b in
            if a.totalBytes != b.totalBytes { return a.totalBytes > b.totalBytes }
            return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
        }
    }

    /// Stats for one app, or nil if it has never recorded a download.
    public func stat(forAppID appID: String) -> AppTrafficStat? {
        stats[appID]
    }

    /// Grand total across every app, to the byte.
    public func totalBytes() -> Int64 {
        stats.values.reduce(0) { $0 + $1.totalBytes }
    }

    /// Clear all recorded traffic and remove the backing file.
    public func reset() {
        stats = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(stats)
            // Atomic so a crash mid-write can't leave a truncated, unreadable file.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.install.error("traffic: failed to persist: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [String: AppTrafficStat] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: AppTrafficStat].self, from: data) else {
            Log.install.error("traffic: stored file unreadable; starting fresh")
            return [:]
        }
        return decoded
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("traffic.json")
    }
}
