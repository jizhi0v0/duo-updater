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
        bundle: String = bundle, arguments: [String]? = nil
    ) -> NestedAppGuard.RunningProcess {
        .init(pid: pid, parentPID: parent, executablePath: "\(bundle)/\(relative)", isRegularApp: regular,
              arguments: arguments)
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

    /// The Backdrop shape: two LaunchAgents plists with the same
    /// `BundleProgram`, `--wallpaper-agent` and `--wallpaper-renderer`, each
    /// started by launchd. The app's next launch re-registers them, so neither
    /// blocks. A nested app that is not an agent still does. `argv[0]` is not
    /// compared. Mutation: drop the `launchAgents` check → red.
    @Test func aLaunchAgentInstanceNeverBlocks() {
        let program = "Contents/Resources/ZZFixtureWallpaper.app/Contents/MacOS/ZZFixtureWallpaper"
        let agent = Self.process(
            714, program, arguments: ["\(Self.bundle)/\(program)", "--wallpaper-agent"])
        let renderer = Self.process(715, program, arguments: ["ZZFixtureWallpaper", "--wallpaper-renderer"])
        let machine = Self.process(
            716, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine")
        let agents: [NestedAppGuard.LaunchAgent] = [
            .init(program: "\(Self.bundle)/\(program)", arguments: ["ZZFixtureWallpaper", "--wallpaper-agent"]),
            .init(program: "\(Self.bundle)/\(program)", arguments: ["ZZFixtureWallpaper", "--wallpaper-renderer"]),
        ]
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [agent, renderer], launchAgents: agents).isEmpty)
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [agent, renderer, machine], launchAgents: agents)
            == [.init(name: "ZZFixtureMachine", pid: 716)])
        // Without the plist it is an ordinary nested app and blocks.
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [agent]).count == 1)
    }

    /// The VMPal 0.108 shape, measured 2026-10-28: the Containers agent's
    /// `BundleProgram` is `VMPalMachine`, the same executable every VM runs in.
    /// A VM (`--machine <folder>`, parent launchd) must still block; only the
    /// agent's own instance passes. A process whose argv could not be read
    /// blocks. Mutation: match the agent by executable path alone → red.
    @Test func aVMRunningTheLaunchAgentsExecutableStillBlocks() {
        let program = "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine"
        let path = "\(Self.bundle)/\(program)"
        let containers = Self.process(722, program, arguments: ["ZZFixtureMachine", "--containers", "--service"])
        let vm = Self.process(723, program, arguments: [
            path, "--machine", "/Volumes/VM/macOS VM 1.vmpal", "--base", "/Volumes/VM/macOS VM 1.vmpal",
            "--by-agent",
        ])
        let unread = Self.process(724, program)
        let agents: [NestedAppGuard.LaunchAgent] = [
            .init(program: path, arguments: ["ZZFixtureMachine", "--containers", "--service"]),
        ]
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [Self.main, containers, vm], launchAgents: agents)
            == [.init(name: "ZZFixtureMachine", pid: 723)])
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [containers], launchAgents: agents).isEmpty)
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [containers, unread], launchAgents: agents)
            == [.init(name: "ZZFixtureMachine", pid: 724)])
        // Extra or missing arguments are not the agent either.
        let extra = Self.process(
            725, program, arguments: ["ZZFixtureMachine", "--containers", "--service", "--machine", "x"])
        let fewer = Self.process(726, program, arguments: ["ZZFixtureMachine", "--containers"])
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [extra, fewer], launchAgents: agents).map(\.pid) == [725, 726])
    }

    /// VMPal's MCP relays, measured 2026-10-28: `VMPalMachine --mcp-library`,
    /// started by each coding agent as its child. They pass; a VM from the same
    /// executable still blocks, and so does a relay-looking process of another
    /// nested app, one with extra arguments, or one whose argv is unknown.
    /// Mutation: drop the `neverBlocks` check → red; match by path alone → red.
    @Test func vmpalMCPRelaysNeverBlockButItsVMsDo() {
        let bundle = "/Applications/ZZFixtureVMPal.app"
        let program = "Contents/Helpers/VMPalMachine.app/Contents/MacOS/VMPalMachine"
        let path = "\(bundle)/\(program)"
        let relay = Self.process(740, program, parent: 9000, bundle: bundle, arguments: [path, "--mcp-library"])
        let vm = Self.process(741, program, bundle: bundle, arguments: [
            path, "--machine", "/Volumes/VM/macOS VM 1.vmpal", "--base", "/Volumes/VM/macOS VM 1.vmpal",
            "--by-agent",
        ])
        #expect(NestedAppGuard.blockers(bundlePath: bundle, processes: [relay]).isEmpty)
        #expect(NestedAppGuard.blockers(bundlePath: bundle, processes: [relay, vm])
            == [.init(name: "VMPalMachine", pid: 741)])
        let unread = Self.process(742, program, parent: 9000, bundle: bundle)
        let extra = Self.process(
            743, program, parent: 9000, bundle: bundle, arguments: [path, "--mcp-library", "--machine", "x"])
        let other = Self.process(
            744, "Contents/Helpers/Other.app/Contents/MacOS/Other", parent: 9000, bundle: bundle,
            arguments: ["Other", "--mcp-library"])
        #expect(NestedAppGuard.blockers(bundlePath: bundle, processes: [unread, extra, other]).map(\.pid)
            == [742, 743, 744])
        // A VM a relay spawned is not let through as the relay's helper: the
        // relay outlives the app. Mutation: keep relays in the parent set → red.
        let spawned = Self.process(745, program, parent: 740, bundle: bundle, arguments: [path, "--machine", "x"])
        #expect(NestedAppGuard.blockers(bundlePath: bundle, processes: [relay, spawned])
            == [.init(name: "VMPalMachine", pid: 745)])
    }

    /// The BetterTouchTool shape: `BTTRelaunch.app`, started by launchd, quits
    /// when its host does. It passes while the host's main app runs, since the
    /// restart quits both. A nested app not on the list still blocks beside it.
    /// Mutation: drop the `exitsWithHost` check → red.
    @Test func aNestedAppThatExitsWithItsHostPassesWhileTheHostRuns() {
        let watchdog = Self.process(
            717, "Contents/Resources/BTTRelaunch.app/Contents/MacOS/BTTRelaunch")
        let machine = Self.process(
            718, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [Self.main, watchdog]).isEmpty)
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [Self.main, watchdog, machine])
            == [.init(name: "ZZFixtureMachine", pid: 718)])
    }

    /// Between crash restarts only the watchdog runs, and nothing would quit it
    /// across the swap. Mutation: drop the `hostIsRunning` condition → red.
    @Test func aNestedAppThatExitsWithItsHostBlocksWhenTheHostIsNotRunning() {
        let watchdog = Self.process(
            719, "Contents/Resources/BTTRelaunch.app/Contents/MacOS/BTTRelaunch")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [watchdog])
            == [.init(name: "BTTRelaunch", pid: 719)])
        // Code deeper than `Contents/MacOS/` is not the host's main app.
        let helper = Self.process(720, "Contents/MacOS/Helpers/zzfixture-helper")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [helper, watchdog])
            == [.init(name: "BTTRelaunch", pid: 719)])
        // Another bundle's main app does not count as this one's.
        let otherMain = Self.process(
            721, "Contents/MacOS/ZZFixtureOther", bundle: "/Applications/ZZFixtureOther.app")
        #expect(NestedAppGuard.blockers(bundlePath: Self.bundle, processes: [otherMain, watchdog])
            == [.init(name: "BTTRelaunch", pid: 719)])
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

    // MARK: - LaunchAgents plists on disk

    /// Reads `BundleProgram` and `ProgramArguments` from every plist in
    /// `Contents/Library/LaunchAgents` and resolves symlinks as `proc_pidpath`
    /// does. A `Program`-only plist, a `BundleProgram` that leaves the bundle
    /// and a non-plist file add nothing. Mutations: read `Program` too → red;
    /// drop the inside-the-bundle check → red; drop `resolvingSymlinksInPath`
    /// → red; drop `ProgramArguments` → red.
    @Test func launchAgentsReadsBundleProgramFromTheBundlesOwnPlists() throws {
        let bundle = try Self.fixtureBundle()
        defer { try? FileManager.default.removeItem(atPath: bundle) }
        let agents = bundle + "/Contents/Library/LaunchAgents"
        try Self.writePlist(["BundleProgram": Self.agentProgram, "Label": "zz.agent",
                             "ProgramArguments": ["ZZFixtureWallpaper", "--wallpaper-agent"]],
                            to: agents + "/zz.agent.plist")
        try Self.writePlist(["BundleProgram": "Contents/Resources/Linked.app/Contents/MacOS/ZZFixtureLinked"],
                            to: agents + "/zz.linked.plist")
        try Self.writePlist(["Program": bundle + "/Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine"],
                            to: agents + "/zz.program.plist")
        try Self.writePlist(["BundleProgram": "../ZZFixtureOutside/tool"], to: agents + "/zz.outside.plist")
        // A `ProgramArguments` with a non-string skips the plist rather than
        // reading as no arguments. Mutation: `as? [String] ?? []` → red.
        try Self.writePlist(["BundleProgram": Self.agentProgram, "ProgramArguments": ["ZZFixtureWallpaper", 1]],
                            to: agents + "/zz.malformed.plist")
        try "not a plist".write(toFile: agents + "/README", atomically: true, encoding: .utf8)
        // `Linked.app` is a symlink to `Real.app`, as `Versions/Current` would be.
        let resources = bundle + "/Contents/Resources"
        try Self.makeExecutable(resources + "/Real.app/Contents/MacOS/ZZFixtureLinked")
        try FileManager.default.createSymbolicLink(
            atPath: resources + "/Linked.app", withDestinationPath: resources + "/Real.app")

        #expect(NestedAppGuard.launchAgents(inBundle: bundle) == [
            .init(program: bundle + "/" + Self.agentProgram,
                  arguments: ["ZZFixtureWallpaper", "--wallpaper-agent"]),
            .init(program: resources + "/Real.app/Contents/MacOS/ZZFixtureLinked", arguments: []),
        ])
    }

    @Test func launchAgentsIsEmptyWithoutTheDirectory() throws {
        let bundle = try Self.fixtureBundle()
        defer { try? FileManager.default.removeItem(atPath: bundle) }
        try FileManager.default.removeItem(atPath: bundle + "/Contents/Library")
        #expect(NestedAppGuard.launchAgents(inBundle: bundle).isEmpty)
    }

    /// `refusal` reads the installed bundle's plists itself. Mutation: stop
    /// passing `launchAgents` from `refusal` → red.
    @Test func theRefusalLetsTheBundlesOwnLaunchAgentThrough() throws {
        let bundle = try Self.fixtureBundle()
        defer { try? FileManager.default.removeItem(atPath: bundle) }
        try Self.writePlist(["BundleProgram": Self.agentProgram,
                             "ProgramArguments": ["ZZFixtureWallpaper", "--wallpaper-agent"]],
                            to: bundle + "/Contents/Library/LaunchAgents/zz.agent.plist")
        let url = URL(fileURLWithPath: bundle)
        let agent = NestedAppGuard.RunningProcess(
            pid: 730, parentPID: 1, executablePath: bundle + "/" + Self.agentProgram, isRegularApp: false,
            arguments: ["ZZFixtureWallpaper", "--wallpaper-agent"])
        #expect(NestedAppGuard.refusal(url, appName: "ZZFixtureVM", processes: { [agent] }) == nil)
        let machine = NestedAppGuard.RunningProcess(
            pid: 731, parentPID: 1,
            executablePath: bundle + "/Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine",
            isRegularApp: false)
        #expect(NestedAppGuard.refusal(url, appName: "ZZFixtureVM", processes: { [agent, machine] })
            == NestedAppRunningError(appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 731)]))
    }

    // MARK: - The message

    @Test func theMessageNamesTheNestedAppsOnce() {
        let one = NestedAppRunningError(
            appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 1)])
        #expect(one.errorDescription == "ZZFixtureMachine is running from inside ZZFixtureVM and would keep running the old version. Quit it, then update again. ZZFixtureVM was not updated.")
        let two = NestedAppRunningError(
            appName: "ZZFixtureVM",
            blockers: [.init(name: "B", pid: 1), .init(name: "A", pid: 2), .init(name: "B", pid: 3)])
        #expect(two.errorDescription == "A, B are running from inside ZZFixtureVM and would keep running the old version. Quit them, then update again. ZZFixtureVM was not updated.")
    }

    // MARK: - The hosts' preflight

    /// What both hosts ask before clearing a staged update or taking a rollback
    /// point. Only the routes whose swap the coordinator performs or starts are
    /// refused. Mutation: return nil for every route → red; refuse every route →
    /// red.
    @Test func thePreflightRefusesOnlyTheRoutesThatSwapTheBundle() {
        let blocking: () -> [NestedAppGuard.RunningProcess] = { [Self.blockingMachine()] }
        for route in [InstallCoordinator.Route.sparkle, .vendor, .homebrew] {
            #expect(InstallCoordinator.nestedAppRefusal(for: Self.result(), route: route, processes: blocking)
                == NestedAppRunningError(appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 700)]),
                "\(route) should be refused")
        }
        for route in [InstallCoordinator.Route.installer, .appStore, .xcode] {
            #expect(InstallCoordinator.nestedAppRefusal(for: Self.result(), route: route, processes: blocking) == nil,
                    "\(route) should not be refused")
        }
        #expect(InstallCoordinator.nestedAppRefusal(for: Self.result(), route: .sparkle, processes: { [] }) == nil)
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
                Self.result(), spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
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
                Self.result(), spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
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
            Self.result(), spaceToApply: 0, progress: { _ in }, releaseAfterDownload: {},
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

    /// A real process inside a nested `.app` comes back with its argv, which the
    /// LaunchAgent and relay rules match on. Mutation: pass `arguments: nil`
    /// in `liveProcesses` → red.
    @Test func theLiveListReadsTheArgvOfANestedApp() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-argv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let executable = parent.path + "/ZZFixtureVM.app/Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine"
        try FileManager.default.createDirectory(
            atPath: (executable as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: executable)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["30"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        // `proc_pidpath` spells the temporary directory as `/private/var/…`.
        let me = NestedAppGuard.liveProcesses().first { $0.pid == child.processIdentifier }
        #expect(me?.executablePath.hasSuffix(String(executable.dropFirst(parent.path.count))) == true)
        #expect(me?.arguments?.dropFirst().elementsEqual(["30"]) == true)
    }

    // MARK: - Fixtures

    private static let agentProgram =
        "Contents/Resources/ZZFixtureWallpaper.app/Contents/MacOS/ZZFixtureWallpaper"

    /// A real `ZZFixtureVM.app` in a fresh temporary directory, holding the
    /// agent's executable and an empty `Contents/Library/LaunchAgents`. The path
    /// comes back with symlinks resolved, as `refusal` resolves it.
    private static func fixtureBundle() throws -> String {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-agents-\(UUID().uuidString)", isDirectory: true)
        let bundle = parent.appendingPathComponent("ZZFixtureVM.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents/Library/LaunchAgents"),
            withIntermediateDirectories: true)
        try makeExecutable(bundle.path + "/" + agentProgram)
        return bundle.resolvingSymlinksInPath().path
    }

    private static func makeExecutable(_ path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: path))
    }

    private static func writePlist(_ plist: [String: Any], to path: String) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: path))
    }

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
