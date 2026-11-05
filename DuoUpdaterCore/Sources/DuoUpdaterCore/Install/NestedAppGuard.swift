import AppKit
import Darwin

/// Refuses to replace a bundle while an app nested inside it is running on its
/// own — a process that will keep running the old code after the swap, and that
/// the restart afterwards can neither quit safely nor bring back. Two exemptions
/// are gated on the host's main app running, both listed under "What counts": a
/// nested app that quits with its host, and one the host replaces on its next
/// launch.
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
/// - It is not the instance of an agent in the bundle's own
///   `Contents/Library/LaunchAgents/`, the agents `SMAppService` registers: its
///   executable is the plist's `BundleProgram` and its argv after `argv[0]` is
///   the plist's `ProgramArguments` after the first. Those also outlive the app. `SMAppService.h` tells the app to re-register
///   one after an update, unregistering first when the executable changed,
///   which kills the running agent. An app that does so replaces a stale agent
///   on its next launch. That is a contract on the vendor, not something
///   launchd does: it was measured for Backdrop's `BackdropWallpaper` only
///   (below), and an app that skips it keeps running the old agent. The bet is
///   the same one the login-item exclusion makes.
/// - Its parent is not a process running from the same bundle. A helper the app
///   spawned goes away with the app — except a helper the host replaces at launch,
///   which outlives it: that one is no parent for this rule, and its own subtree
///   is covered by the exemption below.
/// - It is not a helper the host rebuilds at every launch, while the host's
///   main app is running — Gemini's launcher (below). Gemini terminates any
///   instance and starts a fresh one from its own bundle on every launch, so the
///   restart after the swap replaces it. The gate is there because that helper
///   is also the vendor's updater, and it defers its own install only while the
///   main app runs: with the host quit the lone launcher is exactly when its
///   installer would go ahead, so it blocks.
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
/// AweSun's `AweSun_Desktop.app` stays refused for as long as it runs — that is
/// the agreed cost — and Gemini's launcher did too until 2026-11-01 (below).
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
/// The arguments came into it on 2026-10-28, for VMPal 0.108. Its
/// `com.tableplus.VMPal.Containers.plist` names `VMPalMachine` as
/// `BundleProgram` with `ProgramArguments` `VMPalMachine --containers
/// --service`, the same executable every VM runs in as `--machine <folder>`.
/// Matching by path alone let a running VM through: the swap went ahead and
/// the VM kept running from the moved-aside bundle, the case above. launchd
/// passes `ProgramArguments` as the job's argv (`launchd.plist(5)`), so the
/// agent's own instance is told apart by its arguments. `argv[0]` is left out
/// of the comparison, so a plist that spells it differently from the kernel
/// still matches. Backdrop's two processes are the instances of its two
/// plists, `--wallpaper-agent` and `--wallpaper-renderer`.
/// The same day, `nestedAppInstancesThatNeverBlock` came for VMPal's MCP
/// relays. Each coding agent with VMPal's MCP server configured starts
/// `VMPalMachine --mcp-library` by its fixed `/Applications` path as its own
/// child; five ran at once on the dev Mac. They are not VMs. VMPal's own
/// Sparkle update to 0.107 that day left four of them running from the bundle
/// it moved into its cache, while its update UI offers only "Pause VMs and
/// Update". A relay picks up a new version when its agent restarts. Refusing
/// on them would block VMPal whenever an agent session is open, so they pass,
/// matched by their exact argv; the VM (`--machine <folder>`) still blocks.
/// Over the live process list that day (833 processes, 35 bundles with
/// something running inside), these rules refused two bundles. The exclusion
/// lets Backdrop through. Gemini, refused by
/// `Contents/Helpers/GeminiAppLauncher.app`, has no LaunchAgents plist and
/// stays refused — until `nestedAppsTheHostReplacesOnLaunch` (below). Of the
/// nine installed bundles that ship
/// `Contents/Library/LaunchAgents/`, Backdrop's was the only agent the other
/// rules did not already pass (the rest run from `LoginItems`, `Frameworks`,
/// `Contents/MacOS` or outside any nested `.app`).
///
/// `nestedAppsThatExitWithHost` came on 2026-10-18, for BetterTouchTool, after a
/// user report of a refused 6.885 → 6.944 update. BTT's
/// `Contents/Resources/BTTRelaunch.app` is a background-only watchdog (parent
/// launchd) that restarts BTT after a crash. BTT 6.943 started it by itself
/// 5–35 s after every launch and it stays up, so these rules refused BTT nearly
/// always. The watchdog is one binary across releases: BTTRelaunch 1.17 (23),
/// the same cdhash in BTT 6.880, 6.885, 6.943, 6.944 and the 6.945/6.946 alpha
/// builds, each `LSBackgroundOnly` and with only `BetterTouchTool` in
/// `Contents/MacOS`. Measured with the real watchdog, swapping 6.943 → 6.944 in place,
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
///
/// `nestedAppsTheHostReplacesOnLaunch` came on 2026-11-01, for Gemini, after a
/// user report (#1764) of a refused 1.135.1.1291 → 1.138.0.1315 update.
/// `Contents/Helpers/GeminiAppLauncher.app` is `LSUIElement` and sits in the menu
/// bar with Gemini's global shortcuts; it is also Gemini's own Omaha updater
/// ("Checking for update…", then "Deferring update 1.138.0.1315 — main app is
/// running"). Gemini starts it through LaunchServices about two seconds after it
/// comes up, so its parent is launchd and the parent rule never let it through.
/// It can also be registered as a login item — macOS announced "Login Item
/// Added: GeminiAppLauncher" in the VM on 2026-11-01 — so it can be up with
/// Gemini quit; it lives in `Contents/Helpers`, not `Contents/Library/LoginItems`,
/// so the login-item exclusion never covered it either.
/// It was the only reason the 2026-10-06 survey refused Gemini, and a one-click
/// update with Gemini open hit it every time.
///
/// Measured in VMPal's macOS VM (macOS 27.2) on 2026-11-01, Gemini 1.107.3.828
/// → 1.138.0.1315; the launcher replacement alone was also measured on the dev
/// Mac (27.2, 31504 → 54005):
///
/// - With Gemini and the launcher running, the swap went through, and
///   `duo restart` replaced the launcher with the new bundle's (pid 91219,
///   1.107 code → 91558, 1.138.00.0). Nothing was left running from the old
///   bundle. The app does that itself: its log says "Terminating existing
///   helper app instance(s)", then "Helper app launched successfully", on every
///   launch.
/// - Quitting Gemini leaves the launcher up only while it is busy: it went
///   2 s after a quit while idle, and stayed for the minutes it spent
///   downloading 1.138 with the main app running. So the lone launcher is the
///   state in which Google's installer is free to go ahead on its own — which is
///   why the exemption needs the host's main app running, though for the
///   opposite reason to BetterTouchTool's: here it is the host that would let the
///   helper's own install run, not the host that quits it.
///
/// The launcher is let through only while Gemini runs, so the reported case (the
/// user is using Gemini, its launcher is up and deferring) updates. When Gemini
/// is quit and the launcher is still up, the refusal asks for Gemini to be opened
/// (`Blocker.needsHostRunning`), not for the launcher to be quit: opening Gemini
/// is what replaces the launcher, and the user has no icon of that name to look
/// for. A swap that goes ahead leaves the old launcher running beside the swapped
/// bundle until the next launch — or until the restart duo offers, if the user
/// takes it — the same bet the login-item
/// exclusion makes. Its own updater may then install a build from a different
/// Omaha cohort than the one duo installed: that is the price of installing
/// during a staged rollout at all (the cohort echo, #1621), not something the
/// guard can settle.
///
/// `RunningProcess.launchedPath` came on 2026-11-03, for #1783. A swap replaces
/// the bundle while a nested helper is still running from it, and the copy the
/// installer moved aside is deleted afterwards, so the helper's executable inode
/// is unlinked. `proc_pidpath` then answers `ENOENT` for a process that is still
/// there, the live list dropped it, and `blockers` came back empty while the VM
/// ran: `duo restart VMPal` took the staged path, the guard saw nothing and sent
/// the quit. The swap that put VMPal in that state was the first one; every
/// later one was blind until the helper exited.
/// Measured 2026-11-02 on this Mac with VMPal 0.113 → 0.114 force-installed over
/// a running VM (pid 8631 still up): `proc_pidpath` 0/`ENOENT`,
/// `proc_pidinfo(PROC_PIDTBSDINFO)` 136 bytes with uid 501 and ppid 1, and
/// `blockers(bundlePath: "/Applications/VMPal.app", …)` `[]`. `lsof` still named
/// the executable at the Sparkle staging path, the copy that had been deleted.
/// After the VM was restarted (a new pid from `/Applications/VMPal.app`) the
/// path resolved again and the guard refused as designed. Measured 2026-11-03
/// with a launchd-spawned child (ppid 1) whose copied executable was unlinked
/// while it ran: `proc_pidpath` 0/`ENOENT`, while `KERN_PROCARGS2` still spelled
/// the path `execve` was given — the bundle path the swap replaced, not the
/// staging path — so that is the identity the live list keeps. `argv[0]` read
/// the same, but it is a copy the program can rewrite and the exec path is not.
/// Three other live processes were already in that state when this was measured
/// (Rex Beta, Sogou's `SogouServices`, a ChatGPT-for-Chrome extension host), so
/// it is not only VMPal's staging path.
public enum NestedAppGuard {

    /// One process, as much as this guard needs to know about it.
    public struct RunningProcess: Equatable, Sendable {
        public let pid: pid_t
        public let parentPID: pid_t
        /// As `proc_pidpath` spells it: symlinks resolved. Nil when the kernel
        /// cannot name the executable any more — the swap unlinked it (#1783) —
        /// which does not mean the process is gone: see `launchedPath`.
        public let executablePath: String?
        /// The path `execve` was given, from the argv block the kernel saved at
        /// exec, symlinks resolved like `executablePath`. Only read when the
        /// kernel names nothing, and then it is the identity that survives: a
        /// helper still running from the bundle a swap replaced is placed inside
        /// that bundle by this path. Nil for every other process, and when the
        /// kernel kept no copy (another user's, or gone).
        public let launchedPath: String?
        /// Whether LaunchServices reports it as a `.regular` app. Only asked for
        /// processes inside a nested `.app`; false for everything else.
        public let isRegularApp: Bool
        /// Its argv, from `KERN_PROCARGS2`. Only read for processes inside a
        /// nested `.app`; nil for everything else and when it can't be read,
        /// which matches no LaunchAgent.
        public let arguments: [String]?

        public init(
            pid: pid_t, parentPID: pid_t, executablePath: String?, launchedPath: String? = nil,
            isRegularApp: Bool, arguments: [String]? = nil
        ) {
            self.pid = pid
            self.parentPID = parentPID
            self.executablePath = executablePath
            self.launchedPath = launchedPath
            self.isRegularApp = isRegularApp
            self.arguments = arguments
        }

        /// The path this guard places the process by: what the kernel names now,
        /// or — when it names nothing — where the process was launched from.
        /// Empty when neither, which no bundle claims.
        var path: String { executablePath ?? launchedPath ?? "" }
    }

    /// One plist in the bundle's own `Contents/Library/LaunchAgents/`.
    public struct LaunchAgent: Equatable, Sendable {
        /// `BundleProgram` made absolute, symlinks resolved as `proc_pidpath`
        /// resolves them.
        public let program: String
        /// `ProgramArguments`, empty when the plist has none.
        public let arguments: [String]

        public init(program: String, arguments: [String]) {
            self.program = program
            self.arguments = arguments
        }

        /// Whether `process` is an instance of this agent: the same executable,
        /// and the same argv after `argv[0]`.
        func isInstance(_ process: RunningProcess) -> Bool {
            guard process.path == program, let argv = process.arguments else { return false }
            return argv.dropFirst().elementsEqual(arguments.dropFirst())
        }
    }

    /// A nested app that blocks the swap.
    public struct Blocker: Equatable, Sendable {
        /// The nested bundle's name without `.app` ("VMPalMachine").
        public let name: String
        public let pid: pid_t
        /// The VM it runs, when it is one of VMPal's ("macOS VM 1"). See
        /// `vmName(of:insideBundle:)`.
        public var vmName: String? = nil
        /// Whether starting the host's main app is what clears it: a helper the
        /// host replaces at launch, refused only while the host is not running.
        /// The advice is then to open the app, not to quit the helper. See
        /// `nestedAppsTheHostReplacesOnLaunch`.
        public var needsHostRunning: Bool = false
    }

    /// The nested apps that block replacing the bundle at `bundlePath`, in pid
    /// order. Empty when the swap may go ahead. Pure.
    ///
    /// `bundlePath` is the installed bundle as the kernel reports paths, so
    /// symlinks are resolved. Containment is checked by path component, so
    /// `Foo.app` never claims `Foo.app.old/…`. `launchAgents` is what
    /// `launchAgents(inBundle:)` read from that bundle.
    public static func blockers(
        bundlePath: String, processes: [RunningProcess], launchAgents: [LaunchAgent] = []
    ) -> [Blocker] {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        let prefix = root + "/"
        // An agent instance or a relay outlives the app, so what it spawns does
        // not go away with the app: it is no parent for the parent rule. The
        // same goes for a helper the host replaces at launch — measured to
        // outlive it — whose own subtree the exemption already covers.
        let fromThisBundle = Set(processes.lazy
            .filter { $0.path.hasPrefix(prefix) }
            .filter { process in
                !launchAgents.contains(where: { $0.isInstance(process) })
                    && !neverBlocks(process, insideBundle: prefix)
                    && !replacedOnLaunch(executablePath: process.path, insideBundle: prefix)
            }
            .map(\.pid))
        let hostIsRunning = processes.contains {
            isMainAppExecutable($0.path, insideBundle: prefix)
        }
        return processes
            .compactMap { process -> Blocker? in
                let path = process.path
                guard !process.isRegularApp, !fromThisBundle.contains(process.parentPID),
                      !launchAgents.contains(where: { $0.isInstance(process) }),
                      !neverBlocks(process, insideBundle: prefix),
                      !(hostIsRunning && exitsWithHost(executablePath: path, insideBundle: prefix)),
                      !(hostIsRunning && replacedOnLaunch(executablePath: path, insideBundle: prefix)),
                      let name = nestedAppName(executablePath: path, insideBundle: prefix)
                else { return nil }
                return Blocker(
                    name: name, pid: process.pid,
                    vmName: vmName(of: process, insideBundle: prefix),
                    needsHostRunning: replacedOnLaunch(executablePath: path, insideBundle: prefix))
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

    /// Nested apps the host itself terminates and starts again from its own
    /// bundle every time it launches, as paths relative to the host bundle.
    /// Nothing in them has to be quit before the swap: whatever still runs is
    /// replaced at the host's next launch. Let through only while the host's main
    /// app runs — such a helper is usually the vendor's updater, which defers its
    /// own install only while that app does. See Gemini's launcher in the type's
    /// comment. The name has to stay vendor-unique: matching is by path, and what
    /// makes the exemption safe is the vendor's own launch behaviour.
    static let nestedAppsTheHostReplacesOnLaunch: [String] = [
        "Contents/Helpers/GeminiAppLauncher.app",
    ]

    /// Nested-app processes that never block, as the nested app's path relative
    /// to the host bundle and the exact argv after `argv[0]`. See VMPal's MCP
    /// relays in the type's comment.
    static let nestedAppInstancesThatNeverBlock: [(app: String, arguments: [String])] = [
        ("Contents/Helpers/VMPalMachine.app", ["--mcp-library"]),
    ]

    /// Whether `process` is one of `nestedAppInstancesThatNeverBlock`.
    /// `bundlePrefix` ends in `/`.
    static func neverBlocks(_ process: RunningProcess, insideBundle bundlePrefix: String) -> Bool {
        let path = process.path
        guard path.hasPrefix(bundlePrefix), let argv = process.arguments else { return false }
        let relative = path.dropFirst(bundlePrefix.count)
        return nestedAppInstancesThatNeverBlock.contains {
            relative.hasPrefix($0.app + "/") && argv.dropFirst().elementsEqual($0.arguments)
        }
    }

    /// The VM a VMPal VM process runs: the folder after `--machine`, without
    /// `.vmpal` ("/Volumes/VM/macOS VM 1.vmpal" → "macOS VM 1"). Nil for any
    /// other process, and when its argv was not read. `bundlePrefix` ends in `/`.
    static func vmName(of process: RunningProcess, insideBundle bundlePrefix: String) -> String? {
        guard process.path.hasPrefix(bundlePrefix + "Contents/Helpers/VMPalMachine.app/"),
              let argv = process.arguments,
              let flag = argv.dropFirst().firstIndex(of: "--machine"), flag + 1 < argv.count
        else { return nil }
        let folder = URL(fileURLWithPath: argv[flag + 1])
        let name = folder.pathExtension == "vmpal"
            ? folder.deletingPathExtension().lastPathComponent : folder.lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// Whether `executablePath` is code from one of `nestedAppsThatExitWithHost`.
    /// `bundlePrefix` ends in `/`.
    static func exitsWithHost(executablePath: String, insideBundle bundlePrefix: String) -> Bool {
        guard executablePath.hasPrefix(bundlePrefix) else { return false }
        let relative = executablePath.dropFirst(bundlePrefix.count)
        return nestedAppsThatExitWithHost.contains { relative.hasPrefix($0 + "/") }
    }

    /// Whether `executablePath` is code from one of
    /// `nestedAppsTheHostReplacesOnLaunch`. `bundlePrefix` ends in `/`.
    static func replacedOnLaunch(executablePath: String, insideBundle bundlePrefix: String) -> Bool {
        guard executablePath.hasPrefix(bundlePrefix) else { return false }
        let relative = executablePath.dropFirst(bundlePrefix.count)
        return nestedAppsTheHostReplacesOnLaunch.contains { relative.hasPrefix($0 + "/") }
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

    /// The agents the bundle's own `Contents/Library/LaunchAgents/*.plist`
    /// describe with a `BundleProgram`, symlinks resolved as `proc_pidpath`
    /// resolves them. Only those that stay inside the bundle count. Unreadable
    /// plists are skipped, which leaves their agents refused.
    public static func launchAgents(inBundle bundlePath: String) -> [LaunchAgent] {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        let directory = root + "/Contents/Library/LaunchAgents"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        var agents: [LaunchAgent] = []
        for name in names.sorted() where name.hasSuffix(".plist") {
            guard let data = FileManager.default.contents(atPath: directory + "/" + name),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any],
                  let program = plist["BundleProgram"] as? String
            else { continue }
            let path = URL(fileURLWithPath: root + "/" + program).resolvingSymlinksInPath().path
            guard path.hasPrefix(root + "/") else { continue }
            // A `ProgramArguments` that is not a list of strings skips the
            // plist, like any unreadable one; only a missing key means none.
            let arguments: [String]
            if let value = plist["ProgramArguments"] {
                guard let strings = value as? [String] else { continue }
                arguments = strings
            } else {
                arguments = []
            }
            agents.append(LaunchAgent(program: path, arguments: arguments))
        }
        return agents
    }

    /// Every process this user can see, read fresh from the kernel. The
    /// activation policy comes from a NEW `NSRunningApplication` per pid, which
    /// reads the current value; the shared `NSWorkspace.runningApplications`
    /// snapshot goes stale in a process with no run loop, such as the CLI.
    ///
    /// A process whose executable `proc_pidpath` cannot name is not dropped: the
    /// kernel's answer is `ENOENT` once a swap has unlinked the executable a
    /// helper is still running from (#1783), so `launchedPath` falls back to the
    /// path `execve` was given, which `KERN_PROCARGS2` saved. Only a process the
    /// kernel will not name either — another user's, which no read can reach —
    /// is skipped, and that is on the record rather than silent.
    /// Automatic installs request unknown entries too: an uninspectable live PID
    /// cannot prove a shared bundle is closed. Manual callers keep their policy.
    public static func liveProcesses() -> [RunningProcess] {
        liveProcesses(includeUninspectable: false)
    }

    public static func liveProcesses(includeUninspectable: Bool) -> [RunningProcess] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var processes: [RunningProcess] = []
        if includeUninspectable, count >= capacity {
            // A full enumeration buffer cannot prove every PID was inspected.
            processes.append(RunningProcess(
                pid: 0, parentPID: 0, executablePath: nil, isRegularApp: false))
        }
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
            let kernelPath = length > 0
                ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                : nil
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let answered = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
            let parent = answered ? pid_t(info.pbi_ppid) : 0
            // The executable is unlinked and the kernel has no path for it; the
            // path execve was given lives on in the argv block. See #1783.
            var launchedPath: String?
            if kernelPath == nil, let saved = ClaudeCodeActivity.executablePathSavedAtExec(of: pid),
               !saved.isEmpty {
                launchedPath = resolvedPath(saved)
            }
            guard let path = kernelPath ?? launchedPath else {
                // Alive and unnamable is exactly the state the guard used to miss
                // silently; it cannot be placed in a bundle, so it is not a
                // blocker and there is nothing else to do with it.
                if answered {
                    Log.install.notice("nested-guard: pid \(pid, privacy: .public) is running but neither proc_pidpath nor KERN_PROCARGS2 names its executable")
                }
                if includeUninspectable {
                    let alive = answered || kill(pid, 0) == 0 || errno == EPERM
                    if alive {
                        processes.append(RunningProcess(
                            pid: pid, parentPID: parent, executablePath: nil, isRegularApp: false))
                    }
                }
                continue
            }
            // Only a process inside some `.app` below another `.app` can matter,
            // and asking LaunchServices or reading argv for every pid would be
            // wasted work.
            let nested = path.components(separatedBy: ".app/").count > 2
            let regular = nested
                && NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            processes.append(RunningProcess(
                pid: pid, parentPID: parent, executablePath: kernelPath, launchedPath: launchedPath,
                isRegularApp: regular,
                arguments: nested ? ClaudeCodeActivity.arguments(of: pid) : nil))
        }
        return processes
    }

    /// `path` with the symlinks above its last component resolved, as far as
    /// they exist. `proc_pidpath` resolves whole paths; the executable of a
    /// process a swap unlinked no longer exists, and Foundation's
    /// `resolvingSymlinksInPath` then returns such a path unchanged — so an app
    /// installed through a symlinked directory (`~/Applications` pointing
    /// elsewhere, say) would not match the bundle path `refusal` resolved.
    /// Resolving the deepest existing parent and appending the rest keeps the
    /// two spellings equal for exactly the process this guard has to place.
    static func resolvedPath(_ path: String) -> String {
        var ancestor = path
        var tail: [String] = []
        while !ancestor.isEmpty, !FileManager.default.fileExists(atPath: ancestor) {
            tail.append((ancestor as NSString).lastPathComponent)
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        guard !ancestor.isEmpty else { return path }
        var resolved = URL(fileURLWithPath: ancestor).resolvingSymlinksInPath().path
        if resolved.count > 1, resolved.hasSuffix("/") { resolved = String(resolved.dropLast()) }
        for component in tail.reversed() { resolved += "/" + component }
        return resolved
    }

    /// Why `bundle` cannot be replaced right now, or nil when it can.
    public static func refusal(
        _ bundle: URL, appName: String, processes: () -> [RunningProcess]
    ) -> NestedAppRunningError? {
        let path = bundle.resolvingSymlinksInPath().path
        let found = blockers(
            bundlePath: path, processes: processes(),
            launchAgents: launchAgents(inBundle: path))
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

    /// The button this refusal answers. A staged build is applied by the app's
    /// own updater when the app quits, so `relaunchStagedUpdate` asks the same
    /// question the install path does — and gets the same answer, because the
    /// nested app would keep running the old code either way. Only the closing
    /// clause differs: what the user clicks next.
    public enum NextStep: Sendable, Equatable, CaseIterable {
        case update
        case relaunch

        var tail: String {
            switch self {
            case .update: "then update again."
            case .relaunch: "then relaunch again."
            }
        }
    }

    static let keepsOldVersion = "would keep running the old version"
    static func closeWindow(_ step: NextStep) -> String { "close its window, \(step.tail)" }
    static func closeWindows(_ step: NextStep) -> String { "close their windows, \(step.tail)" }
    /// The fixed tail of the sentence for `Blocker.needsHostRunning`: the app's
    /// name sits between the two halves, so the fragment stops where it starts.
    static let openTheHost = keepsOldVersion + ". Open "

    /// In every message that names a VMPal VM: the user ends that refusal by
    /// shutting the VM down and closing its window, so
    /// `InstallFailureReport.isUserFixable` offers no report for it. The same
    /// for a helper only the host's next launch clears — the row already says
    /// to open the app, and this state is transient by nature. Any other nested
    /// app may be a background helper the user cannot quit, and a report is how
    /// such a case reaches us (BetterTouchTool's watchdog did), so the general
    /// sentence is not in here.
    static var userFixableFragments: [String] {
        NextStep.allCases.flatMap { [closeWindow($0), closeWindows($0)] } + [openTheHost]
    }

    public var errorDescription: String? { errorDescription(nextStep: .update) }

    /// The same refusal worded for `step`: `.update` for our own Update button,
    /// `.relaunch` for a Relaunch that only quits the app so its own updater
    /// applies the build it staged. The fix is the user's either way, so the
    /// sentences differ only in what they are told to click afterwards.
    public func errorDescription(nextStep step: NextStep) -> String {
        var sentences: [String] = []
        // A VMPal VM shut down from inside keeps its process until its window is
        // closed, so "Quit it" would leave the update refused.
        // "Open", not "running": a VM shut down with its window still open
        // blocks too.
        let vms = Array(Set(blockers.compactMap(\.vmName))).sorted()
        if !vms.isEmpty {
            let list = vms.map { "“\($0)”" }.joined(separator: ", ")
            sentences.append(vms.count == 1
                ? "\(list) is open in \(appName). Shut it down and \(Self.closeWindow(step))"
                : "\(list) are open in \(appName). Shut them down and \(Self.closeWindows(step))")
        }
        // Two kinds of advice, because they end differently: quit the helper, or
        // start the host so that its next launch replaces the helper. A name in
        // both is named once, in the sentence whose advice clears it. A refusal
        // mixing the kinds cannot happen with today's two lists — one match path
        // each, and no bundle ships both — and would need one combined sentence
        // rather than these two if it ever could.
        let hostNames = Set(blockers.filter { $0.vmName == nil && $0.needsHostRunning }.map(\.name))
        for needsHostRunning in [false, true] {
            let names = Array(Set(blockers
                .filter { $0.vmName == nil && $0.needsHostRunning == needsHostRunning }
                .map(\.name))
                .subtracting(needsHostRunning ? Set<String>() : hostNames)).sorted()
            guard !names.isEmpty else { continue }
            let list = names.joined(separator: ", ")
            let verb = names.count == 1 ? "is" : "are"
            let advice = needsHostRunning
                ? "Open \(appName), \(step.tail)"
                : "Quit \(names.count == 1 ? "it" : "them"), \(step.tail)"
            sentences.append("\(list) \(verb) running from inside \(appName) and \(Self.keepsOldVersion). \(advice)")
        }
        sentences.append("\(appName) was not updated.")
        return sentences.joined(separator: " ")
    }
}
