import Foundation
import SQLite3
import Testing
@testable import DuoUpdaterCore

struct OpenScreenSharingChannelTests {

    @Test func onlyNightlyAnswers() {
        #expect(OpenScreenSharingChannel.resolve(track: "nightly")?.channel == .nightly)
        #expect(OpenScreenSharingChannel.resolve(track: "stable") == nil)
        #expect(OpenScreenSharingChannel.resolve(track: nil) == nil)
        #expect(OpenScreenSharingChannel.resolve(track: "Nightly") == nil)
    }

    @Test func isBoundAndSelectsARecipe() {
        let id = OpenScreenSharingChannel.bundleID.lowercased()
        #expect(ChannelBinding.boundBundleIDs.contains(id))
        #expect(ChannelBinding.hasResolver(bundleID: OpenScreenSharingChannel.bundleID))
        #expect(ChannelBinding.vendorProbeBackedBindings.contains(id))
    }

    /// Pins the decoding against a database built the way the app's GRDB store
    /// writes it (schema and bytes as read from the real app, 2026-10-17). It
    /// cannot pin the path or the Full Disk Access gate — only a live read can.
    @Test func theReaderDecodesTheGRDBRow() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openscreensharing-binding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Screen Sharing.sqlite")

        #expect(OpenScreenSharingChannel.readTrack(at: file) == nil)

        try write(file, rows: [("checksForUpdatesAutomatically", Data("false".utf8))])
        #expect(OpenScreenSharingChannel.readTrack(at: file) == nil)

        try write(file, rows: [("updateTrack", Data([0x22, 0x6E, 0x69, 0x67, 0x68, 0x74, 0x6C, 0x79, 0x22]))])
        #expect(OpenScreenSharingChannel.readTrack(at: file) == "nightly")

        try write(file, rows: [("updateTrack", Data(#""stable""#.utf8))])
        #expect(OpenScreenSharingChannel.readTrack(at: file) == "stable")

        try write(file, rows: [("updateTrack", Data("nightly".utf8))])
        #expect(OpenScreenSharingChannel.readTrack(at: file) == nil)
    }

    /// GitHub's list on 2026-10-17, after nightly build 27: `v1.0.1` first,
    /// although the recreated `nightly` was published 1.5 hours later.
    @Test func theNightlyRailOpensOnTheNewestPublishedRelease() throws {
        let body = #"""
        [{"tag_name":"v1.0.1","prerelease":false,"draft":false,"published_at":"2026-10-17T04:21:49Z","body":"* Fixes and improvements"},
         {"tag_name":"nightly","prerelease":true,"draft":false,"published_at":"2026-10-17T05:59:36Z","body":"* Fix Info.plist and string catalogs"},
         {"tag_name":"v1.0.0","prerelease":false,"draft":false,"published_at":"2026-10-14T11:19:28Z","body":"* Initial release"}]
        """#
        let recipe = try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == OpenScreenSharingChannel.bundleID && $0.channel == .nightly })
        #expect(recipe.ordersByPublishedDate)
        let sorted = try #require(ChangelogService.parse(recipe, body: body))
        #expect(sorted.entries.map(\.version) == ["nightly", "1.0.1", "1.0.0"])
        let listOrder = try #require(StructuredChangelogDecoder.decode(
            body, format: .gitHubReleases, channel: .nightly, maxEntries: 20,
            includesPromotedStable: true))
        #expect(listOrder.entries.map(\.version) == ["1.0.1", "nightly", "1.0.0"])
    }

    private func write(_ url: URL, rows: [(String, Data)]) throws {
        try? FileManager.default.removeItem(at: url)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        try #require(sqlite3_exec(db, #"CREATE TABLE "preferences" ("name" TEXT PRIMARY KEY NOT NULL, "data" BLOB NOT NULL)"#, nil, nil, nil) == SQLITE_OK)
        for (name, data) in rows {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try #require(sqlite3_prepare_v2(db, "INSERT INTO preferences (name, data) VALUES (?1, ?2)", -1, &statement, nil) == SQLITE_OK)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, name, -1, transient)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient) }
            try #require(sqlite3_step(statement) == SQLITE_DONE)
        }
    }
}
