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
        // What the agent spawns is not the app's helper: the agent outlives the
        // app. Mutation: keep agent instances in the parent set → red.
        let spawned = Self.process(727, program, parent: 722, arguments: ["ZZFixtureMachine", "--machine", "x"])
        #expect(NestedAppGuard.blockers(
            bundlePath: Self.bundle, processes: [containers, spawned], launchAgents: agents)
            == [.init(name: "ZZFixtureMachine", pid: 727)])
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
            == [.init(name: "VMPalMachine", pid: 741, vmName: "macOS VM 1")])
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
            == [.init(name: "VMPalMachine", pid: 745, vmName: "x")])
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
        defer { Self.removeBundleFixture(bundle) }
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
        defer { Self.removeBundleFixture(bundle) }
        try FileManager.default.removeItem(atPath: bundle + "/Contents/Library")
        #expect(NestedAppGuard.launchAgents(inBundle: bundle).isEmpty)
    }

    /// `refusal` reads the installed bundle's plists itself. Mutation: stop
    /// passing `launchAgents` from `refusal` → red.
    @Test func theRefusalLetsTheBundlesOwnLaunchAgentThrough() throws {
        let bundle = try Self.fixtureBundle()
        defer { Self.removeBundleFixture(bundle) }
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

    /// A VMPal VM blocks with its name, read from `--machine <folder>`. The
    /// relay, another nested app with `--machine`, and a VM whose argv was not
    /// read carry no name. Mutation: return nil from `vmName` → red.
    @Test func aVMPalVMBlocksWithItsName() {
        let bundle = "/Applications/ZZFixtureVMPal.app"
        let program = "Contents/Helpers/VMPalMachine.app/Contents/MacOS/VMPalMachine"
        let path = "\(bundle)/\(program)"
        let vm = Self.process(750, program, bundle: bundle, arguments: [
            path, "--machine", "/Volumes/VM/macOS VM 1.vmpal", "--base", "/Volumes/VM/macOS VM 1.vmpal",
            "--by-agent",
        ])
        let unread = Self.process(751, program, bundle: bundle)
        let other = Self.process(
            752, "Contents/Helpers/Other.app/Contents/MacOS/Other", bundle: bundle,
            arguments: ["Other", "--machine", "/Volumes/VM/x.vmpal"])
        #expect(NestedAppGuard.blockers(bundlePath: bundle, processes: [vm, unread, other]) == [
            .init(name: "VMPalMachine", pid: 750, vmName: "macOS VM 1"),
            .init(name: "VMPalMachine", pid: 751),
            .init(name: "Other", pid: 752),
        ])
    }

    /// VMPal's VMs get their own advice: shutting a VM down leaves its process
    /// up until its window is closed (measured 2026-10-28), so "Quit it" is not
    /// enough. Other blockers keep the general sentence. Mutation: drop the VM
    /// branch from `errorDescription` → red.
    @Test func theMessageNamesVMPalVMsAndSaysToCloseTheirWindows() {
        let one = NestedAppRunningError(
            appName: "VMPal", blockers: [.init(name: "VMPalMachine", pid: 1, vmName: "macOS VM 1")])
        #expect(one.errorDescription == "“macOS VM 1” is open in VMPal. Shut it down and close its window, then update again. VMPal was not updated.")
        let two = NestedAppRunningError(appName: "VMPal", blockers: [
            .init(name: "VMPalMachine", pid: 1, vmName: "Win"),
            .init(name: "VMPalMachine", pid: 2, vmName: "Linux"),
        ])
        #expect(two.errorDescription == "“Linux”, “Win” are open in VMPal. Shut them down and close their windows, then update again. VMPal was not updated.")
        let mixed = NestedAppRunningError(appName: "VMPal", blockers: [
            .init(name: "VMPalMachine", pid: 1, vmName: "macOS VM 1"),
            .init(name: "VMPalDock", pid: 2),
        ])
        #expect(mixed.errorDescription == "“macOS VM 1” is open in VMPal. Shut it down and close its window, then update again. VMPalDock is running from inside VMPal and would keep running the old version. Quit it, then update again. VMPal was not updated.")
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

    /// Started after the coordinator's last check, while the apply verified and
    /// unpacked (or waited on an administrator panel): the swap itself refuses,
    /// and the installed bundle is untouched. The apply here is the swap alone,
    /// as `SparkleInstaller` and `VendorInstaller` end in it. Mutation: drop the
    /// `preExchangeCheck` call in `InPlaceSwap.replace` → the swap lands.
    @Test func theSwapRefusesWhenTheNestedAppStartsAfterTheCoordinatorsLastCheck() async throws {
        let fixture = try SwapFixture()
        defer { fixture.remove() }
        let started = Flag()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: { started.value ? [fixture.machine] : [] })
        await #expect(throws: NestedAppRunningError.self) {
            _ = try await coordinator.fetchThenSwap(
                Self.result(at: fixture.target), spaceToApply: 0, progress: { _ in },
                releaseAfterDownload: {},
                download: { _, _ in
                    DownloadedUpdate(
                        archiveURL: fixture.work.appendingPathComponent("ZZFixture.zip"),
                        bytesDownloaded: 1, workDir: fixture.work)
                },
                apply: { _, _, _ in
                    started.set()
                    try await InPlaceSwap.replace(newApp: fixture.incoming, over: fixture.target)
                })
        }
        #expect(fixture.targetIsUntouched)
    }

    /// The other two exchanges ask too: the elevated route before its shell
    /// (no administrator panel for a swap that would be refused), and the
    /// `Contents` rotation input methods take. Mutation: drop the
    /// `preExchangeCheck` call before `runElevated` → the shell runs; drop the
    /// one before `rotateContents` → the rotation lands.
    @Test func theElevatedAndRotationExchangesAskBeforeTheyMoveAnything() async throws {
        let refusal = NestedAppRunningError(
            appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 700)])
        let refuse: @Sendable () throws -> Void = { throw refusal }

        let elevated = try SwapFixture()
        defer {
            chmod(elevated.root.path, 0o755)
            elevated.remove()
        }
        chmod(elevated.root.path, 0o555)
        #expect(InPlaceSwap.needsElevatedReplace(target: elevated.target), "fixture must take the elevated route")
        let shells = Counter()
        await #expect(throws: NestedAppRunningError.self) {
            try await InPlaceSwap.$elevatedShellOverride.withValue({ _ in
                shells.bump()
                return try await ChildProcess.run("/usr/bin/true", [], onCancel: .runToCompletion)
            }) {
                try await InPlaceSwap.$preExchangeCheck.withValue(refuse) {
                    try await InPlaceSwap.replace(newApp: elevated.incoming, over: elevated.target)
                }
            }
        }
        #expect(shells.value == 0)
        #expect(elevated.targetIsUntouched)

        let rotation = try SwapFixture(directory: "Library/Input Methods")
        defer { rotation.remove() }
        #expect(InPlaceSwap.usesContentsRotation(target: rotation.target), "fixture must take the rotation path")
        await #expect(throws: NestedAppRunningError.self) {
            try await InPlaceSwap.$preExchangeCheck.withValue(refuse) {
                try await InPlaceSwap.replace(newApp: rotation.incoming, over: rotation.target)
            }
        }
        #expect(rotation.targetIsUntouched)
    }

    /// Refused inside a patch-route apply: not wrapped for the full-archive
    /// retry, so the refusal is reported as itself. (A retry would be refused
    /// again by `fetchThenSwap`'s first check, before downloading anything.)
    /// Mutation: drop the `NestedAppRunningError` line in
    /// `deltaRouteFailureIsWorthRetrying` → red.
    @Test func aRefusalInsideThePatchRouteIsNotRetriedWithTheFullArchive() {
        let refusal = NestedAppRunningError(
            appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 700)])
        #expect(!deltaRouteFailureIsWorthRetrying(refusal))
    }

    /// A swap outside an install (`InPlaceSwap.replace` with no check set, as a
    /// restore runs it) is not refused by this guard.
    @Test func aSwapWithNoCheckSetGoesAhead() async throws {
        let fixture = try SwapFixture()
        defer { fixture.remove() }
        try await InPlaceSwap.replace(newApp: fixture.incoming, over: fixture.target)
        #expect(FileManager.default.fileExists(
            atPath: fixture.target.appendingPathComponent("Contents/new").path))
    }

    /// The Homebrew route: started while the install waited for the apply
    /// permit, after the check before it. brew must not start. Mutation: drop
    /// the `refuseWhileNestedAppRuns` after `waitForApplyOrCancel` in the
    /// `.homebrew` case → the stand-in brew runs.
    @Test func brewDoesNotStartWhenTheNestedAppStartsWhileWaitingForTheApplyPermit() async throws {
        let fixture = try SwapFixture()
        defer { fixture.remove() }
        let ran = fixture.root.appendingPathComponent("brew-ran")
        let brew = fixture.root.appendingPathComponent("brew")
        try Data("#!/bin/sh\n/usr/bin/touch '\(ran.path)'\nexit 0\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        // The first ask is the check before the permit; the nested app is up by
        // the next one.
        let asks = Counter()
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: {
                asks.bump()
                return asks.value > 1 ? [fixture.machine] : []
            })
        let result = Self.result(
            at: fixture.target,
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Homebrew",
                sourceIdentifier: "zzfixture-cask"))
        await #expect(throws: NestedAppRunningError.self) {
            try await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                _ = try await coordinator.perform(
                    result, route: .homebrew, installedPopulation: [], digestOnlyAllowed: false,
                    progress: { _ in })
            }
        }
        #expect(!FileManager.default.fileExists(atPath: ran.path))
        #expect(fixture.targetIsUntouched)
    }

    /// The Homebrew route: started while brew downloaded. brew's install must
    /// not start. The stand-in brew logs each run's arguments, and its `fetch`
    /// is when the nested app comes up. Mutation: drop the
    /// `refuseWhileNestedAppRuns` after `homebrew.fetch` in the `.homebrew`
    /// case → the install runs.
    @Test func brewDoesNotInstallWhenTheNestedAppStartsDuringTheFetch() async throws {
        let fixture = try SwapFixture()
        defer { fixture.remove() }
        let log = fixture.root.appendingPathComponent("brew-log")
        let fetched = fixture.root.appendingPathComponent("brew-fetched")
        let brew = fixture.root.appendingPathComponent("brew")
        try Data("""
            #!/bin/sh
            echo "$*" >> '\(log.path)'
            [ "$1" = fetch ] && /usr/bin/touch '\(fetched.path)'
            exit 0

            """.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1),
            runningProcesses: {
                FileManager.default.fileExists(atPath: fetched.path) ? [fixture.machine] : []
            },
            // See `HomebrewFetchFirstTests`: no wait for disk space before brew.
            space: DiskSpaceGuard.SpaceLedger())
        let result = Self.result(
            at: fixture.target,
            remote: RemoteVersion(
                shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Homebrew",
                sourceIdentifier: "zzfixture-cask"))
        await #expect(throws: NestedAppRunningError.self) {
            try await BackupStore.$freeBytesOverride.withValue({ 1 << 50 }) {
                try await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                    _ = try await coordinator.perform(
                        result, route: .homebrew, installedPopulation: [], digestOnlyAllowed: false,
                        progress: { _ in })
                }
            }
        }
        let runs = (try? String(contentsOf: log, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        #expect(runs.contains("fetch --cask -- zzfixture-cask"))
        #expect(!runs.contains("install --cask --force -- zzfixture-cask"))
        #expect(fixture.targetIsUntouched)
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
    @Test func theLiveListReadsTheArgvOfANestedApp() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-argv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let relative = "/ZZFixtureVM.app/Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine"
        let executable = parent.path + relative
        try FileManager.default.createDirectory(
            atPath: (executable as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // A copy of an Apple binary is killed at exec (launch constraints): it
        // runs only once signed ad hoc, as its own code.
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: executable)
        let signed = try await ChildProcess.run(
            "/usr/bin/codesign", ["-s", "-", "-f", executable], onCancel: .terminateChild)
        try #require(signed.succeeded)
        // Read while the child runs: `onLaunch` comes after the spawn, before
        // the wait, and the child is ended once read. `proc_pidpath` spells the
        // temporary directory `/private/var/…`.
        let seen = SeenProcess()
        _ = try await ChildProcess.run(executable, ["60"], onCancel: .terminateChild, onLaunch: { pid in
            seen.set(NestedAppGuard.liveProcesses().first { $0.pid == pid })
            kill(pid, SIGTERM)
        })
        let me = seen.value
        #expect(me?.executablePath.hasSuffix(relative) == true)
        #expect(me?.arguments?.dropFirst().elementsEqual(["60"]) == true)
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

    /// Removes the `ZZFixture-agents-<UUID>` directory that `fixtureBundle()` made,
    /// not just the bundle inside it.
    ///
    /// The callers used to remove `bundle` alone, which leaves the parent behind:
    /// one empty directory per test run, 3,621 of them in the mini's temporary
    /// directory by 2026-10-30. Finder had 40 of these open and sat at 148% CPU
    /// beside a `fseventsd` at 76%, from the churn of a directory holding 17,006
    /// such entries.
    private static func removeBundleFixture(_ bundle: String) {
        try? FileManager.default.removeItem(atPath: (bundle as NSString).deletingLastPathComponent)
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

    private static func result(
        at path: URL = URL(fileURLWithPath: bundle),
        remote: RemoteVersion = RemoteVersion(
            shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Vendor")
    ) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "ZZFixtureVM", bundleID: "com.example.zzfixturevm",
                shortVersion: "1.0", buildVersion: "1", path: path,
                isMASApp: false, sparkleFeedURL: nil, sparkleEdPublicKey: nil),
            remote: remote,
            status: .updateAvailable(latest: "1.1"))
    }

    /// A real installed `ZZFixtureVM.app` (marked `Contents/old`) and an
    /// incoming bundle (marked `Contents/new`), each in a fresh temporary directory,
    /// and the VM process a nested app in the installed one would be.
    private struct SwapFixture {
        let root: URL
        let target: URL
        let incoming: URL
        let work: URL
        let machine: NestedAppGuard.RunningProcess

        /// `directory` is where under `root` the installed bundle sits.
        init(directory: String? = nil) throws {
            let fm = FileManager.default
            root = fm.temporaryDirectory
                .appendingPathComponent("ZZFixture-swap-\(UUID().uuidString)", isDirectory: true)
            let root = root
            let parent = directory.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
            target = parent.appendingPathComponent("ZZFixtureVM.app", isDirectory: true)
            work = fm.temporaryDirectory
                .appendingPathComponent("ZZFixture-swap-work-\(UUID().uuidString)", isDirectory: true)
            incoming = work.appendingPathComponent("ZZFixtureVM.app", isDirectory: true)
            for (bundle, marker) in [(target, "old"), (incoming, "new")] {
                try fm.createDirectory(
                    at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
                try Data("\(marker) binary".utf8)
                    .write(to: bundle.appendingPathComponent("Contents/MacOS/ZZFixtureVM"))
                try Data().write(to: bundle.appendingPathComponent("Contents/\(marker)"))
            }
            machine = NestedAppGuardTests.process(
                700, "Contents/Helpers/ZZFixtureMachine.app/Contents/MacOS/ZZFixtureMachine",
                bundle: target.resolvingSymlinksInPath().path)
        }

        var targetIsUntouched: Bool {
            FileManager.default.fileExists(atPath: target.appendingPathComponent("Contents/old").path)
                && !FileManager.default.fileExists(atPath: target.appendingPathComponent("Contents/new").path)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class SeenProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: NestedAppGuard.RunningProcess?
    func set(_ process: NestedAppGuard.RunningProcess?) { lock.withLock { seen = process } }
    var value: NestedAppGuard.RunningProcess? { lock.withLock { seen } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}
