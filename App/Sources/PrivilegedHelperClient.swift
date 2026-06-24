import Foundation
import ServiceManagement
import DuoUpdaterCore
import os

/// Shared identifiers and the code-signing requirement the app pins the helper to.
enum HelperConfig {
    static let machServiceName = "com.duoupdater.helper"
    static let plistName = "com.duoupdater.helper.plist"
    /// The helper must be Apple-anchored, our helper bundle id, our team OU — the
    /// mirror of the check the helper runs on us.
    static let helperRequirement =
        "anchor apple generic and identifier \"com.duoupdater.helper\" "
        + "and certificate leaf[subject.OU] = \"RS59HDH7Y3\""
}

/// App-facing controller for the privileged helper: registers the `SMAppService`
/// daemon, reports its approval status to the UI, and guides the user to the
/// Login Items pane when approval is pending.
@MainActor
final class PrivilegedHelperClient: ObservableObject {
    private let log = Logger(subsystem: "com.duoupdater.app", category: "helper")

    @Published private(set) var status: SMAppService.Status

    private var service: SMAppService { SMAppService.daemon(plistName: HelperConfig.plistName) }

    init() {
        self.status = SMAppService.daemon(plistName: HelperConfig.plistName).status
    }

    /// True only once the user has approved the background item — the gate that
    /// decides whether App Store auto-update is offered (vs falling back to "Get").
    /// Queried live (not the cached `status`) so the gate is always current.
    var isEnabled: Bool { service.status == .enabled }

    func refreshStatus() {
        let current = service.status
        if current != status { status = current }
    }

    /// Register the daemon. First time, macOS surfaces it in Login Items as a
    /// pending background item the user must switch on; `register()` reports
    /// `.requiresApproval` in that case, and we send them to the pane.
    func register() {
        do {
            try service.register()
            log.notice("helper register() ok — status \(self.service.status.rawValue, privacy: .public)")
        } catch {
            log.error("helper register() failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        if status == .requiresApproval { openLoginItems() }
    }

    func unregister() {
        try? service.unregister()
        refreshStatus()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Runs `mas install` as root by handing a structured request to the privileged
/// helper over XPC — the passwordless replacement for the old
/// `osascript … with administrator privileges` escalation. Injected into
/// `MASInstaller` as its `PrivilegedMASRunner`.
///
/// Thread-safe: the NSXPCConnection it owns is itself thread-safe; the only
/// mutable state (the cached connection) is lock-guarded, hence `@unchecked
/// Sendable`. It is intentionally independent of the `@MainActor`
/// `PrivilegedHelperClient` so `MASInstaller` (an actor) can call it off-main.
final class HelperShellRunner: PrivilegedMASRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var cachedConnection: NSXPCConnection?

    func installMAS(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32 {
        // Fail fast (and let the UI show "Get"/guidance) if the helper isn't approved.
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled else {
            throw MASInstaller.MASError.helperNotApproved
        }
        let conn = connection()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            let guard1 = ResumeGuard()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                guard1.once { cont.resume(throwing: error) }
            }) as? MASHelperProtocol else {
                guard1.once { cont.resume(throwing: MASInstaller.MASError.helperNotApproved) }
                return
            }
            proxy.installMASApp(adamID: adamID, uid: uid, gid: gid,
                                userName: userName, logPath: logPath) { status, _ in
                guard1.once { cont.resume(returning: status) }
            }
        }
    }

    private func connection() -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let c = cachedConnection { return c }
        let c = NSXPCConnection(machServiceName: HelperConfig.machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: MASHelperProtocol.self)
        if #available(macOS 13.0, *) {
            c.setCodeSigningRequirement(HelperConfig.helperRequirement)
        }
        c.invalidationHandler = { [weak self] in self?.clearConnection() }
        c.interruptionHandler = { [weak self] in self?.clearConnection() }
        c.resume()
        cachedConnection = c
        return c
    }

    private func clearConnection() {
        lock.lock(); cachedConnection = nil; lock.unlock()
    }
}

/// Single-fire guard so a continuation can't be resumed twice when both the XPC
/// reply and the connection's error handler are in play.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func once(_ body: () -> Void) {
        lock.lock()
        let go = !fired
        fired = true
        lock.unlock()
        if go { body() }
    }
}
