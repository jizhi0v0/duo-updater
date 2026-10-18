import AppKit
import Darwin

/// Refuses to replace a bundle while an app nested inside it is running on its
/// own — a process that will keep running the old code after the swap, and that
/// the restart afterwards can neither quit safely nor bring back.
///
/// The case that motivated it is VMPal. Each virtual machine runs in
/// `VMPal.app/Contents/Helpers/VMPalMachine.app`, launched by LaunchServices
/// (its parent is launchd, not VMPal), started with `--machine <the VM's
/// folder>`, and it switches itself to `.accessory` at runtime. Measured on
/// 2026-10-06 with a VM running:
///
/// - The swap went through, and the VM went on running from the old bundle,
///   which was then deleted from disk. Quitting and relaunching VMPal did not
///   touch it, and stopping and starting the VM in the new VMPal reused the same
///   stale process.
/// - `AppRestarter` skips it, because `isStandaloneNestedApp` counts only
///   `.regular` nested apps. Counting it would be wrong too:
///   `NSRunningApplication.terminate()` made it exit within 0.4 s and the VM
///   stopped with no saved state, which amounts to pulling the plug. And
///   reopening the bundle would not bring the VM back without its arguments.
///
/// Nothing on our side can make that process current again, so the swap waits
/// until the user has quit it. That is what VMPal's own updater asks for as
/// well: it pauses, saves and closes every VM before it installs.
///
/// **What counts**, all of these at once:
///
/// - The executable is inside a `.app` nested in the bundle being replaced.
///   The main app's own `Contents/MacOS` does not count: restarting it is what
///   the relaunch after the swap is for.
/// - That nested app is not under `Contents/Frameworks/`, and no path component
///   above it is a `.framework`, `.xpc` or `.appex`. That excludes Chromium and
///   Electron helpers (`… Helper (Renderer).app`), Sparkle's `Updater.app` and
///   Python's `Python.app` inside a framework.
/// - It is not under `Contents/Library/LoginItems/`. A login item runs for as
///   long as the user is logged in, so refusing on one would block its app's
///   updates for good. A stale login item is replaced at the next login.
/// - Its executable is not the `BundleProgram` of a plist in the bundle's own
///   `Contents/Library/LaunchAgents/`, the agents `SMAppService` registers.
///   Those also outlive the app. `SMAppService.h` tells the app to re-register
///   one after an update, unregistering first when the executable changed,
///   which kills the running agent. An app that does so replaces a stale agent
///   on its next launch. That is a contract on the vendor, not something
///   launchd does: it was measured for Backdrop's `BackdropWallpaper` only
///   (below), and an app that skips it keeps running the old agent. The bet is
///   the same one the login-item exclusion makes.
/// - Its parent is not a process running from the same bundle. A helper the app
///   spawned goes away with the app.
/// - It is not a `.regular` app. That one already has a path: `AppRestarter`
///   quits and reopens it along with the main app (Surge's Dashboard).
///
/// Why the rules are this narrow: on 2026-10-06 a `ps` survey found about 20
/// apps with something running from inside them that the main app had not
/// spawned. Most were crashpad handlers, `.appex` extensions, `.xpc` services
/// and a Sparkle `Autoupdate`. Refusing on all of those would block one-click
/// for most apps. The same day, with these rules over the live process list
/// (1059 processes, 40 bundles with something running inside), the rules
/// without the login-item exclusion blocked three bundles:
///
/// - AppCleaner, by its `AppCleaner SmartDelete.app` login item, which is why
///   login items are now excluded;
/// - AweSun, by `AweSun_Desktop.app`;
/// - Gemini, by `GeminiAppLauncher.app`.
///
/// VMPal was not in that list only because no VM was running at the time.
/// The two `Contents/Helpers` apps stay refused for as long as they run. That is
/// the agreed cost.
///
/// The LaunchAgents exclusion came on 2026-10-12, for Backdrop. Its
/// `Contents/Resources/BackdropWallpaper.app` is the `BundleProgram` of
/// `com.cindori.Backdrop.Wallpaper.agent.plist` (`KeepAlive` and `RunAtLoad`
/// false, started through its MachService). Once Backdrop has been used, it and
/// a `--wallpaper-renderer` sibling keep running after Backdrop quits, so
/// one-click was refused nearly always. Measured with 2.8.0 (build 134): quit
/// Backdrop, swap in 2.9.0 with the old agent still running. The agent went on
/// running the old code for the 60 s watched, so it stays stale until Backdrop
/// is next opened. Opening 2.9.0 replaced it within 3 s: a new pid from the new
/// bundle, and `launchctl print` showed `parent bundle version` 134 → 135.
/// Backdrop keeps the bundle each agent was registered from in its defaults
/// (`com.cindori.Backdrop.Wallpaper.agent.registration` = the bundle path, its
/// inode and hashes). That is presumably how it notices the swap; its code was
/// not traced.
/// Over the live process list that day (833 processes, 35 bundles with
/// something running inside), these rules refused two bundles. The exclusion
/// lets Backdrop through. Gemini, refused by
/// `Contents/Helpers/GeminiAppLauncher.app`, has no LaunchAgents plist and
/// stays refused. Of the nine installed bundles that ship
/// `Contents/Library/LaunchAgents/`, Backdrop's was the only agent the other
/// rules did not already pass (the rest run from `LoginItems`, `Frameworks`,
/// `Contents/MacOS` or outside any nested `.app`).
///
/// `nestedAppsThatExitWithHost` came on 2026-10-18, for BetterTouchTool, after a
/// user report of a refused 6.885 → 6.944 update. BTT's
/// `Contents/Resources/BTTRelaunch.app` is a background-only watchdog (parent
/// launchd) that restarts BTT after a crash. BTT 6.943 started it by itself
/// 5–35 s after every launch and it stays up, so these rules refused BTT nearly
/// always. Measured with the real watchdog, swapping 6.943 → 6.944 in place,
/// then `terminate()` and `openApplication` as `AppRestarter` does:
///
/// - The old watchdog exited within 2 s of BTT's graceful quit and did not
///   restart BTT. The reopened 6.944 started its own watchdog from the new
///   bundle. The same with BTT's "don't force-terminate" setting on.
/// - BTT killed right after the swap: the old watchdog started the new BTT
///   from `/Applications` but itself kept running from the moved-aside
///   bundle. The restart afterwards cleared it like the case above.
/// - BTT stopped (`SIGSTOP`) through the 30 s quit wait: the watchdog did
///   nothing. `AppRestarter` gave up as for any app that won't quit.
/// - Crashed twice in a row, BTT waits about 30 s for its restart, with only
///   the watchdog running. A swap then leaves the old watchdog running beside
///   the new BTT, because nothing quits it. That is why the exception needs the
///   host's main app running.
public enum NestedAppGuard {

    /// One process, as much as this guard needs to know about it.
    public struct RunningProcess: Equatable, Sendable {
        public let pid: pid_t
        public let parentPID: pid_t
        /// As `proc_pidpath` spells it: symlinks resolved.
        public let executablePath: String
        /// Whether LaunchServices reports it as a `.regular` app. Only asked for
        /// processes inside a nested `.app`; false for everything else.
        public let isRegularApp: Bool

        public init(pid: pid_t, parentPID: pid_t, executablePath: String, isRegularApp: Bool) {
            self.pid = pid
            self.parentPID = parentPID
            self.executablePath = executablePath
            self.isRegularApp = isRegularApp
        }
    }

    /// A nested app that blocks the swap.
    public struct Blocker: Equatable, Sendable {
        /// The nested bundle's name without `.app` ("VMPalMachine").
        public let name: String
        public let pid: pid_t
    }

    /// The nested apps that block replacing the bundle at `bundlePath`, in pid
    /// order. Empty when the swap may go ahead. Pure.
    ///
    /// `bundlePath` is the installed bundle as the kernel reports paths, so
    /// symlinks are resolved. Containment is checked by path component, so
    /// `Foo.app` never claims `Foo.app.old/…`. `launchAgentPrograms` is what
    /// `launchAgentPrograms(inBundle:)` read from that bundle.
    public static func blockers(
        bundlePath: String, processes: [RunningProcess], launchAgentPrograms: Set<String> = []
    ) -> [Blocker] {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        let prefix = root + "/"
        let fromThisBundle = Set(processes.lazy
            .filter { $0.executablePath.hasPrefix(prefix) }
            .map(\.pid))
        let hostIsRunning = processes.contains {
            isMainAppExecutable($0.executablePath, insideBundle: prefix)
        }
        return processes
            .compactMap { process -> Blocker? in
                guard !process.isRegularApp, !fromThisBundle.contains(process.parentPID),
                      !launchAgentPrograms.contains(process.executablePath),
                      !(hostIsRunning
                        && exitsWithHost(executablePath: process.executablePath, insideBundle: prefix)),
                      let name = nestedAppName(executablePath: process.executablePath, insideBundle: prefix)
                else { return nil }
                return Blocker(name: name, pid: process.pid)
            }
            .sorted { $0.pid < $1.pid }
    }

    /// Nested apps measured to exit on their own when their host quits
    /// gracefully, as paths relative to the host bundle. Each one is let through
    /// only while the host's main app is running: the restart after the swap
    /// quits the host, and the nested app goes with it. Without a running host
    /// nothing quits it, so it stays refused. See BetterTouchTool in the type's
    /// comment.
    static let nestedAppsThatExitWithHost: [String] = [
        "Contents/Resources/BTTRelaunch.app",
    ]

    /// Whether `executablePath` is code from one of `nestedAppsThatExitWithHost`.
    /// `bundlePrefix` ends in `/`.
    static func exitsWithHost(executablePath: String, insideBundle bundlePrefix: String) -> Bool {
        guard executablePath.hasPrefix(bundlePrefix) else { return false }
        let relative = executablePath.dropFirst(bundlePrefix.count)
        return nestedAppsThatExitWithHost.contains { relative.hasPrefix($0 + "/") }
    }

    /// Whether `executablePath` is directly in the bundle's own `Contents/MacOS/`.
    /// `bundlePrefix` ends in `/`.
    static func isMainAppExecutable(_ executablePath: String, insideBundle bundlePrefix: String) -> Bool {
        guard executablePath.hasPrefix(bundlePrefix + "Contents/MacOS/") else { return false }
        return !executablePath.dropFirst((bundlePrefix + "Contents/MacOS/").count).contains("/")
    }

    /// The name of the nested `.app` whose code `executablePath` is, or nil when
    /// it is not code from a nested app this guard counts. `bundlePrefix` ends
    /// in `/`.
    static func nestedAppName(executablePath: String, insideBundle bundlePrefix: String) -> String? {
        guard executablePath.hasPrefix(bundlePrefix) else { return nil }
        let relative = executablePath.dropFirst(bundlePrefix.count)
        if relative.hasPrefix("Contents/Frameworks/") { return nil }
        // Login items (SMAppService agents, AppCleaner's SmartDelete) run for as
        // long as the user is logged in, so refusing on them would block the app
        // for good. A stale one is replaced at the next login.
        if relative.hasPrefix("Contents/Library/LoginItems/") { return nil }
        // Everything above the executable's file name, outermost first.
        let components = relative.split(separator: "/").dropLast()
        for component in components {
            if component.hasSuffix(".framework") || component.hasSuffix(".xpc")
                || component.hasSuffix(".appex") {
                return nil
            }
            if component.hasSuffix(".app") {
                return String(component.dropLast(".app".count))
            }
        }
        return nil
    }

    /// The executables the bundle's own `Contents/Library/LaunchAgents/*.plist`
    /// name as `BundleProgram`, symlinks resolved as `proc_pidpath` resolves
    /// them. Only those that stay inside the bundle count. Unreadable plists are
    /// skipped, which leaves their agents refused.
    public static func launchAgentPrograms(inBundle bundlePath: String) -> Set<String> {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        let directory = root + "/Contents/Library/LaunchAgents"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        var programs: Set<String> = []
        for name in names where name.hasSuffix(".plist") {
            guard let data = FileManager.default.contents(atPath: directory + "/" + name),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any],
                  let program = plist["BundleProgram"] as? String
            else { continue }
            let path = URL(fileURLWithPath: root + "/" + program).resolvingSymlinksInPath().path
            if path.hasPrefix(root + "/") { programs.insert(path) }
        }
        return programs
    }

    /// Every process this user can see, read fresh from the kernel. The
    /// activation policy comes from a NEW `NSRunningApplication` per pid, which
    /// reads the current value; the shared `NSWorkspace.runningApplications`
    /// snapshot goes stale in a process with no run loop, such as the CLI.
    public static func liveProcesses() -> [RunningProcess] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var processes: [RunningProcess] = []
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let parent: pid_t = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
                ? pid_t(info.pbi_ppid) : 0
            // Only a process inside some `.app` below another `.app` can matter,
            // and asking LaunchServices about every pid would be wasted work.
            let regular = path.components(separatedBy: ".app/").count > 2
                && NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            processes.append(RunningProcess(
                pid: pid, parentPID: parent, executablePath: path, isRegularApp: regular))
        }
        return processes
    }

    /// Why `bundle` cannot be replaced right now, or nil when it can.
    public static func refusal(
        _ bundle: URL, appName: String, processes: () -> [RunningProcess]
    ) -> NestedAppRunningError? {
        let path = bundle.resolvingSymlinksInPath().path
        let found = blockers(
            bundlePath: path, processes: processes(),
            launchAgentPrograms: launchAgentPrograms(inBundle: path))
        return found.isEmpty ? nil : NestedAppRunningError(appName: appName, blockers: found)
    }

    /// Throws when a nested app blocks replacing `bundle`.
    public static func check(
        _ bundle: URL, appName: String, processes: () -> [RunningProcess]
    ) throws {
        if let refusal = refusal(bundle, appName: appName, processes: processes) { throw refusal }
    }
}

/// The swap was refused because an app nested inside the bundle is running on
/// its own. See `NestedAppGuard`.
///
/// The message says the app was not updated, not that nothing changed. Both
/// hosts ask `InstallCoordinator.nestedAppRefusal` before they clear a staged
/// self-update or take a rollback point, so normally nothing has changed. But
/// when the nested app starts after that check, the coordinator refuses after
/// the rollback point was already replaced. "Nothing was changed" would be
/// false then.
public struct NestedAppRunningError: LocalizedError, Equatable, Sendable {
    public let appName: String
    public let blockers: [NestedAppGuard.Blocker]

    public var errorDescription: String? {
        let names = Array(Set(blockers.map(\.name))).sorted()
        let list = names.joined(separator: ", ")
        let verb = names.count == 1 ? "is" : "are"
        return "\(list) \(verb) running from inside \(appName) and would keep running the old version. Quit \(names.count == 1 ? "it" : "them"), then update again. \(appName) was not updated."
    }
}
