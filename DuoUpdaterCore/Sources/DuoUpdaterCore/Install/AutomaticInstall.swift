import Foundation

/// Restrictions inherited by every child of an unattended install, including
/// commit tasks. Manual updates retain their existing behavior.
public enum AutomaticInstall {
    @TaskLocal public static var active = false
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
                $0.hasPrefix(prefix)
            }
        }
    }

    public static func check(_ app: InstalledApp) throws {
        guard active else { return }
        let processes = NestedAppGuard.liveProcesses()
        guard !processes.isEmpty else {
            throw Deferred("Automatic update deferred: running processes could not be checked.")
        }
        guard !hasRunningProcess(at: app.path, processes: processes) else {
            throw Deferred("Automatic update deferred: the app or one of its helpers is running.")
        }
    }
}
