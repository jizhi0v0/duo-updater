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
        await InPlaceSwap.$preExchangeCheck.withValue({
            // Source moved: this guard must run after staging, not at replace entry.
            #expect(!FileManager.default.fileExists(
                atPath: incoming.appendingPathComponent("Contents").path))
            throw AutomaticInstall.Deferred("A helper started while staging.")
        }) {
            await #expect(throws: AutomaticInstall.Deferred.self) {
                try await InPlaceSwap.rotateContents(newApp: incoming, over: target)
            }
        }
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
    }

}
