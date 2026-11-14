import Foundation
import Testing
import DuoUpdaterCore

@Suite struct HelperPackageRunnerTests {
    @Test func preExecutionDeferralIsDistinctFromFallbackAndFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        for status: Int32 in [75, 77, 1] {
            let helper = PackageFakeHelper(version: "149 protocol/6", status: status)
            do {
                try await runner(helper).install(package: fixture.package, installedApp: fixture.app,
                    bundleIdentifier: "test.fixture", fingerprint: Data(count: 32), progress: { _ in })
                Issue.record("An unsuccessful helper reply was accepted")
            } catch is AutomaticInstall.Deferred {
                #expect(status == 75)
            } catch PackageInstaller.PackageError.requiresInteractiveInstaller {
                #expect(status == 77)
            } catch PackageInstaller.PackageError.installationFailed {
                #expect(status == 1)
            }
            #expect(helper.requests == 1)
        }
    }

    @Test func anOlderHelperIsNeverSentThePackageSelector() async throws {
        let helper = PackageFakeHelper(version: "149 protocol/5")
        let runner = runner(helper)
        #expect(!(await runner.isAvailable()))
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        await #expect(throws: (any Error).self) {
            try await runner.install(package: fixture.package, installedApp: fixture.app,
                bundleIdentifier: "test.fixture", fingerprint: Data(count: 32), progress: { _ in })
        }
        #expect(helper.requests == 0)
    }

    @Test func descriptorsAndFingerprintCrossXPCAndProgressIsDrained() async throws {
        let helper = PackageFakeHelper(version: "149 protocol/6")
        let runner = runner(helper)
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let progress = PackageProgress()
        #expect(await runner.isAvailable())
        try await runner.install(package: fixture.package, installedApp: fixture.app,
            bundleIdentifier: "test.fixture", fingerprint: Data(repeating: 7, count: 32), progress: { progress.add($0) })
        #expect(helper.requests == 1)
        #expect(helper.received == Data("fixture package".utf8))
        #expect(helper.fingerprint == Data(repeating: 7, count: 32))
        #expect(progress.lines.contains("installer:%100"))
    }

    @Test func aSilentHelperReturnsUnavailableWithoutAnInstallRequest() async {
        let helper = PackageFakeHelper(version: nil)
        var runner = runner(helper)
        runner.timeout = .milliseconds(50)
        #expect(!(await runner.isAvailable()))
        #expect(helper.requests == 0)
    }

    @Test func missingApprovalDoesNotCreateAnXPCConnectionOrInstall() async throws {
        let runner = HelperPackageRunner(connect: { nil })
        #expect(!(await runner.isAvailable()))
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        await #expect(throws: (any Error).self) {
            try await runner.install(package: fixture.package, installedApp: fixture.app,
                bundleIdentifier: "test.fixture", fingerprint: Data(count: 32), progress: { _ in })
        }
    }

    private func runner(_ helper: PackageFakeHelper) -> HelperPackageRunner {
        let listener = NSXPCListener.anonymous()
        let delegate = ZZExportingDelegate(exported: helper)
        listener.delegate = delegate
        listener.resume()
        let box = EndpointBox(listener.endpoint, retaining: [listener, delegate])
        return HelperPackageRunner(connect: { NSXPCConnection(listenerEndpoint: box.value) })
    }

    private struct Fixture {
        let root: URL
        let package: URL
        let app = URL(fileURLWithPath: "/Applications/NonexistentPackageFixture.app")
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("package-runner-\(UUID().uuidString)")
            package = root.appendingPathComponent("fixture.pkg")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try Data("fixture package".utf8).write(to: package)
        }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}

private final class PackageProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var lines: [String] { lock.withLock { values } }
    func add(_ value: String) { lock.withLock { values.append(value) } }
}

private final class PackageFakeHelper: NSObject, MASHelperProtocol, @unchecked Sendable {
    let version: String?
    let status: Int32
    private let lock = NSLock()
    private var calls = 0
    private var bytes = Data()
    private var digest = Data()
    var requests: Int { lock.withLock { calls } }
    var received: Data { lock.withLock { bytes } }
    var fingerprint: Data { lock.withLock { digest } }
    init(version: String?, status: Int32 = 0) { self.version = version; self.status = status }

    func helperVersion(withReply reply: @escaping (String) -> Void) { if let version { reply(version) } }
    func installPackage(package: FileHandle, fingerprint: Data, installedAppPath: String,
                        bundleIdentifier: String, automatic: Bool, progress: FileHandle,
                        withReply reply: @escaping (Int32, String?) -> Void) {
        let received = (try? package.readToEnd()) ?? Data()
        lock.withLock { calls += 1; bytes = received; digest = fingerprint }
        if status == 0 { try? progress.write(contentsOf: Data("installer:%100\n".utf8)) }
        reply(status, nil)
    }
    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) { reply(-1, "Fixture") }
    func stagedSparkleBundleVersions(bundleID: String,
                                     withReply reply: @escaping (String?, String?, String?) -> Void) { reply(nil, nil, nil) }
    func processExecutablePath(pid: Int32, startedSeconds: Int64, startedMicroseconds: Int32,
                               withReply reply: @escaping (String?) -> Void) { reply(nil) }
}
