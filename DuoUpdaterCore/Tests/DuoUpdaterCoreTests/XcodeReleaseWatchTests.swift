import Foundation
import Testing
@testable import DuoUpdaterCore

// MARK: - Simulation harness
//
// Drives the real `XcodeReleaseWatcher.run` loop on a virtual clock: `sleep`
// advances time instantly, and every answer the loop gets — the index, Apple's
// feed, the gate, whether a check could start — comes from a script keyed on
// the virtual time. Nothing here waits on a real timer.

private let pacific = XcodeReleaseWindow.timeZone

private func pt(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacific
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func entry(_ order: Int, _ build: String, _ label: String) -> XcodeReleaseWatch.IndexEntry {
    .init(order: order, build: build, label: label)
}

private let oldIndex = [
    entry(26_006_000_999, "17F113", "26.6 (17F113)"),
    entry(27_000_000_901, "27A266a", "27.0 RC 1 (27A266a)"),
]
private let newBeta = entry(27_001_000_002, "27A9300b", "27.1 beta 2 (27A9300b)")

private struct Scripted: Error, CustomStringConvertible {
    let description: String
}

private struct World: Sendable {
    var index: @Sendable (Date) throws -> [XcodeReleaseWatch.IndexEntry]
    var feed: @Sendable (Date) throws -> [AppleDeveloperReleaseFeed.Announcement] = { _ in [] }
    var gate: @Sendable (Date) -> XcodeReleaseWatcher.Gate = { _ in .on }
    var busy: @Sendable (Date) -> Bool = { _ in false }
}

private final class Run: @unchecked Sendable {
    private let lock = NSLock()
    private var clock: Date
    let end: Date
    private(set) var indexAsks: [Date] = []
    private(set) var feedAsks: [Date] = []
    private(set) var checks: [Date] = []
    private(set) var lines: [(Date, String, Bool)] = []

    init(from start: Date, to end: Date) {
        self.clock = start
        self.end = end
    }

    var now: Date { lock.withLock { clock } }

    func advance(_ seconds: TimeInterval) throws {
        try lock.withLock {
            clock = clock.addingTimeInterval(seconds)
            if clock >= end { throw CancellationError() }
        }
    }

    func note(index at: Date) { lock.withLock { indexAsks.append(at) } }
    func note(feed at: Date) { lock.withLock { feedAsks.append(at) } }
    func note(check at: Date) { lock.withLock { checks.append(at) } }
    func note(line: String, notable: Bool) { lock.withLock { lines.append((clock, line, notable)) } }

    /// The lines the app logs at `.notice`, which outlive the in-memory buffer.
    var notable: [String] { lock.withLock { lines.filter(\.2).map(\.1) } }

    /// The log as the app would print it, stamped with Pacific time.
    var transcript: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = pacific
        formatter.dateFormat = "EEE MM-dd HH:mm zzz"
        return lock.withLock { lines.map { "\(formatter.string(from: $0.0))  \($0.1)" } }
    }
}

private func simulate(_ world: World, from start: Date, to end: Date) async -> Run {
    let run = Run(from: start, to: end)
    await XcodeReleaseWatcher.run(XcodeReleaseWatcher.Environment(
        now: { run.now },
        sleep: { try run.advance($0) },
        indexEntries: {
            let now = run.now
            run.note(index: now)
            return try world.index(now)
        },
        announcements: {
            let now = run.now
            run.note(feed: now)
            return try world.feed(now)
        },
        gate: { world.gate(run.now) },
        check: {
            let now = run.now
            if world.busy(now) { return false }
            run.note(check: now)
            return true
        },
        log: { run.note(line: $0, notable: $1) }))
    return run
}

/// The index before `visible`, and with `added` from then on.
private func releasing(_ added: XcodeReleaseWatch.IndexEntry, at visible: Date)
    -> @Sendable (Date) throws -> [XcodeReleaseWatch.IndexEntry] {
    { $0 >= visible ? oldIndex + [added] : oldIndex }
}

private func announcement(_ title: String, _ build: String, at date: Date) -> AppleDeveloperReleaseFeed.Announcement {
    AppleDeveloperReleaseFeed.Announcement(title: title, build: build, date: date)
}

// MARK: - The window

@Test func windowIsWeekdaysHalfPastNineToFourPacific() {
    #expect(!XcodeReleaseWindow.contains(pt(2026, 9, 28, 9, 29)))   // Mon
    #expect(XcodeReleaseWindow.contains(pt(2026, 9, 28, 9, 30)))
    #expect(XcodeReleaseWindow.contains(pt(2026, 9, 28, 15, 59)))
    #expect(!XcodeReleaseWindow.contains(pt(2026, 9, 28, 16, 0)))
    #expect(XcodeReleaseWindow.contains(pt(2026, 10, 2, 10, 0)))    // Fri
    #expect(!XcodeReleaseWindow.contains(pt(2026, 10, 3, 10, 0)))   // Sat
    #expect(!XcodeReleaseWindow.contains(pt(2026, 10, 4, 10, 0)))   // Sun
    #expect(XcodeReleaseWindow.nextOpening(after: pt(2026, 10, 2, 16, 0)) == pt(2026, 10, 5, 9, 30))
    #expect(XcodeReleaseWindow.nextOpening(after: pt(2026, 9, 28, 9, 30)) == pt(2026, 9, 29, 9, 30))
}

// MARK: - A week with no release

@Test func aQuietWeekAsksOnlyInsideTheWindowEveryFiveMinutes() async {
    let run = await simulate(World(index: { _ in oldIndex }),
                             from: pt(2026, 9, 27), to: pt(2026, 10, 4))  // Sun → Sun
    // The baseline, taken at launch on the Sunday, then 78 asks a weekday
    // (09:30, 09:35 … 15:55).
    #expect(run.indexAsks.first == pt(2026, 9, 27))
    let inWindow = run.indexAsks.dropFirst()
    #expect(inWindow.count == 5 * 78)
    #expect(inWindow.allSatisfy(XcodeReleaseWindow.contains))
    #expect(inWindow.first == pt(2026, 9, 28, 9, 30))
    #expect(inWindow.last == pt(2026, 10, 2, 15, 55))
    #expect(run.feedAsks.count == 5 * 78)
    #expect(run.checks.isEmpty)
}

/// The first ask of each Pacific day that has one.
private func openings(_ run: Run) -> [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacific
    return Dictionary(grouping: run.indexAsks.dropFirst()) { calendar.startOfDay(for: $0) }
        .values.map { $0.min()! }.sorted()
}

@Test func theWindowFollowsPacificTimeAcrossBothDaylightSavingSwitches() async {
    // DST ends Sun 2026-11-01: 09:30 is 16:30 UTC on Friday, 17:30 UTC on Monday.
    let autumn = await simulate(World(index: { _ in oldIndex }), from: pt(2026, 10, 30), to: pt(2026, 11, 3))
    #expect(openings(autumn) == [utc("2026-10-30T16:30:00Z"), utc("2026-11-02T17:30:00Z")])
    // DST starts Sun 2026-03-08: 17:30 UTC on Friday, 16:30 UTC on Monday.
    let spring = await simulate(World(index: { _ in oldIndex }), from: pt(2026, 3, 6), to: pt(2026, 3, 10))
    #expect(openings(spring) == [utc("2026-03-06T17:30:00Z"), utc("2026-03-09T16:30:00Z")])
}

// MARK: - A release

@Test func aReleaseInTheWindowRunsOneCheckAtTheNextAsk() async {
    let run = await simulate(World(index: releasing(newBeta, at: pt(2026, 9, 28, 10, 52))),
                             from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(run.checks == [pt(2026, 9, 28, 10, 55)])
    #expect(run.transcript.contains { $0.contains("index lists new: 27.1 beta 2 (27A9300b)") })
    #expect(run.transcript.contains { $0.contains("ran a check for the new index entries") })
}

@Test func aGAThatReusesItsRCsBuildIsStillNew() async {
    // 27 RC 1 and 27 are both 27A266a; only the index's order tells them apart.
    let ga = entry(27_000_000_999, "27A266a", "27.0 (27A266a)")
    let run = await simulate(World(index: releasing(ga, at: pt(2026, 9, 14, 11, 11))),
                             from: pt(2026, 9, 14), to: pt(2026, 9, 15))
    #expect(run.checks == [pt(2026, 9, 14, 11, 15)])
}

@Test func aReleaseOutsideTheWindowIsLeftToTheScheduleThenSeenAtTheNextOpening() async {
    // 27 beta 3 reached the index at 20:17 PDT. Nothing is asked in the evening;
    // the next opening sees it (the scheduled check has likely run by then —
    // one extra check at most).
    let run = await simulate(World(index: releasing(newBeta, at: pt(2026, 7, 6, 20, 27))),
                             from: pt(2026, 7, 6), to: pt(2026, 7, 8))
    #expect(!run.indexAsks.contains { $0 > pt(2026, 7, 6, 16, 0) && $0 < pt(2026, 7, 7, 9, 30) })
    #expect(run.checks == [pt(2026, 7, 7, 9, 30)])
}

/// Every Xcode release of 2026 with a known index commit, replayed: the index
/// shows the release ten minutes after its commit (xcodereleases.com serves
/// `max-age=600`), and Apple's feed carries the four it carried, at their
/// `pubDate`. Commit times are from XcodeReleasesOrg/xcodereleases.com.
@Test func the2026ReleasesReplayed() async {
    struct Case { let name: String; let committed: Date; let announced: Date?; let caughtAt: Date? }
    let cases: [Case] = [
        .init(name: "26.5 RC", committed: utc("2026-05-04T18:02:31Z"), announced: nil, caughtAt: pt(2026, 5, 4, 11, 15)),
        .init(name: "26.5", committed: utc("2026-05-11T17:55:28Z"), announced: nil, caughtAt: pt(2026, 5, 11, 11, 10)),
        .init(name: "26.6 RC", committed: utc("2026-06-08T20:01:33Z"), announced: nil, caughtAt: pt(2026, 6, 8, 13, 15)),
        .init(name: "26.6 RC 2", committed: utc("2026-06-18T17:42:07Z"), announced: nil, caughtAt: pt(2026, 6, 18, 10, 55)),
        // After the window, no announcement: the next opening.
        .init(name: "27 beta 2", committed: utc("2026-06-23T00:23:10Z"), announced: nil, caughtAt: pt(2026, 6, 23, 9, 30)),
        // Announced 15:00, indexed 16:13: kept asking past 16:00.
        .init(name: "26.6", committed: utc("2026-06-25T23:13:22Z"), announced: pt(2026, 6, 25, 15, 0), caughtAt: pt(2026, 6, 25, 16, 25)),
        .init(name: "27 beta 3", committed: utc("2026-07-07T03:17:36Z"), announced: nil, caughtAt: pt(2026, 7, 7, 9, 30)),
        .init(name: "27 beta 4", committed: utc("2026-07-20T20:42:49Z"), announced: nil, caughtAt: pt(2026, 7, 20, 13, 55)),
        .init(name: "27 beta 5", committed: utc("2026-08-10T18:28:26Z"), announced: nil, caughtAt: pt(2026, 8, 10, 11, 40)),
        .init(name: "27 beta 6", committed: utc("2026-08-24T17:58:57Z"), announced: nil, caughtAt: pt(2026, 8, 24, 11, 10)),
        .init(name: "27 RC", committed: utc("2026-09-09T19:17:40Z"), announced: nil, caughtAt: pt(2026, 9, 9, 12, 30)),
        .init(name: "27", committed: utc("2026-09-14T18:11:10Z"), announced: pt(2026, 9, 14, 10, 0), caughtAt: pt(2026, 9, 14, 11, 25)),
        .init(name: "27.2 beta", committed: utc("2026-09-16T17:50:51Z"), announced: pt(2026, 9, 16, 10, 0), caughtAt: pt(2026, 9, 16, 11, 5)),
        .init(name: "27.1 beta", committed: utc("2026-09-18T18:22:23Z"), announced: pt(2026, 9, 18, 10, 0), caughtAt: pt(2026, 9, 18, 11, 35)),
    ]
    for c in cases {
        let visible = c.committed.addingTimeInterval(600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let day = calendar.startOfDay(for: c.committed.addingTimeInterval(-8 * 3600))
        let added = entry(99_000_000_001, "99Z\(c.name.count)", c.name)
        var world = World(index: releasing(added, at: visible))
        if let announced = c.announced {
            world.feed = { $0 >= announced ? [announcement("Xcode \(c.name) (\(added.build))", added.build, at: announced)] : [] }
        }
        let run = await simulate(world, from: day, to: day.addingTimeInterval(36 * 3600))
        #expect(run.checks.first == c.caughtAt, "\(c.name): caught at \(run.checks.first.map(String.init(describing:)) ?? "never")")
        #expect(run.checks.count == 1, "\(c.name)")
        if let caught = run.checks.first, caught < calendar.date(byAdding: .hour, value: 16, to: day)! || c.announced != nil {
            // In the window (or kept open by an announcement): within one ask of visible.
            #expect(caught.timeIntervalSince(visible) <= XcodeReleaseWatch.pollInterval, "\(c.name)")
        }
    }
}

// MARK: - xcodereleases misbehaving

@Test func anIndexOutageOverTheReleaseChecksOnceWhenItRecovers() async {
    let visible = pt(2026, 9, 28, 10, 50)
    let world = World(index: { now in
        if now >= pt(2026, 9, 28, 10, 0) && now < pt(2026, 9, 28, 11, 30) {
            throw URLError(.badServerResponse)
        }
        return now >= visible ? oldIndex + [newBeta] : oldIndex
    })
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(run.checks == [pt(2026, 9, 28, 11, 30)])
    let failures = run.transcript.filter { $0.contains("index unavailable") }
    #expect(failures.count == 18)   // 10:00 … 11:25
    #expect(failures.last?.contains("18 in a row") == true)
    // Kept on disk once at each end of the outage, not every five minutes.
    let kept = run.notable.filter { $0.contains("index unavailable") || $0.contains("index back") }
    #expect(kept.count == 2)
    #expect(kept.last?.contains("index back after 18 failed ask(s)") == true)
}

@Test func anIndexDownAtLaunchTakesItsBaselineAfterwardsAndStillCatchesTheRelease() async {
    // Launched Sunday while the index is down; it comes back Monday 10:00 with a
    // release that landed during the outage. The baseline must predate it.
    let world = World(index: { now in
        if now < pt(2026, 9, 27, 3, 0) { throw URLError(.timedOut) }
        if now >= pt(2026, 9, 28, 9, 0) && now < pt(2026, 9, 28, 10, 0) { throw URLError(.timedOut) }
        return now >= pt(2026, 9, 28, 9, 40) ? oldIndex + [newBeta] : oldIndex
    })
    let run = await simulate(world, from: pt(2026, 9, 27), to: pt(2026, 9, 29))
    // Hourly while it has no baseline outside the window, not every five minutes.
    #expect(run.indexAsks.prefix(4) == [pt(2026, 9, 27, 0), pt(2026, 9, 27, 1), pt(2026, 9, 27, 2), pt(2026, 9, 27, 3)])
    #expect(run.checks == [pt(2026, 9, 28, 10, 0)])
}

@Test func anUnreadableOrShortIndexNeverTriggersACheck() async {
    let world = World(index: { now in
        if now >= pt(2026, 9, 28, 10, 0) && now < pt(2026, 9, 28, 10, 30) { return [] }           // garbage
        if now >= pt(2026, 9, 28, 11, 0) && now < pt(2026, 9, 28, 11, 30) { return [oldIndex[0]] } // partial deploy
        return oldIndex
    })
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(run.checks.isEmpty)
    #expect(run.transcript.contains { $0.contains("index unavailable (no Xcode entries)") })
}

// MARK: - Apple's feed misbehaving

@Test func anAppleFeedOutageDoesNotStopTheIndexWatch() async {
    var world = World(index: releasing(newBeta, at: pt(2026, 9, 28, 10, 52)))
    world.feed = { _ in throw URLError(.cannotParseResponse) }
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(run.checks == [pt(2026, 9, 28, 10, 55)])
    #expect(run.transcript.contains { $0.contains("Apple feed unavailable") })
}

@Test func anAnnouncedBuildTheIndexNeverListsIsAbandonedAfterTwelveHours() async {
    var world = World(index: { _ in oldIndex })
    world.feed = { now in
        now >= pt(2026, 9, 28, 10, 0) ? [announcement("Xcode 27.1 beta 2 (27A9300b)", "27A9300b", at: pt(2026, 9, 28, 10, 0))] : []
    }
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 30))
    // Asked past 16:00 until 22:00, then quiet until Tuesday 09:30 — and the
    // still-fresh announcement is not taken up again.
    #expect(run.indexAsks.contains(pt(2026, 9, 28, 21, 55)))
    #expect(!run.indexAsks.contains { $0 > pt(2026, 9, 28, 22, 0) && $0 < pt(2026, 9, 29, 9, 30) })
    #expect(!run.indexAsks.contains { $0 >= pt(2026, 9, 29, 16, 0) })
    #expect(run.transcript.filter { $0.contains("Apple announced") }.count == 1)
    #expect(run.transcript.contains { $0.contains("gave up waiting for the index to list 27A9300b") })
    #expect(run.checks.isEmpty)
}

@Test func anOldAnnouncementDoesNotKeepTheWatchOpen() async {
    var world = World(index: { _ in oldIndex })
    world.feed = { _ in [announcement("Xcode 26.6 (17F999)", "17F999", at: pt(2026, 6, 25, 15, 0))] }
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(!run.indexAsks.contains { $0 >= pt(2026, 9, 28, 16, 0) })
}

// MARK: - The app's side

@Test func offlineAsksNothingAndCatchesUpWhenBack() async {
    var world = World(index: releasing(newBeta, at: pt(2026, 9, 28, 10, 20)))
    world.gate = { now in now >= pt(2026, 9, 28, 10, 0) && now < pt(2026, 9, 28, 11, 0) ? .offline : .on }
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(!run.indexAsks.contains { $0 >= pt(2026, 9, 28, 10, 0) && $0 < pt(2026, 9, 28, 11, 0) })
    #expect(run.checks == [pt(2026, 9, 28, 11, 0)])
}

@Test func aBusyAppGetsTheCheckAtTheNextAskExactlyOnce() async {
    var world = World(index: releasing(newBeta, at: pt(2026, 9, 28, 10, 50)))
    world.busy = { $0 < pt(2026, 9, 28, 11, 0) }
    let run = await simulate(world, from: pt(2026, 9, 28), to: pt(2026, 9, 29))
    #expect(run.checks == [pt(2026, 9, 28, 11, 0)])
    #expect(run.transcript.contains { $0.contains("check owed, busy") })
}

@Test func switchedOffItAsksNothingAtAll() async {
    var world = World(index: releasing(newBeta, at: pt(2026, 9, 28, 10, 50)))
    world.gate = { _ in .off("scheduled checks already run every 5 min") }
    let run = await simulate(world, from: pt(2026, 9, 27), to: pt(2026, 10, 4))
    #expect(run.indexAsks.isEmpty && run.feedAsks.isEmpty && run.checks.isEmpty)
    #expect(run.transcript == run.transcript.filter { $0.contains("off — scheduled checks") })
}

// MARK: - Apple's feed

/// Trimmed from the live feed (2026-09-23), verbatim items.
private let feedSample = #"""
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Releases - Apple Developer</title>
<item><title>iOS 27.2 beta 2 (24B5089g)</title><link>https://developer.apple.com/news/releases/?id=1</link><pubDate>Mon, 21 Sep 2026 10:00:00 PDT</pubDate></item>
<item><title>Xcode 27.1 beta (27A9269)</title><link>https://developer.apple.com/news/releases/?id=2</link><pubDate>Fri, 18 Sep 2026 10:00:00 PDT</pubDate></item>
<item><title>Xcode 27 (27A266a)</title><link>https://developer.apple.com/news/releases/?id=3</link><pubDate>Mon, 14 Sep 2026 10:00:00 PDT</pubDate></item>
<item><title>TestFlight Update</title><link>https://developer.apple.com/news/releases/?id=4</link><pubDate>Fri, 18 Sep 2026 14:00:00 PDT</pubDate></item>
<item><title><![CDATA[Xcode 26.3 Release Candidate (17C519)]]></title><pubDate>Tue, 03 Feb 2026 10:00:00 PST</pubDate></item>
</channel></rss>
"""#

@Test func appleFeedYieldsOnlyXcodeItemsWithTheirBuildAndTime() throws {
    let items = try #require(AppleDeveloperReleaseFeed.xcodeAnnouncements(in: Data(feedSample.utf8)))
    #expect(items.map(\.build) == ["27A9269", "27A266a", "17C519"])
    #expect(items[0].title == "Xcode 27.1 beta (27A9269)")
    #expect(items[0].date == utc("2026-09-18T17:00:00Z"))
    #expect(items[2].date == utc("2026-02-03T18:00:00Z"))   // PST
}

@Test func appleFeedTellsAnErrorPageFromAFeedWithNoXcode() {
    #expect(AppleDeveloperReleaseFeed.xcodeAnnouncements(in: Data("<html><body>502</body></html>".utf8)) == nil)
    let empty = #"<rss version="2.0"><channel><item><title>TestFlight Update</title><pubDate>Fri, 18 Sep 2026 14:00:00 PDT</pubDate></item></channel></rss>"#
    #expect(AppleDeveloperReleaseFeed.xcodeAnnouncements(in: Data(empty.utf8)) == [])
}
