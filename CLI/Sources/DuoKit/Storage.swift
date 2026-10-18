import Foundation
import DuoUpdaterCore

/// `duo storage` — where DuoUpdater keeps things on this Mac, how big each part
/// is, and clearing the caches.
///
/// The same map as Settings › Storage: which path is which item, which group it
/// is shown under and what a clear removes all come from `StorageInventory` in
/// Core, so the two cannot disagree about any of it. Only the names are this
/// file's own — the app's are localized, these are the English ones.
///
/// One cache is listed here and not cleared: the menu-bar app's web and
/// download cache. Its owners are live inside the app's process — `URLCache`
/// holds the database open, WebKit's network process holds its cache — and the
/// app clears them through their own APIs. From another process the only tool
/// is deleting the files under an open database, which is not clearing it. So
/// `clear` says where to do that instead of pretending.
public enum Storage {

    public struct Options: Sendable {
        public enum Operation: Sendable, Equatable {
            case list
            case clear
        }
        public var operation: Operation
        public var json = false
        public init(operation: Operation) { self.operation = operation }
    }

    public static func run(_ options: Options) async -> Int32 {
        switch options.operation {
        case .list: list(json: options.json)
        case .clear: clear(json: options.json)
        }
    }

    // MARK: - list

    struct Row: Encodable, Equatable {
        /// `StorageInventory.Item`'s raw value — stable, unlike `name`.
        let item: String
        let group: String
        let name: String
        let bytes: Int64
        /// What `duo storage clear` or the app's Clear Caches would remove.
        let clearableBytes: Int64
        /// Every path counted, existing ones only.
        let paths: [String]
    }

    static func rows(in layout: StorageInventory.Layout = .current) -> [Row] {
        StorageInventory.measure(in: layout)
            // Shown only when there is something in it, as on the Settings page.
            .filter { $0.item != .otherData || $0.bytes > 0 }
            .map {
                Row(item: $0.item.rawValue, group: $0.item.group.rawValue, name: name($0.item),
                    bytes: $0.bytes, clearableBytes: $0.clearableBytes, paths: $0.paths.map(\.path))
            }
    }

    @discardableResult
    static func list(
        json: Bool, layout: StorageInventory.Layout = .current,
        print: (String) -> Void = { Swift.print($0) }
    ) -> Int32 {
        let rows = rows(in: layout)
        if json {
            NDJSON.begin("storage", print: print)
            for row in rows { NDJSON.row(row, print: print) }
            return 0
        }
        print("DuoUpdater uses \(format(rows.reduce(0) { $0 + $1.bytes })) on this Mac.")
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let sizeWidth = rows.map { format($0.bytes).count }.max() ?? 0
        for group in StorageInventory.Group.allCases {
            let members = rows.filter { $0.group == group.rawValue }
            guard !members.isEmpty else { continue }
            print("")
            switch group {
            case .caches:
                print(cachesHeading(members))
            case .appData:
                print("App data — needed for restores, history and checks; not cleared")
            case .system:
                print("Kept by macOS for DuoUpdater")
            }
            for row in members {
                let size = format(row.bytes)
                let padding = String(repeating: " ", count: sizeWidth - size.count)
                print("  \(row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  "
                    + "\(padding)\(size)  \(location(of: row.paths) ?? "—")")
            }
        }
        return 0
    }

    /// What `duo storage clear` would free, apart from what only the app can:
    /// a single sum that included the app's web cache promised bytes this
    /// command then leaves behind.
    static func cachesHeading(_ caches: [Row]) -> String {
        let appOnly = StorageInventory.Item.networkCache.rawValue
        let here = caches.filter { $0.item != appOnly }.reduce(0) { $0 + $1.clearableBytes }
        let inApp = caches.filter { $0.item == appOnly }.reduce(0) { $0 + $1.clearableBytes }
        switch (here, inApp) {
        case (0, 0): return "Caches — nothing to clear"
        case (_, 0): return "Caches — \(format(here)) can be cleared with `duo storage clear`"
        case (0, _): return "Caches — \(format(inApp)) can be cleared in DuoUpdater › Settings › Storage"
        default:
            return "Caches — \(format(here)) can be cleared with `duo storage clear`, "
                + "\(format(inApp)) more in DuoUpdater › Settings › Storage"
        }
    }

    // MARK: - clear

    struct ClearRow: Encodable, Equatable {
        let item: String
        /// Nil for the item that was not cleared.
        let freedBytes: Int64?
        /// Why an item was left alone, in a sentence.
        let skipped: String?
    }

    static let networkCacheSkipReason =
        "Held open by the menu-bar app; clear it in DuoUpdater › Settings › Storage."

    @discardableResult
    static func clear(
        json: Bool, layout: StorageInventory.Layout = .current,
        print: (String) -> Void = { Swift.print($0) },
        printError: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> Int32 {
        var results: [ClearRow] = []
        var failure: String?
        for item in StorageInventory.Group.caches.items where item != .networkCache {
            do {
                let freed = try StorageInventory.removeContents(of: item, in: layout)
                results.append(ClearRow(item: item.rawValue, freedBytes: freed, skipped: nil))
            } catch {
                failure = "\(name(item)): \(error.localizedDescription)"
                break
            }
        }
        // Measured after, so the note says what is still there — and says
        // nothing when there is nothing left to clear.
        let leftInApp = StorageInventory.measure(in: layout)
            .first { $0.item == .networkCache }?.clearableBytes ?? 0
        if leftInApp > 0 {
            results.append(ClearRow(item: StorageInventory.Item.networkCache.rawValue,
                                    freedBytes: nil, skipped: networkCacheSkipReason))
        }

        if json {
            NDJSON.begin("storage clear", print: print)
            for row in results { NDJSON.row(row, print: print) }
        } else {
            let freed = results.compactMap(\.freedBytes).reduce(0, +)
            print("Cleared \(format(freed)).")
            for row in results {
                guard let item = StorageInventory.Item(rawValue: row.item) else { continue }
                if let bytes = row.freedBytes {
                    print("  \(name(item)): \(format(bytes))")
                } else if let reason = row.skipped {
                    print("  \(name(item)): \(format(leftInApp)) not cleared. \(reason)")
                }
            }
        }
        if let failure {
            printError("duo storage clear: \(failure)")
            return 1
        }
        return 0
    }

    // MARK: - Presentation

    static func name(_ item: StorageInventory.Item) -> String {
        switch item {
        case .changelogImages: "Release note images"
        case .networkCache: "Web and download cache"
        case .formulaIcons: "Homebrew formula icons"
        case .cliCache: "duo command-line cache"
        case .backups: "Backups on this Mac"
        case .backupIndex: "Backup index"
        case .history: "History and network log"
        case .releaseNotes: "Release notes"
        case .checkState: "Update check state"
        case .appleDeveloperSession: "Apple Developer sign-in"
        case .httpStorage: "Cookies"
        case .preferences: "Settings"
        case .otherData: "Other"
        }
    }

    /// "0 bytes" for an empty cache, not the formatter's "Zero KB".
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// The path itself when there is one, the folder they share when there are
    /// several — the same line the Settings page prints. `--json` has them all.
    static func location(of paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        let path: String
        if paths.count == 1 {
            path = first
        } else {
            var common = (first as NSString).deletingLastPathComponent.split(separator: "/")
            for other in paths.dropFirst() {
                let parts = (other as NSString).deletingLastPathComponent.split(separator: "/")
                common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
            }
            path = "/" + common.joined(separator: "/")
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
