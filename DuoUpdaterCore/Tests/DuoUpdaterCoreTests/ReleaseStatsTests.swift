import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ReleaseStats` buckets releases by weekday and hour so the UI can answer "what
/// time do these apps like to ship?". The load-bearing parts: correct weekday
/// indexing (Calendar's 1-based weekday → 0-based Sunday-first) and that the
/// bucketing honors the supplied calendar's time zone.

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// A release published at the given UTC wall-clock. June 2026: 21st = Sunday,
/// 23rd = Tuesday, 24th = Wednesday.
private func event(_ day: Int, _ hour: Int, version: String) -> ReleaseEvent {
    let date = utc.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: 0))!
    return ReleaseEvent(version: version, publishedAt: date, detectedAt: date, sourceName: "Sparkle")
}

@Test func emptyStatsAreAllZero() {
    let stats = ReleaseStats(events: [], calendar: utc)
    #expect(stats.total == 0)
    #expect(stats.byHour.allSatisfy { $0 == 0 })
    #expect(stats.byWeekday.allSatisfy { $0 == 0 })
    #expect(stats.maxCellCount == 0)
    #expect(stats.peakCell == nil)
    #expect(stats.peakHour == nil)
    #expect(stats.peakWeekday == nil)
}

@Test func bucketsByHourAndWeekday() {
    let events = [
        event(24, 17, version: "1"),   // Wed 17:00
        event(24, 17, version: "2"),   // Wed 17:00
        event(24, 17, version: "3"),   // Wed 17:00
        event(23, 9,  version: "4"),   // Tue 09:00
        event(21, 23, version: "5"),   // Sun 23:00
    ]
    let stats = ReleaseStats(events: events, calendar: utc)
    #expect(stats.total == 5)
    #expect(stats.byHour[17] == 3)
    #expect(stats.byHour[9] == 1)
    #expect(stats.byHour[23] == 1)
    // Weekday index: Sunday = 0, Tuesday = 2, Wednesday = 3.
    #expect(stats.byWeekday[3] == 3)   // Wed
    #expect(stats.byWeekday[2] == 1)   // Tue
    #expect(stats.byWeekday[0] == 1)   // Sun
    // The 7×24 grid cell for Wed 17:00 holds all three.
    #expect(stats.grid[3][17] == 3)
    #expect(stats.maxCellCount == 3)
}

@Test func peakCellIsTheBusiestSlot() {
    let events = [
        event(24, 17, version: "1"),
        event(24, 17, version: "2"),
        event(23, 9,  version: "3"),
    ]
    let stats = ReleaseStats(events: events, calendar: utc)
    let peak = stats.peakCell
    #expect(peak?.weekday == 3)   // Wednesday
    #expect(peak?.hour == 17)
    #expect(peak?.count == 2)
    #expect(stats.peakHour == 17)
    #expect(stats.peakWeekday == 3)
}

@Test func approximateEventsAreExcluded() {
    // A published event plus a detection-only estimate: only the published one may
    // reach the heatmap, so our polling clock never pollutes the release-habit data.
    let published = event(24, 17, version: "1")
    let approx = ReleaseEvent(
        version: "2",
        estimatedRange: DateInterval(start: utc.date(from: DateComponents(year:2026,month:6,day:24,hour:2))!,
                                     end: utc.date(from: DateComponents(year:2026,month:6,day:24,hour:9))!),
        detectedAt: utc.date(from: DateComponents(year:2026,month:6,day:24,hour:9))!,
        sourceName: "Vendor")
    let stats = ReleaseStats(events: [published, approx], calendar: utc)
    #expect(stats.total == 1)            // only the published one counts
    #expect(stats.byHour[17] == 1)       // Wed 17:00 (published)
    #expect(stats.byHour[9] == 0)        // the estimate's hour is not plotted
}

/// #239: a `vendorDay` event is real vendor information (unlike the
/// detection-only estimate above), but still carries no time of day — plotting
/// it would mean inventing an hour, and possibly a weekday, the vendor never
/// stated. Must be excluded exactly like the estimated tier.
@Test func vendorDayEventsAreExcludedEvenThoughTheyAreNotDetectionOnly() {
    let published = event(24, 17, version: "1")
    let dayOnly = ReleaseEvent(
        version: "2",
        vendorDay: utc.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 9))!,
        detectedAt: utc.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 9))!,
        sourceName: "Sparkle")
    #expect(dayOnly.isApproximate == false, "a vendor-stated day is not a detection guess")
    let stats = ReleaseStats(events: [published, dayOnly], calendar: utc)
    #expect(stats.total == 1)            // only the minute-precise one counts
    #expect(stats.byHour[17] == 1)       // Wed 17:00 (published)
    #expect(stats.byHour[9] == 0)        // the vendor day's arbitrary hour is not plotted
}

@Test func timeZoneShiftsTheBucket() {
    // 23:00 UTC on Wed the 24th is 08:00 the next day (Thu) in UTC+9.
    var jst = Calendar(identifier: .gregorian)
    jst.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
    let e = event(24, 23, version: "1")   // 23:00 UTC
    let stats = ReleaseStats(events: [e], calendar: jst)
    #expect(stats.byHour[8] == 1)         // 08:00 local
    #expect(stats.byWeekday[4] == 1)      // Thursday
}
