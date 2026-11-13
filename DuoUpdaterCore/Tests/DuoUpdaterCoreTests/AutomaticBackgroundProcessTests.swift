import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticBackgroundProcessTests {
    // The kernel cannot inspect this PID; the injected privileged reader models
    // its successful read of a root service that ordinary inspection cannot name.
    private static let pid: Int32 = .max - 1
    private static let service = "/Applications/RustDesk.app/Contents/MacOS/service"
    private static let list: @Sendable (UnsafeMutableRawPointer?, Int32) -> Int32 = { buffer, _ in
        buffer?.storeBytes(of: pid, as: Int32.self)
        buffer?.storeBytes(of: getpid(), toByteOffset: MemoryLayout<Int32>.size, as: Int32.self)
        return 2
    }

    @Test func identifiedHelperDoesNotCountAsRunningMainApp() throws {
        try NestedAppGuard.$listPIDs.withValue(Self.list) {
            try NestedAppGuard.$privilegedExecutablePath.withValue({ _ in Self.service }) {
                var diagnostics: [AutomaticProcessDiagnostic] = []
                let processes = NestedAppGuard.liveProcesses(includeUninspectable: true) { diagnostics.append($0) }
                #expect(processes.count == 2)
                #expect(processes.first(where: { $0.pid == Self.pid })?.launchedPath == Self.service)
                #expect(diagnostics.contains { $0.probes.contains(.init(.privilegedPath, 1, 0)) })
                try AutomaticInstall.checkProcesses(at: URL(fileURLWithPath: "/Applications/Amp.app"), processes: processes)
                try AutomaticInstall.checkProcesses(at: URL(fileURLWithPath: "/Applications/RustDesk.app"), processes: processes)
                #expect(AutomaticInstall.backgroundProcessReason(processes.filter { $0.pid == Self.pid }) ==
                    "Background processes are still running (service). Automatic updating is paused for this app.")
            }
        }
    }

    @Test func manualEnumerationNeverAsksForPrivilege() {
        NestedAppGuard.$listPIDs.withValue(Self.list) {
            NestedAppGuard.$privilegedExecutablePath.withValue({ _ in
                Issue.record("Manual enumeration must retain its existing policy")
                return Self.service
            }) {
                #expect(NestedAppGuard.liveProcesses().map(\.pid) == [getpid()])
            }
        }
    }

    @Test func failedOrMalformedPrivilegedReadsDoNotBlockUnrelatedApps() throws {
        for path in [nil, "service", "/bad\0path"] as [String?] {
            try NestedAppGuard.$listPIDs.withValue(Self.list) {
                try NestedAppGuard.$lifecycleInfo.withValue({ pid, buffer, _ in
                    var info = proc_bsdshortinfo()
                    info.pbsi_pid = UInt32(pid)
                    info.pbsi_status = UInt32(SRUN)
                    return withUnsafeBytes(of: &info) {
                        buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
                        return Int32($0.count)
                    }
                }) {
                    try NestedAppGuard.$privilegedExecutablePath.withValue({ _ in path }) {
                        let processes = NestedAppGuard.liveProcesses(includeUninspectable: true)
                        #expect(processes.count == 2)
                        #expect(processes.contains { $0.pid == Self.pid && $0.executablePath == nil && $0.launchedPath == nil })
                        try AutomaticInstall.checkProcesses(at: URL(fileURLWithPath: "/Applications/Amp.app"), processes: processes)
                    }
                }
            }
        }
    }

    @Test func exchangeCheckCarriesTheReaderAcrossDispatchAndReadsFreshEachTime() async throws {
        let state = ServicePath()
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Fixture.app")
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "FixtureMain"], format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let app = InstalledApp(name: "Amp", bundleID: "test.automatic.background",
            shortVersion: "1", buildVersion: nil, path: bundle,
            isMASApp: false, sparkleFeedURL: nil)
        let check = AutomaticInstall.$active.withValue(true) {
            NestedAppGuard.$privilegedExecutablePath.withValue({ _ in state.path }) {
                AutomaticInstall.processCheck(app)
            }
        }
        try await offCooperativePool {
            try NestedAppGuard.$listPIDs.withValue(Self.list) { try check() }
        }
        state.path = bundle.appendingPathComponent("Contents/MacOS/FixtureMain").path
        await #expect(throws: AutomaticInstall.Deferred.self) {
            try await offCooperativePool {
                try NestedAppGuard.$listPIDs.withValue(Self.list) { try check() }
            }
        }
    }

    private final class ServicePath: @unchecked Sendable {
        private let lock = NSLock()
        private var value = AutomaticBackgroundProcessTests.service
        var path: String {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }
}
