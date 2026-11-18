import Foundation
import Observation
import ServiceManagement
import DuoUpdaterCore
import os

/// Shared identifiers and the code-signing requirement the app pins the helper to.
enum HelperConfig {
    static let machServiceName = "com.duoupdater.helper"
    static let plistName = "com.duoupdater.helper.plist"
    /// The helper must be Apple-anchored, our helper bundle id, and signed by the
    /// **same team that signed this app** — the mirror of the check the helper runs
    /// on us. nil when our own team can't be read (unsigned/ad-hoc) or isn't a
    /// well-formed Team ID; the connection
    /// is then left unpinned-and-unusable rather than pinned to nothing. See
    /// `OwnTeamIdentifier`.
    static let helperRequirement =
        OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.helper")
}

/// App-facing controller for the privileged helper: registers the `SMAppService`
/// daemon, reports its approval status to the UI, and guides the user to the
/// Login Items pane when approval is pending.
@MainActor
@Observable
final class PrivilegedHelperClient {
    private let log = Logger(subsystem: "com.duoupdater.app", category: "helper")

    private(set) var status: SMAppService.Status?
    private(set) var answering: Bool?
    private var reachabilityProbe: Task<Void, Never>?
    private var approvalConfirmation: Task<Void, Never>?
    @ObservationIgnored private var recentApproval: (until: ContinuousClock.Instant, recheckAvailable: Bool)?

    private let readStatus: @Sendable () async -> SMAppService.Status
    private let probe: @Sendable (Bool) async -> Bool
    private let retryDelay: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Why the last `register()` failed, for the Diagnostics row to show. Registering
    /// is the only lever the app has — macOS grants no API to flip the approval
    /// switch itself — so when even that is refused the button appears to do nothing
    /// at all. Surfacing the reason is the difference between "this button is broken"
    /// and "macOS is refusing; here's what to do".
    private(set) var lastRegisterError: String?

    /// The registration in flight, so the next one waits for it. They used to block
    /// the main thread, which queued a second call behind the first; off the main
    /// thread, a second call would interleave its `unregister()` with the first
    /// one's `register()`. Waiting rather than dropping the second call matters to
    /// its caller: it reads `isEnabled` straight after, and a dropped call would
    /// leave that reading the status from before either registration ran.
    @ObservationIgnored private var statusOperation: Task<Void, Never>?

    init(
        readStatus: @escaping @Sendable () async -> SMAppService.Status = PrivilegedHelperClient.systemStatus,
        probe: @escaping @Sendable (Bool) async -> Bool = HelperShellRunner.isAnswering,
        retryDelay: Duration = .milliseconds(500),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.readStatus = readStatus
        self.probe = probe
        self.retryDelay = retryDelay
        self.now = now
        Task { await refreshStatusOffMain() }
    }

    /// True only once the user has approved the background item — the gate that
    /// decides whether App Store auto-update is offered (vs falling back to an
    /// "Update" button that just opens the store).
    ///
    /// Reads the cached `status`, which every path that can change it refreshes
    /// (`register()`, `reregister()`, `restartDaemon()`, and the window-appear and
    /// 1.5 s permission polls for an approval given in System Settings). It used to
    /// query `SMAppService` live, and the Diagnostics row read it from `body`: two
    /// main-thread XPC round trips per redraw, which the permission poll causes
    /// every 1.5 s. Measured 2026-10-11 on macOS 27.2 with the page open: 561 of
    /// 42,416 main-thread samples in 60 s, stalls of 17–32 ms.
    var isEnabled: Bool { status == .enabled }
    var isConfirmingApproval: Bool { approvalConfirmation != nil && status == .requiresApproval }
    var isCheckingReachability: Bool { reachabilityProbe != nil }
    private var wasRecentlyApproved: Bool {
        recentApproval.map { now() < $0.until } ?? false
    }

    /// Refresh `status` with the query off the main thread. `SMAppService.status` is a
    /// synchronous XPC round trip to `smd` — measured 16–40 ms per call on macOS 27 —
    /// and the window-appear and 1.5 s permission polls ran it on the main thread,
    /// inside a window's first layout.
    func refreshStatusOffMain() async {
        await serialized { self.apply(await self.readStatus()) }
    }

    nonisolated static func systemStatus() async -> SMAppService.Status {
        let plistName = HelperConfig.plistName
        return await offCooperativePool { SMAppService.daemon(plistName: plistName).status }
    }

    private func apply(_ current: SMAppService.Status) {
        let previous = status
        if current == .enabled { lastRegisterError = nil }
        guard current != previous else { return }

        if current == .requiresApproval, previous == .enabled, wasRecentlyApproved,
           recentApproval?.recheckAvailable == true {
            // Login Items can briefly report pending again just after approval.
            // Keep the update action during this bounded check, but gate the actual
            // install on an enabled reading. Consume the grace period on regression.
            recentApproval?.recheckAvailable = false
            approvalConfirmation = Task { [weak self, retryDelay] in
                for _ in 0..<3 {
                    do { try await Task.sleep(for: retryDelay) } catch { break }
                    guard let self else { return }
                    await self.refreshStatusOffMain()
                    if self.status != .requiresApproval { break }
                }
                self?.approvalConfirmation = nil
            }
        } else if current != .enabled, current != .requiresApproval {
            recentApproval = nil
        }

        status = current
        resetReachability()
        if current == .enabled, previous == .requiresApproval || previous == .notRegistered {
            if approvalConfirmation == nil {
                recentApproval = (now() + .seconds(5), true)
            }
            startReachabilityCheck(afterApproval: true)
        }
    }

    /// Verify live approval and return whether the install is in the initial
    /// approval window, when launchd may still be publishing the XPC service.
    func requireApprovalForInstall() async throws -> Bool {
        await refreshStatusOffMain()
        let confirmation = isConfirmingApproval ? approvalConfirmation : nil
        await confirmation?.value
        try Task.checkCancellation()
        guard isEnabled else { throw MASInstaller.MASError.helperNotApproved }
        return confirmation != nil || wasRecentlyApproved
    }

    func checkReachability(manual: Bool = false) {
        guard isEnabled, reachabilityProbe == nil else { return }
        startReachabilityCheck(afterApproval: wasRecentlyApproved, manual: manual)
    }

    private func startReachabilityCheck(afterApproval: Bool, manual: Bool = false) {
        reachabilityProbe = Task { [weak self, probe] in
            let began = ContinuousClock.now
            let result = await probe(afterApproval)
            if manual {
                try? await Task.sleep(until: began + .milliseconds(350), clock: .continuous)
            }
            guard !Task.isCancelled, let self else { return }
            self.answering = result
            self.reachabilityProbe = nil
        }
    }

    private func resetReachability() {
        reachabilityProbe?.cancel()
        reachabilityProbe = nil
        answering = nil
    }

    /// `register()` and the status it leaves behind, off the main thread: both are
    /// synchronous XPC round trips to `smd`.
    private nonisolated static func registerOffMain() async -> (error: (any Error)?, status: SMAppService.Status) {
        let plistName = HelperConfig.plistName
        return await offCooperativePool {
            let service = SMAppService.daemon(plistName: plistName)
            do {
                try service.register()
                return (nil, service.status)
            } catch {
                return (error, service.status)
            }
        }
    }

    private nonisolated static func unregisterOffMain() async {
        let plistName = HelperConfig.plistName
        await offCooperativePool { try? SMAppService.daemon(plistName: plistName).unregister() }
    }

    /// Register the daemon. First time, macOS surfaces it in Login Items as a
    /// pending background item the user must switch on; `register()` reports
    /// `.requiresApproval` in that case, and we send them to the pane.
    func register() async {
        await serialized { await self.performRegister() }
    }

    /// Order reads with registration changes so an earlier permission poll cannot
    /// overwrite the result of a newer query or registration.
    private func serialized(_ body: @escaping @MainActor @Sendable () async -> Void) async {
        let previous = statusOperation
        let next = Task {
            await previous?.value
            await body()
        }
        statusOperation = next
        await next.value
    }

    private func performRegister() async {
        let (failure, current) = await Self.registerOffMain()
        guard let error = failure else {
            lastRegisterError = nil
            apply(current)
            log.notice("helper register() ok — status \(current.rawValue, privacy: .public)")
            if status == .requiresApproval { openLoginItems() }
            return
        }
        apply(current)
        // Only when it left the helper off. A refusal on an item that is
        // already switched on changes nothing the user has to act on, and
        // posting a message would put red type next to the green "Enabled" —
        // the same contradiction `apply(_:)` exists to clear.
        lastRegisterError = current == .enabled ? nil : Self.explain(error, status: current)
        log.error("helper register() failed: \(error.localizedDescription, privacy: .public) — status \(current.rawValue, privacy: .public)")
        // A refusal is not proof of a damaged record. macOS also refuses while
        // a background item exists but sits switched OFF, and there the switch
        // — not a system-wide reset — is the whole cure: reported 2026-08-23,
        // register() was refused and turning DuoUpdater on by hand in Login
        // Items fixed it outright. `status` does not separate the two cases, so
        // open the pane for both; on the damaged one that costs a window.
        if Self.isRefusal(error) || status == .requiresApproval { openLoginItems() }
    }

    /// Whether macOS refused the registration outright — `SMAppService` reports
    /// this as a bare "Operation not permitted" (code 1) with no indication of
    /// which of its several causes applies.
    private static func isRefusal(_ error: Error) -> Bool {
        (error as NSError).code == 1
            || error.localizedDescription.localizedCaseInsensitiveContains("not permitted")
    }

    /// Turn a `SMAppService` failure into something a user can act on.
    ///
    /// A refusal has more than one cause and macOS names none of them, so the
    /// advice leads with the cheap, reversible fix (switch the item on in Login
    /// Items) and keeps the drastic one (a Background Task Management record macOS
    /// can no longer resolve — log line "fullPath is nil, container=(null)", curable
    /// only by `sfltool resetbtm`) as the fallback for when that changed nothing.
    /// Leading with the reset was wrong: it sent at least one user to reset every
    /// app's background approvals for a problem one toggle solved.
    private static func explain(_ error: Error, status: SMAppService.Status) -> String {
        guard isRefusal(error) else { return error.localizedDescription }
        if status == .requiresApproval {
            return String(localized: "macOS is waiting for your approval. Switch DuoUpdater on under “Allow in the Background” in Login Items & Extensions — it's open now.")
        }
        return String(localized: "macOS refused the registration. Switch DuoUpdater on under “Allow in the Background” in Login Items & Extensions — that alone usually fixes it. If it isn't listed there, or switching it on changes nothing, macOS's record of this background item is damaged and needs a system-level reset: run “sudo sfltool resetbtm” in Terminal and restart. That clears background-item approvals for every app, so you'll re-approve the others too.")
    }

    func unregister() async {
        await serialized {
            await Self.unregisterOffMain()
            self.apply(await self.readStatus())
        }
    }

    /// Unregister and register again, to rebuild a Background Task Management record
    /// that no longer resolves to the daemon. Used by the helper approval flow.
    func reregister() async {
        await serialized { await self.performReregister() }
    }

    private func performReregister() async {
        // Gentle first:
        // on a corrupt record `register()` is refused, and an unregister-first order
        // leaves the background item switched OFF with no way back from in-app.
        //
        // ⚠️ Do NOT "improve" this by tearing an already-enabled record down first,
        // however tempting: on a live service `register()` is a no-op, so it looks
        // like the gentle order simply cannot repair the enabled-but-dead case.
        // Tried exactly that on 2026-08-17 and it made a working machine worse —
        // `unregister()` DID dislodge the stale daemon, and then `register()` came
        // back "Operation not permitted", leaving the item switched off with no way
        // back short of `sudo sfltool resetbtm` + a restart. The enabled-but-dead
        // case needs the separate Restart Helper action.
        let (failure, current) = await Self.registerOffMain()
        guard let error = failure else {
            log.notice("helper re-registered — status \(current.rawValue, privacy: .public)")
            apply(current)
            if status == .requiresApproval { openLoginItems() }
            return
        }
        log.notice("helper register() refused (\(error.localizedDescription, privacy: .public)) — retrying via unregister")
        await Self.unregisterOffMain()
        await performRegister()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Kill the running daemon so launchd starts the copy that belongs to the app
    /// bundle currently on disk. The cure for a helper stranded by an in-place
    /// replacement — and the only one that works from inside the app.
    ///
    /// It needs an administrator prompt because the daemon runs as root and the
    /// registration APIs cannot reach it: `register()` on a live record does
    /// nothing, and `unregister()` first switches the background item off and then
    /// refuses to come back (both measured). Newer builds exit on their own when
    /// idle, but a helper already stranded by an older build predates that code —
    /// which is exactly who needs this button.
    ///
    /// - Returns: true when the daemon was restarted; false when the user
    ///   dismissed the authorization panel, which is a decision, not a failure.
    @discardableResult
    func restartDaemon() async -> Bool {
        // The authorization panel stays up for as long as the user takes to answer
        // it. The wait is awaited through `ChildProcess`, so neither the main
        // thread nor any other is held for it — a synchronous `waitUntilExit()`
        // here was a frozen window behind the password prompt. Callers guard
        // against a second press while this is in flight.
        let label = HelperConfig.machServiceName
        // nil means it ran and succeeded; a string is why it didn't.
        let failure: String?
        let shell = "/bin/launchctl kickstart -k system/\(label)"
        let script = "do shell script \"\(shell)\" with administrator privileges"
        do {
            // Runs to completion if this task is cancelled, as the uncancellable
            // hop it replaced did: a kickstart cut off halfway is a helper in an
            // unknown state. stdout was inherited before; it carries only the
            // shell's (empty) output.
            let outcome = try await ChildProcess.run(
                "/usr/bin/osascript", ["-e", script],
                standardOutput: .discard, onCancel: .runToCompletion)
            failure = outcome.terminationStatus == 0
                ? nil
                : String(data: outcome.standardError, encoding: .utf8) ?? "unknown error"
        } catch {
            failure = "could not run: \(error.localizedDescription)"
        }
        if let message = failure {
            // Dismissing the panel lands here too, and is a decision rather than a
            // fault: nothing ran, so nothing is claimed.
            log.error("helper kickstart failed: \(message, privacy: .public)")
            return false
        }
        log.notice("helper kickstarted — launchd will start the copy in the current bundle")
        resetReachability()
        await refreshStatusOffMain()
        return true
    }
}

/// Runs `mas install` over XPC. The version check and install use the same
/// authenticated connection, which is closed when the operation finishes.
struct HelperShellRunner: PrivilegedMASRunner {
    typealias MASError = MASInstaller.MASError

    let requireApproval: @Sendable () async throws -> Bool

    func installMAS(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32 {
        let afterApproval = try await requireApproval()
        let (version, connection) = try await Self.handshake(afterApproval: afterApproval)
        defer { connection.invalidate() }
        try HelperInstallGate.require(versionReply: version)
        try Task.checkCancellation()
        return try await Self.send(
            on: connection, adamID: adamID, uid: uid, gid: gid, userName: userName, logPath: logPath)
    }

    static func isAnswering(afterApproval: Bool) async -> Bool {
        do {
            let (_, connection) = try await handshake(afterApproval: afterApproval)
            connection.invalidate()
            return true
        } catch {
            return false
        }
    }

    private static func handshake(afterApproval: Bool) async throws -> (String, NSXPCConnection) {
        try await retryHandshake(
            afterApproval: afterApproval,
            isEnabled: { await PrivilegedHelperClient.systemStatus() == .enabled },
            probe: probeVersion)
    }

    /// Retry only a read-only version request that failed with XPC connection
    /// invalidation during the initial approval window. Each attempt opens a
    /// fresh pinned connection. A timeout or interruption is surfaced directly.
    static func retryHandshake<Value>(
        afterApproval: Bool,
        retryDelay: Duration = .milliseconds(500),
        isEnabled: () async -> Bool,
        probe: () async throws -> Value
    ) async throws -> Value {
        let retries = afterApproval ? 3 : 0
        for _ in 0..<retries {
            try Task.checkCancellation()
            do {
                return try await probe()
            } catch let error as MASError {
                guard case .helperCommunication(.handshake, .xpc(let domain, let code)) = error,
                      domain == NSCocoaErrorDomain, code == NSXPCConnectionInvalid else {
                    throw error
                }
                try await Task.sleep(for: retryDelay)
                guard await isEnabled() else { throw MASError.helperNotApproved }
            }
        }
        try Task.checkCancellation()
        return try await probe()
    }

    private static func probeVersion() async throws -> (String, NSXPCConnection) {
        guard let requirement = HelperConfig.helperRequirement else {
            throw MASError.helperCommunication(.handshake, .missingSigningRequirement)
        }
        let connection = NSXPCConnection(machServiceName: HelperConfig.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MASHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        do {
            let version = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                // A task group would wait for the silent XPC child even after
                // timing out. Race the deadline and the reply on one continuation.
                let once = ResumeGuard()
                let deadline = Task {
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    once.once {
                        continuation.resume(throwing: MASError.helperCommunication(.handshake, .timeout))
                    }
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    once.once {
                        deadline.cancel()
                        continuation.resume(throwing: MASError.helperCommunication(.handshake, .xpc(error)))
                    }
                }
                guard let helper = proxy as? MASHelperProtocol else {
                    once.once {
                        deadline.cancel()
                        continuation.resume(throwing: MASError.helperCommunication(.handshake, .proxyUnavailable))
                    }
                    return
                }
                helper.helperVersion { version in
                    once.once {
                        deadline.cancel()
                        continuation.resume(returning: version)
                    }
                }
            }
            return (version, connection)
        } catch {
            connection.invalidate()
            throw error
        }
    }

    private static func send(
        on connection: NSXPCConnection, adamID: Int, uid: Int, gid: Int, userName: String, logPath: String
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            let once = ResumeGuard()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.once {
                    // The helper may already have started mas. Never resend this
                    // request or re-register the service after this error.
                    continuation.resume(throwing: MASError.helperCommunication(.installRequest, .xpc(error)))
                }
            }
            guard let helper = proxy as? MASHelperProtocol else {
                once.once {
                    continuation.resume(throwing: MASError.helperCommunication(.installRequest, .proxyUnavailable))
                }
                return
            }
            helper.installMASApp(adamID: adamID, uid: uid, gid: gid,
                                 userName: userName, logPath: logPath) { status, message in
                once.once {
                    // The helper uses -1 for its own validation or process
                    // launch failures. Other statuses come from the launched command.
                    if status == -1 {
                        continuation.resume(throwing: MASError.helperCommunication(
                            .installRequest, .rejected(message ?? "no reason provided")))
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        }
    }
}

/// The production reader: the installed daemon, pinned to our team, and only
/// while the background item is enabled. `SMAppService.status` is a synchronous
/// XPC round trip to `smd`; `read` is nonisolated, so it runs off the main actor.
extension HelperPackageRunner {
    static let live = HelperPackageRunner(connect: {
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled,
              let requirement = HelperConfig.helperRequirement else { return nil }
        let connection = NSXPCConnection(machServiceName: HelperConfig.machServiceName, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        return connection
    })
}

extension HelperStagedVersionReader {
    static let live = HelperStagedVersionReader(connect: {
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled,
              let requirement = HelperConfig.helperRequirement
        else { return nil }
        let conn = NSXPCConnection(machServiceName: HelperConfig.machServiceName, options: .privileged)
        if #available(macOS 13.0, *) { conn.setCodeSigningRequirement(requirement) }
        return conn
    })
}

extension HelperProcessIdentityReader {
    static let live = HelperProcessIdentityReader(connect: {
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled,
              let requirement = HelperConfig.helperRequirement else { return nil }
        let connection = NSXPCConnection(machServiceName: HelperConfig.machServiceName, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        return connection
    })
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
