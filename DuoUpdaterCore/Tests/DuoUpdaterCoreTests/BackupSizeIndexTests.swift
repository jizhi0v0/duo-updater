import Foundation
import Testing

@testable import DuoUpdaterCore

/// ``BackupSizeIndex``: that a measurement is reused, that it stops being reused
/// the moment the directory it describes is replaced, and that the file does not
/// grow without bound.
///
/// Every test drives its own instance through `init(fileURL:)` — the singleton is
/// process-wide and these run in parallel with everything else.
@Suite struct BackupSizeIndexTests {

    /// A walker that answers the size of a directory and counts how many times it
    /// was asked, which is the only way to tell a hit from a miss: both return the
    /// same number, and a cache that quietly re-walked everything would pass every
    /// assertion about the answers.
    private final class CountingWalker: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var walked: [String] = []

        func callAsFunction(_ url: URL) -> Int64 {
            lock.lock()
            walked.append(url.lastPathComponent)
            lock.unlock()
            var total: Int64 = 0
            let files = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
            for case let file as URL in files ?? .init() {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return total
        }

        var count: Int { lock.lock(); defer { lock.unlock() }; return walked.count }
        func reset() { lock.lock(); walked = []; lock.unlock() }
    }

    private func withScratch(_ body: (URL, BackupSizeIndex, CountingWalker) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoBackupSizeIndex-\(UUID().uuidString)", isDirectory: true)
        let store = base.appendingPathComponent("store", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let index = BackupSizeIndex(fileURL: base.appendingPathComponent("sizes.json"))
        try body(store, index, CountingWalker())
    }

    /// One backup directory holding `bytes` bytes in a file, under a bundle so the
    /// fixture has the shape the walk is used on.
    @discardableResult
    private func makeBackup(_ key: String, in store: URL, bytes: Int) throws -> URL {
        let dir = store.appendingPathComponent(key, isDirectory: true)
        let contents = dir.appendingPathComponent("App.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes)
            .write(to: contents.appendingPathComponent("payload.bin"))
        return dir
    }

    private func keyDirectories(in store: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: store, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).sorted { $0.path < $1.path }
    }

    // MARK: - Reuse

    @Test func aSecondLookIsAnsweredWithoutWalkingAnythingAgain() throws {
        try withScratch { store, index, walk in
            try makeBackup("one", in: store, bytes: 4096)
            try makeBackup("two", in: store, bytes: 8192)
            let dirs = try keyDirectories(in: store)

            let first = index.sizes(of: dirs, measuring: walk.callAsFunction)
            #expect(walk.count == 2)
            #expect(first.count == 2)
            #expect(first[0] >= 4096 && first[1] >= 8192)

            walk.reset()
            let second = index.sizes(of: dirs, measuring: walk.callAsFunction)
            #expect(walk.count == 0)
            #expect(second == first)
        }
    }

    /// A different instance reading the same file — the app having measured, and
    /// `duo` asking next, or the reverse. Without this the index would only ever
    /// help within one process, which is not where the cost is.
    @Test func aMeasurementOutlivesTheInstanceThatTookIt() throws {
        try withScratch { store, index, walk in
            try makeBackup("one", in: store, bytes: 4096)
            let dirs = try keyDirectories(in: store)
            let first = index.sizes(of: dirs, measuring: walk.callAsFunction)

            let other = BackupSizeIndex(fileURL: index.resolvedFileURL)
            walk.reset()
            #expect(other.sizes(of: dirs, measuring: walk.callAsFunction) == first)
            #expect(walk.count == 0)
        }
    }

    // MARK: - Freshness

    /// The swap `BackupStore.save` performs: the new copy is built elsewhere and
    /// moved over the old key directory. The recorded size describes bytes that are
    /// gone, and reporting it would show the sheet a figure for a backup that is no
    /// longer there.
    @Test func aSupersededBackupIsMeasuredAgain() throws {
        try withScratch { store, index, walk in
            let dir = try makeBackup("one", in: store, bytes: 4096)
            let dirs = try keyDirectories(in: store)
            let before = index.sizes(of: dirs, measuring: walk.callAsFunction)

            let staging = store.deletingLastPathComponent()
                .appendingPathComponent("staging", isDirectory: true)
            let replacement = staging.appendingPathComponent("App.app/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
            try Data(repeating: 0x62, count: 40960)
                .write(to: replacement.appendingPathComponent("payload.bin"))
            _ = try FileManager.default.replaceItemAt(dir, withItemAt: staging)

            walk.reset()
            let after = index.sizes(of: dirs, measuring: walk.callAsFunction)
            #expect(walk.count == 1)
            #expect(after[0] > before[0])
            #expect(after[0] >= 40960)
        }
    }

    /// The same swap, inside the same second. Modification date is a one-second
    /// field on HFS+ — which is what an external backup disk generally is — so on
    /// that filesystem a fast supersede is invisible to the date alone. The inode
    /// is what catches it, and this test is what says so: both copies are stamped
    /// with the same date on purpose, leaving nothing else to tell them apart.
    @Test func aBackupReplacedWithinTheSameSecondIsMeasuredAgain() throws {
        try withScratch { store, index, walk in
            let dir = try makeBackup("one", in: store, bytes: 4096)
            let dirs = try keyDirectories(in: store)
            // A whole second, so that stamping it back on afterwards survives
            // whatever the filesystem's own resolution is and both copies really
            // do carry the same date.
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: dir.path)
            let before = try #require(BackupSizeIndex.identity(of: dir))
            _ = index.sizes(of: dirs, measuring: walk.callAsFunction)

            let staging = store.deletingLastPathComponent()
                .appendingPathComponent("staging", isDirectory: true)
            let replacement = staging.appendingPathComponent("App.app/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
            try Data(repeating: 0x62, count: 40960)
                .write(to: replacement.appendingPathComponent("payload.bin"))
            _ = try FileManager.default.replaceItemAt(dir, withItemAt: staging)
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: dir.path)

            let after = try #require(BackupSizeIndex.identity(of: dir))
            // The fixture is only worth anything if the dates really do match, so
            // that the difference below can only be coming from the inode.
            #expect(after != before)
            #expect(after.split(separator: "@").last == before.split(separator: "@").last)

            walk.reset()
            let sizes = index.sizes(of: try keyDirectories(in: store), measuring: walk.callAsFunction)
            #expect(walk.count == 1)
            #expect(sizes[0] >= 40960)
        }
    }

    /// A sidecar rewritten in place — `holdOnThisMac`, which writes `backup.json`
    /// back into a key directory that keeps its inode. Nothing about the size
    /// changes materially, but the entry has to stop being a hit, because this is
    /// the one mutation the inode cannot see.
    @Test func aSidecarRewrittenInPlaceRetiresTheEntry() throws {
        try withScratch { store, index, walk in
            let dir = try makeBackup("one", in: store, bytes: 4096)
            let dirs = try keyDirectories(in: store)
            _ = index.sizes(of: dirs, measuring: walk.callAsFunction)

            try Data(repeating: 0x63, count: 512)
                .write(to: dir.appendingPathComponent("backup.json"), options: .atomic)

            walk.reset()
            _ = index.sizes(of: dirs, measuring: walk.callAsFunction)
            #expect(walk.count == 1)
        }
    }

    // MARK: - Bounds

    /// A deleted backup's entry goes with it. This is the only thing keeping the
    /// file from growing for the life of the machine: the entries are keyed by
    /// path, and nothing else ever revisits the path of a backup that is gone.
    @Test func aDeletedBackupLosesItsEntry() throws {
        try withScratch { store, index, walk in
            try makeBackup("one", in: store, bytes: 4096)
            let gone = try makeBackup("two", in: store, bytes: 8192)
            _ = index.sizes(of: try keyDirectories(in: store), measuring: walk.callAsFunction)
            let recorded = try recordedPaths(in: index)
            #expect(recorded.count == 2)

            try FileManager.default.removeItem(at: gone)
            _ = index.sizes(of: try keyDirectories(in: store), measuring: walk.callAsFunction)
            let left = try recordedPaths(in: index)
            #expect(left.count == 1)
            #expect(!left.contains(gone.path))
        }
    }

    /// Pruning is scoped to the store that was scanned. One index serves this Mac
    /// and every disk that can be read, and they are listed separately — a pass
    /// over one must not retire what is known about another, or two stores would
    /// take turns re-walking each other.
    @Test func scanningOneStoreLeavesAnotherStoresEntriesAlone() throws {
        try withScratch { store, index, walk in
            let other = store.deletingLastPathComponent()
                .appendingPathComponent("disk", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try makeBackup("here", in: store, bytes: 4096)
            try makeBackup("there", in: other, bytes: 8192)
            _ = index.sizes(of: try keyDirectories(in: other), measuring: walk.callAsFunction)
            _ = index.sizes(of: try keyDirectories(in: store), measuring: walk.callAsFunction)

            walk.reset()
            _ = index.sizes(of: try keyDirectories(in: other), measuring: walk.callAsFunction)
            #expect(walk.count == 0)
        }
    }

    /// A directory that cannot be stat'd — a disk pulled between the listing and
    /// the measurement — still gets an answer, and nothing is recorded against an
    /// identity that does not exist.
    @Test func aDirectoryThatCannotBeStatdIsAnsweredAndNotRecorded() throws {
        try withScratch { store, index, walk in
            let missing = store.appendingPathComponent("never-existed", isDirectory: true)
            let sizes = index.sizes(of: [missing], measuring: walk.callAsFunction)
            #expect(sizes == [0])
            let recorded = try recordedPaths(in: index)
            #expect(recorded.isEmpty)
        }
    }

    private func recordedPaths(in index: BackupSizeIndex) throws -> Set<String> {
        guard let data = try? Data(contentsOf: index.resolvedFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [String: Any]
        else { return [] }
        return Set(entries.keys)
    }
}
