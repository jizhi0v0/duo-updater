import Darwin
import Foundation
import Testing

struct HelperProcessIdentityReaderTests {
    private static let expected = ProcessExecutablePath.Identity(seconds: 100, microseconds: 7)

    private func reader(_ fake: ProcessPathHelper) -> HelperProcessIdentityReader {
        let listener = NSXPCListener.anonymous()
        let delegate = ZZExportingDelegate(exported: fake)
        listener.delegate = delegate
        listener.resume()
        let box = EndpointBox(listener.endpoint, retaining: [listener, delegate])
        return HelperProcessIdentityReader(connect: { NSXPCConnection(listenerEndpoint: box.value) },
            identity: { _ in Self.expected })
    }

    @Test func currentHelperReceivesTheExactProcessLifetime() {
        let fake = ProcessPathHelper(path: "/Applications/RustDesk.app/Contents/MacOS/service")
        #expect(reader(fake).read(pid: 554) == fake.path)
        #expect(fake.requests.map(\.0) == [554])
        #expect(fake.requests.map(\.1) == [Self.expected.seconds])
        #expect(fake.requests.map(\.2) == [Self.expected.microseconds])
    }

    @Test func oldHelperIsNeverSentAnUnsupportedSelector() {
        let fake = ProcessPathHelper(version: "148 protocol/3", path: "/Applications/RustDesk.app/Contents/MacOS/service")
        #expect(reader(fake).read(pid: 554) == nil)
        #expect(fake.requests.isEmpty)
        #expect(!HelperProtocolRevision.supportsProcessExecutablePath(versionReply: "148"))
        #expect(HelperProtocolRevision.supportsProcessExecutablePath(
            versionReply: HelperProtocolRevision.versionReply(bundleVersion: "148")))
    }

    @Test func missingSilentAndMalformedAnswersStayUnknown() {
        #expect(HelperProcessIdentityReader(connect: { nil }).read(pid: getpid()) == nil)
        for path in [nil, "service", "/Applications/Bad\0Path"] as [String?] {
            #expect(reader(ProcessPathHelper(path: path)).read(pid: 554) == nil)
        }
        let fake = ProcessPathHelper(version: nil, path: "/should/not/be/asked")
        var read = reader(fake)
        read.timeout = .milliseconds(20)
        #expect(read.read(pid: 554) == nil)
        #expect(fake.requests.isEmpty)
    }

    @Test func replyForARecycledPIDIsRejectedByTheClient() {
        let fake = ProcessPathHelper(path: "/Applications/Unrelated.app/Contents/MacOS/tool")
        let count = IdentityReads()
        var read = reader(fake)
        read.identity = { _ in
            count.next() == 1 ? Self.expected : .init(seconds: 101, microseconds: 7)
        }
        #expect(read.read(pid: 554) == nil)
        #expect(fake.requests.count == 1)
    }

    @Test func rootReaderChecksIdentityBeforeAndAfterReadingThePath() {
        let expected = Self.expected
        let path = "/Applications/RustDesk.app/Contents/MacOS/service"
        #expect(ProcessExecutablePath.read(pid: 554, expected: expected,
            identity: { _ in expected }, executablePath: { _ in path }) == path)
        let changed = ProcessExecutablePath.Identity(seconds: 101, microseconds: 7)
        #expect(ProcessExecutablePath.read(pid: 554, expected: expected,
            identity: { _ in changed }, executablePath: { _ in
                Issue.record("A mismatched process must not be inspected")
                return path
            }) == nil)
        var reads = 0
        #expect(ProcessExecutablePath.read(pid: 554, expected: expected,
            identity: { _ in reads += 1; return reads == 1 ? expected : changed },
            executablePath: { _ in path }) == nil)
        for badPID: Int32 in [0, -1] {
            #expect(ProcessExecutablePath.read(pid: badPID, expected: expected,
                identity: { _ in expected }, executablePath: { _ in path }) == nil)
        }
        for badPath in ["service", "", "/bad\0path"] {
            #expect(ProcessExecutablePath.read(pid: 554, expected: expected,
                identity: { _ in expected }, executablePath: { _ in badPath }) == nil)
        }
    }

    @Test func liveProcessReadUsesItsActualKernelIdentity() throws {
        let pid = getpid()
        let identity = try #require(ProcessExecutablePath.identity(of: pid))
        let path = try #require(ProcessExecutablePath.read(pid: pid, expected: identity))
        #expect(path.hasPrefix("/"))
        #expect(ProcessExecutablePath.read(pid: pid,
            expected: .init(seconds: identity.seconds + 1, microseconds: identity.microseconds)) == nil)
    }

    @Test func unlinkedExecutableIsRecoveredFromTheSavedExecPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("BackgroundService")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: executable.path)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["60"]
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let identity = try #require(ProcessExecutablePath.identity(of: process.processIdentifier))
        let original = try #require(ProcessExecutablePath.read(pid: process.processIdentifier, expected: identity))
        try FileManager.default.removeItem(at: executable)
        var buffer = [CChar](repeating: 0, count: 4096)
        #expect(proc_pidpath(process.processIdentifier, &buffer, UInt32(buffer.count)) == 0)
        let recovered = try #require(ProcessExecutablePath.read(pid: process.processIdentifier, expected: identity))
        #expect(recovered == executable.path)
        #expect(original.hasSuffix("/" + directory.lastPathComponent + "/BackgroundService"))
    }
}

private final class IdentityReads: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}

private final class ProcessPathHelper: NSObject, MASHelperProtocol, @unchecked Sendable {
    let version: String?
    let path: String?
    private let lock = NSLock()
    private var recorded: [(Int32, Int64, Int32)] = []
    var requests: [(Int32, Int64, Int32)] { lock.withLock { recorded } }
    init(version: String? = "148 protocol/4", path: String?) {
        self.version = version; self.path = path
    }
    func helperVersion(withReply reply: @escaping (String) -> Void) {
        if let version { reply(version) }
    }
    func processExecutablePath(pid: Int32, startedSeconds: Int64, startedMicroseconds: Int32,
                               withReply reply: @escaping (String?) -> Void) {
        lock.withLock { recorded.append((pid, startedSeconds, startedMicroseconds)) }
        reply(path)
    }
    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) { reply(-1, "Fixture") }
    func stagedSparkleBundleVersions(bundleID: String,
                                     withReply reply: @escaping (String?, String?, String?) -> Void) {
        reply(nil, nil, nil)
    }
}
