import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// `duo storage` against a fake `~/Library`, never the real one: `clear`
/// deletes files.
@Suite struct StorageCommandTests {

    private func makeLayout() throws -> (StorageInventory.Layout, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoKitStorage-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        for file in [
            "Application Support/com.duoupdater.app/changelog-images/a.img",
            "Application Support/com.duoupdater.app/formula-icons/wget.png",
            "Application Support/com.duoupdater.app/changelogs/x.json",
            "Application Support/com.duoupdater.app/events.sqlite",
            "Caches/com.duoupdater.app/fsCachedData/body",
            "Caches/com.duoupdater.cli/fsCachedData/body",
        ] {
            let url = library.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: url)
        }
        return (StorageInventory.Layout(
            library: library,
            stateBase: library.appendingPathComponent("Application Support")), root)
    }

    @Test func listGroupsEveryItemAsTheSettingsPageDoes() throws {
        let (layout, root) = try makeLayout()
        defer { try? FileManager.default.removeItem(at: root) }
        var lines: [String] = []
        Storage.list(json: false, layout: layout) { lines.append($0) }
        let text = lines.joined(separator: "\n")
        #expect(lines.first?.hasPrefix("DuoUpdater uses ") == true)
        #expect(text.contains("Caches — "))
        #expect(text.contains("App data — "))
        #expect(text.contains("Kept by macOS for DuoUpdater"))
        #expect(text.contains("Release note images"))
        // Nothing under "Other" in this layout, so no row for it.
        #expect(!text.contains("  Other "))
    }

    /// The heading names only what this command frees; the app's web cache is
    /// a separate figure, said to be cleared in the app.
    @Test func cachesHeadingKeepsTheAppsShareApart() {
        func row(_ item: StorageInventory.Item, _ clearable: Int64) -> Storage.Row {
            Storage.Row(item: item.rawValue, group: "caches", name: "", bytes: clearable,
                        clearableBytes: clearable, paths: [])
        }
        let mb: Int64 = 1_000_000
        #expect(Storage.cachesHeading([row(.changelogImages, 0), row(.networkCache, 0)])
            == "Caches — nothing to clear")
        #expect(Storage.cachesHeading([row(.changelogImages, 6 * mb), row(.networkCache, 0)])
            == "Caches — 6 MB can be cleared with `duo storage clear`")
        #expect(Storage.cachesHeading([row(.changelogImages, 6 * mb), row(.networkCache, 2 * mb)])
            == "Caches — 6 MB can be cleared with `duo storage clear`, 2 MB more in DuoUpdater › Settings › Storage")
        #expect(Storage.cachesHeading([row(.changelogImages, 0), row(.networkCache, 2 * mb)])
            == "Caches — 2 MB can be cleared in DuoUpdater › Settings › Storage")
    }

    @Test func jsonRowsCarryEveryPathAndTheClearableShare() throws {
        let (layout, root) = try makeLayout()
        defer { try? FileManager.default.removeItem(at: root) }
        var lines: [String] = []
        Storage.list(json: true, layout: layout) { lines.append($0) }
        #expect(lines.first?.contains("\"command\":\"storage\"") == true)
        let rows = lines.dropFirst().compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let images = rows.first { $0["item"] as? String == "changelogImages" }
        #expect(images?["group"] as? String == "caches")
        #expect((images?["clearableBytes"] as? Int ?? 0) > 0)
        let history = rows.first { $0["item"] as? String == "history" }
        #expect(history?["clearableBytes"] as? Int == 0)
        #expect((history?["paths"] as? [String])?.first?.hasSuffix("events.sqlite") == true)
    }

    /// The three caches the CLI owns are emptied; the app's web cache is named
    /// and left; nothing else changes.
    @Test func clearEmptiesTheCLIsCachesAndLeavesTheAppsWebCache() throws {
        let (layout, root) = try makeLayout()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = Dictionary(uniqueKeysWithValues:
            StorageInventory.measure(in: layout).map { ($0.item, $0.bytes) })
        var lines: [String] = []
        let status = Storage.clear(json: true, layout: layout) { lines.append($0) }
        #expect(status == 0)
        let after = Dictionary(uniqueKeysWithValues:
            StorageInventory.measure(in: layout).map { ($0.item, $0.bytes) })
        for item in [StorageInventory.Item.changelogImages, .formulaIcons, .cliCache] {
            #expect(after[item] == 0, "\(item) should be empty")
        }
        for item in StorageInventory.Item.allCases
        where ![.changelogImages, .formulaIcons, .cliCache].contains(item) {
            #expect(after[item] == before[item], "\(item) must not change")
        }
        let skipped = lines.dropFirst().compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }.first { $0["item"] as? String == "networkCache" }
        #expect(skipped?["skipped"] as? String == Storage.networkCacheSkipReason)
    }
}
