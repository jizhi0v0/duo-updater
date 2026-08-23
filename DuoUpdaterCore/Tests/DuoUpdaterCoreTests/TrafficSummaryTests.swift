import Testing
import Foundation
@testable import DuoUpdaterCore

/// `TrafficSummary` is the aggregate the Traffic window's header reads. The
/// fragile parts are month bucketing (which must not drift with the machine's time
/// zone), the per-source split adding back up to the grand total, and the
/// present/removed partition that keeps a renamed app's history from reading as a
/// duplicate of its current entry.

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func event(_ when: Date, _ bytes: Int64, source: String? = "Vendor") -> TrafficEvent {
    TrafficEvent(date: when, fromVersion: "1.0", toVersion: "1.1",
                 sourceName: source, bytes: bytes)
}

private func stat(_ path: String, _ events: [TrafficEvent]) -> AppTrafficStat {
    AppTrafficStat(appID: path, appName: (path as NSString).lastPathComponent,
                   bundleID: nil, totalBytes: events.reduce(0) { $0 + $1.bytes },
                   events: events)
}

// MARK: - Totals

@Test func sumsEveryEventAcrossApps() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 6, 3), 100), event(date(2026, 6, 4), 250)]),
        stat("/Applications/B.app", [event(date(2026, 7, 1), 7)]),
    ], calendar: utc)
    #expect(s.totalBytes == 357)
    #expect(s.downloadCount == 3)
    #expect(s.appCount == 2)
}

@Test func emptyInputProducesEmptySummary() {
    let s = TrafficSummary(stats: [], calendar: utc)
    #expect(s.totalBytes == 0)
    #expect(s.downloadCount == 0)
    #expect(s.appCount == 0)
    #expect(s.firstDownload == nil)
    #expect(s.months.isEmpty)
    #expect(s.sources.isEmpty)
}

/// A stat carrying no events contributes nothing to the total, so counting it as
/// an app would put "3 apps" next to a total only two of them produced.
@Test func appCountIgnoresStatsWithNoEvents() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 6, 3), 100)]),
        stat("/Applications/B.app", [event(date(2026, 6, 4), 50)]),
        stat("/Applications/Ghost.app", []),
    ], calendar: utc)
    #expect(s.appCount == 2)
    #expect(s.downloadCount == 2)
}

@Test func firstDownloadIsTheEarliestEventAnywhere() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 8, 1), 1), event(date(2026, 6, 15), 1)]),
        stat("/Applications/B.app", [event(date(2026, 6, 3), 1)]),
    ], calendar: utc)
    #expect(s.firstDownload == date(2026, 6, 3))
}

// MARK: - Months

@Test func bucketsEventsByCalendarMonthOldestFirst() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [
            event(date(2026, 8, 20), 8),
            event(date(2026, 6, 3), 6),
            event(date(2026, 7, 11), 7),
            event(date(2026, 7, 12), 70),
        ]),
    ], calendar: utc)
    #expect(s.months.map(\.bytes) == [6, 77, 8])
    #expect(s.months.map(\.count) == [1, 2, 1])
    #expect(s.months.map(\.start) == [
        utc.date(from: DateComponents(year: 2026, month: 6))!,
        utc.date(from: DateComponents(year: 2026, month: 7))!,
        utc.date(from: DateComponents(year: 2026, month: 8))!,
    ])
}

/// The first instant of a month belongs to that month, not the previous one — the
/// classic off-by-one when a boundary event is bucketed by a rounded-down date.
@Test func monthBoundaryEventLandsInTheNewMonth() {
    let firstInstant = utc.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    let lastInstant = utc.date(from:
        DateComponents(year: 2026, month: 6, day: 30, hour: 23, minute: 59, second: 59))!
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(lastInstant, 6), event(firstInstant, 7)]),
    ], calendar: utc)
    #expect(s.months.count == 2)
    #expect(s.months[0].bytes == 6)
    #expect(s.months[1].bytes == 7)
}

/// Months with nothing recorded are absent, not zero-filled: the header reads the
/// trailing entries, and a filler month would push a real one out of view.
@Test func monthsWithNoDownloadsAreAbsent() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 1, 5), 1), event(date(2026, 5, 5), 1)]),
    ], calendar: utc)
    #expect(s.months.count == 2)
}

@Test func calendarMonthsTakesTheTrailingWindow() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", (1...5).map { event(date(2026, $0, 10), Int64($0)) }),
    ], calendar: utc)
    #expect(s.calendarMonths(3, endingAt: date(2026, 5, 20)).map(\.bytes) == [3, 4, 5])
    // Asking for more months than the log covers reaches back to the first
    // download and stops — it does not invent months from before the log existed.
    #expect(s.calendarMonths(12, endingAt: date(2026, 5, 20)).count == 5)
}

/// The whole reason this exists. `months` skips months with nothing in them, so
/// reading its last entry as "this month" attaches the label to an older figure
/// the moment a month goes quiet — and the caller has no way to notice.
@Test func calendarMonthsAlwaysEndsOnTheCurrentMonthEvenWhenItIsQuiet() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 6, 3), 100), event(date(2026, 7, 4), 200)]),
    ], calendar: utc)
    // Nothing recorded in August.
    let window = s.calendarMonths(3, endingAt: date(2026, 8, 23))
    #expect(window.map(\.start) == [
        utc.date(from: DateComponents(year: 2026, month: 6))!,
        utc.date(from: DateComponents(year: 2026, month: 7))!,
        utc.date(from: DateComponents(year: 2026, month: 8))!,
    ])
    #expect(window.map(\.bytes) == [100, 200, 0])
    #expect(window.map(\.count) == [1, 1, 0])
    // The trailing entry is August — the month asked for — not July, the last
    // month that happened to have a download.
    #expect(window.last?.bytes == 0)
}

/// A month-over-month delta is only meaningful between adjacent months, so the
/// window has to be gap-free rather than a compaction of the active ones.
@Test func calendarMonthsZeroFillsGapsSoNeighboursAreConsecutive() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 6, 3), 100), event(date(2026, 9, 4), 900)]),
    ], calendar: utc)
    let window = s.calendarMonths(4, endingAt: date(2026, 9, 30))
    #expect(window.map(\.bytes) == [100, 0, 0, 900])
    // Every neighbouring pair really is one month apart.
    for (earlier, later) in zip(window, window.dropFirst()) {
        #expect(utc.date(byAdding: .month, value: 1, to: earlier.start) == later.start)
    }
}

@Test func calendarMonthsNeverReachesBeforeTheFirstDownload() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 8, 10), 42)]),
    ], calendar: utc)
    // A log that starts this month gets one column, not two invented zeroes.
    #expect(s.calendarMonths(3, endingAt: date(2026, 8, 23)).map(\.bytes) == [42])
}

@Test func calendarMonthsIsEmptyWithNothingRecorded() {
    let s = TrafficSummary(stats: [], calendar: utc)
    #expect(s.calendarMonths(3, endingAt: date(2026, 8, 23)).isEmpty)
}

/// The window has to be bucketed by the same calendar that placed `months`, or
/// every lookup misses and a month with real traffic renders as a zero.
@Test func calendarMonthsUsesTheCalendarTheSummaryWasBuiltWith() {
    var la = Calendar(identifier: .gregorian)
    la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [event(date(2026, 7, 15), 500)]),
    ], calendar: la)
    let window = s.calendarMonths(1, endingAt: date(2026, 7, 20))
    #expect(window.count == 1)
    #expect(window.first?.bytes == 500)   // zero here would mean the buckets drifted
}

/// Bucketing must follow the calendar it was handed, not the machine's. Same
/// instant, two time zones either side of a month boundary, two different buckets.
@Test func monthBucketsFollowTheSuppliedCalendar() {
    // 2026-07-01 00:30 UTC is still 2026-06-30 in Los Angeles.
    let instant = utc.date(from:
        DateComponents(year: 2026, month: 7, day: 1, hour: 0, minute: 30))!
    let stats = [stat("/Applications/A.app", [event(instant, 42)])]

    var la = Calendar(identifier: .gregorian)
    la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

    let inUTC = TrafficSummary(stats: stats, calendar: utc)
    let inLA = TrafficSummary(stats: stats, calendar: la)
    #expect(inUTC.months[0].start == utc.date(from: DateComponents(year: 2026, month: 7))!)
    #expect(inLA.months[0].start == la.date(from: DateComponents(year: 2026, month: 6))!)
}

// MARK: - Sources

@Test func splitsBySourceHeaviestFirstAndSumsBackToTotal() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [
            event(date(2026, 6, 3), 100, source: "Sparkle"),
            event(date(2026, 6, 4), 900, source: "Vendor"),
        ]),
        stat("/Applications/B.app", [
            event(date(2026, 7, 1), 500, source: "GitHub"),
            event(date(2026, 7, 2), 100, source: "Vendor"),
        ]),
    ], calendar: utc)
    #expect(s.sources.map(\.sourceName) == ["Vendor", "GitHub", "Sparkle"])
    #expect(s.sources.map(\.bytes) == [1000, 500, 100])
    #expect(s.sources.map(\.count) == [2, 1, 1])
    #expect(s.sources.reduce(0) { $0 + $1.bytes } == s.totalBytes)
}

/// An event with no recorded source still has to land somewhere, or the legend
/// would silently add up to less than the headline number above it.
@Test func eventsWithoutASourceLandInUnknown() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [
            event(date(2026, 6, 3), 300, source: nil),
            event(date(2026, 6, 4), 100, source: "Vendor"),
        ]),
    ], calendar: utc)
    #expect(s.sources.map(\.sourceName) == [TrafficSummary.unknownSource, "Vendor"])
    #expect(s.sources.reduce(0) { $0 + $1.bytes } == 400)
}

/// Equal byte totals must not shuffle between redraws — the legend's colours are
/// keyed to this order.
@Test func equalSourceTotalsAreOrderedByName() {
    let s = TrafficSummary(stats: [
        stat("/Applications/A.app", [
            event(date(2026, 6, 3), 100, source: "Vendor"),
            event(date(2026, 6, 4), 100, source: "GitHub"),
            event(date(2026, 6, 5), 100, source: "Sparkle"),
        ]),
    ], calendar: utc)
    #expect(s.sources.map(\.sourceName) == ["GitHub", "Sparkle", "Vendor"])
}

// MARK: - Present vs. removed

@Test func partitionSplitsOnTheSuppliedPredicate() {
    let live = stat("/Applications/Live.app", [event(date(2026, 6, 3), 10)])
    let gone = stat("/Applications/Gone.app", [event(date(2026, 6, 4), 90)])
    let p = TrafficPartition(stats: [live, gone, gone]) { $0.appID.contains("Live") }
    #expect(p.present.map(\.appID) == ["/Applications/Live.app"])
    #expect(p.removed.count == 2)
    #expect(p.removedBytes == 180)
}

@Test func partitionPreservesInputOrderWithinEachGroup() {
    let a = stat("/Applications/A.app", [event(date(2026, 6, 1), 3)])
    let b = stat("/Applications/B.app", [event(date(2026, 6, 2), 2)])
    let c = stat("/Applications/C.app", [event(date(2026, 6, 3), 1)])
    let p = TrafficPartition(stats: [a, b, c]) { $0.appID != "/Applications/B.app" }
    #expect(p.present.map(\.appID) == ["/Applications/A.app", "/Applications/C.app"])
    #expect(p.removed.map(\.appID) == ["/Applications/B.app"])
}

@Test func isOnDiskRequiresAnExistingDirectory() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("traffic-ondisk-\(UUID().uuidString)")
    let bundle = base.appendingPathComponent("Real.app")
    let plainFile = base.appendingPathComponent("NotABundle.app")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: plainFile)
    defer { try? FileManager.default.removeItem(at: base) }

    #expect(stat(bundle.path, []).isOnDisk())
    #expect(!stat(base.appendingPathComponent("Missing.app").path, []).isOnDisk())
    // A plain file at the path is not an installed bundle.
    #expect(!stat(plainFile.path, []).isOnDisk())
}

// MARK: - Version transition labelling

/// Several builds under one marketing version is normal (Surge shipped four
/// releases as "6.9.0"), and the row has to say which one moved — otherwise it
/// claims the app updated from a version to itself.

private func build(_ from: String?, _ to: String?,
                   _ fromBuild: String?, _ toBuild: String?) -> TrafficEvent {
    TrafficEvent(date: date(2026, 8, 12), fromVersion: from, toVersion: to,
                 sourceName: "Sparkle", bytes: 1, fromBuild: fromBuild, toBuild: toBuild)
}

@Test func identicalMarketingVersionsFallBackToBuildNumbers() {
    let sides = build("6.9.0", "6.9.0", "12028", "12030").versionSides
    #expect(sides.from == "6.9.0 (12028)")
    #expect(sides.to == "6.9.0 (12030)")
}

/// Builds on a row whose marketing versions already differ are noise.
@Test func differingMarketingVersionsDoNotShowBuilds() {
    let sides = build("6.8.0", "6.9.0", "11990", "12028").versionSides
    #expect(sides.from == "6.8.0")
    #expect(sides.to == "6.9.0")
}

/// Events written before builds were recorded still have to render.
@Test func eventsWithoutBuildsKeepTheirMarketingStrings() {
    let sides = build("6.9.0", "6.9.0", nil, nil).versionSides
    #expect(sides.from == "6.9.0")
    #expect(sides.to == "6.9.0")
}

/// Same version AND same build is a download that changed nothing. It must not
/// render like an event whose builds were never recorded — that is the one case
/// the log can prove, and collapsing them throws the proof away.
@Test func aDownloadThatChangedNothingStillShowsItsBuilds() {
    let event = build("6.9.0", "6.9.0", "12030", "12030")
    #expect(event.versionSides.from == "6.9.0 (12030)")
    #expect(event.versionSides.to == "6.9.0 (12030)")
    #expect(event.changedNothing)
}

@Test func aRealBuildBumpIsNotReportedAsUnchanged() {
    #expect(build("6.9.0", "6.9.0", "12028", "12030").changedNothing == false)
}

@Test func aMarketingVersionChangeIsNotReportedAsUnchanged() {
    #expect(build("6.8.0", "6.9.0", "11990", "12030").changedNothing == false)
}

/// An older event carries no builds, so whether it changed anything is unknown —
/// and unknown must never be reported as "no change".
@Test func anEventWithoutBuildsIsUnknownRatherThanUnchanged() {
    #expect(build("6.9.0", "6.9.0", nil, nil).changedNothing == false)
    #expect(build("6.9.0", "6.9.0", "12030", nil).changedNothing == false)
    #expect(build("6.9.0", "6.9.0", nil, "12030").changedNothing == false)
}

@Test func aMissingSideIsLeftAlone() {
    #expect(build(nil, "6.9.0", nil, "12030").versionSides.from == nil)
    #expect(build("6.9.0", nil, "12028", nil).versionSides.to == nil)
}

/// Old traffic.json files have no build keys at all; decoding must not fail.
@Test func eventsDecodeFromJSONWrittenBeforeBuildsExisted() throws {
    let legacy = """
    {"date":"2026-08-12T02:07:00Z","fromVersion":"6.8.0","toVersion":"6.9.0",
     "sourceName":"Sparkle","bytes":50755741}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let event = try decoder.decode(TrafficEvent.self, from: Data(legacy.utf8))
    #expect(event.bytes == 50_755_741)
    #expect(event.fromBuild == nil)
    #expect(event.toBuild == nil)
    #expect(event.versionSides.to == "6.9.0")
}
