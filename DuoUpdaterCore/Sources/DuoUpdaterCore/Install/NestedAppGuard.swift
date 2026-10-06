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
/// (1059 processes, 40 bundles with something running inside), three bundles
/// were blocked:
///
/// - AppCleaner, by its `AppCleaner SmartDelete.app` login item;
/// - AweSun, by `AweSun_Desktop.app`;
/// - Gemini, by `GeminiAppLauncher.app`.
///
/// VMPal was not in that list only because no VM was running at the time.
/// A login item like SmartDelete keeps its app refused for as long as it runs.
/// That is the agreed cost: after a swap it too would run the old code until the
/// next login.
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
    /// `Foo.app` never claims `Foo.app.old/…`.
    public static func blockers(bundlePath: String, processes: [RunningProcess]) -> [Blocker] {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        let prefix = root + "/"
        let fromThisBundle = Set(processes.lazy
            .filter { $0.executablePath.hasPrefix(prefix) }
            .map(\.pid))
        return processes
            .compactMap { process -> Blocker? in
                guard !process.isRegularApp, !fromThisBundle.contains(process.parentPID),
                      let name = nestedAppName(executablePath: process.executablePath, insideBundle: prefix)
                else { return nil }
                return Blocker(name: name, pid: process.pid)
            }
            .sorted { $0.pid < $1.pid }
    }

    /// The name of the nested `.app` whose code `executablePath` is, or nil when
    /// it is not code from a nested app this guard counts. `bundlePrefix` ends
    /// in `/`.
    static func nestedAppName(executablePath: String, insideBundle bundlePrefix: String) -> String? {
        guard executablePath.hasPrefix(bundlePrefix) else { return nil }
        let relative = executablePath.dropFirst(bundlePrefix.count)
        if relative.hasPrefix("Contents/Frameworks/") { return nil }
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

    /// Throws when a nested app blocks replacing `bundle`.
    public static func check(
        _ bundle: URL, appName: String, processes: () -> [RunningProcess]
    ) throws {
        let found = blockers(
            bundlePath: bundle.resolvingSymlinksInPath().path, processes: processes())
        guard !found.isEmpty else { return }
        throw NestedAppRunningError(appName: appName, blockers: found)
    }
}

/// The swap was refused because an app nested inside the bundle is running on
/// its own. See `NestedAppGuard`. Nothing was downloaded or changed when it is
/// thrown before the download; nothing was changed when it is thrown before the
/// swap.
public struct NestedAppRunningError: LocalizedError, Equatable, Sendable {
    public let appName: String
    public let blockers: [NestedAppGuard.Blocker]

    public var errorDescription: String? {
        let names = Array(Set(blockers.map(\.name))).sorted()
        let list = names.joined(separator: ", ")
        let verb = names.count == 1 ? "is" : "are"
        return "\(list) \(verb) running from inside \(appName) and would keep running the old version. Quit \(names.count == 1 ? "it" : "them"), then update again. Nothing was changed."
    }
}
