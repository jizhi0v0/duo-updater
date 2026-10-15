import Testing
import Foundation
@testable import DuoUpdaterCore

/// Failures kept for a later report: stored and read back whole, pruned with
/// the request log, and turned into a report that leaves the account name out.
@Suite(.serialized)
struct InstallFailureEventTests {

    private static func store(
        retentionDays: Int = 30, now: @escaping @Sendable () -> Date = Date.init
    ) -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, retentionDays: retentionDays,
                           flushEventCount: 1, flushDelay: .milliseconds(10),
                           pruneInterval: .zero, now: now), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    private static let failure = InstallFailureEvent(
        appID: "/Applications/Surge.app", appName: "Surge",
        bundleID: "com.nssurge.surge-mac", fromVersion: "6.9.0", toVersion: "6.9.1",
        sourceName: "Sparkle", stage: .relaunch,
        message: "Surge restarted without applying the update.")

    @Test func roundTripsThroughTheStore() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()

        let read = await store.events(EventQuery(kind: "failure"))
        #expect(read.count == 1)
        #expect(read.first?.failure == Self.failure)
        // The app column is filled, so a per-app query over every kind finds it.
        let rows = await store.rawRows(EventQuery(kind: "failure"))
        #expect(rows.first?.kind == "failure")
    }

    @Test func aPayloadThisBuildCannotReadStaysUnknown() {
        let row = EventRow(
            id: UUID(), date: Date(), client: .app, kind: "failure",
            payloadJSON: #"{"appName":"Surge"}"#)
        let event = DuoEvent(row: row)
        #expect(event?.failure == nil)
        #expect(event?.kind == "failure")
    }

    @Test func prunedWithTheRequestLog() async {
        let (store, url) = Self.store(retentionDays: 30)
        defer { Self.remove(url) }
        let old = Date().addingTimeInterval(-40 * 86_400)
        await store.append(DuoEvent(date: old, payload: .failure(Self.failure)))
        await store.flush()
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()

        let left = await store.events(EventQuery(kind: "failure"))
        #expect(left.count == 1)
        #expect(left.first.map { $0.date > old } == true)
    }

    @Test func clearingTheRequestLogKeepsFailures() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()
        await store.reset()

        #expect(await store.events(EventQuery(kind: "failure")).count == 1)
    }

    @Test func reportAbbreviatesTheHomeDirectory() {
        let failure = InstallFailureEvent(
            appID: "/Users/someone/Applications/Foo.app", appName: "Foo",
            bundleID: "com.example.foo", fromVersion: "1.0", toVersion: "1.1",
            sourceName: "GitHub", stage: .install,
            message: "Couldn’t replace /Users/someone/Applications/Foo.app")
        let text = InstallFailureReport.text(
            for: failure, at: Date(timeIntervalSince1970: 1_760_000_000),
            duoUpdaterVersion: "0.6.0 (600)", osVersion: "Version 27.2",
            architecture: "arm64", homeDirectory: "/Users/someone")
        #expect(!text.contains("someone"))
        #expect(text.contains("Couldn’t replace ~/Applications/Foo.app"))
        #expect(text.contains("App: Foo (com.example.foo)"))
        #expect(text.contains("Update: 1.0 → 1.1 via GitHub"))
        #expect(text.contains("Stage: install"))
        #expect(text.contains("DuoUpdater: 0.6.0 (600)"))
        #expect(text.contains("macOS: Version 27.2 (arm64)"))
    }
}
