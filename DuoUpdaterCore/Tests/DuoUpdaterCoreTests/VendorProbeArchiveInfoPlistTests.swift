import Foundation
import Testing
@testable import DuoUpdaterCore

/// `.redirectArchiveInfoPlist` end to end, offline: a zip built here with
/// `/usr/bin/zip`, served by an in-process `URLProtocol` that honours (or, on
/// request, ignores) `Range`, read by the real `RemoteZipEntry` through the real
/// `VendorProbeSource`. The recipe and app are invented; nothing on the network or
/// the host is asked.
///
/// Each test names the mutation it exists to catch.
@Suite(.serialized)
struct VendorProbeArchiveInfoPlistTests {

    // MARK: - Server

    private final class ArchiveServer: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var body = Data()
        nonisolated(unsafe) private static var honoursRange = true
        nonisolated(unsafe) private static var rangeStatus: Int?
        nonisolated(unsafe) private static var extraBytes = 0
        nonisolated(unsafe) private static var tailFromFront = false
        nonisolated(unsafe) private static var changesEveryRead = false
        nonisolated(unsafe) private static var served: [(range: String?, bytes: Int)] = []

        /// `extraBytes` pads every 206 body past the range its `Content-Range` names;
        /// `tailFromFront` answers a suffix range with the archive's first bytes;
        /// `changesEveryRead` stamps each response with a new `Last-Modified`.
        static func serve(
            _ data: Data, honoursRange: Bool = true, rangeStatus: Int? = nil, extraBytes: Int = 0,
            tailFromFront: Bool = false, changesEveryRead: Bool = false
        ) {
            lock.withLock {
                body = data
                self.honoursRange = honoursRange
                self.rangeStatus = rangeStatus
                self.extraBytes = extraBytes
                self.tailFromFront = tailFromFront
                self.changesEveryRead = changesEveryRead
                served = []
            }
        }

        /// The GETs answered so far: the `Range` each asked for and the bytes sent.
        static var gets: [(range: String?, bytes: Int)] { lock.withLock { served } }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ArchiveServer.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let (body, honoursRange, rangeStatus, extraBytes, tailFromFront, changesEveryRead) =
                Self.lock.withLock {
                    (Self.body, Self.honoursRange, Self.rangeStatus, Self.extraBytes,
                     Self.tailFromFront, Self.changesEveryRead)
                }
            let url = request.url!
            if request.httpMethod == "HEAD" {
                respond(url, 200, ["Content-Length": "\(body.count)"], Data())
                return
            }
            let range = request.value(forHTTPHeaderField: "Range")
            if let rangeStatus {
                record(range, 0)
                respond(url, rangeStatus, [:], Data())
                return
            }
            guard honoursRange, let range,
                  var span = Self.span(range, total: body.count) else {
                record(range, body.count)
                respond(url, 200, ["Content-Length": "\(body.count)"], body)
                return
            }
            if tailFromFront, range.hasPrefix("bytes=-") {
                span = 0 ... span.upperBound - span.lowerBound
            }
            let modified = changesEveryRead ? "Mon, 14 Sep 2026 22:28:\(10 + Self.gets.count) GMT"
                : "Mon, 14 Sep 2026 22:28:02 GMT"
            let slice = body.subdata(in: span.lowerBound ..< span.upperBound + 1)
                + Data(repeating: 0, count: extraBytes)
            record(range, slice.count)
            respond(url, 206, [
                "Content-Range": "bytes \(span.lowerBound)-\(span.upperBound)/\(body.count)",
                "Content-Length": "\(slice.count)",
                "Last-Modified": modified,
            ], slice)
        }

        override func stopLoading() {}

        private func record(_ range: String?, _ bytes: Int) {
            Self.lock.withLock { Self.served.append((range, bytes)) }
        }

        private func respond(_ url: URL, _ status: Int, _ headers: [String: String], _ data: Data) {
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        /// `bytes=-N` or `bytes=A-B`, clamped to the body.
        private static func span(_ header: String, total: Int) -> ClosedRange<Int>? {
            guard header.hasPrefix("bytes="), total > 0 else { return nil }
            let spec = header.dropFirst("bytes=".count)
            if spec.hasPrefix("-"), let count = Int(spec.dropFirst()) {
                return max(0, total - count) ... total - 1
            }
            let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]),
                  start < total, start <= end else { return nil }
            return start ... min(end, total - 1)
        }
    }

    // MARK: - Fixtures

    private static let bundleID = "com.example.zzfixture.archiveprobe"
    private static let entry = "ZZStub.app/Contents/Info.plist"

    private static func recipe() -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "https://zzfixture.invalid/versions/ZZFixture7.50.1.zip")!,
            mode: .redirectArchiveInfoPlist(entry: entry),
            versionPattern: #"ZZFixture([0-9]+(?:\.[0-9]+)+)\.zip"#)
    }

    private static func app(_ short: String, _ build: String) -> InstalledApp {
        let path = "/Applications/ZZFixture-ArchiveProbe.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: "ZZFixture", bundleID: bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// A zip of `ZZStub.app` whose `Info.plist` (XML, so a byte flip stays
    /// parseable) carries `plist`, beside 60 incompressible 4 KB resources — enough
    /// that reading the archive whole would show in the served byte count, and a
    /// central directory longer than the first directory chunk.
    private static func archive(
        _ plist: [String: String], stored: Bool = false
    ) async throws -> (zip: Data, plist: Data) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-archiveprobe-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let contents = dir.appendingPathComponent("ZZStub.app/Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in 0..<60 {
            var bytes = Data(count: 4_096)
            for i in bytes.indices {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                bytes[i] = UInt8(truncatingIfNeeded: state >> 33)
            }
            try bytes.write(to: resources.appendingPathComponent(
                "a-resource-with-a-long-enough-name-to-fill-the-directory-\(index).bin"))
        }
        let made = try await ChildProcess.run(
            "/usr/bin/zip", ["-q", "-r", "-X"] + (stored ? ["-0"] : []) + ["stub.zip", "ZZStub.app"],
            workingDirectory: dir, onCancel: .runToCompletion)
        #expect(made.succeeded)
        return (try Data(contentsOf: dir.appendingPathComponent("stub.zip")), plistData)
    }

    private static let release = [
        "CFBundleIdentifier": bundleID,
        "CFBundleShortVersionString": "7.50",
        "CFBundleVersion": "2356",
    ]

    private static func probe() async -> ProbeOutcome? {
        await VendorProbeSource(recipes: [recipe()], session: ArchiveServer.session())
            .probeDiagnostic(for: app("7.50", "2355"))
    }

    /// Serves `zip` from memory to `RemoteZipEntry.read` directly.
    private static func fetch(_ zip: Data) -> RemoteZipEntry.Fetch {
        { range in
            let total = zip.count
            switch range {
            case .suffix(let count):
                return .init(data: zip.subdata(in: max(0, total - count) ..< total),
                             totalLength: total, identity: "v1")
            case .span(let start, let end):
                return .init(data: zip.subdata(in: start ..< min(end, total - 1) + 1),
                             totalLength: total, identity: "v1")
            }
        }
    }

    // MARK: - Through the probe

    /// Mutation: drop `bundle:` from `makeRemoteVersion` → the remote is the
    /// filename's `7.50.1` and the copy already on build 2356 reads out of date.
    /// Mutation: send no `Range` header from `archiveBytes` → the host answers
    /// with the whole archive and the probe fails.
    @Test func theOfferIsTheArchivesOwnBundle() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip)

        let outcome = try #require(await Self.probe())
        #expect(outcome.failure == nil, "\(String(describing: outcome.failure?.detail))")
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "7.50")
        #expect(remote.version == "2356")
        #expect(remote.marketingMatchesBundle)

        #expect(UpdateChecker.evaluate(installed: Self.app("7.50", "2356"), remote: remote) == .upToDate)
        #expect(UpdateChecker.evaluate(installed: Self.app("7.50", "2355"), remote: remote)
            == .updateAvailable(latest: "7.50"))

        let gets = ArchiveServer.gets
        #expect(!gets.isEmpty)
        #expect(gets.allSatisfy { $0.range != nil })
        let served = gets.reduce(0) { $0 + $1.bytes }
        #expect(served * 10 < zip.count, "served \(served) of \(zip.count) bytes")
    }

    /// Mutation: accept any 2xx in `archiveBytes` → the failure names an unreadable
    /// `Content-Range` instead of the refused range.
    @Test func aHostThatIgnoresRangeFailsTheProbe() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, honoursRange: false)

        let outcome = try #require(await Self.probe())
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.kind == "archiveExtractionFailed")
        #expect(outcome.failure?.detail
            == "zzfixture.invalid answered a byte range with HTTP 200, not 206")
    }

    /// Mutation: map every refused range to `.archiveExtractionFailed` → a vendor
    /// outage files as a broken recipe. Mutation: drop the gateway retry → one GET.
    @Test func aServerErrorOnTheRangeIsRetriedOnceThenInfra() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, rangeStatus: 503)

        let outcome = try #require(await Self.probe())
        #expect(outcome.failure == .httpStatus(503))
        #expect(outcome.failure?.classification == .infra)
        #expect(ArchiveServer.gets.count == 2)
    }

    /// A 404 on the archive is the archive's answer, not the redirect endpoint's.
    /// Mutation: map every non-206 status to `.httpStatus` → the report blames
    /// `recipe.url`, which answered its redirect.
    @Test func aMissingArchiveIsNamedAsTheArchive() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, rangeStatus: 404)

        let outcome = try #require(await Self.probe())
        #expect(outcome.failure?.kind == "archiveExtractionFailed")
        #expect(outcome.failure?.detail
            == "zzfixture.invalid answered a byte range with HTTP 404, not 206")
        #expect(ArchiveServer.gets.count == 1)
    }

    /// Mutation: drop the suffix check in `archiveBytes` → the archive's first
    /// bytes are searched for an end record and the failure blames the zip.
    @Test func aTailReadAnsweredFromTheFrontFails() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, tailFromFront: true)

        let outcome = try #require(await Self.probe())
        #expect(outcome.failure?.detail
            == "asked zzfixture.invalid for the archive's tail, it sent bytes 0-1023 of \(zip.count)")
    }

    /// The vendor replacing the file between reads is its publish, not a broken
    /// recipe. Mutation: map `ArchiveChanged` to `.archiveExtractionFailed` → the
    /// classification is `.recipe`. Mutation: stop comparing identities → the
    /// probe answers from offsets taken in another copy.
    @Test func anArchiveReplacedBetweenReadsIsInfra() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, changesEveryRead: true)

        let outcome = try #require(await Self.probe())
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.classification == .infra)
        #expect(outcome.failure?.detail.hasPrefix("the archive changed between range reads") == true)
    }

    /// A 206 longer than its own `Content-Range` is not the range asked for.
    /// Mutation: stop reading at `length` and return → the padded body is accepted.
    @Test func aRangeLongerThanAskedFailsTheProbe() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        ArchiveServer.serve(zip, extraBytes: 7)

        let outcome = try #require(await Self.probe())
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.detail
            == "zzfixture.invalid sent more than the 1024 bytes asked for")
    }

    /// Mutation: delete the `CFBundleIdentifier` guard → another app's version is
    /// offered as this one's.
    @Test func anArchiveHoldingAnotherAppFails() async throws {
        var other = Self.release
        other["CFBundleIdentifier"] = "com.example.zzfixture.somethingelse"
        let (zip, _) = try await Self.archive(other)
        ArchiveServer.serve(zip)

        let outcome = try #require(await Self.probe())
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.detail
            == "'\(Self.entry)' is com.example.zzfixture.somethingelse, not \(Self.bundleID)")
    }

    /// Mutation: let a missing `CFBundleVersion` through → a marketing-only remote,
    /// which cannot tell a re-published build from the one it replaces.
    @Test func aBundleWithoutABuildFails() async throws {
        var noBuild = Self.release
        noBuild["CFBundleVersion"] = nil
        let (zip, _) = try await Self.archive(noBuild)
        ArchiveServer.serve(zip)

        let outcome = try #require(await Self.probe())
        #expect(outcome.failure == .plistKeyMissing(entry: Self.entry, key: "CFBundleVersion"))
    }

    // MARK: - The reader

    /// A directory read 46 bytes at a time splits almost every record across two
    /// reads. Mutation: fetch the next chunk from `have + 1` instead of `have` → the
    /// records are misaligned and the read fails.
    @Test func aDirectoryReadInTinyChunksStillFindsTheEntry() async throws {
        for stored in [false, true] {
            let (zip, plist) = try await Self.archive(Self.release, stored: stored)
            let bytes = try await RemoteZipEntry.read(
                Self.entry, fetch: Self.fetch(zip), directoryChunk: 46)
            #expect(bytes == plist, "stored: \(stored)")
        }
    }

    /// Mutation: delete the size/CRC-32 check → the corrupted archive is read as
    /// build 2357, a version the vendor never published.
    @Test func aCorruptedEntryIsRefusedNotMisread() async throws {
        let (zip, _) = try await Self.archive(Self.release, stored: true)
        var corrupted = zip
        let needle = Data("<string>2356</string>".utf8)
        let found = try #require(corrupted.range(of: needle))
        corrupted[found.lowerBound + "<string>235".utf8.count] = UInt8(ascii: "7")

        await #expect(throws: RemoteZipEntry.Unreadable(
            detail: "'\(Self.entry)' does not match its directory record's size and CRC-32")) {
            _ = try await RemoteZipEntry.read(Self.entry, fetch: Self.fetch(corrupted))
        }
    }

    /// An archive comment pushes the end record out of the first tail read.
    /// Mutation: drop the second, longer tail read → "no zip end-of-central-directory
    /// record in the last 1024 bytes".
    @Test func anArchiveCommentLongerThanTheFirstTailReadIsSkipped() async throws {
        let (zip, plist) = try await Self.archive(Self.release)
        var commented = zip
        let end = try #require(RemoteZipEntry.endOfDirectory(in: zip))
        let comment = Data(repeating: UInt8(ascii: "c"), count: 4_000)
        commented[end.position + 20] = UInt8(comment.count & 0xFF)
        commented[end.position + 21] = UInt8(comment.count >> 8)
        commented.append(comment)

        let bytes = try await RemoteZipEntry.read(Self.entry, fetch: Self.fetch(commented))
        #expect(bytes == plist)
    }

    /// Mutation: fold the three stopping paths back into "not in the central
    /// directory" → the message names a missing entry for a malformed directory.
    @Test func aRecordRunningPastTheDirectoryIsNamed() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        var short = zip
        let end = try #require(RemoteZipEntry.endOfDirectory(in: zip))
        short[end.position + 12] = 50
        for offset in 13..<16 { short[end.position + offset] = 0 }

        await #expect(throws: RemoteZipEntry.Unreadable(
            detail: "central directory record 0 runs past the directory's end")) {
            _ = try await RemoteZipEntry.read(Self.entry, fetch: Self.fetch(short))
        }
    }

    /// Mutation: skip the ZIP64 check → the sentinel offset 0xFFFFFFFF is read as a
    /// real one and the failure names an overlapping directory instead.
    @Test func aZip64ArchiveIsRefused() async throws {
        let (zip, _) = try await Self.archive(Self.release)
        var zip64 = zip
        let end = try #require(RemoteZipEntry.endOfDirectory(in: zip))
        for offset in 16..<20 { zip64[end.position + offset] = 0xFF }

        await #expect(throws: RemoteZipEntry.Unreadable(detail: "ZIP64 archive — not supported")) {
            _ = try await RemoteZipEntry.read(Self.entry, fetch: Self.fetch(zip64))
        }
    }
}
