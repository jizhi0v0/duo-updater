import Foundation

/// Aggregate "when do these apps like to ship?" statistics over a set of recorded
/// releases — the analysis layer on top of `ReleaseTimelineStore`.
///
/// Every bucket is computed from `ReleaseEvent.publishedAt` (the vendor's own
/// release moment) interpreted in a supplied `Calendar` — so the answer is "what
/// time of day, in *this* clock". The store never records a release without a
/// trustworthy `publishedAt`, so there's no polling-time noise to filter here.
public struct ReleaseStats: Sendable, Equatable {
    /// Total releases counted.
    public let total: Int
    /// Count per hour of day, index 0...23.
    public let byHour: [Int]
    /// Count per weekday, index 0 = Sunday ... 6 = Saturday (so it lines up with
    /// `Calendar`'s 1-based `.weekday` minus one).
    public let byWeekday: [Int]
    /// Count per (weekday, hour): `grid[weekday][hour]`, same index conventions as
    /// `byWeekday` / `byHour`. The 7×24 heatmap.
    public let grid: [[Int]]

    /// Build the histogram from release events, bucketing each by its publish
    /// instant in `calendar` (whose `timeZone` decides the wall-clock reading).
    ///
    /// Only the trustworthy tier counts: events with no real `publishedAt`
    /// (detection-only estimates) are skipped entirely, so a heatmap built from
    /// this never reflects our polling clock — only when vendors actually shipped.
    public init(events: [ReleaseEvent], calendar: Calendar = .current) {
        var hour = Array(repeating: 0, count: 24)
        var weekday = Array(repeating: 0, count: 7)
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        var counted = 0

        for event in events {
            guard let published = event.publishedAt else { continue }
            let comps = calendar.dateComponents([.hour, .weekday], from: published)
            guard let h = comps.hour, let w = comps.weekday else { continue }
            let wd = w - 1                       // 1...7 → 0...6
            guard (0..<24).contains(h), (0..<7).contains(wd) else { continue }
            hour[h] += 1
            weekday[wd] += 1
            grid[wd][h] += 1
            counted += 1
        }

        self.total = counted
        self.byHour = hour
        self.byWeekday = weekday
        self.grid = grid
    }

    /// The single busiest cell, or nil when there are no releases — the headline
    /// "they mostly ship on <weekday> around <hour>" signal.
    public var peakCell: (weekday: Int, hour: Int, count: Int)? {
        var best: (weekday: Int, hour: Int, count: Int)?
        for w in 0..<7 {
            for h in 0..<24 where grid[w][h] > 0 {
                if grid[w][h] > (best?.count ?? 0) {
                    best = (w, h, grid[w][h])
                }
            }
        }
        return best
    }

    /// The hour of day with the most releases (ties → earliest hour), or nil when
    /// empty.
    public var peakHour: Int? {
        guard total > 0 else { return nil }
        return byHour.indices.max { byHour[$0] < byHour[$1] }.flatMap { byHour[$0] > 0 ? $0 : nil }
    }

    /// The weekday with the most releases (ties → earliest, Sunday-first), or nil
    /// when empty.
    public var peakWeekday: Int? {
        guard total > 0 else { return nil }
        return byWeekday.indices.max { byWeekday[$0] < byWeekday[$1] }.flatMap { byWeekday[$0] > 0 ? $0 : nil }
    }

    /// The largest count in any single grid cell — the scale the heatmap colors
    /// against. 0 when empty (callers must avoid dividing by it).
    public var maxCellCount: Int {
        grid.flatMap { $0 }.max() ?? 0
    }
}
