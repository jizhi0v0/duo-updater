import Foundation

/// Restrictions inherited by every child of an unattended install, including
/// commit tasks. Manual updates retain their existing behavior.
public enum AutomaticInstall {
    @TaskLocal public static var active = false
    @TaskLocal public static var diagnostic: (@Sendable (AutomaticProcessDiagnostic) -> Void)?
    @TaskLocal public static var permission: (@Sendable () async -> Bool)?

    /// Synchronous policy read at the filesystem exchange, after staging and dispatch.
    @TaskLocal public static var commitPermission: (@Sendable () -> Bool)?

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
        guard active else { return }
        try checkProcesses(at: app.path,
            processes: NestedAppGuard.liveProcesses(includeUninspectable: true, diagnostic: diagnostic))
    }

    static func checkProcesses(at bundle: URL, processes: [NestedAppGuard.RunningProcess]) throws {
        for process in processes where hasRunningProcess(at: bundle, processes: [process]) {
            diagnostic?(.init(kind: .targetRunning, pid: process.pid, parentPID: process.parentPID))
        }
        guard !processes.isEmpty,
              processes.allSatisfy({ $0.executablePath != nil || $0.launchedPath != nil }) else {
            throw Deferred("Automatic update deferred: running processes could not be checked completely.")
        }
        guard !hasRunningProcess(at: bundle, processes: processes) else {
            throw Deferred("Automatic update deferred: the app or one of its helpers is running.")
        }
    }
}
