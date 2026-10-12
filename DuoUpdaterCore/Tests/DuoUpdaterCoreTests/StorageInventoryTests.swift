import Testing
import Foundation
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
}
