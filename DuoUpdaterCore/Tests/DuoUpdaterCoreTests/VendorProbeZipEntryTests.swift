import Foundation
import Testing
@testable import DuoUpdaterCore

/// `.zipEntryPlist` end to end, offline: a zip built here with `ditto`, served by
/// an in-process `URLProtocol`, read by the real `unzip` through `ChildProcess`.
/// The recipe and app are invented; nothing on the network or the host is asked.
///
/// These pin the two things the `unzip` call site owns: the entry comes back on
/// stdout (stderr is discarded), and a non-zero exit is reported with its status
/// as "unzip exited N extracting '…'".
@Suite(.serialized)
struct VendorProbeZipEntryTests {

    private final class ZipServer: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var body = Data()

        static func serve(_ data: Data) { lock.withLock { body = data } }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ZipServer.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.lock.withLock { Self.body })
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static let bundleID = "com.example.zzfixture.zipprobe"

    private static func recipe(entry: String) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "https://zzfixture.invalid/stub.zip")!,
            mode: .zipEntryPlist(entry: entry, key: "CFBundleShortVersionString"),
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#)
    }

    private static let app = InstalledApp(
        name: "ZZFixture", bundleID: bundleID,
        shortVersion: "1.0.0", buildVersion: "1",
        path: URL(fileURLWithPath: "/Applications/ZZFixture-ZipProbe.app"),
        isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)

    /// A zip holding `ZZStub.app/Contents/Info.plist` with version 7.8.9.
    private static func stubZip() async throws -> Data {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-zipprobe-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let contents = dir.appendingPathComponent("ZZStub.app/Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "7.8.9"], format: .binary, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("stub.zip")
        let made = try await ChildProcess.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent", dir.appendingPathComponent("ZZStub.app").path, zip.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
        return try Data(contentsOf: zip)
    }

    /// Mutation: in `zipEntryPlistValue`, read `extracted.standardError` as the
    /// plist data → "'…' extracted empty", no version.
    @Test func theEntryIsReadFromUnzipsStandardOutput() async throws {
        ZipServer.serve(try await Self.stubZip())
        let source = VendorProbeSource(
            recipes: [Self.recipe(entry: "ZZStub.app/Contents/Info.plist")],
            session: ZipServer.session())
        let outcome = try #require(await source.probeDiagnostic(for: Self.app))
        #expect(outcome.failure == nil, "\(String(describing: outcome.failure?.detail))")
        #expect(outcome.remote?.shortVersion == "7.8.9")
    }

    /// Mutation: build the message from `extracted.standardError.count` instead of
    /// `extracted.terminationStatus` → it says "exited 0".
    @Test func aMissingEntryReportsUnzipsExitStatus() async throws {
        ZipServer.serve(try await Self.stubZip())
        let source = VendorProbeSource(
            recipes: [Self.recipe(entry: "ZZStub.app/Contents/Nope.plist")],
            session: ZipServer.session())
        let outcome = await source.probeDiagnostic(for: Self.app)
        #expect(outcome?.failure?.kind == "archiveExtractionFailed")
        #expect(outcome?.failure?.detail
            == "unzip exited 11 extracting 'ZZStub.app/Contents/Nope.plist'")
    }
}
