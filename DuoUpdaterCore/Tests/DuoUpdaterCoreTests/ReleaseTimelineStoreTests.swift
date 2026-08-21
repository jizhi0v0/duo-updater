import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ReleaseTimelineStore` is the persistent log of every release we've seen a
/// source announce. The fragile parts are: it records each version exactly once
/// (re-checks don't pile up), it silently drops releases with no trustworthy
/// vendor date, and the JSON round-trips so history survives a relaunch.

private func tempFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("releases-test-\(UUID().uuidString)")
        .appendingPathComponent("releases.json")
}

private let d1 = Date(timeIntervalSince1970: 1_700_000_000)
private let d2 = Date(timeIntervalSince1970: 1_710_000_000)
private let d3 = Date(timeIntervalSince1970: 1_720_000_000)

@Test func recordsAReleaseWithItsPublishedDate() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let added = await store.record(
        appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.foo",
        version: "1.2.0", sourceName: "Sparkle", publishedAt: d1)
    #expect(added)
    let tl = await store.timeline(forAppID: "/Applications/Foo.app")
    #expect(tl?.events.count == 1)
    #expect(tl?.events.first?.version == "1.2.0")
    #expect(tl?.events.first?.publishedAt == d1)
    #expect(tl?.events.first?.sourceName == "Sparkle")
}

@Test func skipsReleasesWithNoTrustworthyDate() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    // A vendor probe with no published date must not be logged at all.
    let added = await store.record(
        appID: "/Applications/Probe.app", appName: "Probe", bundleID: nil,
        version: "9.9", sourceName: "Vendor", publishedAt: nil)
    #expect(!added)
    #expect(await store.timeline(forAppID: "/Applications/Probe.app") == nil)
    #expect(await store.totalEvents() == 0)
}

@Test func dedupesSameVersionAtFirstSighting() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let id = "/Applications/Bar.app"
    let first = await store.record(appID: id, appName: "Bar", bundleID: nil,
        version: "2.0", sourceName: "GitHub", publishedAt: d1, detectedAt: d1)
    // Re-checking the same version later is a no-op — and must not move detectedAt.
    let second = await store.record(appID: id, appName: "Bar", bundleID: nil,
        version: "2.0", sourceName: "GitHub", publishedAt: d1, detectedAt: d3)
    #expect(first)
    #expect(!second)
    let tl = await store.timeline(forAppID: id)
    #expect(tl?.events.count == 1)
    #expect(tl?.events.first?.detectedAt == d1)   // first sighting wins
}

@Test func appendsDistinctVersionsSortedByPublishDate() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let id = "/Applications/Baz.app"
    // Record out of order; the timeline must end up oldest-published first.
    await store.record(appID: id, appName: "Baz", bundleID: nil,
        version: "1.2", sourceName: "Sparkle", publishedAt: d2)
    await store.record(appID: id, appName: "Baz", bundleID: nil,
        version: "1.3", sourceName: "Sparkle", publishedAt: d3)
    await store.record(appID: id, appName: "Baz", bundleID: nil,
        version: "1.1", sourceName: "Sparkle", publishedAt: d1)
    let tl = await store.timeline(forAppID: id)
    #expect(tl?.events.map(\.version) == ["1.1", "1.2", "1.3"])
    #expect(tl?.latest?.version == "1.3")
}

@Test func snapshotSortsByMostRecentReleaseFirst() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    await store.record(appID: "/old.app", appName: "Old", bundleID: nil,
        version: "1", sourceName: "Sparkle", publishedAt: d1)
    await store.record(appID: "/new.app", appName: "New", bundleID: nil,
        version: "1", sourceName: "Sparkle", publishedAt: d3)
    await store.record(appID: "/mid.app", appName: "Mid", bundleID: nil,
        version: "1", sourceName: "Sparkle", publishedAt: d2)
    let snap = await store.snapshot()
    #expect(snap.map(\.appName) == ["New", "Mid", "Old"])
}

@Test func allEventsAreGlobalNewestFirst() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    await store.record(appID: "/a.app", appName: "A", bundleID: nil,
        version: "1", sourceName: "Sparkle", publishedAt: d1)
    await store.record(appID: "/b.app", appName: "B", bundleID: nil,
        version: "1", sourceName: "GitHub", publishedAt: d3)
    await store.record(appID: "/a.app", appName: "A", bundleID: nil,
        version: "2", sourceName: "Sparkle", publishedAt: d2)
    let events = await store.allEvents()
    #expect(events.map(\.event.publishedAt) == [d3, d2, d1])
    #expect(events.first?.timeline.appName == "B")
}

@Test func releaseTimelinePersistsAcrossReload() async {
    let url = tempFileURL()
    let store = ReleaseTimelineStore(fileURL: url)
    await store.record(appID: "/p.app", appName: "Persisted", bundleID: "com.p",
        version: "3.1", sourceName: "GitHub", publishedAt: d2)
    // Writes are batched, so persistence happens at the end of a recording batch.
    await store.flush()
    // A fresh store over the same file must see the logged release — proving the
    // JSON round-trips with the time-of-day intact.
    let reloaded = ReleaseTimelineStore(fileURL: url)
    let tl = await reloaded.timeline(forAppID: "/p.app")
    #expect(tl?.events.first?.version == "3.1")
    #expect(tl?.events.first?.publishedAt == d2)
    #expect(tl?.bundleID == "com.p")
    await store.reset()
}

@Test func releaseTimelineRefreshesDisplayName() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let id = "/Applications/Renamed.app"
    await store.record(appID: id, appName: "OldName", bundleID: "com.x",
        version: "1", sourceName: "Sparkle", publishedAt: d1)
    await store.record(appID: id, appName: "NewName", bundleID: "com.x",
        version: "2", sourceName: "Sparkle", publishedAt: d2)
    let tl = await store.timeline(forAppID: id)
    #expect(tl?.appName == "NewName")
}

@Test func sameVersionDisplayMetadataPersistsAcrossReload() async {
    let url = tempFileURL()
    let store = ReleaseTimelineStore(fileURL: url)
    let id = "/Applications/Renamed.app"
    await store.record(appID: id, appName: "OldName", bundleID: "com.old",
        version: "1", sourceName: "Sparkle", publishedAt: d1)
    await store.flush()

    let added = await store.record(appID: id, appName: "NewName", bundleID: "com.new",
        version: "1", sourceName: "Sparkle", publishedAt: d1)
    #expect(!added)
    await store.flush()

    let reloaded = ReleaseTimelineStore(fileURL: url)
    let timeline = await reloaded.timeline(forAppID: id)
    #expect(timeline?.appName == "NewName")
    #expect(timeline?.bundleID == "com.new")
    await store.reset()
}

@Test func ignoresEmptyVersion() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let added = await store.record(appID: "/e.app", appName: "E", bundleID: nil,
        version: "  ", sourceName: "Sparkle", publishedAt: d1)
    #expect(!added)
    #expect(await store.totalEvents() == 0)
}

// MARK: - Detection-only estimated windows (observeForChange)

@Test func firstSightingRecordsNoEstimate() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    // No prior baseline → can't bound a window, so nothing is logged yet.
    let added = await store.observeForChange(appID: "/v.app", appName: "V", bundleID: nil,
        version: "1.0", sourceName: "Vendor", now: d1)
    #expect(!added)
    #expect(await store.totalEvents() == 0)
}

@Test func versionChangeRecordsEstimatedWindow() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let id = "/v.app"
    // See 1.0 twice (baseline tightens to d2), then 1.1 at d3.
    await store.observeForChange(appID: id, appName: "V", bundleID: nil,
        version: "1.0", sourceName: "Vendor", now: d1)
    await store.observeForChange(appID: id, appName: "V", bundleID: nil,
        version: "1.0", sourceName: "Vendor", now: d2)
    let added = await store.observeForChange(appID: id, appName: "V", bundleID: nil,
        version: "1.1", sourceName: "Vendor", now: d3)
    #expect(added)
    let e = await store.timeline(forAppID: id)?.events.first
    #expect(e?.version == "1.1")
    #expect(e?.isApproximate == true)
    #expect(e?.publishedAt == nil)
    // Window is bounded by the *last* time we saw the old version (d2), not d1.
    #expect(e?.estimatedRange?.start == d2)
    #expect(e?.estimatedRange?.end == d3)
}

@Test func unchangedVersionAddsNothing() async {
    let store = ReleaseTimelineStore(fileURL: tempFileURL())
    let id = "/v.app"
    await store.observeForChange(appID: id, appName: "V", bundleID: nil,
        version: "2.0", sourceName: "Vendor", now: d1)
    let again = await store.observeForChange(appID: id, appName: "V", bundleID: nil,
        version: "2.0", sourceName: "Vendor", now: d3)
    #expect(!again)
    #expect(await store.totalEvents() == 0)
}

@Test func estimatedBaselinePersistsAcrossReload() async {
    let url = tempFileURL()
    let store = ReleaseTimelineStore(fileURL: url)
    // Establish a baseline, then a *fresh* store (reload) must still detect the
    // change against it — proving the observation baseline round-trips to disk.
    await store.observeForChange(appID: "/v.app", appName: "V", bundleID: nil,
        version: "1.0", sourceName: "Vendor", now: d1)
    await store.flush()
    let reloaded = ReleaseTimelineStore(fileURL: url)
    let added = await reloaded.observeForChange(appID: "/v.app", appName: "V", bundleID: nil,
        version: "1.1", sourceName: "Vendor", now: d2)
    #expect(added)
    #expect(await reloaded.timeline(forAppID: "/v.app")?.events.first?.estimatedRange?.start == d1)
    await store.reset()
}
