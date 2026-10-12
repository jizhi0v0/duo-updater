import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

struct StorageInventoryTests {

    /// A fake `~/Library` with DuoUpdater's state inside it, laid out the way a
    /// real one is (names taken from a real Mac's directories, 2026-10-12).
    private func makeLayout() throws -> (StorageInventory.Layout, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-inventory-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let state = library.appendingPathComponent("Application Support", isDirectory: true)
        let files = [
            "Application Support/com.duoupdater.app/changelog-images/a.img",
            "Application Support/com.duoupdater.app/formula-icons/wget.png",
            "Application Support/com.duoupdater.app/changelogs/x.json",
            "Application Support/com.duoupdater.app/events.sqlite",
            "Application Support/com.duoupdater.app/events.sqlite-wal",
            "Application Support/com.duoupdater.app/github-conditional-cache.json",
            "Application Support/com.duoupdater.app/zoxide-published-digests.json",
            "Application Support/com.duoupdater.app/something-new.json",
            "Application Support/DuoUpdater/BackupFacts/k.json",
            "Caches/com.duoupdater.app/Cache.db",
            "Caches/com.duoupdater.cli/Cache.db",
            "WebKit/com.duoupdater.app/WebsiteDataStore/cookies",
            "Preferences/com.duoupdater.app.plist",
        ]
        for file in files {
            let url = library.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: url)
        }
        return (StorageInventory.Layout(library: library, stateBase: state), root)
    }

    @Test func everyEntryLandsInTheItemItBelongsTo() throws {
        let (layout, root) = try makeLayout()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = StorageInventory.paths(in: layout)
        func names(_ item: StorageInventory.Item) -> [String] {
            (paths[item] ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
                .map(\.lastPathComponent)
        }
        #expect(names(.changelogImages) == ["changelog-images"])
        #expect(names(.formulaIcons) == ["formula-icons"])
        #expect(names(.releaseNotes) == ["changelogs"])
        #expect(names(.history) == ["events.sqlite", "events.sqlite-wal"])
        #expect(names(.checkState) == ["github-conditional-cache.json", "zoxide-published-digests.json"])
        #expect(names(.backupIndex) == ["BackupFacts"])
        #expect(names(.networkCache) == ["com.duoupdater.app"])
        #expect(names(.cliCache) == ["com.duoupdater.cli"])
        // A file nobody has named yet still counts — toward "other", not nowhere.
        #expect(names(.otherData) == ["something-new.json"])
    }

    /// The Settings page and `duo storage` both lay their sections out from
    /// these, in this order.
    @Test func groupsListTheirItemsInPageOrder() {
        #expect(StorageInventory.Group.caches.items == [.changelogImages, .networkCache, .formulaIcons, .cliCache])
        #expect(StorageInventory.Group.appData.items
            == [.backups, .backupIndex, .history, .releaseNotes, .checkState, .otherData])
        #expect(StorageInventory.Group.system.items == [.appleDeveloperSession, .httpStorage, .preferences])
        let notClearable = StorageInventory.Group.caches.items.filter { !$0.isClearable }
        #expect(notClearable.isEmpty)
    }

    @Test func onlyRedownloadableCachesAreClearable() {
        #expect(StorageInventory.Item.allCases.filter(\.isClearable)
            == [.changelogImages, .networkCache, .formulaIcons, .cliCache])
    }

    @Test func clearingEmptiesTheCacheAndNothingElse() throws {
        let (layout, root) = try makeLayout()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = Dictionary(uniqueKeysWithValues:
            StorageInventory.measure(in: layout).map { ($0.item, $0.bytes) })
        #expect(before[.changelogImages, default: 0] > 0)

        let freed = try StorageInventory.removeContents(of: .changelogImages, in: layout)
        try StorageInventory.removeContents(of: .cliCache, in: layout)

        let after = Dictionary(uniqueKeysWithValues:
            StorageInventory.measure(in: layout).map { ($0.item, $0.bytes) })
        #expect(freed == before[.changelogImages])
        #expect(after[.changelogImages] == 0)
        #expect(after[.cliCache] == 0)
        // The directories stay: their owners create them once.
        #expect(FileManager.default.fileExists(
            atPath: layout.stateBase.appendingPathComponent("com.duoupdater.app/changelog-images").path))
        for item in StorageInventory.Item.allCases where item != .changelogImages && item != .cliCache {
            #expect(after[item] == before[item], "\(item) must not change")
        }
    }
    /// WebKit's network cache links each blob from two directories. Summed per
    /// path, the real one read twice what `du` does.
    @Test func aHardLinkedFileCountsOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-inventory-links-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blobs = root.appendingPathComponent("Blobs", isDirectory: true)
        let record = root.appendingPathComponent("Records/r1", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
        let blob = blobs.appendingPathComponent("b")
        try Data(repeating: 7, count: 64 * 1024).write(to: blob)
        let single = StorageInventory.allocatedSize(of: root)
        try FileManager.default.linkItem(at: blob, to: record.appendingPathComponent("b-blob"))
        #expect(single > 0)
        #expect(StorageInventory.allocatedSize(of: root) == single)
    }
    /// What a clear leaves in `Caches/com.duoupdater.app` (2026-10-12, this Mac):
    /// WebKit's alternative-services database and HSTS list, its `salt` files, and
    /// `Cache.db` as an empty database. None of that is something Clear Caches
    /// removes, so none of it may be offered as clearable.
    @Test func whatAClearLeavesBehindIsNotClearable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-inventory-net-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ count: Int = 8192) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: count).write(to: url)
        }
        try write("WebKit/AlternativeServices/AlternativeService.sqlite-wal", 64 * 1024)
        try write("WebKit/HSTS/HSTS.plist")
        try write("WebKit/CacheStorage/salt")
        try write("WebKit/NetworkCache/Version 17/salt")
        let database = root.appendingPathComponent("Cache.db")
        try makeURLCacheDatabase(at: database, rows: 0)

        #expect(StorageInventory.allocatedSize(of: root) > 0)
        #expect(StorageInventory.networkCacheClearableBytes(in: root) == 0)

        // A response cached afterwards is clearable again: its body, its record,
        // and the database now that it holds a row.
        try write("fsCachedData/0CFDA485")
        try write("WebKit/NetworkCache/Version 17/Records/R1/Resource/blob")
        try makeURLCacheDatabase(at: database, rows: 1)
        let clearable = StorageInventory.networkCacheClearableBytes(in: root)
        let bodies = StorageInventory.allocatedSize(of: root.appendingPathComponent("fsCachedData"))
            + StorageInventory.allocatedSize(of: root.appendingPathComponent("WebKit/NetworkCache/Version 17/Records"))
        #expect(clearable > bodies, "the database counts once it holds a response")
    }

    /// The table `URLCache` keeps responses in, with `rows` of them.
    private func makeURLCacheDatabase(at url: URL, rows: Int) throws {
        try? FileManager.default.removeItem(at: url)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE cfurl_cache_response (entry_ID INTEGER PRIMARY KEY, request_key TEXT)", nil, nil, nil) == SQLITE_OK)
        for row in 0..<rows {
            #expect(sqlite3_exec(db, "INSERT INTO cfurl_cache_response (request_key) VALUES ('https://example.com/\(row)')", nil, nil, nil) == SQLITE_OK)
        }
    }
}
