import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// A download that stops part-way keeps its bytes for the next `Downloader`
/// call (`ResumableDownloadStore`), against a loopback HTTP server like the
/// rest of the `Downloader` tests: no external network, and the store bound to
/// a scratch directory per test — never `~/Library/Caches`.
///
/// "Stops part-way" is a real cancellation: the server sends the headers and
/// the first `stallAt` bytes, then holds the connection open, and the test
/// cancels the download once the client has written them.
///
/// Mutations (each verified red, then restored):
/// - `Downloader`'s keep decision ignores the validator → the weak-ETag test
///   finds a kept partial.
/// - `ResumableDownloadStore.isExpired` never true → the expiry test keeps it.
/// - `DiskSpaceGuard.reclaim` asks `BackupStore` first → the backup is deleted.
/// - `InstallCoordinator.swap` no longer forgets the app's partials → the
///   install test finds them.
@Suite(.serialized)
struct ResumableDownloadStoreTests {

    // MARK: - Loopback server

    /// Answers an unranged GET with `200`, the full `Content-Length` and
    /// `validators`, then either the whole body or — the first time only — `stallAt`
    /// bytes on a connection it keeps open until `stop()`. A ranged GET gets an honest
    /// `206` with the remainder, or `200` with the whole body (`rangeAs200`).
    /// Every request head is recorded.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "ResumableDownloadStoreTests.Server")
        private let state = State()
        let port: UInt16

        final class State: @unchecked Sendable {
            let lock = NSLock()
            var requests: [String] = []
            var held: [NWConnection] = []
            var stalled = false
        }

        var requests: [String] { state.lock.withLock { state.requests } }

        init(body: Data, validators: [String: String], stallAt: Int?, rangeAs200: Bool = false) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let state = self.state
            let queue = self.queue
            let total = body.count
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    state.lock.withLock { state.requests.append(request) }
                    let extra = validators.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                    func send(_ head: [String], _ payload: Data, hold: Bool) {
                        var response = Data((head.joined(separator: "\r\n") + "\r\n\r\n").utf8)
                        response.append(payload)
                        conn.send(content: response, completion: .contentProcessed { _ in
                            if hold {
                                state.lock.withLock { state.held.append(conn) }
                            } else {
                                conn.cancel()
                            }
                        })
                    }
                    if let start = Self.rangeStart(request) {
                        if rangeAs200 {
                            send(["HTTP/1.1 200 OK", "Content-Length: \(total)", "Connection: close"] + extra,
                                 body, hold: false)
                        } else {
                            let chunk = body.subdata(in: start..<total)
                            send(["HTTP/1.1 206 Partial Content",
                                  "Content-Range: bytes \(start)-\(total - 1)/\(total)",
                                  "Content-Length: \(chunk.count)", "Connection: close"] + extra,
                                 chunk, hold: false)
                        }
                        return
                    }
                    let head = ["HTTP/1.1 200 OK", "Content-Length: \(total)",
                                "Accept-Ranges: bytes", "Connection: close"] + extra
                    // Only the first unranged request stalls; a later one (a
                    // download that found nothing to resume) gets the whole body.
                    let stall = state.lock.withLock {
                        defer { state.stalled = true }
                        return !state.stalled
                    }
                    if let stallAt, stall {
                        send(head, body.subdata(in: 0..<stallAt), hold: true)
                    } else {
                        send(head, body, hold: false)
                    }
                }
            }
            listener.start(queue: queue)
            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let p = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = p
        }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)/\(path)")! }

        static func header(_ name: String, in request: String) -> String? {
            for line in request.split(separator: "\r\n") {
                guard let colon = line.firstIndex(of: ":"),
                      line[..<colon].lowercased() == name.lowercased() else { continue }
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        private static func rangeStart(_ request: String) -> Int? {
            guard let value = header("Range", in: request),
                  let eq = value.firstIndex(of: "="),
                  let dash = value[value.index(after: eq)...].firstIndex(of: "-") else { return nil }
            return Int(value[value.index(after: eq)..<dash])
        }

        func stop() {
            listener.cancel()
            let held = state.lock.withLock { state.held }
            held.forEach { $0.cancel() }
        }
    }

    private static let body = Data((0..<200_000).map { UInt8(($0 * 7) & 0xFF) })
    private static let stallAt = 80_000
    private static let strong = ["ETag": "\"zz-v1\""]

    // MARK: - Helpers

    private func scratch(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZResumable-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func files(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// Start a download of `url` and cancel it once the server's first
    /// `stallAt` bytes are on disk. `whileStalled` runs at that moment, before
    /// the cancellation — the state a process killed right then would leave.
    private func downloadThenCancel(
        _ url: URL, workDir: URL, whileStalled: () throws -> Void = {}
    ) async throws {
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let task = Task { try await downloader.download(url) }
        let deadline = Date().addingTimeInterval(10)
        while downloader.bytesDownloaded < Int64(Self.stallAt), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(downloader.bytesDownloaded == Int64(Self.stallAt))
        try whileStalled()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func seed(_ url: URL, appID: String?, in root: URL) throws -> ResumableDownloadStore.Entry {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = ResumableDownloadStore.Entry(url: url, root: root)
        try Data(repeating: 7, count: 10).write(to: entry.partial)
        try ResumableDownloadStore.writeMeta(
            .init(url: url.absoluteString, validator: "\"zz\"", bytesWritten: 10,
                  appID: appID, createdAt: Date()),
            to: entry)
        return entry
    }

    // MARK: - Resume

    @Test func aStrongETagResumesFromTheKeptPartial() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(body: Self.body, validators: Self.strong, stallAt: Self.stallAt)
        defer { server.stop() }
        let url = server.url("zz.dmg?token=a")

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await downloadThenCancel(url, workDir: work)
            let entry = ResumableDownloadStore.Entry(url: url, root: root)
            #expect(try Data(contentsOf: entry.partial) == Self.body.prefix(Self.stallAt))
            #expect(ResumableDownloadStore.readMeta(entry)?.validator == "\"zz-v1\"")

            let downloader = Downloader(destinationDir: work) { _ in }
            let file = try await downloader.download(url)
            #expect(try Data(contentsOf: file) == Self.body)
            #expect(downloader.bytesDownloaded == Int64(Self.body.count - Self.stallAt))
        }
        let requests = server.requests
        #expect(requests.count == 2)
        #expect(Server.header("Range", in: requests[1]) == "bytes=\(Self.stallAt)-")
        #expect(Server.header("If-Range", in: requests[1]) == "\"zz-v1\"")
        // Finished: nothing kept, the finished file included.
        #expect(files(in: root).isEmpty)
    }

    @Test func aWeakETagIsNotKept() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(body: Self.body, validators: ["ETag": "W/\"zz-v1\""], stallAt: Self.stallAt)
        defer { server.stop() }
        let url = server.url("zz.dmg")

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await downloadThenCancel(url, workDir: work)
            #expect(files(in: root).isEmpty)
        }
    }

    @Test func aServerThatAnswersTheRangeWith200StartsOver() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(
            body: Self.body, validators: Self.strong, stallAt: Self.stallAt, rangeAs200: true)
        defer { server.stop() }
        let url = server.url("zz.dmg")

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await downloadThenCancel(url, workDir: work)
            let downloader = Downloader(destinationDir: work) { _ in }
            let file = try await downloader.download(url)
            #expect(try Data(contentsOf: file) == Self.body)
            #expect(downloader.bytesDownloaded == Int64(Self.body.count))
        }
        let requests = server.requests
        #expect(requests.count == 2)
        #expect(Server.header("Range", in: requests[1]) == "bytes=\(Self.stallAt)-")
        #expect(files(in: root).isEmpty)
    }

    /// Another URL is another download — query included — and for the same
    /// app it also retires the partial under the old one.
    @Test func aDifferentURLIsNoHitAndRetiresTheSameAppsOldPartial() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(body: Self.body, validators: Self.strong, stallAt: Self.stallAt)
        defer { server.stop() }
        let old = server.url("zz.dmg?token=a")
        let new = server.url("zz.dmg?token=b")

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await RequestAttribution.withApp("/Applications/ZZOne.app") {
                try await downloadThenCancel(old, workDir: work)
            }
            let oldEntry = ResumableDownloadStore.Entry(url: old, root: root)
            #expect(FileManager.default.fileExists(atPath: oldEntry.partial.path))
            let unrelated = try seed(server.url("other.dmg"), appID: "/Applications/ZZTwo.app", in: root)

            try await RequestAttribution.withApp("/Applications/ZZOne.app") {
                let downloader = Downloader(destinationDir: work) { _ in }
                let file = try await downloader.download(new)
                #expect(try Data(contentsOf: file) == Self.body)
            }
            #expect(!FileManager.default.fileExists(atPath: oldEntry.partial.path))
            #expect(!FileManager.default.fileExists(atPath: oldEntry.sidecar.path))
            #expect(FileManager.default.fileExists(atPath: unrelated.partial.path))
        }
        let requests = server.requests
        #expect(requests.count == 2)
        #expect(Server.header("Range", in: requests[1]) == nil)
    }

    // MARK: - Retention

    @Test func aPartialExpiresAfterTheRetention() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(body: Self.body, validators: Self.strong, stallAt: Self.stallAt)
        defer { server.stop() }
        let url = server.url("zz.dmg")
        let start = Date()
        let retention = ResumableDownloadStore.resumeRetention

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await downloadThenCancel(url, workDir: work)
            let kept = files(in: root)
            #expect(kept.count == 2)

            ResumableDownloadStore.$nowOverride.withValue({ start.addingTimeInterval(retention - 60) }) {
                #expect(ResumableDownloadStore.sweepExpired() == 0)
            }
            #expect(files(in: root) == kept)

            // Past the retention, a download does not resume it either.
            try await ResumableDownloadStore.$nowOverride.withValue({ start.addingTimeInterval(retention + 60) }) {
                let downloader = Downloader(destinationDir: work) { _ in }
                let file = try await downloader.download(url)
                #expect(try Data(contentsOf: file) == Self.body)
                #expect(downloader.bytesDownloaded == Int64(Self.body.count))
            }
            #expect(Server.header("Range", in: server.requests[1]) == nil)

            // And the sweep takes one that has aged out.
            _ = try seed(url, appID: nil, in: root)
            ResumableDownloadStore.$nowOverride.withValue({ Date().addingTimeInterval(retention + 60) }) {
                #expect(ResumableDownloadStore.sweepExpired() == 1)
            }
            #expect(files(in: root).isEmpty)
        }
    }

    /// The process dies with the transfer under way: no cancellation, no
    /// cleanup. Simulated by copying the store's directory as it stands while
    /// the bytes are flowing; a new `Downloader` pointed at that copy resumes.
    @Test func aProcessKilledAfterTheHeadersLeavesAPartialTheNextOneResumes() async throws {
        let root = try scratch("root"), work = try scratch("work"), afterKill = try scratch("killed")
        defer { [root, work, afterKill].forEach { try? FileManager.default.removeItem(at: $0) } }
        let server = try Server(body: Self.body, validators: Self.strong, stallAt: Self.stallAt)
        defer { server.stop() }
        let url = server.url("zz.dmg")

        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            try await downloadThenCancel(url, workDir: work) {
                for name in files(in: root) {
                    try FileManager.default.copyItem(
                        at: root.appendingPathComponent(name),
                        to: afterKill.appendingPathComponent(name))
                }
            }
        }
        let entry = ResumableDownloadStore.Entry(url: url, root: afterKill)
        #expect(ResumableDownloadStore.readMeta(entry)?.validator == "\"zz-v1\"")

        try await ResumableDownloadStore.$rootOverride.withValue(afterKill) {
            let downloader = Downloader(destinationDir: work) { _ in }
            let file = try await downloader.download(url)
            #expect(try Data(contentsOf: file) == Self.body)
        }
        #expect(Server.header("Range", in: server.requests[1]) == "bytes=\(Self.stallAt)-")
        #expect(files(in: afterKill).isEmpty)
    }

    // MARK: - Disk space

    private func withBackupScratch(_ body: (URL, URL) async throws -> Void) async throws {
        let scratch = try scratch("disk")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let backups = scratch.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try await BackupStore.$rootOverride.withValue(backups) {
            try await BackupStore.$destinationOverride.withValue(.local) {
                try await BackupFactsLibrary.$rootOverride.withValue(scratch.appendingPathComponent("Facts")) {
                    try await body(scratch, backups)
                }
            }
        }
    }

    private func storeBackup(in scratch: URL) async throws -> String {
        let app = scratch.appendingPathComponent("ZZOld.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.example.zzold</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        let key = BackupStore.key(bundleID: "com.example.zzold", path: app)
        _ = try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: "com.example.zzold")
        return key
    }

    /// Short of space before the swap: the kept partial goes, and that is
    /// enough, so the backup stays.
    @Test func roomIsMadeFromPartialsBeforeAnyBackup() async throws {
        try await withBackupScratch { scratch, backups in
            let backupKey = try await storeBackup(in: scratch)
            let root = scratch.appendingPathComponent("partials")
            let floor = BackupStore.freeSpaceFloorBytes
            try await ResumableDownloadStore.$rootOverride.withValue(root) {
                let entry = try seed(URL(string: "https://example.invalid/zz.dmg")!, appID: nil, in: root)
                try await BackupStore.$freeBytesOverride.withValue({
                    FileManager.default.fileExists(atPath: entry.partial.path) ? floor : floor + (3 << 30)
                }) {
                    try await DiskSpaceGuard.ensureRoom(for: 2 << 30, sparing: "zz-not-a-key")
                }
                #expect(!FileManager.default.fileExists(atPath: entry.partial.path))
            }
            #expect(FileManager.default.fileExists(
                atPath: backups.appendingPathComponent(backupKey).path))
        }
    }

    /// The claim before anything is fetched: refused only after the partials
    /// have been given up.
    @Test func aClaimIsGrantedOnceThePartialsAreGone() async throws {
        let root = try scratch("root")
        defer { try? FileManager.default.removeItem(at: root) }
        let floor = BackupStore.freeSpaceFloorBytes
        let ledger = DiskSpaceGuard.SpaceLedger()
        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            let entry = try seed(URL(string: "https://example.invalid/zz.dmg")!, appID: nil, in: root)
            try await BackupStore.$freeBytesOverride.withValue({
                FileManager.default.fileExists(atPath: entry.partial.path) ? floor : floor + (3 << 30)
            }) {
                try await ledger.reserve(2 << 30)
            }
            #expect(!FileManager.default.fileExists(atPath: entry.partial.path))
        }
        #expect(ledger.reservedBytes == 2 << 30)
    }

    // MARK: - After an install

    @Test func aSuccessfulInstallForgetsThatAppsPartials() async throws {
        let root = try scratch("root"), work = try scratch("work")
        defer { [root, work].forEach { try? FileManager.default.removeItem(at: $0) } }
        let result = UpdateResult(
            app: InstalledApp(
                name: "ZZFixture", bundleID: "com.example.zzfixture", shortVersion: "1.0",
                buildVersion: "1", path: work.appendingPathComponent("ZZFixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: RemoteVersion(shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Sparkle"),
            status: .updateAvailable(latest: "1.1"))
        try await ResumableDownloadStore.$rootOverride.withValue(root) {
            let mine = try seed(URL(string: "https://example.invalid/zz-1.0.dmg")!, appID: result.app.id, in: root)
            let other = try seed(URL(string: "https://example.invalid/other.dmg")!, appID: "/Applications/ZZOther.app", in: root)
            let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
            let archive = work.appendingPathComponent("ZZFixture.zip")
            let outcome = try await coordinator.fetchThenSwap(
                result, spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
                download: { _, _ in DownloadedUpdate(archiveURL: archive, bytesDownloaded: 1, workDir: work) },
                apply: { _, _, _ in })
            #expect(outcome.applied)
            #expect(!FileManager.default.fileExists(atPath: mine.partial.path))
            #expect(FileManager.default.fileExists(atPath: other.partial.path))
        }
    }
}
