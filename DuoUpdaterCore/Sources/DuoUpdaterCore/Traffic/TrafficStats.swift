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
    /// `CFBundleVersion` of the build being replaced, when known.
    ///
    /// Recorded because plenty of vendors ship several builds under one marketing
    /// version — Surge put four separate releases out as "6.9.0" — and without the
    /// build number those rows all read "6.9.0 → 6.9.0". Optional, and absent from
    /// every event written before this was added.
    public let fromBuild: String?
    /// Build version the update moved to (a source's own canonical comparison key:
    /// Sparkle's `sparkle:version`), when known.
    public let toBuild: String?

    public init(
        date: Date,
        fromVersion: String?,
        toVersion: String?,
        sourceName: String?,
        bytes: Int64,
        fromBuild: String? = nil,
        toBuild: String? = nil
    ) {
        self.date = date
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.sourceName = sourceName
        self.bytes = bytes
        self.fromBuild = fromBuild
        self.toBuild = toBuild
    }
}

extension TrafficEvent {
    /// The two sides of this download's version transition, as they should read.
    ///
    /// Normally just the marketing versions. When those are identical the build
    /// numbers are the only thing that actually changed, so they get folded in —
    /// otherwise the row claims an app updated from a version to itself.
    ///
    /// Builds are never shown when the marketing versions already differ: they add
    /// noise to a row that is already unambiguous. Events recorded before builds
    /// were stored fall through to the plain marketing strings.
    ///
    /// Note the builds are folded in even when they are *equal*, which is what
    /// separates a download that changed nothing from one whose builds were never
    /// recorded — see ``changedNothing``. Rendering both as a bare "6.9.0 → 6.9.0"
    /// would throw away the one case the log can actually prove.
    public var versionSides: (from: String?, to: String?) {
        guard let fromVersion, let toVersion, fromVersion == toVersion,
              let fromBuild, let toBuild
        else { return (fromVersion, toVersion) }
        return ("\(fromVersion) (\(fromBuild))", "\(toVersion) (\(toBuild))")
    }

    /// True when this download provably landed on the build that was already
    /// installed — same marketing version, same build, both measured.
    ///
    /// Real bytes spent for no change. It happens: a version-scheme mismatch, a
    /// mirror advertising what is already on disk, a feed that moved backwards.
    /// The traffic log is where that should be visible, and it is only knowable
    /// for events recorded with both build numbers — an older event with no builds
    /// is unknown, not unchanged, so it is never reported here.
    public var changedNothing: Bool {
        guard let fromVersion, let toVersion, let fromBuild, let toBuild else { return false }
        return fromVersion == toVersion && fromBuild == toBuild
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
    /// Full history, newest last.
    public var events: [TrafficEvent]

    public var id: String { appID }

    /// Number of recorded downloads.
    public var updateCount: Int { events.count }

    /// Most recent download timestamp — derived from the history (newest event)
    /// rather than stored, so it can't drift out of sync with `events`.
    public var lastUpdated: Date? { events.last?.date }

    public init(
        appID: String,
        appName: String,
        bundleID: String?,
        totalBytes: Int64 = 0,
        events: [TrafficEvent] = []
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.totalBytes = totalBytes
        self.events = events
    }
}

/// Formats byte counts for display. Scoped here rather than as an extension on
/// `Int64` so the framework doesn't bolt a UI concern onto a fundamental type's
/// public API.
public enum ByteFormat {
    /// Human-readable byte count (e.g. "1.2 MB"), via `ByteCountFormatter`'s file
    /// style — the binary base macOS users expect for download sizes.
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
