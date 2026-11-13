import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticInstallTests {
    private final class CheckCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }

    @Test func policyRefusalsDeferOnlyAutomaticWorkAndNeverRetryDownloads() {
        let gate = OneClickGateRegistry.Withheld(appName: "Test", reason: "Copy changed")
        let nested = NestedAppRunningError(appName: "Test", blockers: [])
        #expect(AutomaticInstall.classifiedRefusal(gate) is OneClickGateRegistry.Withheld)
        #expect(AutomaticInstall.classifiedRefusal(nested) is NestedAppRunningError)
        AutomaticInstall.$active.withValue(true) {
            for error: Error in [gate, nested] {
                let mapped = AutomaticInstall.classifiedRefusal(error)
                #expect((mapped as? AutomaticInstall.Deferred)?.reason == error.localizedDescription)
                #expect(!deltaRouteFailureIsWorthRetrying(mapped))
                #expect(!localStashFailureIsWorthRetrying(mapped))
            }
            #expect(AutomaticInstall.classifiedRefusal(CocoaError(.fileReadNoPermission)) is CocoaError)
            #expect(AutomaticInstall.classifiedRefusal(SignatureVerifier.VerifyError.edSignatureInvalid)
                is SignatureVerifier.VerifyError)
        }
    }

    @Test func safetyDeferralIsNeitherFailureNorSuccessfulInstall() {
        let outcome = InstallAttemptOutcome.deferred(reason: "Helper started before exchange")
        #expect(outcome != .notInstalled)
        #expect(!outcome.countsAsUpdatedApp)
        let event = AutomaticInstall.eventResult(outcome)
        #expect(event.status == "deferred")
        #expect(event.reason == "Helper started before exchange")
        #expect(AutomaticInstall.eventResult(.notInstalled).status == "notInstalled")
        #expect(AutomaticInstall.eventResult(.installed).status == "installed")
    }

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

    @Test func onlyTheMainExecutableBlocksAutomaticUpdates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Main"], format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        func process(_ relative: String, unlinked: Bool = false) -> NestedAppGuard.RunningProcess {
            let path = bundle.appendingPathComponent(relative).path
            return .init(pid: 10, parentPID: 1, executablePath: unlinked ? nil : path,
                launchedPath: unlinked ? path : nil, isRegularApp: false)
        }
        for path in ["Contents/PlugIns/Quota.appex/Contents/MacOS/Quota",
                     "Contents/Library/LoginItems/Agent.app/Contents/MacOS/Agent",
                     "Contents/MacOS/worker", "Contents/Frameworks/Helper"] {
            let helper = process(path)
            #expect(!AutomaticInstall.hasRunningMainProcess(at: bundle, processes: [helper]))
            try AutomaticInstall.checkProcesses(at: bundle, processes: [helper])
        }
        for unlinked in [false, true] {
            let main = process("Contents/MacOS/Main", unlinked: unlinked)
            #expect(AutomaticInstall.hasRunningMainProcess(at: bundle, processes: [main]))
            #expect(throws: AutomaticInstall.Deferred.self) {
                try AutomaticInstall.checkProcesses(at: bundle, processes: [main], allowRunningApp: false)
            }
        }
        let vm = process("Contents/Helpers/VMPalMachine.app/Contents/MacOS/VMPalMachine")
        #expect(!NestedAppGuard.blockers(bundlePath: bundle.path, processes: [vm]).isEmpty)
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

    @Test(arguments: [false, true])
    func permissionWithdrawnDuringFinalProcessCheckPreservesOriginal(rotation: Bool) async throws {
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
        try Data("new".utf8).write(to: incoming.appendingPathComponent("Contents/original"))
        let permission = AutomaticInstall.PermissionSnapshot()
        permission.set(true)
        let checks = CheckCounter()
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$commitPermission.withValue({ permission.allowed }) {
                    await InPlaceSwap.$preExchangeCheck.withValue({
                        // Rotation has no entry check; replace's first check must pass.
                        if checks.next() == (rotation ? 1 : 2) { permission.set(false) }
                    }) {
                        await #expect(throws: AutomaticInstall.Deferred.self) {
                            if rotation {
                                _ = try await InPlaceSwap.rotateContents(newApp: incoming, over: target)
                            } else {
                                _ = try await InPlaceSwap.replace(newApp: incoming, over: target)
                            }
                        }
                    }
                }
            }
        }
        #expect(!permission.allowed)
        #expect(checks.next() == (rotation ? 2 : 3))
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
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let helper = target.appendingPathComponent("Contents/MacOS/Target")
        let signingCopy = root.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: signingCopy)
        let signed = try await ChildProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", signingCopy.path],
                                                standardOutput: .discard, standardError: .discard,
                                                onCancel: .runToCompletion)
        try #require(signed.succeeded)
        try FileManager.default.moveItem(at: signingCopy, to: helper)
        let app = InstalledApp(name: "Test", bundleID: nil, shortVersion: nil,
                               buildVersion: nil, path: target, isMASApp: false, sparkleFeedURL: nil)
        #expect(!AutomaticInstall.hasRunningProcess(at: target, processes: NestedAppGuard.liveProcesses()))
        let (launches, launch) = AsyncStream<Void>.makeStream()
        let helperTask = Task {
            for await _ in launches {
                return try await ChildProcess.run(helper.path, ["60"],
                    standardOutput: .discard, standardError: .discard,
                    onCancel: .terminateChild)
            }
            throw CancellationError()
        }
        await InPlaceSwap.$preExchangeCheck.withValue({
            // Source moved: this guard must run after staging, not at replace entry.
            #expect(!FileManager.default.fileExists(
                atPath: incoming.appendingPathComponent("Contents").path))
            // Launch only now, after staging. The async runner owns child cleanup;
            // this synchronous exchange guard is on Dispatch.
            launch.yield(())
            launch.finish()
            var observed: [NestedAppGuard.RunningProcess] = []
            for _ in 0..<100 {
                observed = NestedAppGuard.liveProcesses().filter {
                    AutomaticInstall.hasRunningProcess(at: target, processes: [$0])
                }
                if !observed.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            try #require(!observed.isEmpty, "The real helper must be visible before testing its guard")
            try AutomaticInstall.checkProcesses(at: app.path, processes: observed)
        }) {
            await #expect(throws: AutomaticInstall.Deferred.self) {
                try await InPlaceSwap.rotateContents(newApp: incoming, over: target)
            }
        }
        launch.finish()
        helperTask.cancel()
        _ = await helperTask.result
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
    }

    @Test func unidentifiedBackgroundProcessesDoNotBlockButAnEmptySnapshotDoes() throws {
        let bundle = URL(fileURLWithPath: "/Applications/Test.app")
        let visible = NestedAppGuard.RunningProcess(
            pid: 1, parentPID: 0, executablePath: "/usr/bin/visible", isRegularApp: false)
        let unknown = NestedAppGuard.RunningProcess(
            pid: 2, parentPID: 0, executablePath: nil, isRegularApp: false)
        try AutomaticInstall.checkProcesses(at: bundle, processes: [visible, unknown])
        let truncated = NestedAppGuard.RunningProcess(
            pid: 0, parentPID: 0, executablePath: nil, isRegularApp: false)
        #expect(throws: AutomaticInstall.Deferred.self) {
            try AutomaticInstall.checkProcesses(at: bundle, processes: [visible, truncated])
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
