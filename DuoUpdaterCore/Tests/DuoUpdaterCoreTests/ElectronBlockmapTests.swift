import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

private let oldMapBytes = Data(base64Encoded: "H4sIAAAAAAAA/6tWKkstKs7Mz1OyUjJS0lFKy8xJLVayiq5WykvMTQUKggSA4vlpacWpJUpWBjpKyRmpydnFpbkgZUqOQDknIHZWitVRKs6sAms20QHC2NrYWgCCF1d2XgAAAA==")!
private let newMapBytes = Data(base64Encoded: "H4sIAAAAAAAA/6tWKkstKs7Mz1OyUjJS0lFKy8xJLVayiq5WykvMTQUKggSA4vlpacWpJUpWBjpKyRmpydnFpbkgZUqOQLkIIHZWitVRKs6sAms20QHC2NrYWgApKmacXgAAAA==")!
private let oldZIP = Data("AAAABBBBCCCC".utf8)
private let newZIP = Data("AAAAXXXXCCCC".utf8)

struct ElectronBlockmapTests {
    @Test func plansOnlyChangedBlocksAndReusesMovedBlocks() throws {
        let old = try ElectronBlockmap(compressed: oldMapBytes)
        let new = try ElectronBlockmap(compressed: newMapBytes, expectedSize: 12)
        #expect(new.operations(from: old) == [
            .init(kind: .copy, offset: 0, length: 4),
            .init(kind: .download, offset: 4, length: 4),
            .init(kind: .copy, offset: 8, length: 4),
        ])
        let moved = try ElectronBlockmap(json: Data(#"{"version":"2","files":[{"name":"file","offset":0,"checksums":["C","A"],"sizes":[4,4]}]}"#.utf8))
        #expect(moved.operations(from: old) == [
            .init(kind: .copy, offset: 8, length: 4), .init(kind: .copy, offset: 0, length: 4),
        ])
    }

    @Test func equalHashWithDifferentSizeCannotBeCopied() throws {
        let old = try ElectronBlockmap(compressed: oldMapBytes)
        let new = try ElectronBlockmap(json: Data(#"{"version":"2","files":[{"name":"file","offset":0,"checksums":["A"],"sizes":[5]}]}"#.utf8))
        #expect(new.operations(from: old) == [.init(kind: .download, offset: 0, length: 5)])
    }

    @Test func coalescesTinyGapsAndBoundsFragmentedRequests() throws {
        func map(_ checksums: [String], _ sizes: [Int]) throws -> ElectronBlockmap {
            let json = try JSONSerialization.data(withJSONObject: ["version": "2", "files": [
                ["name": "file", "offset": 0, "checksums": checksums, "sizes": sizes]]])
            return try ElectronBlockmap(json: json)
        }
        let old = try map(["A"], [4])
        let new = try map(Array(repeating: ["A", "X"], count: 100_000).flatMap { $0 },
                          Array(repeating: [4, 1], count: 100_000).flatMap { $0 })
        let plan = try #require(new.downloadPlan(from: old, maxRange: ElectronZIPDownload.requestLimit))
        #expect(plan == [.init(kind: .copy, offset: 0, length: 4),
                         .init(kind: .download, offset: 4, length: 499_996)])
        let bigBase = try map(["A"], [8192])
        let fragmented = try map(Array(repeating: ["A", "X"], count: 513).flatMap { $0 },
                                 Array(repeating: [8192, 1], count: 513).flatMap { $0 })
        #expect(fragmented.downloadPlan(from: bigBase, maxRange: ElectronZIPDownload.requestLimit) == nil)
        // Repeated old offsets cannot merge as contiguous COPY operations.
        // No network requests does not make half a million local I/O hops safe.
        let copyOnly = try map(Array(repeating: "A", count: 500_000), Array(repeating: 4, count: 500_000))
        #expect(copyOnly.downloadPlan(from: old, maxRange: ElectronZIPDownload.requestLimit) == nil)
    }

    @Test(arguments: [
        #"{"version":"1","files":[]}"#,
        #"{"version":"2","files":[{"name":"file","offset":-1,"checksums":["A"],"sizes":[1]}]}"#,
        #"{"version":"2","files":[{"name":"file","offset":0,"checksums":["A"],"sizes":[0]}]}"#,
        #"{"version":"2","files":[{"name":"file","offset":0,"checksums":[],"sizes":[4]}]}"#,
        #"{"version":"2","files":[{"name":"file","offset":0,"checksums":["A"],"sizes":[9223372036854775807]}]}"#,
        #"{"version":"2","files":[{"name":"file","offset":0,"checksums":["A"],"sizes":[1.5]}]}"#,
    ])
    func refusesMalformedAndUnsupportedMaps(_ json: String) {
        #expect(throws: (any Error).self) { try ElectronBlockmap(json: Data(json.utf8)) }
    }

    @Test func refusesV3AndMapForAnotherSize() {
        #expect(throws: (any Error).self) { try ElectronBlockmap(compressed: Data("EBB3".utf8)) }
        #expect(throws: (any Error).self) { try ElectronBlockmap(compressed: newMapBytes, expectedSize: 13) }
    }
}

@Suite(.serialized)
struct ElectronZIPDownloadTests {
    private func app(at root: URL) -> InstalledApp {
        InstalledApp(name: "Blockmap", bundleID: "example.blockmap", shortVersion: "1.0", buildVersion: "1.0",
                     path: root.appendingPathComponent("Blockmap.app"), isMASApp: false, sparkleFeedURL: nil)
    }

    private func remote(url: URL, map: URL, digest: Data = newZIP) -> RemoteVersion {
        RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: url, downloadSize: 12,
                      electronBlockmapURL: map, sourceName: "Vendor", vendorInstallerKind: .zip,
                      expectedSHA512: Data(SHA512.hash(data: digest)).base64EncodedString())
    }

    private func seed(root: URL, app: InstalledApp) throws {
        let old = root.appendingPathComponent("old.zip")
        let map = root.appendingPathComponent("old.blockmap")
        try oldZIP.write(to: old); try oldMapBytes.write(to: map)
        ElectronArchiveCache.retain(archive: old, map: map, for: app)
        #expect(ElectronArchiveCache.open(for: app) != nil)
    }

    @Test func reconstructsAndVerifiesTheExactTargetWithOneRange() async throws {
        let sim = try HTTPDownloadSimulation([
            .response(200, body: newMapBytes),
            .response(206, headers: ["Content-Range": "bytes 4-7/12"], body: Data("XXXX".utf8)),
        ])
        let app = app(at: sim.sandbox.root)
        try await ElectronArchiveCache.$rootOverride.withValue(sim.sandbox.root.appendingPathComponent("cache")) {
            try seed(root: sim.sandbox.root, app: app)
            try await ElectronBlockmapHTTP.$configurationOverride.withValue(sim.configuration) {
                let result = try await ElectronZIPDownload.prepare(
                    app: app, remote: remote(url: sim.url, map: sim.url.appendingPathExtension("blockmap")),
                    workDir: sim.sandbox.destination, onProgress: { _ in })
                let archive = try #require(result?.archive)
                #expect(try Data(contentsOf: archive) == newZIP)
                #expect(result?.bytes == Int64(newMapBytes.count + 4))
                #expect(sim.script.requests.map(\.range) == [nil, "bytes=4-7"])
                #expect(sim.script.unexpectedRequests.isEmpty)
            }
        }
        try await sim.close()
    }

    @Test func corruptCachedBaseIsRejectedBeforeRequestingAnyRanges() async throws {
        let sim = try HTTPDownloadSimulation([.response(200, body: newMapBytes)])
        let app = app(at: sim.sandbox.root)
        let root = sim.sandbox.root.appendingPathComponent("cache")
        try await ElectronArchiveCache.$rootOverride.withValue(root) {
            try seed(root: sim.sandbox.root, app: app)
            try Data("ZZZZBBBBCCCC".utf8).write(to: root.appendingPathComponent(ElectronArchiveCache.key(for: app)).appendingPathComponent("archive.zip"))
            try await ElectronBlockmapHTTP.$configurationOverride.withValue(sim.configuration) {
                let result = try await ElectronZIPDownload.prepare(
                    app: app, remote: remote(url: sim.url, map: sim.url.appendingPathExtension("blockmap")),
                    workDir: sim.sandbox.destination, onProgress: { _ in })
                #expect(result?.archive == nil)
                #expect(result?.bytes == Int64(newMapBytes.count))
                #expect(sim.script.requests.count == 1)
            }
        }
        try await sim.close()
    }

    @Test func targetDigestFailureFallsBackAndCountsFailedDifferentialBytes() async throws {
        let server = try HTTPDownloadLoopbackServer([
            .init(status: 200, body: newMapBytes),
            .init(status: 206, headers: ["Content-Range": "bytes 4-7/12"], body: Data("BAD!".utf8)),
            .init(status: 200, body: newZIP),
        ])
        defer { server.stop() }
        let box = try HTTPDownloadSandbox()
        let app = app(at: box.root)
        try await ElectronArchiveCache.$rootOverride.withValue(box.root.appendingPathComponent("cache")) {
            try seed(root: box.root, app: app)
            let result = UpdateResult(app: app,
                remote: remote(url: server.url, map: server.url.appendingPathExtension("blockmap")), status: .updateAvailable(latest: "2.0"))
            let download = try await VendorInstaller().download(result, population: nil, onStage: { _ in })
            defer { try? FileManager.default.removeItem(at: download.workDir) }
            #expect(try Data(contentsOf: download.archiveURL) == newZIP)
            #expect(download.bytesDownloaded == Int64(newMapBytes.count + 4 + newZIP.count))
            #expect(server.requests.count == 3)
            #expect(server.requests[1].contains("Range: bytes=4-7"))
            #expect(!server.requests[2].contains("Range:"))
            // Merely downloading must not promote the pending map/new archive.
            let retained = try #require(ElectronArchiveCache.open(for: app))
            #expect(try retained.archive.readToEnd() == oldZIP)
        }
        try await box.close()
    }

    @Test func ignoredRangeFallsBackInsteadOfAppendingAWholeArchive() async throws {
        let sim = try HTTPDownloadSimulation([.response(200, body: newMapBytes), .response(200, body: newZIP)])
        let app = app(at: sim.sandbox.root)
        try await ElectronArchiveCache.$rootOverride.withValue(sim.sandbox.root.appendingPathComponent("cache")) {
            try seed(root: sim.sandbox.root, app: app)
            try await ElectronBlockmapHTTP.$configurationOverride.withValue(sim.configuration) {
                let result = try await ElectronZIPDownload.prepare(
                    app: app, remote: remote(url: sim.url, map: sim.url.appendingPathExtension("blockmap")),
                    workDir: sim.sandbox.destination, onProgress: { _ in })
                #expect(result?.archive == nil)
                #expect(!FileManager.default.fileExists(atPath: sim.sandbox.destination.appendingPathComponent("electron-update.zip").path))
                #expect(sim.script.requests.count == 2)
            }
        }
        try await sim.close()
    }

    @Test func HTTPBridgeCancelsTheActiveTransferEvenWhenTheServerFinishes() async throws {
        let server = try HTTPDownloadLoopbackServer([.init(status: 200, heldBody: newMapBytes)])
        defer { server.stop() }
        let task = Task {
            try await ElectronBlockmapHTTP(limit: 1024, range: nil, total: nil, accounting: .init(), appID: "test")
                .get(server.url, headers: [:])
        }
        var observed = server.observedRequests.makeAsyncIterator()
        #expect(await observed.next() != nil)
        task.cancel()
        _ = await server.releaseHeldBody()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(server.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func cancellationDuringMapOrRangeDoesNotStartAFullDownload(duringRange: Bool) async throws {
        let responses: [HTTPDownloadLoopbackServer.Response] = duringRange ? [
            .init(status: 200, body: newMapBytes),
            .init(status: 206, headers: ["Content-Range": "bytes 4-7/12"], heldBody: Data("XXXX".utf8)),
        ] : [.init(status: 200, heldBody: newMapBytes)]
        let server = try HTTPDownloadLoopbackServer(responses)
        defer { server.stop() }
        let box = try HTTPDownloadSandbox()
        let app = app(at: box.root)
        try await ElectronArchiveCache.$rootOverride.withValue(box.root.appendingPathComponent("cache")) {
            if duringRange { try seed(root: box.root, app: app) }
            let result = UpdateResult(app: app, remote: remote(url: server.url,
                map: server.url.appendingPathExtension("blockmap")), status: .updateAvailable(latest: "2.0"))
            let task = Task { try await VendorInstaller().download(result, population: nil, onStage: { _ in }) }
            var observed = server.observedRequests.makeAsyncIterator()
            let mapRequest = try #require(await observed.next())
            #expect(mapRequest.hasPrefix("GET /payload.bin.blockmap "))
            if duringRange {
                let rangeRequest = try #require(await observed.next())
                #expect(rangeRequest.contains("Range: bytes=4-7"))
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(server.requests.count == (duringRange ? 2 : 1))
            #expect(server.unexpectedRequests.isEmpty)
        }
        try await box.close()
    }

    @Test(arguments: [
        ["Content-Range": "bytes 0-3/12"],
        ["Content-Range": "bytes 4-7/13"],
        ["Content-Range": "bytes 4-7/12", "Content-Encoding": "gzip"],
        ["Content-Range": "bytes 4-7/12", "Content-Length": "5"],
    ])
    func rejectsMalformedRangeHeaders(headers: [String: String]) async throws {
        let sim = try HTTPDownloadSimulation([.response(206, headers: headers, body: Data("XXXX".utf8))])
        await ElectronBlockmapHTTP.$configurationOverride.withValue(sim.configuration) {
            await #expect(throws: (any Error).self) {
                try await ElectronBlockmapHTTP(limit: 4, range: 4..<8, total: 12, accounting: .init(), appID: "test")
                    .get(sim.url, headers: [:])
            }
            #expect(sim.script.requests.count == 1)
        }
        try await sim.close()
    }

    @Test func mapBodyCannotExceedItsBoundWithoutContentLength() async throws {
        let sim = try HTTPDownloadSimulation([.response(200, headers: ["Content-Length": "-1"], body: Data(repeating: 1, count: 5))])
        await ElectronBlockmapHTTP.$configurationOverride.withValue(sim.configuration) {
            await #expect(throws: (any Error).self) {
                try await ElectronBlockmapHTTP(limit: 4, range: nil, total: nil, accounting: .init(), appID: "test")
                    .get(sim.url, headers: [:])
            }
        }
        try await sim.close()
    }

    @Test func redirectDropsCredentialsAndKeepsTheRange() async throws {
        let target = try HTTPDownloadLoopbackServer([
            .init(status: 206, headers: ["Content-Range": "bytes 4-7/12"], body: Data("XXXX".utf8)),
        ])
        defer { target.stop() }
        let origin = try HTTPDownloadLoopbackServer([
            .init(status: 302, headers: ["Location": target.url.absoluteString]),
        ])
        defer { origin.stop() }
        let result = try await ElectronBlockmapHTTP(
            limit: 4, range: 4..<8, total: 12, accounting: .init(), appID: "test").get(
                origin.url, headers: ["Authorization": "Bearer private", "Cookie": "private=1", "X-Api-Key": "private"])
        #expect(result.0 == Data("XXXX".utf8))
        let request = try #require(target.requests.first).lowercased()
        #expect(request.contains("range: bytes=4-7"))
        #expect(!request.contains("authorization:"))
        #expect(!request.contains("cookie:"))
        #expect(!request.contains("x-api-key:"))
    }

    @Test func reclaimsCrashLeftoversButPreservesUnownedFiles() throws {
        let box = try HTTPDownloadSandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let root = box.root.appendingPathComponent("cache")
        let orphan = root.appendingPathComponent(".incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try oldZIP.write(to: orphan.appendingPathComponent("archive.zip"))
        let foreign = root.appendingPathComponent(".incoming-unowned")
        try oldZIP.write(to: foreign)
        ElectronArchiveCache.$rootOverride.withValue(root) {
            #expect(ElectronArchiveCache.discardAllForSpace() > 0)
            #expect(!FileManager.default.fileExists(atPath: orphan.path))
            #expect(FileManager.default.fileExists(atPath: foreign.path))
        }
    }

    @Test func cacheBudgetIncludesAllocatedMetadataAndRefusesSymlinkedArchive() throws {
        let box = try HTTPDownloadSandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let app = app(at: box.root)
        let root = box.root.appendingPathComponent("cache")
        let zip = box.root.appendingPathComponent("old.zip")
        let map = box.root.appendingPathComponent("old.blockmap")
        try oldZIP.write(to: zip); try oldMapBytes.write(to: map)
        try ElectronArchiveCache.$rootOverride.withValue(root) {
            ElectronArchiveCache.$budgetOverride.withValue(Int64(oldZIP.count + oldMapBytes.count)) {
                ElectronArchiveCache.retain(archive: zip, map: map, for: app)
                #expect(ElectronArchiveCache.open(for: app) == nil)
            }
            try seed(root: box.root, app: app)
            let cached = root.appendingPathComponent(ElectronArchiveCache.key(for: app)).appendingPathComponent("archive.zip")
            try FileManager.default.removeItem(at: cached)
            try FileManager.default.createSymbolicLink(at: cached, withDestinationURL: zip)
            #expect(ElectronArchiveCache.open(for: app) == nil)
        }
    }

    @Test func parallelRetentionCannotExceedBudgetAroundAnActiveBaseline() throws {
        let box = try HTTPDownloadSandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let first = app(at: box.root)
        let second = app(at: box.root.appendingPathComponent("second"))
        let root = box.root.appendingPathComponent("cache")
        try ElectronArchiveCache.$rootOverride.withValue(root) {
            try seed(root: box.root, app: first)
            let allocation = StorageInventory.allocatedSize(of: root)
            let active = try #require(ElectronArchiveCache.open(for: first))
            ElectronArchiveCache.$budgetOverride.withValue(allocation) {
                ElectronArchiveCache.retain(archive: box.root.appendingPathComponent("old.zip"),
                    map: box.root.appendingPathComponent("old.blockmap"), for: second)
                #expect(StorageInventory.allocatedSize(of: root) <= allocation)
                #expect(ElectronArchiveCache.open(for: second) == nil)
                #expect((try? active.archive.readToEnd()) == oldZIP)
            }
        }
    }

    @Test func cacheReclamationSparesAnActiveReader() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blockmap-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = app(at: root)
        try ElectronArchiveCache.$rootOverride.withValue(root.appendingPathComponent("cache")) {
            try seed(root: root, app: app)
            var baseline = ElectronArchiveCache.open(for: app)
            #expect(baseline != nil)
            #expect(ElectronArchiveCache.discardAllForSpace() == 0)
            #expect(try baseline?.archive.readToEnd() == oldZIP)
            baseline = nil
            #expect(ElectronArchiveCache.discardAllForSpace() > 0)
            #expect(ElectronArchiveCache.open(for: app) == nil)
        }
    }
}
