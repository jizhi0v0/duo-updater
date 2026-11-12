import Foundation

/// Restrictions inherited by every child of an unattended install, including
/// commit tasks. Manual updates retain their existing behavior.
public enum AutomaticInstall {
    @TaskLocal public static var active = false
    @TaskLocal public static var diagnostic: (@Sendable (AutomaticProcessDiagnostic) -> Void)?
    @TaskLocal public static var permission: (@Sendable () async -> Bool)?

    /// Synchronous policy read at the filesystem exchange, after staging and dispatch.
    @TaskLocal public static var commitPermission: (@Sendable () -> Bool)?

    /// Set when an unattended pass updates a running app the user allowed: the
    /// app is quit only once its update is downloaded and verified, right before
    /// the swap's commit (`quitPlannedApp`), so it is closed for the swap alone,
    /// not for the download. Until then the checks that refuse a
    /// running app or a running nested app let it pass (`appQuitsBeforeApply`);
    /// once the quit has run, every check applies in full again.
    @TaskLocal public static var quitBeforeApply: QuitBeforeApply?

    public final class QuitBeforeApply: @unchecked Sendable {
        private let lock = NSLock()
        private var ran = false
        private let quit: @Sendable () async throws -> Void

        /// `quit` quits the app, or throws `Deferred` when it should stay up.
        public init(_ quit: @escaping @Sendable () async throws -> Void) { self.quit = quit }

        /// Whether the quit is still to come.
        public var pending: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !ran
        }

        /// Quit once; later calls (a patch retried with the full archive) do nothing.
        /// Marked as run before the quit, so a quit that throws still leaves
        /// every check in force.
        public func run() async throws {
            guard claim() else { return }
            try await quit()
        }

        private func claim() -> Bool {
            lock.withLock {
                defer { ran = true }
                return !ran
            }
        }
    }

    /// Quit the running app an unattended pass planned to quit (`quitBeforeApply`),
    /// once, right before the swap of `target` commits. Before the commit, not in
    /// it: the install journal marks the commit before the body runs, and a crash
    /// during a quit that can take half a minute would then read as an install
    /// cut off mid-swap. A cancel between the quit and the commit makes the
    /// commit refuse, and the host reopens the app. A target that needs an
    /// administrator is deferred first: the swap would defer it after the quit.
    /// The swap's own checks (`preExchangeCheck`) then refuse whatever did not quit.
    public static func quitPlannedApp(before target: URL) async throws {
        guard active, let quit = quitBeforeApply, quit.pending else { return }
        try await checkPermission()
        if InPlaceSwap.needsElevatedReplace(target: target) {
            throw Deferred("Automatic update needs administrator authorization.")
        }
        try await quit.run()
    }

    /// True while a running app is still to be quit before the swap: its own
    /// processes are expected until then.
    public static var appQuitsBeforeApply: Bool {
        active && quitBeforeApply?.pending == true
    }

    public final class PermissionSnapshot: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        public init() {}
        public func set(_ value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            self.value = value
        }
        public var allowed: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    public static func checkPermission() async throws {
        guard active else { return }
        guard let permission, await permission() else {
            throw Deferred("Automatic updates are paused.")
        }
    }

    public struct Deferred: LocalizedError {
        public let reason: String
        public init(_ reason: String) { self.reason = reason }
        public var errorDescription: String? { reason }
    }

    /// Only policy/process refusals are converted; integrity and I/O errors
    /// remain failures, and manual callers retain their original error types.
    static func classifiedRefusal(_ error: Error) -> Error {
        guard active, error is OneClickGateRegistry.Withheld || error is NestedAppRunningError else {
            return error
        }
        return Deferred(error.localizedDescription)
    }

    public static func eventResult(_ outcome: InstallAttemptOutcome) -> (status: String, reason: String?) {
        switch outcome {
        case .installed: return ("installed", nil)
        case .deferred(let reason): return ("deferred", reason)
        default: return ("notInstalled", nil)
        }
    }

    public static func backupPermitsInstall(_ outcome: InstallCoordinator.BackupOutcome) -> Bool {
        outcome == .saved
    }

    public static func supports(_ route: InstallCoordinator.Route) -> Bool {
        route == .vendor || route == .sparkle
    }

    public static func hasRunningProcess(
        at bundle: URL, processes: [NestedAppGuard.RunningProcess]
    ) -> Bool {
        let prefix = bundle.resolvingSymlinksInPath().path + "/"
        return processes.contains {
            [$0.executablePath, $0.launchedPath].compactMap { $0 }.contains {
                NestedAppGuard.resolvedPath($0).hasPrefix(prefix)
            }
        }
    }

    public static func check(_ app: InstalledApp) throws {
        try processCheck(app)()
    }

    /// Process inspection can need a bounded XPC read. Keep it off the UI and
    /// cooperative pool, carrying the same policy into the Dispatch hop.
    public static func checkAsync(_ app: InstalledApp) async throws {
        try await offCooperativePool(processCheck(app))
    }

    /// A fresh check whose dependencies survive the final exchange's Dispatch
    /// hop. No process/path result is cached: a service may start during download.
    public static func processCheck(_ app: InstalledApp) -> @Sendable () throws -> Void {
        let enabled = active
        let capture = diagnostic
        let resolve = NestedAppGuard.privilegedExecutablePath
        let quit = quitBeforeApply
        return {
            guard enabled else { return }
            try NestedAppGuard.$privilegedExecutablePath.withValue(resolve) {
                try $diagnostic.withValue(capture) {
                    try checkProcesses(at: app.path,
                        processes: NestedAppGuard.liveProcesses(includeUninspectable: true, diagnostic: capture),
                        allowRunningApp: quit?.pending == true)
                }
            }
        }
    }

    public static func backgroundProcessReason(_ processes: [NestedAppGuard.RunningProcess]) -> String {
        let names = Set(processes.compactMap { $0.executablePath ?? $0.launchedPath }
            .map { ($0 as NSString).lastPathComponent }).sorted().joined(separator: ", ")
        return "Background processes are still running (\(names)). Automatic updating is paused for this app."
    }

    static func checkProcesses(at bundle: URL, processes: [NestedAppGuard.RunningProcess],
                               allowRunningApp: Bool = appQuitsBeforeApply) throws {
        for process in processes where hasRunningProcess(at: bundle, processes: [process]) {
            diagnostic?(.targetRunning(process, in: bundle, among: processes))
        }
        guard !processes.isEmpty,
              processes.allSatisfy({ $0.executablePath != nil || $0.launchedPath != nil }) else {
            throw Deferred("Automatic update deferred: running processes could not be checked completely.")
        }
        guard allowRunningApp || !hasRunningProcess(at: bundle, processes: processes) else {
            throw Deferred("Automatic update deferred: the app or one of its helpers is running.")
        }
    }
}
