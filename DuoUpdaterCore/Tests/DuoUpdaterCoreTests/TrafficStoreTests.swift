import Testing
import Foundation
@testable import DuoUpdaterCore

/// `TrafficStore` is the per-app, to-the-byte download ledger. The fragile parts
/// are exact accumulation, the guard against zero/placeholder records, and that
/// the JSON file round-trips so totals survive a relaunch.

private func tempFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("traffic-test-\(UUID().uuidString)")
        .appendingPathComponent("traffic.json")
}

@Test func recordsExactBytesPerApp() async {
    let store = TrafficStore(fileURL: tempFileURL())
    await store.record(
        appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.foo",
        fromVersion: "1.0", toVersion: "1.1", sourceName: "Sparkle", bytes: 1_234_567
    )
    let stat = await store.stat(forAppID: "/Applications/Foo.app")
    #expect(stat?.totalBytes == 1_234_567)
    #expect(stat?.updateCount == 1)
    #expect(stat?.events.first?.bytes == 1_234_567)
    #expect(stat?.events.first?.fromVersion == "1.0")
    #expect(stat?.events.first?.toVersion == "1.1")
    #expect(stat?.events.first?.downloadKind == .full)
}

@Test func recordsTheExactDeltaRoute() async {
    let store = TrafficStore(fileURL: tempFileURL())
    await store.record(
        appID: "/Applications/Patched.app", appName: "Patched", bundleID: "com.patched",
        fromVersion: "1.0", toVersion: "1.1", sourceName: "Sparkle", bytes: 1_900_000,
        downloadKind: .delta
    )
    let event = await store.stat(forAppID: "/Applications/Patched.app")?.events.first
    #expect(event?.downloadKind == .delta)
}

@Test func accumulatesMultipleDownloadsToTheByte() async {
    let store = TrafficStore(fileURL: tempFileURL())
    let id = "/Applications/Bar.app"
    await store.record(appID: id, appName: "Bar", bundleID: nil,
                       fromVersion: "1.0", toVersion: "1.1", sourceName: "Vendor", bytes: 100)
    await store.record(appID: id, appName: "Bar", bundleID: nil,
                       fromVersion: "1.1", toVersion: "1.2", sourceName: "Vendor", bytes: 250)
    await store.record(appID: id, appName: "Bar", bundleID: nil,
                       fromVersion: "1.2", toVersion: "1.3", sourceName: "Vendor", bytes: 7)
    let stat = await store.stat(forAppID: id)
    #expect(stat?.totalBytes == 357)
    #expect(stat?.updateCount == 3)
}

@Test func keepsAppsSeparateAndSumsGrandTotal() async {
    let store = TrafficStore(fileURL: tempFileURL())
    await store.record(appID: "/a.app", appName: "A", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Sparkle", bytes: 1000)
    await store.record(appID: "/b.app", appName: "B", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Sparkle", bytes: 500)
    #expect(await store.totalBytes() == 1500)
    #expect(await store.stat(forAppID: "/a.app")?.totalBytes == 1000)
    #expect(await store.stat(forAppID: "/b.app")?.totalBytes == 500)
}

@Test func ignoresNonPositiveBytes() async {
    let store = TrafficStore(fileURL: tempFileURL())
    let id = "/z.app"
    await store.record(appID: id, appName: "Z", bundleID: nil,
                       fromVersion: nil, toVersion: nil, sourceName: nil, bytes: 0)
    await store.record(appID: id, appName: "Z", bundleID: nil,
                       fromVersion: nil, toVersion: nil, sourceName: nil, bytes: -42)
    // Nothing recorded — no event, no row, no inflated count.
    #expect(await store.stat(forAppID: id) == nil)
    #expect(await store.totalBytes() == 0)
}

@Test func snapshotSortsByTotalBytesDescending() async {
    let store = TrafficStore(fileURL: tempFileURL())
    await store.record(appID: "/small.app", appName: "Small", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 10)
    await store.record(appID: "/big.app", appName: "Big", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 9_000_000)
    await store.record(appID: "/mid.app", appName: "Mid", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 5000)
    let snapshot = await store.snapshot()
    #expect(snapshot.map(\.appName) == ["Big", "Mid", "Small"])
}

@Test func persistsAcrossReloadFromSameFile() async {
    let url = tempFileURL()
    let store = TrafficStore(fileURL: url)
    await store.record(appID: "/p.app", appName: "Persisted", bundleID: "com.p",
                       fromVersion: "2.0", toVersion: "2.1", sourceName: "GitHub", bytes: 424_242)
    // A fresh store over the same file must see the recorded total — proving the
    // JSON round-trips and totals survive a relaunch.
    let reloaded = TrafficStore(fileURL: url)
    let stat = await reloaded.stat(forAppID: "/p.app")
    #expect(stat?.totalBytes == 424_242)
    #expect(stat?.bundleID == "com.p")
    #expect(stat?.events.first?.sourceName == "GitHub")
    await store.reset()
}

@Test func resetClearsEverythingAndFile() async {
    let url = tempFileURL()
    let store = TrafficStore(fileURL: url)
    await store.record(appID: "/r.app", appName: "R", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 999)
    await store.reset()
    #expect(await store.totalBytes() == 0)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    // A new store over the now-deleted file starts empty.
    let reloaded = TrafficStore(fileURL: url)
    #expect(await reloaded.snapshot().isEmpty)
}

@Test func refreshesDisplayNameOnLaterRecord() async {
    let store = TrafficStore(fileURL: tempFileURL())
    let id = "/Applications/Renamed.app"
    await store.record(appID: id, appName: "OldName", bundleID: "com.x",
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 10)
    await store.record(appID: id, appName: "NewName", bundleID: "com.x",
                       fromVersion: nil, toVersion: "2", sourceName: "Vendor", bytes: 20)
    let stat = await store.stat(forAppID: id)
    #expect(stat?.appName == "NewName")
    #expect(stat?.totalBytes == 30)
}

@Test func formattedBytesIsHumanReadable() {
    // A megabyte-scale value renders in MB, not raw bytes.
    #expect(ByteFormat.string(5_000_000).contains("MB"))
    // A small value stays small-unit (KB/bytes), never MB/GB.
    let small = ByteFormat.string(512)
    #expect(!small.contains("MB") && !small.contains("GB"))
}

@Test func lastUpdatedTracksNewestEvent() async {
    let store = TrafficStore(fileURL: tempFileURL())
    let id = "/Applications/Timed.app"
    let t1 = Date(timeIntervalSince1970: 1_000_000)
    let t2 = Date(timeIntervalSince1970: 2_000_000)
    await store.record(appID: id, appName: "Timed", bundleID: nil,
                       fromVersion: nil, toVersion: "1", sourceName: "Vendor", bytes: 10, date: t1)
    await store.record(appID: id, appName: "Timed", bundleID: nil,
                       fromVersion: nil, toVersion: "2", sourceName: "Vendor", bytes: 20, date: t2)
    let stat = await store.stat(forAppID: id)
    // Derived from the newest event, not stored separately.
    #expect(stat?.lastUpdated == t2)
}
