import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticInstallTests {
    @Test func unattendedRoutesExcludeInstallersAndExternalManagers() {
        for route in InstallCoordinator.Route.allCases {
            #expect(AutomaticInstall.supports(route) == (route == .vendor || route == .sparkle))
        }
    }

    @Test func helpersAndUnlinkedProcessesBlockButSiblingCopiesDoNot() {
        let bundle = URL(fileURLWithPath: "/Applications/Test.app")
        func process(_ path: String?, launched: String? = nil) -> NestedAppGuard.RunningProcess {
            .init(pid: 1, parentPID: 0, executablePath: path, launchedPath: launched, isRegularApp: false)
        }
        #expect(AutomaticInstall.hasRunningProcess(at: bundle, processes: [process("/Applications/Test.app/Contents/Library/LoginItems/Agent")]))
        #expect(AutomaticInstall.hasRunningProcess(at: bundle, processes: [process(nil, launched: "/Applications/Test.app/Contents/MacOS/Test")]))
        #expect(!AutomaticInstall.hasRunningProcess(at: bundle, processes: [process("/Applications/Test.app other/Contents/MacOS/Test")]))
    }

    @Test func onlyACompleteBackupPermitsAutomaticInstallation() {
        #expect(AutomaticInstall.backupPermitsInstall(.saved))
        let outcomes: [InstallCoordinator.BackupOutcome] = [.failed, .cancelled, .insufficientSpace,
            .unreadable(path: "/test"), .savedWithoutRuntimeState(omitted: 1), .skippedForEarlierInstall(.interrupted)]
        for outcome in outcomes {
            #expect(!AutomaticInstall.backupPermitsInstall(outcome))
        }
    }

    @Test func disablingAutomaticUpdatesBeforeCommitLeavesTheBundleUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Target.app")
        let incoming = root.appendingPathComponent("Incoming.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("original")
        try Data("old".utf8).write(to: marker)
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ false }) {
                await #expect(throws: AutomaticInstall.Deferred.self) {
                    try await InPlaceSwap.replace(newApp: incoming, over: target)
                }
            }
        }
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
        #expect(FileManager.default.fileExists(atPath: incoming.path))
    }

    @Test func unattendedPermissionFailsClosed() async {
        await AutomaticInstall.$active.withValue(true) {
            await #expect(throws: AutomaticInstall.Deferred.self) {
                try await AutomaticInstall.checkPermission()
            }
            await AutomaticInstall.$permission.withValue({ false }) {
                await #expect(throws: AutomaticInstall.Deferred.self) {
                    try await AutomaticInstall.checkPermission()
                }
            }
        }
    }

    @Test func permissionWithdrawnAfterEntryBlocksTheWholeBundleExchange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Target.app")
        let incoming = root.appendingPathComponent("Incoming.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("original")
        try Data("old".utf8).write(to: marker)
        let permission = AutomaticInstall.PermissionSnapshot()
        permission.set(true)
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$commitPermission.withValue({ permission.allowed }) {
                    await InPlaceSwap.$preExchangeCheck.withValue({
                        // Entry's process guard passes, then policy changes before Dispatch.
                        permission.set(false)
                    }) {
                        await #expect(throws: AutomaticInstall.Deferred.self) {
                            try await InPlaceSwap.replace(newApp: incoming, over: target)
                        }
                    }
                }
            }
        }
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
    }

    @Test func rotationChecksProcessesAfterStagingAndBeforeExchangingContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Target.app")
        let incoming = root.appendingPathComponent("Incoming.app")
        for app in [target, incoming] {
            try FileManager.default.createDirectory(
                at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        }
        let marker = target.appendingPathComponent("Contents/original")
        try Data("old".utf8).write(to: marker)
        let helper = target.appendingPathComponent("Contents/helper")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: helper)
        let signed = try await ChildProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", helper.path],
                                                standardOutput: .discard, standardError: .discard,
                                                onCancel: .runToCompletion)
        try #require(signed.succeeded)
        let app = InstalledApp(name: "Test", bundleID: nil, shortVersion: nil,
                               buildVersion: nil, path: target, isMASApp: false, sparkleFeedURL: nil)
        #expect(!AutomaticInstall.hasRunningProcess(at: target, processes: NestedAppGuard.liveProcesses()))
        await InPlaceSwap.$preExchangeCheck.withValue({
            // Source moved: this guard must run after staging, not at replace entry.
            #expect(!FileManager.default.fileExists(
                atPath: incoming.appendingPathComponent("Contents").path))
            let process = Process()
            process.executableURL = helper
            process.arguments = ["30"]
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            try process.run()
            // The exchange-side callback runs on Dispatch, not the cooperative pool.
            defer { process.terminate(); exited.wait() }
            // Process.run can return before exec has made the helper path visible.
            var observed = false
            for _ in 0..<100 {
                observed = AutomaticInstall.hasRunningProcess(at: target, processes: NestedAppGuard.liveProcesses())
                if observed { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            try #require(observed, "The real helper must be visible before testing its guard")
            try AutomaticInstall.checkProcesses(at: app.path,
                processes: NestedAppGuard.liveProcesses().filter { $0.pid == process.processIdentifier })
        }) {
            await #expect(throws: AutomaticInstall.Deferred.self) {
                try await InPlaceSwap.rotateContents(newApp: incoming, over: target)
            }
        }
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
    }

    @Test func aVisibleProcessDoesNotMakeAnUninspectablePIDSafe() throws {
        let bundle = URL(fileURLWithPath: "/Applications/Test.app")
        let visible = NestedAppGuard.RunningProcess(
            pid: 1, parentPID: 0, executablePath: "/usr/bin/visible", isRegularApp: false)
        let unknown = NestedAppGuard.RunningProcess(
            pid: 2, parentPID: 0, executablePath: nil, isRegularApp: false)
        #expect(throws: AutomaticInstall.Deferred.self) {
            try AutomaticInstall.checkProcesses(at: bundle, processes: [visible, unknown])
        }
        #expect(throws: AutomaticInstall.Deferred.self) {
            try AutomaticInstall.checkProcesses(at: bundle, processes: [])
        }
        try AutomaticInstall.checkProcesses(at: bundle, processes: [visible])
        let unlinked = NestedAppGuard.RunningProcess(
            pid: 3, parentPID: 0, executablePath: nil,
            launchedPath: "/Applications/Test.app/Contents/MacOS/Test", isRegularApp: false)
        #expect(throws: AutomaticInstall.Deferred.self) {
            try AutomaticInstall.checkProcesses(at: bundle, processes: [visible, unlinked])
        }
    }

}
