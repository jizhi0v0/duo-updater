import Testing
import Foundation
@testable import DuoUpdaterCore

/// The daily backstop over `$TMPDIR`'s `DuoUpdater-…` directories, run against
/// a scratch root with a fixed clock and replayed `hdiutil info` listings —
/// never the real temporary directory, never a real image.
@Suite(.serialized)
struct InstallScratchSweepTests {

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func withScratch(_ body: (_ root: URL, _ journal: URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-scratchsweep-\(UUID().uuidString)", isDirectory: true)
        let root = dir.appendingPathComponent("tmp", isDirectory: true)
        let journal = dir.appendingPathComponent("install-journal", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await InstallScratchSweep.$rootOverride.withValue(root) {
            try await InstallScratchSweep.$nowOverride.withValue(now) {
                try await InstallJournal.$rootOverride.withValue(journal) {
                    try await body(root, journal)
                }
            }
        }
    }

    private func lock(_ root: URL) -> (url: URL, lock: ProcessInstallLock) {
        let url = root.deletingLastPathComponent().appendingPathComponent("install.lock")
        return (url, ProcessInstallLock(url: url))
    }

    @discardableResult
    private func directory(_ name: String, in root: URL, ageDays: Double) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appendingPathComponent("archive.zip"))
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-ageDays * 86_400)], ofItemAtPath: url.path)
        return url
    }

    private func listing(_ images: [(image: String, mountPoint: String?)]) -> Data {
        let plist: [String: Any] = ["images": images.map { image in
            ["image-path": image.image,
             "system-entities": [["dev-entry": "/dev/disk99"]
                .merging(image.mountPoint.map { ["mount-point": $0] } ?? [:]) { a, _ in a }]]
        }]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private static let empty = InstallScratchSweep.Mounts(
        listing: { try? PropertyListSerialization.data(
            fromPropertyList: ["images": [Any]()], format: .xml, options: 0) },
        detach: { _, _ in true })

    @Test func onlyStaleScratchDirectoriesGo() async throws {
        try await withScratch { root, _ in
            let stale = try directory("DuoUpdater-ZZFixture-old", in: root, ageDays: 4)
            let fresh = try directory("DuoUpdater-ZZFixture-new", in: root, ageDays: 2)
            let other = try directory("ZZFixture-not-ours", in: root, ageDays: 30)
            let removed = await InstallScratchSweep.sweep(lock: lock(root).lock, mounts: Self.empty)
            #expect(removed == 1)
            #expect(!FileManager.default.fileExists(atPath: stale.path))
            #expect(FileManager.default.fileExists(atPath: fresh.path))
            #expect(FileManager.default.fileExists(atPath: other.path))
        }
    }

    @Test func anotherProcessHoldingTheLockSkipsTheSweep() async throws {
        try await withScratch { root, _ in
            let stale = try directory("DuoUpdater-ZZFixture-old", in: root, ageDays: 4)
            let (url, lock) = lock(root)
            let other = try InstallLock.acquire(at: url)
            defer { other.release() }
            #expect(await InstallScratchSweep.sweep(lock: lock, mounts: Self.empty) == nil)
            #expect(FileManager.default.fileExists(atPath: stale.path))
        }
    }

    /// An image attached under a stale directory is detached first; one that
    /// will not detach keeps its directory. Only images under the directory are
    /// touched.
    @Test(arguments: [true, false])
    func imagesUnderAStaleDirectoryAreDetachedFirst(detachSucceeds: Bool) async throws {
        try await withScratch { root, _ in
            let stale = try directory("DuoUpdater-ZZFixture-dmg", in: root, ageDays: 4)
            let canonical = stale.standardizedFileURL.path
            let image = canonical + "/ZZFixture.dmg"
            let mountPoint = canonical + "/mnt-ZZFixture.dmg"
            let data = listing([(image, mountPoint), ("/Volumes/ZZFixture-elsewhere.dmg", "/Volumes/Else")])
            let detached = JournalBox<[String]>([])
            let mounts = InstallScratchSweep.Mounts(
                listing: { data },
                detach: { point, img in
                    detached.set(detached.value + [point.path, img.path])
                    return detachSucceeds
                })
            let removed = await InstallScratchSweep.sweep(lock: lock(root).lock, mounts: mounts)
            #expect(detached.value == [mountPoint, image])
            #expect(removed == (detachSucceeds ? 1 : 0))
            #expect(FileManager.default.fileExists(atPath: stale.path) == !detachSucceeds)
        }
    }

    /// No listing could be read at all: nothing is removed, since any of them
    /// might hold a mount.
    @Test func anUnreadableImageTableRemovesNothing() async throws {
        try await withScratch { root, _ in
            let stale = try directory("DuoUpdater-ZZFixture-old", in: root, ageDays: 4)
            let mounts = InstallScratchSweep.Mounts(listing: { nil }, detach: { _, _ in true })
            #expect(await InstallScratchSweep.sweep(lock: lock(root).lock, mounts: mounts) == 0)
            #expect(FileManager.default.fileExists(atPath: stale.path))
        }
    }

    /// A directory a running install has journaled is not the sweep's, however
    /// old it looks.
    @Test func aDirectoryARunningInstallJournaledStays() async throws {
        try await withScratch { root, journal in
            let held = try directory("DuoUpdater-ZZFixture-held", in: root, ageDays: 4)
            let me = try #require(InstallJournal.ProcessStamp.of(getpid()))
            let entry = InstallJournal.Entry(
                job: "job", appID: "a", appName: "ZZFixture", bundleID: nil,
                appPath: "/ZZFixture/none.app", oldVersion: nil, oldBuild: nil, oldCDHash: nil,
                targetVersion: nil, targetBuild: nil, route: "sparkle", backupKey: "k",
                startedAt: now, owner: me, workDirectories: [held.path])
            try #require(InstallJournal.write(entry, to: journal.appendingPathComponent("job.json")))
            #expect(await InstallScratchSweep.sweep(lock: lock(root).lock, mounts: Self.empty) == 0)
            #expect(FileManager.default.fileExists(atPath: held.path))
        }
    }

    /// A listing can drop an attached image but never invent one, so the
    /// listings are merged: an image any of them shows counts as attached.
    @Test func listingsAreMergedAcrossReads() async {
        let reads = JournalBox(0)
        let full = listing([("/ZZFixture/a.dmg", "/ZZFixture/mnt")])
        let truncated = listing([])
        let images = await DiskImageMount.attachedImages(listing: {
            reads.set(reads.value + 1)
            return reads.value == 2 ? full : truncated
        })
        #expect(reads.value == DiskImageMount.absentListings)
        #expect(images == [DiskImageMount.AttachedImage(image: "/ZZFixture/a.dmg", mountPoints: ["/ZZFixture/mnt"])])
    }
}
