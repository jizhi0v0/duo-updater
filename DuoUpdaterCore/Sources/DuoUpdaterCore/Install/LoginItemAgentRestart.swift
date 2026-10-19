import Darwin
import Foundation

/// Restarts a login-item agent nested in a bundle we just replaced, for the apps
/// whose recipe asks for it (`AppRecipeSet.loginItemAgentRestarts`).
///
/// The case is Secretive. Its `Contents/Library/LoginItems/SecretAgent.app` is
/// an `SMAppService` login item, the SSH agent every `ssh` call talks to, and it
/// runs while the host app is closed. Measured on 2026-10-19 (audit,
/// 「一键安装」): after a swap the old agent keeps signing until its
/// `SecretAgentInputParser.xpc` exits idle and is relaunched from the new
/// bundle; the new XPC then refuses the old agent on its code-signing
/// requirement and every signing request hangs. Killing the old agent made
/// launchd relaunch it from the new bundle, and signing worked again.
///
/// Nothing else covers it: `AppRestarter` only quits and reopens `.regular`
/// nested apps, and `NestedAppGuard` lets a login item through because refusing
/// on one would block its app for good. Most login items are harmless to leave
/// stale until the next login, so this is opt-in per app rather than a rule
/// over every login item: a recipe names the agent once it has been shown to
/// break.
///
/// **How**, in two halves around the swap:
///
/// - `snapshot` runs just before the bundle is replaced. It reads the declared
///   ids from the agents in the bundle's own `Contents/Library/LoginItems/` and
///   records each process running one of their executables, with its start
///   time. Taken before the swap because that is when "running from inside this
///   bundle" can be read off the executable path: afterwards the old file has
///   been moved aside or deleted, and what the kernel reports for it is not
///   something to match on.
/// - `restart` runs once the swap has landed. It sends `SIGTERM` to each
///   recorded process that is still the same process (pid *and* start time, so
///   a reused pid is never signalled), waits for it to exit, then waits for a
///   new process running the agent's executable from the live bundle. That one
///   is launchd's doing — the job `SMAppService` registered — not ours: we
///   never launch the agent, so an agent the user had not enabled stays off.
///   Both waits are bounded, and an agent that did not come back is reported.
///
/// An agent outside the swapped bundle is never touched, even with a declared
/// bundle id: only processes whose executable was inside this bundle's
/// `LoginItems` at snapshot time are signalled.
public enum LoginItemAgentRestart {

    /// One process, as much as this needs.
    public struct Process: Equatable, Sendable {
        public let pid: pid_t
        /// Microseconds since the epoch. With `pid`, identifies the process:
        /// pids are reused, start times are not.
        public let startTime: UInt64
        /// As `proc_pidpath` spells it: symlinks resolved, `/private` kept.
        /// Empty when the kernel has no path for it — the case for the very
        /// process this exists for: an agent whose executable the swap deleted
        /// (`proc_pidpath` fails with ENOENT). Such a process is still listed,
        /// so it can be matched on pid and start time and signalled.
        public let executablePath: String

        public init(pid: pid_t, startTime: UInt64, executablePath: String) {
            self.pid = pid
            self.startTime = startTime
            self.executablePath = executablePath
        }
    }

    /// One declared agent, found in the bundle about to be replaced.
    public struct Agent: Equatable, Sendable {
        public let bundleID: String
        /// `…/Host.app/Contents/Library/LoginItems/Agent.app`, symlinks resolved.
        public let bundlePath: String
        /// Its processes running when the snapshot was taken. Empty when the
        /// agent was not running, which leaves it alone.
        public let processes: [Process]
    }

    /// What `restart` did for one agent.
    public enum Result: Equatable, Sendable {
        /// The old process exited and a new one runs from the live bundle.
        case restarted(bundleID: String, newPID: pid_t)
        /// The old process did not exit after `SIGTERM`. Nothing else was tried.
        case stillRunning(bundleID: String)
        /// The old process exited and nothing relaunched it within the wait.
        case notRelaunched(bundleID: String)

        public var bundleID: String {
            switch self {
            case .restarted(let id, _), .stillRunning(let id), .notRelaunched(let id): id
            }
        }

        public var succeeded: Bool {
            if case .restarted = self { return true }
            return false
        }
    }

    /// Host bundle id (lowercased) → the agent bundle ids to restart.
    static let agentsByHost: [String: [String]] = {
        var table: [String: [String]] = [:]
        for (host, agents) in AppRecipeIndex.merged(
            \.loginItemAgentRestarts, into: "LoginItemAgentRestart.agentsByHost") {
            table[host.lowercased(), default: []] += agents
        }
        return table
    }()

    /// What a notice calls an agent from `Outcome.agentsNotRestarted`: the last
    /// component of its bundle id (`com.maxgoedjen.Secretive.SecretAgent` →
    /// `SecretAgent`), the id itself when it has no dot or ends in one. Taken
    /// from the id rather than the agent's `Info.plist` because the agent being
    /// reported is the one that may not be there to read.
    public static func displayName(forAgentBundleID bundleID: String) -> String {
        guard let last = bundleID.split(separator: ".", omittingEmptySubsequences: false).last,
              !last.isEmpty else { return bundleID }
        return String(last)
    }

    /// The agents to restart for `app`, or nil when its recipe names none —
    /// every app but a few.
    public static func declaredAgents(for app: InstalledApp) -> [String]? {
        guard let id = app.recipeBundleID?.lowercased() else { return nil }
        return agentsByHost[id]
    }

    // MARK: - Before the swap

    /// The declared agents in `bundle` and their running processes, or an empty
    /// list when there is nothing to restart (none declared, none present).
    public static func snapshot(
        bundle: URL, agentBundleIDs: [String],
        processes: () -> [Process] = liveProcesses
    ) -> [Agent] {
        guard !agentBundleIDs.isEmpty else { return [] }
        let found = agentBundles(inBundle: bundle, bundleIDs: agentBundleIDs)
        guard !found.isEmpty else { return [] }
        let live = processes()
        return found.map { agent in
            Agent(bundleID: agent.bundleID, bundlePath: agent.path,
                  processes: live.filter { isExecutable($0.executablePath, ofAgentAt: agent.path) })
        }
    }

    /// Each `.app` directly in `bundle`'s `Contents/Library/LoginItems/` whose
    /// `CFBundleIdentifier` is one of `bundleIDs` (case-insensitively).
    static func agentBundles(inBundle bundle: URL, bundleIDs: [String]) -> [(bundleID: String, path: String)] {
        let wanted = Set(bundleIDs.map { $0.lowercased() })
        let loginItems = URL(fileURLWithPath: kernelPath(bundle.path), isDirectory: true)
            .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: loginItems.path) else { return [] }
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".app") else { return nil }
            let path = loginItems.appendingPathComponent(name, isDirectory: true)
            guard let id = plistBundleID(path), wanted.contains(id.lowercased()) else { return nil }
            return (id, path.path)
        }
    }

    /// `path` spelled the way `proc_pidpath` reports executables under it:
    /// `realpath`, which keeps `/private` where `resolvingSymlinksInPath`
    /// strips it (`/private/tmp/…` → `/tmp/…`), so the two would never match.
    /// The path as given when it cannot be resolved.
    static func kernelPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Read from the plist each time rather than through `Bundle`, so the
    /// answer is always the bundle on disk now.
    private static func plistBundleID(_ app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// Whether `executablePath` is a binary in the agent's own `Contents/MacOS`.
    /// Not anything below the agent: an `.xpc` it embeds is started and stopped
    /// by launchd on demand and is not ours to signal.
    static func isExecutable(_ executablePath: String, ofAgentAt agentPath: String) -> Bool {
        executablePath.hasPrefix(agentPath + "/Contents/MacOS/")
    }

    // MARK: - After the swap

    /// Restart every agent in `snapshot` that had a process running. Agents
    /// that were not running are skipped and produce no result.
    ///
    /// - Parameter exitTimeout: how long the old process gets to exit after
    ///   `SIGTERM`.
    /// - Parameter relaunchTimeout: how long launchd gets, after that, to start
    ///   the agent from the new bundle.
    public static func restart(
        _ snapshot: [Agent],
        processes: @Sendable () -> [Process] = liveProcesses,
        signal: @Sendable (pid_t, Int32) -> Void = { _ = kill($0, $1) },
        exitTimeout: Duration = .seconds(5),
        relaunchTimeout: Duration = .seconds(10),
        pollInterval: Duration = .milliseconds(200)
    ) async -> [Result] {
        var results: [Result] = []
        for agent in snapshot where !agent.processes.isEmpty {
            let old = Set(agent.processes.map(Identity.init))
            // Only the processes still alive *as the same process*: a pid that
            // has since exited and been reused by something else is not signalled.
            for process in processes() where old.contains(Identity(process)) {
                signal(process.pid, SIGTERM)
            }
            let exited = await poll(timeout: exitTimeout, interval: pollInterval) {
                !processes().contains { old.contains(Identity($0)) }
            }
            guard exited else {
                Log.install.error(
                    "login-item agent \(agent.bundleID, privacy: .public): still running after SIGTERM — left running")
                results.append(.stillRunning(bundleID: agent.bundleID))
                continue
            }
            var newPID: pid_t?
            _ = await poll(timeout: relaunchTimeout, interval: pollInterval) {
                newPID = processes().first {
                    !old.contains(Identity($0)) && isExecutable($0.executablePath, ofAgentAt: agent.bundlePath)
                }?.pid
                return newPID != nil
            }
            if let newPID {
                Log.install.notice(
                    "login-item agent \(agent.bundleID, privacy: .public): restarted from the new bundle (pid \(newPID, privacy: .public))")
                results.append(.restarted(bundleID: agent.bundleID, newPID: newPID))
            } else {
                Log.install.error(
                    "login-item agent \(agent.bundleID, privacy: .public): exited and was not relaunched within \(relaunchTimeout, privacy: .public)")
                results.append(.notRelaunched(bundleID: agent.bundleID))
            }
        }
        return results
    }

    private struct Identity: Hashable {
        let pid: pid_t
        let startTime: UInt64
        init(_ process: Process) { pid = process.pid; startTime = process.startTime }
    }

    /// True as soon as `condition` holds, false once `timeout` has passed
    /// without it. A cancelled task would turn the sleep into a spin, which is
    /// why `InstallCoordinator` runs this in an unstructured task; the timeout
    /// bounds it either way.
    private static func poll(
        timeout: Duration, interval: Duration, _ condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if condition() { return true }
            if clock.now >= deadline { return false }
            // cancel-ok: bounded by `timeout`; InstallCoordinator runs this in an unstructured task no cancel reaches
            try? await Task.sleep(for: interval)
        }
    }

    /// Every process this user can see, read from the kernel — not
    /// `NSWorkspace`, whose list goes stale in a process without a run loop
    /// (the CLI).
    public static func liveProcesses() -> [Process] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var processes: [Process] = []
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            let length = max(0, Int(proc_pidpath(pid, &buffer, UInt32(buffer.count))))
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { continue }
            let start = UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
            let path = String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            processes.append(Process(pid: pid, startTime: start, executablePath: path))
        }
        return processes
    }
}
