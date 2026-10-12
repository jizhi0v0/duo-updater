import Foundation

/// Everywhere DuoUpdater writes on this Mac, sorted into what it is for, measured,
/// and — for the parts that are only caches — emptied.
///
/// The Homebrew cask lists these directories in its `zap` stanza, so a `brew`
/// user is told where DuoUpdater keeps things. Someone who installed from the
/// GitHub download is told nothing; the Storage settings page reads this to show
/// them the same map.
///
/// Every top-level entry under DuoUpdater's own directories lands in exactly one
/// ``Item``. An entry this file does not know by name goes to ``Item/otherData``
/// rather than being skipped, so a store added later still counts toward the
/// total before anyone remembers to name it here.
///
/// **Only an ``Item/isClearable`` item may be emptied**, and those are the ones
/// whose bytes come back unchanged from the network on the next read. History,
/// release notes, check state and backups are not on that list even where they
/// are cache-shaped: release notes are what a vendor page said *then* (the page
/// may say something else now), and the GitHub validators are what keeps checks
/// inside the anonymous rate limit.
public enum StorageInventory {

    public enum Item: String, CaseIterable, Sendable {
        // Clearable — re-downloaded on demand, identical when they come back.
        case changelogImages
        case networkCache
        case formulaIcons
        case cliCache
        // Kept.
        case backups
        case backupIndex
        case history
        case releaseNotes
        case checkState
        case appleDeveloperSession
        case httpStorage
        case preferences
        case otherData

        public var isClearable: Bool {
            switch self {
            case .changelogImages, .networkCache, .formulaIcons, .cliCache: true
            default: false
            }
        }
    }

    /// The two roots everything hangs off. Separate because they move separately:
    /// `DUO_STATE_DIR` relocates DuoUpdater's own state, while Caches, WebKit,
    /// HTTPStorages and Preferences are placed by the system under `~/Library`.
    public struct Layout: Sendable {
        public var library: URL
        public var stateBase: URL

        public init(library: URL, stateBase: URL) {
            self.library = library
            self.stateBase = stateBase
        }

        public static var current: Layout {
            Layout(
                library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library"),
                stateBase: DuoStateDirectory.base)
        }

        var appState: URL { stateBase.appendingPathComponent("com.duoupdater.app", isDirectory: true) }
        var duoState: URL { stateBase.appendingPathComponent("DuoUpdater", isDirectory: true) }
        var appCaches: URL { library.appendingPathComponent("Caches/com.duoupdater.app", isDirectory: true) }
        var cliCaches: URL { library.appendingPathComponent("Caches/com.duoupdater.cli", isDirectory: true) }
    }

    /// One item's share: how many bytes, and the paths that hold them (only the
    /// ones that exist), for "Show in Finder".
    public struct Measurement: Sendable, Equatable {
        public let item: Item
        public let bytes: Int64
        public let paths: [URL]
    }

    /// Which item a top-level entry of `com.duoupdater.app` belongs to.
    static func classifyAppState(_ name: String) -> Item {
        switch name {
        case "changelog-images": .changelogImages
        case "formula-icons": .formulaIcons
        case "changelogs", "formula-releases": .releaseNotes
        case "backup-sizes.json": .backupIndex
        case "releases.json", "release-observations.json", "traffic.json", "requests.json":
            .history
        case _ where name.hasPrefix("events.sqlite"): .history
        case "github-conditional-cache.json", "resolved-channels.json", "tauri-proofs.json",
             "install.lock":
            .checkState
        case _ where name.hasSuffix("-published-digests.json")
            || name.hasSuffix("-verified-files.json")
            || name.hasSuffix("-file-facts.json"):
            .checkState
        default: .otherData
        }
    }

    /// Which item a top-level entry of `DuoUpdater` belongs to.
    static func classifyDuoState(_ name: String) -> Item {
        switch name {
        case "Backups": .backups
        case "BackupFacts", "BackupDiskIcons": .backupIndex
        default: .otherData
        }
    }

    /// Every path DuoUpdater may have written, by item. Directories DuoUpdater
    /// owns outright are listed entry by entry; the rest are whole directories
    /// the system creates for this bundle id.
    public static func paths(in layout: Layout = .current, fileManager: FileManager = .default) -> [Item: [URL]] {
        var out: [Item: [URL]] = [:]
        func add(_ item: Item, _ url: URL) { out[item, default: []].append(url) }

        for (root, classify) in [(layout.appState, classifyAppState), (layout.duoState, classifyDuoState)] {
            let entries = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                // Finder's droppings are not ours to account for.
                if entry.lastPathComponent == ".DS_Store" { continue }
                add(classify(entry.lastPathComponent), entry)
            }
        }

        let lib = layout.library
        add(.networkCache, layout.appCaches)
        add(.cliCache, layout.cliCaches)
        add(.appleDeveloperSession, lib.appendingPathComponent("WebKit/com.duoupdater.app", isDirectory: true))
        for name in ["com.duoupdater.app", "com.duoupdater.app.binarycookies",
                     "com.duoupdater.cli", "com.duoupdater.cli.binarycookies"] {
            add(.httpStorage, lib.appendingPathComponent("HTTPStorages").appendingPathComponent(name))
        }
        add(.preferences, lib.appendingPathComponent("Preferences/com.duoupdater.app.plist"))
        // Sparkle's own download area for DuoUpdater's self-update. Not a cache to
        // empty: an update staged there is mid-install.
        add(.otherData, lib.appendingPathComponent("Caches/com.duoupdater.app.sparkle", isDirectory: true))
        add(.otherData, lib.appendingPathComponent("Saved Application State/com.duoupdater.app.savedState", isDirectory: true))
        return out
    }

    /// Measures every item. Walks the whole tree, backups included, so call it
    /// off the main thread. Backups go through ``BackupStore/storeSize(of:)`` —
    /// the index the Backups page and the clean-up sheet already pay for — rather
    /// than a fresh walk of tens of gigabytes.
    public static func measure(in layout: Layout = .current, fileManager: FileManager = .default) -> [Measurement] {
        let byItem = paths(in: layout, fileManager: fileManager)
        return Item.allCases.compactMap { item in
            let existing = (byItem[item] ?? []).filter { fileManager.fileExists(atPath: $0.path) }
            let bytes = existing.reduce(Int64(0)) { sum, url in
                if item == .backups { return sum + BackupStore.storeSize(of: url) }
                return sum + allocatedSize(of: url, fileManager: fileManager)
            }
            return Measurement(item: item, bytes: bytes, paths: existing)
        }
    }

    /// Empties a clearable item's files on disk. Leaves the directories in place
    /// (their owners create them once and expect them to be there) and removes
    /// what is inside. Returns the bytes that were there before.
    ///
    /// ``Item/networkCache`` is not emptied here: its owners are live in the app
    /// process — `URLCache.shared` holds its database open and WebKit's network
    /// process holds its cache — so the app clears them through their own APIs.
    /// Deleting a SQLite file out from under an open connection is not a clear.
    @discardableResult
    public static func removeContents(
        of item: Item, in layout: Layout = .current, fileManager: FileManager = .default
    ) throws -> Int64 {
        precondition(item.isClearable && item != .networkCache,
                     "\(item) is not one StorageInventory empties from disk")
        var freed: Int64 = 0
        for root in paths(in: layout, fileManager: fileManager)[item] ?? [] {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [])
            else { continue }
            let before = allocatedSize(of: root, fileManager: fileManager)
            for entry in entries { try fileManager.removeItem(at: entry) }
            freed += before - allocatedSize(of: root, fileManager: fileManager)
        }
        return freed
    }

    /// Bytes on disk under `url` — allocated, so a 4 KB block holding a 10-byte
    /// JSON counts as 4 KB, the same answer `du` and Finder give. A file is
    /// measured directly; a directory is walked, symlinks not followed.
    ///
    /// A file with several hard links counts once, as `du` counts it. WebKit's
    /// network cache links every blob from two places (`Blobs/` and the record
    /// that uses it): summed per path, `Caches/com.duoupdater.app` read 143 MB
    /// where `du` read 70 MB on the Mac this was written on (2026-10-12).
    static func allocatedSize(of url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .isRegularFileKey, .linkCountKey, .fileResourceIdentifierKey,
        ]
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        var seenLinked = Set<AnyHashable>()
        func size(_ file: URL) -> Int64 {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true
            else { return 0 }
            if (values.linkCount ?? 1) > 1, let identity = values.fileResourceIdentifier as? AnyHashable,
               !seenLinked.insert(identity).inserted {
                return 0
            }
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard isDirectory.boolValue else { return size(url) }
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator { total += size(file) }
        return total
    }
}
