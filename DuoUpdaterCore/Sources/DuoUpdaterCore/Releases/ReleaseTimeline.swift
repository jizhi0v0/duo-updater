import Foundation

/// One observed release of an app, in one of two confidence tiers that must never
/// be conflated:
///
///  - **Published** (`publishedAt` set): the vendor's own release moment, to the
///    minute, from a feed that timestamps its releases (Sparkle/GitHub/Alcove).
///    The only tier the release-habits heatmap is allowed to use.
///  - **Estimated** (`estimatedRange` set, `publishedAt` nil): for sources that
///    report a version but no date (a vendor probe, a Homebrew cask, the App
///    Store). We can't know *when* they shipped, only that it happened between the
///    last check that still saw the old version and the first that saw the new one
///    — so we record that window. Honest about its imprecision (a wide window =
///    low confidence) and kept out of the heatmap entirely.
///
/// `detectedAt` — when our check first recorded this version — is always set, but
/// reflects our polling cadence and the user's machine being awake, so it's never
/// used as a release time on its own.
public struct ReleaseEvent: Codable, Sendable, Hashable {
    /// The version string we keyed on (the remote's `displayVersion`). Also the
    /// dedupe key within an app — we record each version exactly once.
    public let version: String
    /// The vendor's published timestamp, to the minute — set only for the
    /// trustworthy tier. nil for estimated (detection-only) events.
    public let publishedAt: Date?
    /// For the estimated tier: the window the release must have happened in
    /// (last-saw-old → first-saw-new). nil for published events.
    public let estimatedRange: DateInterval?
    /// When our check first recorded this version (our observation, not the
    /// vendor's release moment).
    public let detectedAt: Date
    /// The source that reported it ("Sparkle", "GitHub", "Alcove", "Vendor"…).
    public let sourceName: String

    public init(
        version: String,
        publishedAt: Date? = nil,
        estimatedRange: DateInterval? = nil,
        detectedAt: Date,
        sourceName: String
    ) {
        self.version = version
        self.publishedAt = publishedAt
        self.estimatedRange = estimatedRange
        self.detectedAt = detectedAt
        self.sourceName = sourceName
    }

    /// True when this is a detection-window estimate, not a vendor-published date.
    public var isApproximate: Bool { publishedAt == nil }

    /// The single instant to sort and place this event by: the real publish date
    /// when known, else the end of the estimated window (when we first saw it).
    public var timestamp: Date { publishedAt ?? estimatedRange?.end ?? detectedAt }
}

/// The release history we've accumulated for a single app, newest-published last.
public struct AppReleaseTimeline: Codable, Sendable, Hashable, Identifiable {
    /// Stable per-app key: the bundle's on-disk path (same identity rule as
    /// `InstalledApp.id` and `AppTrafficStat.appID`).
    public let appID: String
    /// Display name, kept fresh on each record so a renamed app reads correctly.
    public var appName: String
    /// `CFBundleIdentifier`, for grouping/labelling. May be nil for malformed apps.
    public var bundleID: String?
    /// Recorded releases, oldest-first by timestamp.
    public var events: [ReleaseEvent]

    public var id: String { appID }

    /// Newest release we've recorded (by its best-known timestamp), or nil if empty.
    public var latest: ReleaseEvent? { events.max { $0.timestamp < $1.timestamp } }

    public init(appID: String, appName: String, bundleID: String?, events: [ReleaseEvent] = []) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.events = events
    }
}
