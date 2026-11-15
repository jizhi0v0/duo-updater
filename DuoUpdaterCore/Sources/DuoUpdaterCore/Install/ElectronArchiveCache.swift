import CryptoKit
import Darwin
import Foundation

/// Disposable, bounded original ZIPs for future blockmap downloads. A completed
/// install publishes a ZIP/map pair; failed or cancelled installs publish none.
/// Cached bytes are never installation proof: the reconstructed target must pass
/// the publisher's whole-archive digest and the normal install identity gates.
public enum ElectronArchiveCache {
    static let budget: Int64 = 2 * 1024 * 1024 * 1024
    @TaskLocal static var rootOverride: URL?
    @TaskLocal static var budgetOverride: Int64?
    private static let lock = NSLock()
    private nonisolated(unsafe) static var claimed: Set<String> = []

    static var root: URL? {
        if let rootOverride { return rootOverride }
        guard !DuoStateDirectory.isTestProcess else { return nil }
        return DuoStateDirectory.cachesBase.appendingPathComponent("com.duoupdater.installers", isDirectory: true)
    }

    struct Location: Sendable {
        let root: URL?
        let budget: Int64
        static var current: Self { Self(root: ElectronArchiveCache.root,
                                       budget: budgetOverride ?? ElectronArchiveCache.budget) }
    }

    static func key(for app: InstalledApp) -> String {
        let identity = (app.bundleID ?? "") + "\n" + app.path.resolvingSymlinksInPath().standardizedFileURL.path
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    final class Baseline: @unchecked Sendable {
        let archive: FileHandle
        let map: ElectronBlockmap
        private let release: @Sendable () -> Void
        init(archive: FileHandle, map: ElectronBlockmap, release: @escaping @Sendable () -> Void) {
            self.archive = archive; self.map = map; self.release = release
        }
        deinit { try? archive.close(); release() }
    }

    private struct Meta: Codable {
        let archiveSHA256: String
        let createdAt: Date
    }

    /// No symlinks and no unbounded reads from cache metadata. Hold the opened
    /// old archive, rather than reopening its path between COPY operations.
    private static func openPair(at directory: URL, release: @escaping @Sendable () -> Void) -> Baseline? {
        let archiveURL = directory.appendingPathComponent("archive.zip")
        let mapURL = directory.appendingPathComponent("archive.blockmap")
        guard isDirectory(directory), let data = boundedRegularData(mapURL, limit: ElectronBlockmap.compressedLimit),
              let map = try? ElectronBlockmap(compressed: data),
              let fd = openRegular(archiveURL, expectedSize: map.size)
        else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        // The map/file pair is checked against the digest captured when retained.
        // The target's own published digest still checks every reconstruction.
        guard let metaData = boundedRegularData(directory.appendingPathComponent("meta.json"), limit: 4096),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              (try? digest(handle)) == meta.archiveSHA256 else { try? handle.close(); return nil }
        return Baseline(archive: handle, map: map, release: release)
    }

    static func open(for app: InstalledApp, at location: Location = .current) -> Baseline? {
        guard let root = location.root, isDirectory(root) else { return nil }
        return lock.withLock {
            let key = key(for: app)
            guard !claimed.contains(key) else { return nil }
            claimed.insert(key)
            let baseline = openPair(at: root.appendingPathComponent(key, isDirectory: true)) {
                _ = lock.withLock { claimed.remove(key) }
            }
            if baseline == nil { claimed.remove(key) }
            return baseline
        }
    }

    /// A vendor may already have left a usable ZIP and map. Its directory name
    /// must come from the installed bundle, never from the display name. The
    /// target digest protects against a stale or concurrently changed vendor pair.
    static func openVendorBaseline(for app: InstalledApp) -> Baseline? {
        guard !DuoStateDirectory.isTestProcess,
              let name = app.electronUpdate?.updaterCacheDirName,
              !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\")
        else { return nil }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        for base in [library.appendingPathComponent("Caches"), library.appendingPathComponent("Application Support/Caches")] {
            let directory = base.appendingPathComponent(name, isDirectory: true)
            guard isDirectory(directory),
                  let data = boundedRegularData(directory.appendingPathComponent("current.blockmap"),
                                                limit: ElectronBlockmap.compressedLimit),
                  let map = try? ElectronBlockmap(compressed: data),
                  let fd = openRegular(directory.appendingPathComponent("update.zip"), expectedSize: map.size)
            else { continue }
            return Baseline(archive: FileHandle(fileDescriptor: fd, closeOnDealloc: true), map: map, release: {})
        }
        return nil
    }

    /// Called only after installApp succeeded. Failure here costs a future full
    /// download, never a failed install. All paths and deletion targets are ours.
    static func retain(archive: URL, map: URL, for app: InstalledApp, at location: Location = .current) {
        guard let root = location.root,
              let bytes = boundedRegularData(map, limit: ElectronBlockmap.compressedLimit),
              let decoded = try? ElectronBlockmap(compressed: bytes),
              decoded.size + Int64(bytes.count) <= location.budget,
              (BackupStore.outboxFreeBytes() ?? Int64.max) > BackupStore.freeSpaceFloorBytes + decoded.size
        else { return }
        lock.withLock {
            let fm = FileManager.default
            let key = key(for: app)
            guard !claimed.contains(key) else { return }
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                guard isDirectory(root) else { return }
                // A prior process can die between copying and publication. No
                // active staging writer exists while this process owns the lock.
                for orphan in entries(in: root) where orphan.lastPathComponent.hasPrefix(".incoming-") {
                    try fm.removeItem(at: orphan)
                }
                let staging = root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                                       attributes: [.posixPermissions: 0o700])
                defer { try? fm.removeItem(at: staging) }
                let saved = staging.appendingPathComponent("archive.zip")
                try fm.copyItem(at: archive, to: saved)
                guard let fd = openRegular(saved, expectedSize: decoded.size) else { return }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                let meta = Meta(archiveSHA256: try digest(handle), createdAt: Date())
                try bytes.write(to: staging.appendingPathComponent("archive.blockmap"))
                try JSONEncoder().encode(meta).write(to: staging.appendingPathComponent("meta.json"))
                // Allocation includes metadata and filesystem blocks, not just
                // the archive's logical size. Oversized entries are disposable.
                guard StorageInventory.allocatedSize(of: staging) <= location.budget else { return }
                let destination = root.appendingPathComponent(key, isDirectory: true)
                // Readers use the same lock; the process-wide InstallLock excludes
                // the other installer process. A crash in this gap leaves a miss.
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: staging, to: destination)
                trim(in: root, keeping: key, budget: location.budget)
            } catch {
                Log.install.notice("electron archive cache: could not retain this install's ZIP")
            }
        }
    }

    private static func entries(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter {
                let name = $0.lastPathComponent
                let retained = name.count == 64 && name.allSatisfy { "0123456789abcdef".contains($0) }
                let incoming = name.hasPrefix(".incoming-") && UUID(uuidString: String(name.dropFirst(10))) != nil
                return retained || incoming
            }
    }

    private static func trim(in root: URL, keeping key: String, budget: Int64) {
        let fm = FileManager.default
        let entries = entries(in: root).sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        var total = entries.reduce(Int64(0)) { $0 + StorageInventory.allocatedSize(of: $1) }
        for entry in entries where total > budget || entry.lastPathComponent.hasPrefix(".incoming-") {
            guard entry.lastPathComponent != key, !claimed.contains(entry.lastPathComponent) else { continue }
            let size = StorageInventory.allocatedSize(of: entry)
            if (try? fm.removeItem(at: entry)) != nil { total -= size }
        }
        // Active baselines may consume the whole budget during parallel installs.
        // A new cache entry is optional; drop it instead of exceeding the cap.
        let newest = root.appendingPathComponent(key, isDirectory: true)
        if total > budget, !claimed.contains(key) { try? fm.removeItem(at: newest) }
    }

    /// Reclaimed before an install is refused for disk space. Active COPY readers
    /// keep their baseline; callers can retry once they release it.
    @discardableResult
    public static func discardAllForSpace() -> Int64 {
        guard let root, isDirectory(root) else { return 0 }
        return lock.withLock {
            var freed: Int64 = 0
            for entry in entries(in: root) where !claimed.contains(entry.lastPathComponent) {
                let size = StorageInventory.allocatedSize(of: entry)
                if (try? FileManager.default.removeItem(at: entry)) != nil { freed += size }
            }
            return freed
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func openRegular(_ url: URL, expectedSize: Int64? = nil) -> Int32? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              expectedSize.map({ $0 == info.st_size }) ?? true else { Darwin.close(fd); return nil }
        return fd
    }

    private static func boundedRegularData(_ url: URL, limit: Int) -> Data? {
        guard let fd = openRegular(url) else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }

    private static func digest(_ file: FileHandle) throws -> String {
        try file.seek(toOffset: 0)
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        try file.seek(toOffset: 0)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
