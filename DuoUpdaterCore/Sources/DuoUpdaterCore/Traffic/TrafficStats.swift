import Foundation

/// One recorded download for an app — the bytes pulled over the network for a
/// single update install, with the version transition and source that produced
/// it. The atomic unit behind the per-app totals.
public struct TrafficEvent: Codable, Sendable, Hashable {
    /// When the download completed.
    public let date: Date
    /// Version the app was on before this update (the installed `shortVersion`).
    public let fromVersion: String?
    /// Version this update moved the app to (the remote `displayVersion`).
    public let toVersion: String?
    /// Update source that served the bytes ("Sparkle", "Vendor", "GitHub", "pkg").
    public let sourceName: String?
    /// Exact number of bytes transferred for this download.
    public let bytes: Int64

    public init(
        date: Date,
        fromVersion: String?,
        toVersion: String?,
        sourceName: String?,
        bytes: Int64
    ) {
        self.date = date
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.sourceName = sourceName
        self.bytes = bytes
    }
}

/// Cumulative download traffic for a single app — the per-app dimension of the
/// statistics. `totalBytes` is the sum of every recorded `TrafficEvent.bytes`,
/// tracked to the byte.
public struct AppTrafficStat: Codable, Sendable, Hashable, Identifiable {
    /// Stable per-app key: the bundle's on-disk path (same identity rule as
    /// `InstalledApp.id`, so two installs sharing a bundle id stay distinct).
    public let appID: String
    /// Display name, kept fresh on each record so a renamed app reads correctly.
    public var appName: String
    /// `CFBundleIdentifier`, for grouping/labelling. May be nil for malformed apps.
    public var bundleID: String?
    /// Sum of all recorded download bytes for this app, to the byte.
    public var totalBytes: Int64
    /// Most recent download timestamp.
    public var lastUpdated: Date?
    /// Full history, newest last.
    public var events: [TrafficEvent]

    public var id: String { appID }

    /// Number of recorded downloads.
    public var updateCount: Int { events.count }

    public init(
        appID: String,
        appName: String,
        bundleID: String?,
        totalBytes: Int64 = 0,
        lastUpdated: Date? = nil,
        events: [TrafficEvent] = []
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.totalBytes = totalBytes
        self.lastUpdated = lastUpdated
        self.events = events
    }
}

extension Int64 {
    /// Human-readable byte count (e.g. "1.2 MB"), for surfacing a total in the UI.
    /// Uses the binary (1024) base via `ByteCountFormatter`'s file style, which is
    /// what users expect for download sizes on macOS.
    public var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
