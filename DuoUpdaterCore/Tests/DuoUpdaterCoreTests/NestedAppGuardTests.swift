import Foundation
import Testing
@testable import DuoUpdaterCore

/// `NestedAppGuard`: which processes running from inside a bundle block
/// replacing it, and that `InstallCoordinator` asks before the download and
/// again before the apply. Every process here is invented; the paths are under
/// `/Applications/ZZFixture*.app`, which nothing reads.
@Suite struct NestedAppGuardTests {

    private static let bundle = "/Applications/ZZFixtureVM.app"
    private static let mainPID: pid_t = 500

    private static func process(
        _ pid: pid_t, _ relative: String, parent: pid_t = 1, regular: Bool = false,
        bundle: String = bundle
    ) -> NestedAppGuard.RunningProcess {
        .init(pid: pid, parentPID: parent, executablePath: "\(bundle)/\(relative)", isRegularApp: regular)
    }

    private static let main = process(mainPID, "Contents/MacOS/ZZFixtureVM", regular: true)

    // MARK: - What counts

    /// The VMPal shape: a nested app in `Contents/Helpers`, started by launchd,
    /// `.accessory` at runtime. Mutation: return `[]` from `blockers` → red.
    @Test func anAccessoryHelperAppStartedOnItsOwnBlocks() {
        let machine = Self.process(
            700, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [Self.main, machine])
            == [.init(name: "ZZFixtureMachine", pid: 700)])
        // It blocks whether or not the main app is running: that is the state
        // VMPal is in after its main app has been quit.
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [machine])
            == [.init(name: "ZZFixtureMachine", pid: 700)])
    }

    @Test func theMainAppItselfNeverBlocks() {
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [Self.main]).isEmpty)
    }

    /// Chromium helpers, Sparkle's `Updater.app`, crashpad handlers: anything
    /// under `Contents/Frameworks` belongs to the app's machinery. Mutation: drop
    /// the `Contents/Frameworks/` check → red.
    @Test func helpersUnderFrameworksNeverBlock() {
        let renderer = Self.process(
            701, "Contents/Frameworks/ZZFixture Helper (Renderer).app/Contents/MacOS/ZZFixture Helper (Renderer)")
        let updater = Self.process(
            702, "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [renderer, updater]).isEmpty)
    }

    /// An `.app` inside a framework, XPC service or extension that is NOT under
    /// `Contents/Frameworks` (Xcode keeps `Python.app` in a framework under
    /// `Contents/Developer`). Mutation: drop the `.framework`/`.xpc`/`.appex`
    /// check → red.
    @Test func anAppInsideAFrameworkXPCOrExtensionNeverBlocks() {
        let python = Self.process(
            703, "Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python")
        let xpc = Self.process(
            704, "Contents/XPCServices/ZZFixture.xpc/Contents/Resources/Inner.app/Contents/MacOS/Inner")
        let appex = Self.process(
            705, "Contents/PlugIns/ZZFixture.appex/Contents/Resources/Inner.app/Contents/MacOS/Inner")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [python, xpc, appex]).isEmpty)
    }

    /// The AppCleaner SmartDelete shape: a login item runs for the whole login
    /// session, so it must not block its app for good. Mutation: drop the
    /// `Contents/Library/LoginItems/` check → red.
    @Test func aLoginItemNeverBlocks() {
        let agent = Self.process(
            713, "Contents/Library/LoginItems/ZZFixture SmartDelete.app/Contents/MacOS/ZZFixture SmartDelete")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [agent]).isEmpty)
    }

    /// A bare executable that is not part of any nested `.app` (an XPC service,
    /// a command-line helper) is out of scope.
    @Test func codeOutsideANestedAppNeverBlocks() {
        let xpc = Self.process(706, "Contents/XPCServices/ZZFixture.xpc/Contents/MacOS/ZZFixture")
        let tool = Self.process(707, "Contents/Helpers/zzfixture-daemon")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [xpc, tool]).isEmpty)
    }

    /// A helper the main app spawned goes away with it. Mutation: drop the
    /// parent check → red.
    @Test func aHelperTheAppItselfStartedNeverBlocks() {
        let child = Self.process(
            708, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine",
            parent: Self.mainPID)
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [Self.main, child]).isEmpty)
    }

    /// The Surge Dashboard shape: a `.regular` nested app, which `AppRestarter`
    /// already quits and reopens with the main app. Mutation: drop the
    /// `isRegularApp` check → red.
    @Test func aRegularNestedAppIsLeftToTheRestart() {
        let dashboard = Self.process(
            709, "Contents/Applications/ZZFixture Dashboard.app/Contents/MacOS/ZZFixture Dashboard",
            regular: true)
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [dashboard]).isEmpty)
    }

    /// Containment is by path component: `ZZFixtureVM.app.old` is a different
    /// bundle, and a trailing slash on the bundle path changes nothing.
    @Test func containmentIsByPathComponent() {
        let sibling = Self.process(
            710, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine",
            bundle: Self.bundle + ".old")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [sibling]).isEmpty)
        let machine = Self.process(
            711, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle + "/", processes: [machine]).count == 1)
    }

    @Test func blockersComeBackInPIDOrder() {
        let b = Self.process(720, "Contents/Helpers/B.app/Contents/MacOS/B")
        let a = Self.process(712, "Contents/Helpers/A.app/Contents/MacOS/A")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [b, a]).map(\.pid) == [712, 720])
    }

    // MARK: - The message

    @Test func theMessageNamesTheNestedAppsOnce() {
        let one = NestedAppRunningError(
            appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 1)])
        #expect(one.errorDescription == "ZZFixtureMachine is running from inside ZZFixtureVM and would keep running the old version. Quit it, then update again. Nothing was changed.")
        let two = NestedAppRunningError(
            appName: "ZZFixtureVM",
            blockers: [.init(name: "B", pid: 1), .init(name: "A", pid: 2), .init(name: "B", pid: 3)])
        #expect(two.errorDescription == "A, B are running from inside ZZFixtureVM and would keep running the old version. Quit them, then update again. Nothing was changed.")
    }

    // MARK: - InstallCoordinator asks twice

    private struct ZZApplied: Error {}

    /// Refused before any byte moves. Mutation: drop the first
    /// `refuseWhileNestedAppRuns` in `fetchThenSwap` → the download runs.
    @Test func theCoordinatorRefusesBeforeTheDownload() async throws {
        let downloads = Counter()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: { [Self.blockingMachine()] })
        await #expect(throws: NestedAppRunningError.self) {
            _ = try await coordinator.fetchThenSwap(
                Self.result(), progress: { _ in }, releaseAfterDownload: {},
                download: { _, _ in
                    downloads.bump()
                    throw ZZApplied()
                },
                apply: { _, _, _ in throw ZZApplied() })
        }
        #expect(downloads.value == 0)
    }

    /// Started while the download ran: refused before the apply, and the
    /// scratch directory still goes. Mutation: drop the second
    /// `refuseWhileNestedAppRuns` (in `swap`) → the apply runs.
    @Test func theCoordinatorRefusesBeforeTheApplyWhenTheNestedAppStartsMidDownload() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let started = Flag()
        let applies = Counter()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: { started.value ? [Self.blockingMachine()] : [] })
        await #expect(throws: NestedAppRunningError.self) {
            _ = try await coordinator.fetchThenSwap(
                Self.result(), progress: { _ in }, releaseAfterDownload: {},
                download: { _, _ in
                    started.set()
                    return DownloadedUpdate(
                        archiveURL: workDir.appendingPathComponent("ZZFixture.zip"),
                        bytesDownloaded: 1, workDir: workDir)
                },
                apply: { _, _, _ in applies.bump() })
        }
        #expect(applies.value == 0)
        #expect(!FileManager.default.fileExists(atPath: workDir.path))
    }

    @Test func theCoordinatorGoesAheadWhenNothingBlocks() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let applies = Counter()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1), runningProcesses: { [] })
        _ = try await coordinator.fetchThenSwap(
            Self.result(), progress: { _ in }, releaseAfterDownload: {},
            download: { _, _ in
                DownloadedUpdate(
                    archiveURL: workDir.appendingPathComponent("ZZFixture.zip"),
                    bytesDownloaded: 1, workDir: workDir)
            },
            apply: { _, _, _ in applies.bump() })
        #expect(applies.value == 1)
    }

    // MARK: - The live list

    /// The one test that reads the real process table: this test process is in
    /// it, with its own executable path and parent.
    @Test func theLiveListIncludesThisProcess() {
        let me = NestedAppGuard.liveProcesses().first { $0.pid == getpid() }
        #expect(me != nil)
        #expect(me?.parentPID == getppid())
        #expect(me?.executablePath.isEmpty == false)
    }

    // MARK: - Fixtures

    private static func blockingMachine() -> NestedAppGuard.RunningProcess {
        process(700, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine")
    }

    private static func result() -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "ZZFixtureVM", bundleID: "com.example.zzfixturevm",
                shortVersion: "1.0", buildVersion: "1", path: URL(fileURLWithPath: bundle),
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Vendor"),
            status: .updateAvailable(latest: "1.1"))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}
