import Foundation
import Testing
@testable import DuoUpdaterCore

struct RunningAppQuitBeforeApplyTests {
    let bundle = URL(fileURLWithPath: "/Applications/Test.app")

    @Test func withdrawnPermissionDoesNotReachTheNormalQuit() async {
        let quits = Counter()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ false }) {
                await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                    await #expect(throws: AutomaticInstall.Deferred.self) {
                        try await AutomaticInstall.quitPlannedApp(before: FileManager.default.temporaryDirectory)
                    }
                }
            }
        }
        #expect(quits.value == 0)
        #expect(plan.pending)
    }

    func process(_ pid: pid_t, parent: pid_t, _ path: String) -> NestedAppGuard.RunningProcess {
        .init(pid: pid, parentPID: parent, executablePath: path, isRegularApp: false)
    }

    @Test func helpersStartedByTheAppQuitWithIt() {
        let processes = [
            process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test"),
            process(101, parent: 100, "/Applications/Test.app/Contents/Frameworks/Test Helper.app/Contents/MacOS/Test Helper"),
            process(102, parent: 101, "/Applications/Test.app/Contents/Frameworks/Test Helper.app/Contents/MacOS/Test Helper"),
            // launchd starts XPC services and ends them with their client.
            process(103, parent: 1, "/Applications/Test.app/Contents/XPCServices/Fetch.xpc/Contents/MacOS/Fetch"),
            // Chromium's crash handler is reparented to launchd and ends with the app.
            process(105, parent: 1, "/Applications/Test.app/Contents/Frameworks/Test Framework.framework/Helpers/chrome_crashpad_handler"),
            // Not in the bundle at all.
            process(104, parent: 1, "/Applications/Other.app/Contents/MacOS/Other"),
        ]
        #expect(RunningAppAutoUpdate.independentHelper(of: bundle, processes: processes, instancePIDs: [100]) == nil)
    }

    @Test func anExtensionTheSystemRunsKeepsTheQuitBack() {
        let widget = process(300, parent: 1, "/Applications/Test.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget")
        let processes = [process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test"), widget]
        #expect(RunningAppAutoUpdate.independentHelper(of: bundle, processes: processes, instancePIDs: [100]) == widget)
    }

    @Test func aLoginItemTheAppDidNotStartKeepsTheQuitBack() {
        let agent = process(200, parent: 1, "/Applications/Test.app/Contents/Library/LoginItems/Agent.app/Contents/MacOS/Agent")
        let processes = [process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test"), agent]
        #expect(RunningAppAutoUpdate.independentHelper(of: bundle, processes: processes, instancePIDs: [100]) == agent)
        // The same agent started by the app quits with it.
        let child = process(200, parent: 100, agent.executablePath!)
        #expect(RunningAppAutoUpdate.independentHelper(
            of: bundle, processes: [processes[0], child], instancePIDs: [100]) == nil)
    }

    @Test func anIndependentRootServiceKeepsTheMainAppFromBeingQuitForNothing() {
        let app = process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test")
        let service = NestedAppGuard.RunningProcess(pid: 200, parentPID: 1,
            executablePath: nil, launchedPath: "/Applications/Test.app/Contents/MacOS/service",
            isRegularApp: false, userID: 0)
        #expect(RunningAppAutoUpdate.independentHelper(
            of: bundle, processes: [app, service], instancePIDs: [100]) == service)
        #expect(RunningAppAutoUpdate.independentHelper(
            of: URL(fileURLWithPath: "/Applications/Other.app"), processes: [app, service], instancePIDs: [300]) == nil)
    }

    @Test func aRunningAppPassesTheEarlyChecksOnlyUntilItsQuitRan() async throws {
        let running = [process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test")]
        let quits = Counter()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        try await AutomaticInstall.$active.withValue(true) {
            try await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                // Before the swap: the app is expected to be running.
                try AutomaticInstall.checkProcesses(at: bundle, processes: running)
                try await plan.run()
                // A patch retried with the full archive does not quit twice.
                try await plan.run()
                // After the quit every check is back: an app still up is refused.
                #expect(throws: AutomaticInstall.Deferred.self) {
                    try AutomaticInstall.checkProcesses(at: bundle, processes: running)
                }
            }
        }
        #expect(quits.value == 1)
    }

    @Test func aQuitThatThrowsStillRestoresEveryCheck() async {
        let running = [process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test")]
        let plan = AutomaticInstall.QuitBeforeApply { throw AutomaticInstall.Deferred("stays up") }
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                await #expect(throws: AutomaticInstall.Deferred.self) { try await plan.run() }
                #expect(!AutomaticInstall.appQuitsBeforeApply)
                #expect(throws: AutomaticInstall.Deferred.self) {
                    try AutomaticInstall.checkProcesses(at: bundle, processes: running)
                }
            }
        }
    }

    @Test func manualInstallsIgnoreAPlan() throws {
        let running = [process(100, parent: 1, "/Applications/Test.app/Contents/MacOS/Test")]
        let plan = AutomaticInstall.QuitBeforeApply {}
        AutomaticInstall.$quitBeforeApply.withValue(plan) {
            #expect(!AutomaticInstall.appQuitsBeforeApply)
        }
        // Without a plan a running app is refused, as before.
        AutomaticInstall.$active.withValue(true) {
            #expect(throws: AutomaticInstall.Deferred.self) {
                try AutomaticInstall.checkProcesses(at: bundle, processes: running)
            }
        }
    }

    /// The app is closed for the swap alone: quit after the download and the
    /// verification, right before the swap. Mutation: make `quitPlannedApp`
    /// skip the quit → red.
    @Test func theQuitComesAfterTheDownloadAndRightBeforeTheExchange() async throws {
        let (result, workDir) = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let order = Log()
        let plan = AutomaticInstall.QuitBeforeApply { order.append("quit") }
        // `fetchThenSwap` scans every process on the host, and an automatic
        // install defers when one cannot be inspected. Scope the scan to this
        // process so another test's child (or the CI host's) cannot defer it.
        let onlyThisProcess: @Sendable (UnsafeMutableRawPointer?, Int32) -> Int32 = { buffer, _ in
            buffer?.assumingMemoryBound(to: pid_t.self).pointee = getpid()
            return 1
        }
        _ = try await NestedAppGuard.$listPIDs.withValue(onlyThisProcess) {
        try await AutomaticInstall.$active.withValue(true) {
            try await AutomaticInstall.$permission.withValue({ true }) {
                try await AutomaticInstall.$commitPermission.withValue({ true }) {
                try await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                    try await InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1)).fetchThenSwap(
                        result, spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
                        download: { _, _ in
                            order.append("download")
                            return DownloadedUpdate(archiveURL: workDir.appendingPathComponent("ZZFixture.zip"),
                                                    bytesDownloaded: 1, workDir: workDir)
                        },
                        apply: { _, _, _ in
                            order.append("verify")
                            let (target, incoming) = try Self.bundles(in: workDir)
                            try await AutomaticInstall.quitPlannedApp(before: target)
                            // The check right before the exchange runs on a
                            // Dispatch queue, which the `listPIDs` override does
                            // not reach: scope it to this process the same way.
                            let scoped: @Sendable () throws -> Void = {
                                try AutomaticInstall.checkProcesses(at: target, processes:
                                    NestedAppGuard.liveProcesses(includeUninspectable: true)
                                        .filter { $0.pid == getpid() })
                            }
                            try await InPlaceSwap.$preExchangeCheck.withValue(scoped) {
                                try await InPlaceSwap.replace(newApp: incoming, over: target)
                            }
                            order.append("exchanged")
                        })
                }
                }
            }
        }
        }
        #expect(order.value == ["download", "verify", "quit", "exchanged"])
    }

    /// An app that stays up (the person came back, a save prompt) leaves the
    /// installed bundle as it was.
    @Test func aQuitThatDefersLeavesTheBundleUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (target, incoming) = try Self.bundles(in: root)
        let plan = AutomaticInstall.QuitBeforeApply { throw AutomaticInstall.Deferred("stays up") }
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                    await #expect(throws: AutomaticInstall.Deferred.self) {
                        try await AutomaticInstall.quitPlannedApp(before: target)
                        try await InPlaceSwap.replace(newApp: incoming, over: target)
                    }
                }
            }
        }
        #expect(try Data(contentsOf: target.appendingPathComponent("original")) == Data("old".utf8))
        #expect(FileManager.default.fileExists(atPath: incoming.path))
    }

    /// A planned quit that never ran refuses the exchange instead of swapping
    /// a running app. Mutation: drop the guard in `InPlaceSwap.replace` → red.
    @Test func anExchangeReachedWithoutThePlannedQuitIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (target, incoming) = try Self.bundles(in: root)
        let plan = AutomaticInstall.QuitBeforeApply {}
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$commitPermission.withValue({ true }) {
                    await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                        await #expect(throws: AutomaticInstall.Deferred.self) {
                            try await InPlaceSwap.replace(newApp: incoming, over: target)
                        }
                    }
                }
            }
        }
        #expect(try Data(contentsOf: target.appendingPathComponent("original")) == Data("old".utf8))
    }

    static func bundles(in root: URL) throws -> (target: URL, incoming: URL) {
        let target = root.appendingPathComponent("Target.app")
        let incoming = root.appendingPathComponent("Incoming.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("original"))
        return (target, incoming)
    }

    static func fixture() throws -> (UpdateResult, URL) {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-quit-before-apply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try Data("zz".utf8).write(to: workDir.appendingPathComponent("ZZFixture.zip"))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-\(UUID().uuidString).app")
        let result = UpdateResult(
            app: InstalledApp(
                name: "ZZFixture", bundleID: "com.example.zzfixture",
                shortVersion: "1.0", buildVersion: "1", path: path,
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: RemoteVersion(shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Sparkle"),
            status: .updateAvailable(latest: "1.1"))
        return (result, workDir)
    }

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { lock.withLock { entries.append(entry) } }
        var value: [String] { lock.withLock { entries } }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}
