import Foundation

/// Download traffic rolled up for one calendar month.
public struct TrafficMonth: Sendable, Hashable, Identifiable {
    /// First instant of the month, in the calendar the summary was built with.
    /// Kept as a `Date` rather than a year/month pair so callers can feed it
    /// straight to a `DateFormatter` without rebuilding the components.
    public let start: Date
    public let bytes: Int64
    /// Number of downloads recorded in the month.
    public let count: Int

    public var id: Date { start }

    public init(start: Date, bytes: Int64, count: Int) {
        self.start = start
        self.bytes = bytes
        self.count = count
    }
}

/// Download traffic rolled up for one update source ("Vendor", "GitHub", …).
public struct TrafficSourceTotal: Sendable, Hashable, Identifiable {
    public let sourceName: String
    public let bytes: Int64
    public let count: Int

    public var id: String { sourceName }

    public init(sourceName: String, bytes: Int64, count: Int) {
        self.sourceName = sourceName
        self.bytes = bytes
        self.count = count
    }
}

/// The aggregate read of the traffic log: the numbers the window's header shows,
/// derived in one pass over every recorded event.
///
/// Derived here rather than in the view because each figure is a real rule (which
/// calendar buckets a month, how an event with no source name is labelled) that
/// deserves a test, and because the view recomputes on every redraw.
public struct TrafficSummary: Sendable, Hashable {
    /// Sum of every recorded download, to the byte.
    public let totalBytes: Int64
    /// Number of recorded downloads across every app.
    public let downloadCount: Int
    /// Number of apps with at least one recorded download.
    public let appCount: Int
    /// Timestamp of the earliest recorded download, or nil when nothing is recorded.
    public let firstDownload: Date?
    /// Every month that has at least one download, oldest first. Months with no
    /// downloads are absent rather than zero-filled — the header reads the trailing
    /// entries, and a gap month would push a real month out of view.
    public let months: [TrafficMonth]
    /// Per-source totals, heaviest first.
    public let sources: [TrafficSourceTotal]

    /// The label used for an event whose source we never recorded. Events predating
    /// the field, or written by a path that didn't set it, still have to land in a
    /// bucket or the per-source totals wouldn't add up to `totalBytes`.
    public static let unknownSource = "Unknown"

    /// The calendar `months` was bucketed with. Carried on the value so
    /// `calendarMonths(_:endingAt:)` can't be asked a question in a different
    /// calendar than the one that placed the buckets — the two would disagree
    /// about where a month starts and every lookup would miss.
    public let calendar: Calendar

    public static let empty = TrafficSummary(
        totalBytes: 0, downloadCount: 0, appCount: 0,
        firstDownload: nil, months: [], sources: [])

    public init(
        totalBytes: Int64,
        downloadCount: Int,
        appCount: Int,
        firstDownload: Date?,
        months: [TrafficMonth],
        sources: [TrafficSourceTotal],
        calendar: Calendar = .current
    ) {
        self.totalBytes = totalBytes
        self.downloadCount = downloadCount
        self.appCount = appCount
        self.firstDownload = firstDownload
        self.months = months
        self.sources = sources
        self.calendar = calendar
    }

    /// Roll up every event in `stats`.
    ///
    /// - Parameter calendar: which calendar buckets the months. Defaults to the
    ///   user's current calendar so the header agrees with the dates shown on the
    ///   event rows; tests pin it so the buckets don't move with the machine's
    ///   time zone.
    public init(stats: [AppTrafficStat], calendar: Calendar = .current) {
        var total: Int64 = 0
        var count = 0
        var earliest: Date?
        var monthBytes: [Date: Int64] = [:]
        var monthCount: [Date: Int] = [:]
        var sourceBytes: [String: Int64] = [:]
        var sourceCount: [String: Int] = [:]

        for stat in stats {
            for event in stat.events {
                total += event.bytes
                count += 1
                if earliest == nil || event.date < earliest! { earliest = event.date }

                let start = calendar.date(
                    from: calendar.dateComponents([.year, .month], from: event.date))
                    ?? event.date
                monthBytes[start, default: 0] += event.bytes
                monthCount[start, default: 0] += 1

                let source = event.sourceName ?? Self.unknownSource
                sourceBytes[source, default: 0] += event.bytes
                sourceCount[source, default: 0] += 1
            }
        }

        self.calendar = calendar
        self.totalBytes = total
        self.downloadCount = count
        // An app with an empty history isn't counted: the store only writes a stat
        // alongside a real event, but a hand-edited or partially-decoded file could
        // still carry one, and it would inflate "N apps" against a total it added
        // nothing to.
        self.appCount = stats.count { !$0.events.isEmpty }
        self.firstDownload = earliest
        self.months = monthBytes.keys.sorted().map {
            TrafficMonth(start: $0, bytes: monthBytes[$0] ?? 0, count: monthCount[$0] ?? 0)
        }
        self.sources = sourceBytes.keys
            .map { TrafficSourceTotal(
                sourceName: $0, bytes: sourceBytes[$0] ?? 0, count: sourceCount[$0] ?? 0) }
            // Ties broken by name so the legend's order — and the colours keyed to
            // it — stay put between redraws.
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.sourceName < $1.sourceName }
    }

    /// The `count` calendar months ending at the month containing `date`, oldest
    /// first — zero-filled, so the trailing entry is *always* the current month
    /// and any two neighbours are *always* consecutive months.
    ///
    /// `months` deliberately omits months with nothing recorded, which makes it
    /// the wrong thing to read positionally: in a quiet month its last entry is
    /// some earlier month, and its neighbours can be a year apart. Anything that
    /// labels a column "this month" or works out a month-over-month change has to
    /// come through here instead.
    ///
    /// Never reaches back past the first recorded download: a log that starts
    /// this month returns one entry, not two invented zeroes from before it
    /// existed. Empty when nothing is recorded at all.
    public func calendarMonths(_ count: Int, endingAt date: Date = Date()) -> [TrafficMonth] {
        guard count > 0, let firstDownload else { return [] }
        let parts: Set<Calendar.Component> = [.year, .month]
        guard let end = calendar.date(from: calendar.dateComponents(parts, from: date)),
              let first = calendar.date(from: calendar.dateComponents(parts, from: firstDownload))
        else { return [] }

        // The current month is always present, even with nothing in it — that is
        // the whole point of anchoring here rather than at the last active month.
        var starts = [end]
        while starts.count < count,
              let previous = calendar.date(byAdding: .month, value: -1, to: starts[starts.count - 1]),
              previous >= first {
            starts.append(previous)
        }

        let recorded = Dictionary(months.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        return starts.reversed().map {
            recorded[$0] ?? TrafficMonth(start: $0, bytes: 0, count: 0)
        }
    }
}

// MARK: - Live vs. removed

extension AppTrafficStat {
    /// Whether the bundle this stat was recorded against is still on disk.
    ///
    /// `appID` is the app's path, so an app that was renamed, moved, or deleted
    /// leaves its history behind under a path that no longer resolves. Those
    /// entries are real measured traffic and are never discarded — but they'd read
    /// as duplicates next to the app's current entry, so the window groups them
    /// separately.
    public func isOnDisk(fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: appID, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

/// Per-app stats split into the apps still installed and the ones whose path is
/// gone. Order within each group is preserved from the input.
public struct TrafficPartition: Sendable {
    public let present: [AppTrafficStat]
    public let removed: [AppTrafficStat]

    /// Total bytes recorded against paths that no longer resolve.
    public var removedBytes: Int64 { removed.reduce(0) { $0 + $1.totalBytes } }

    /// - Parameter isPresent: existence test, injected so tests don't have to
    ///   create real bundles on disk.
    public init(stats: [AppTrafficStat], isPresent: (AppTrafficStat) -> Bool = { $0.isOnDisk() }) {
        var present: [AppTrafficStat] = []
        var removed: [AppTrafficStat] = []
        for stat in stats {
            if isPresent(stat) { present.append(stat) } else { removed.append(stat) }
        }
        self.present = present
        self.removed = removed
    }
}
