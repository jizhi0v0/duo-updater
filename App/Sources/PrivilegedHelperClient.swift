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

    /// Why the last `register()` failed, for the Diagnostics row to show. Registering
    /// is the only lever the app has — macOS grants no API to flip the approval
    /// switch itself — so when even that is refused the button appears to do nothing
    /// at all. Surfacing the reason is the difference between "this button is broken"
    /// and "macOS is refusing; here's what to do".
    @Published private(set) var lastRegisterError: String?

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
            lastRegisterError = nil
            log.notice("helper register() ok — status \(self.service.status.rawValue, privacy: .public)")
        } catch {
            lastRegisterError = Self.explain(error)
            log.error("helper register() failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        if status == .requiresApproval { openLoginItems() }
    }

    /// Turn a `SMAppService` failure into something a user can act on. The one worth
    /// naming is a Background Task Management record macOS can no longer resolve
    /// (its log line: "fullPath is nil, container=(null)"): registering is refused
    /// with a bare "Operation not permitted", the Login Items switch has no effect on
    /// it, and nothing an app is allowed to do will clear it — only a system-level
    /// reset will.
    private static func explain(_ error: Error) -> String {
        let message = error.localizedDescription
        guard (error as NSError).code == 1 || message.localizedCaseInsensitiveContains("not permitted")
        else { return message }
        return "macOS refused the registration — its record of this background item "
            + "is damaged. Fixing it needs a system-level reset: run "
            + "“sudo sfltool resetbtm” in Terminal and restart. That clears background-item "
            + "approvals for every app, so you'll re-approve the others too."
    }

    func unregister() {
        try? service.unregister()
        refreshStatus()
    }

    /// Unregister and register again, to rebuild a Background Task Management record
    /// that reads as approved but no longer resolves to the daemon (see
    /// `HelperShellRunner`'s repair path). Surfaced in Diagnostics so the user can
    /// clear it without first walking into a failed App Store update.
    func reregister() {
        // Gentle first, for the reason spelled out in `HelperShellRunner`'s repair:
        // on a corrupt record `register()` is refused, and an unregister-first order
        // leaves the background item switched OFF with no way back from in-app.
        do {
            try service.register()
            log.notice("helper re-registered — status \(self.service.status.rawValue, privacy: .public)")
            refreshStatus()
            if status == .requiresApproval { openLoginItems() }
            return
        } catch {
            log.notice("helper register() refused (\(error.localizedDescription, privacy: .public)) — retrying via unregister")
        }
        try? service.unregister()
        register()
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
    private let log = Logger(subsystem: "com.duoupdater.app", category: "helper")
    private let lock = NSLock()
    private var cachedConnection: NSXPCConnection?

    func installMAS(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32 {
        // Fail fast (and let the UI show "Get"/guidance) if the helper isn't approved.
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled else {
            throw MASInstaller.MASError.helperNotApproved
        }
        do {
            return try await send(adamID: adamID, uid: uid, gid: gid,
                                  userName: userName, logPath: logPath)
        } catch let error as NSError where Self.isConnectionFailure(error) {
            // Approved but unreachable — the Background Task Management record can
            // survive the app bundle being replaced (an in-place update, `make
            // install`) while losing the resolved path to the daemon:
            //   "FATAL ERROR - fullPath is nil, container=(null) … disposition=[enabled, allowed]"
            // launchd then never spawns the helper, yet `status` still reads
            // `.enabled`, so the guard above lets the call through and every App
            // Store update fails with "Couldn't communicate with a helper
            // application". Nothing in the UI could fix it either: the Enable button
            // only shows while NOT enabled. Re-registering rebuilds the record, so
            // do it once and retry rather than stranding the user.
            log.error("helper unreachable (\(error.code, privacy: .public)) — re-registering and retrying once")
            clearConnection()
            repairRegistration()
            do {
                return try await send(adamID: adamID, uid: uid, gid: gid,
                                      userName: userName, logPath: logPath)
            } catch let retryError as NSError where Self.isConnectionFailure(retryError) {
                // Still unreachable after rebuilding the record — most likely macOS
                // dropped the background item back to "pending approval". Report it
                // as `helperNotApproved` rather than letting the raw XPC message
                // ("Couldn't communicate with a helper application") reach the row:
                // that text tells the user nothing they can act on, whereas this case
                // is the one the UI knows how to guide out of.
                throw MASInstaller.MASError.helperNotApproved
            }
        }
    }

    /// The two ways an XPC call fails when the peer never came up: Cocoa's
    /// `NSXPCConnectionInvalid` (4097, "Couldn't communicate with a helper
    /// application") and `NSXPCConnectionInterrupted` (4099) if it died mid-call.
    private static func isConnectionFailure(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && (error.code == 4097 || error.code == 4099)
    }

    /// Tear the daemon's registration down and put it back, so BTM re-resolves the
    /// path to the helper inside the *current* app bundle. If macOS decides this
    /// needs the user's blessing again it lands as `.requiresApproval`, which the
    /// Diagnostics row already surfaces as an "Enable…" button.
    private func repairRegistration() {
        let service = SMAppService.daemon(plistName: HelperConfig.plistName)
        // Re-register FIRST, without tearing anything down. `register()` on a live
        // service is a no-op, so this costs nothing when the record is fine — and it
        // can't make a broken one worse. That matters: when BTM's record is corrupt
        // (`fullPath is nil, container=(null)`), `register()` is refused with
        // "Operation not permitted", so an unregister-first repair *disables* the
        // item and then can't put it back, turning "approved but unreachable" into
        // "switched off and unfixable from here". Only fall back to the destructive
        // order once the gentle one has failed.
        do {
            try service.register()
            log.notice("helper re-registered — status \(service.status.rawValue, privacy: .public)")
            return
        } catch {
            log.notice("helper register() refused (\(error.localizedDescription, privacy: .public)) — retrying via unregister")
        }
        try? service.unregister()
        do {
            try service.register()
            log.notice("helper re-registered after unregister — status \(service.status.rawValue, privacy: .public)")
        } catch {
            // Both orders refused: the BTM record is corrupt beyond what an app is
            // allowed to touch. The caller turns this into the approval prompt, which
            // is the only lever left on this side.
            log.error("helper re-register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func send(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32 {
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
