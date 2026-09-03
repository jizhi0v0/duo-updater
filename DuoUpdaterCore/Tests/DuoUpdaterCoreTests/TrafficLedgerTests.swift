import Testing
import Foundation
@testable import DuoUpdaterCore

/// The rules of the per-app download ledger.
///
/// These used to run against `TrafficStore` and its `traffic.json`. The ledger
/// moved into ``EventStore`` as `install` events; the rules did not change, so
/// they moved with it rather than being deleted — a rule that stops being
/// executed because its subject was renamed is a rule that stops holding.
@Suite(.serialized)
struct TrafficLedgerTests {

    private static func store() -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, flushEventCount: 1,
                           flushDelay: .milliseconds(10)), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    private static func install(
        _ store: EventStore, app: String, name: String, bundleID: String? = nil,
        from: String? = "1.0", to: String? = "1.1", source: String? = "Sparkle",
        bytes: Int64, kind: TrafficDownloadKind = .full, at date: Date = Date()
    ) async {
        await store.append(DuoEvent(date: date, client: .app, payload: .install(
            InstallEvent(appID: app, appName: name, bundleID: bundleID,
                         fromVersion: from, toVersion: to, sourceName: source,
                         bytes: bytes, downloadKind: kind))))
        await store.flush()
    }

    @Test func recordsExactBytesPerApp() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A",
                           bundleID: "com.example.a", bytes: 1_234_567)

        let stat = await store.appTrafficStats().first
        #expect(stat?.appID == "/Applications/A.app")
        #expect(stat?.bundleID == "com.example.a")
        // To the byte. A rounded ledger is a ledger nobody can check.
        #expect(stat?.totalBytes == 1_234_567)
        #expect(stat?.updateCount == 1)
    }

    @Test func recordsTheExactDeltaRoute() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A",
                           bytes: 500, kind: .delta)
        let event = await store.appTrafficStats().first?.events.first
        #expect(event?.downloadKind == .delta)
    }

    @Test func accumulatesMultipleDownloadsToTheByte() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        for bytes in [Int64(100), 250, 3] {
            await Self.install(store, app: "/Applications/A.app", name: "A", bytes: bytes)
        }
        let stat = await store.appTrafficStats().first
        #expect(stat?.totalBytes == 353)
        #expect(stat?.updateCount == 3)
    }

    @Test func keepsAppsSeparateAndSumsGrandTotal() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 10)
        await Self.install(store, app: "/Applications/B.app", name: "B", bytes: 20)

        let stats = await store.appTrafficStats()
        #expect(stats.count == 2)
        #expect(stats.reduce(Int64(0)) { $0 + $1.totalBytes } == 30)
    }

    @Test func ignoresNonPositiveBytes() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 0)
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: -5)

        // A download that moved nothing is not a download, and a zero-byte row
        // would inflate the update count with an install that never happened.
        #expect(await store.appTrafficStats().isEmpty)
        #expect(await store.rejectedCount == 2)
    }

    @Test func snapshotSortsByTotalBytesDescending() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/Small.app", name: "Small", bytes: 10)
        await Self.install(store, app: "/Applications/Big.app", name: "Big", bytes: 900)
        await Self.install(store, app: "/Applications/Mid.app", name: "Mid", bytes: 100)

        #expect(await store.appTrafficStats().map(\.appName) == ["Big", "Mid", "Small"])
    }

    @Test func persistsAcrossReloadFromSameFile() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 4_242)

        let reopened = EventStore(fileURL: url, flushEventCount: 1,
                                  flushDelay: .milliseconds(10))
        #expect(await reopened.appTrafficStats().first?.totalBytes == 4_242)
    }

    @Test func resetClearsEverythingWhenAskedTo() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 10)

        // Only when asked: the default spares the ledger, which
        // `InstallEventMigrationTests` pins separately.
        await store.reset(includingInstalls: true)
        #expect(await store.appTrafficStats().isEmpty)
    }

    @Test func refreshesDisplayNameOnLaterRecord() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await Self.install(store, app: "/Applications/A.app", name: "Old Name",
                           bytes: 10, at: start)
        await Self.install(store, app: "/Applications/A.app", name: "New Name",
                           bytes: 10, at: start + 60)

        // The row should read as the app is called now, not as it was called the
        // first time it updated.
        #expect(await store.appTrafficStats().first?.appName == "New Name")
    }

    @Test func formattedBytesIsHumanReadable() {
        #expect(ByteFormat.string(0) == ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
        #expect(ByteFormat.string(1_500_000).contains("MB"))
    }

    @Test func lastUpdatedTracksNewestEvent() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 10, at: start)
        await Self.install(store, app: "/Applications/A.app", name: "A", bytes: 10,
                           at: start + 3_600)

        let stat = await store.appTrafficStats().first
        // Derived from the history rather than stored, so it cannot drift out of
        // step with the events — and the history has to come back in order for
        // that to hold.
        #expect(stat?.lastUpdated == start + 3_600)
        #expect(stat?.events.map(\.date) == [start, start + 3_600])
    }
}
