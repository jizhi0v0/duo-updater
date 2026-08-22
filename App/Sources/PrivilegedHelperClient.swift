import Foundation
import ServiceManagement
import DuoUpdaterCore
import os

/// Shared identifiers and the code-signing requirement the app pins the helper to.
enum HelperConfig {
    static let machServiceName = "com.duoupdater.helper"
    static let plistName = "com.duoupdater.helper.plist"
    /// The helper must be Apple-anchored, our helper bundle id, and signed by the
    /// **same team that signed this app** — the mirror of the check the helper runs
    /// on us. nil when our own team can't be read (unsigned/ad-hoc); the connection
    /// is then left unpinned-and-unusable rather than pinned to nothing. See
    /// `OwnTeamIdentifier`.
    static let helperRequirement =
        OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.helper")
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
    /// decides whether App Store auto-update is offered (vs falling back to an
    /// "Update" button that just opens the store).
    /// Queried live (not the cached `status`) so the gate is always current.
    var isEnabled: Bool { service.status == .enabled }

    func refreshStatus() {
        let current = service.status
        if current != status { status = current }
        // A registration failure explains why the helper ISN'T on. Once it is, the
        // explanation is not just stale but contradictory — the pane showed a green
        // "Enabled" next to red text telling the user to reset their whole system.
        // Any path that reaches `.enabled` (a later register, the user approving in
        // Login Items, a reset that cleared a damaged record) retires the message.
        if current == .enabled { lastRegisterError = nil }
    }

    /// Register the daemon. First time, macOS surfaces it in Login Items as a
    /// pending background item the user must switch on; `register()` reports
    /// `.requiresApproval` in that case, and we send them to the pane.
    func register() {
        do {
            try service.register()
            lastRegisterError = nil
            refreshStatus()
            log.notice("helper register() ok — status \(self.status.rawValue, privacy: .public)")
            if status == .requiresApproval { openLoginItems() }
            return
        } catch {
            refreshStatus()
            // Only when it left the helper off. A refusal on an item that is
            // already switched on changes nothing the user has to act on, and
            // posting a message would put red type next to the green "Enabled" —
            // the same contradiction `refreshStatus()` exists to clear.
            lastRegisterError = status == .enabled ? nil : Self.explain(error, status: status)
            log.error("helper register() failed: \(error.localizedDescription, privacy: .public) — status \(self.status.rawValue, privacy: .public)")
            // A refusal is not proof of a damaged record. macOS also refuses while
            // a background item exists but sits switched OFF, and there the switch
            // — not a system-wide reset — is the whole cure: reported 2026-08-23,
            // register() was refused and turning Duo Updater on by hand in Login
            // Items fixed it outright. `status` does not separate the two cases, so
            // open the pane for both; on the damaged one that costs a window.
            if Self.isRefusal(error) || status == .requiresApproval { openLoginItems() }
        }
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
            return String(localized: "macOS is waiting for your approval. Switch Duo Updater on under “Allow in the Background” in Login Items & Extensions — it's open now.")
        }
        return String(localized: "macOS refused the registration. Switch Duo Updater on under “Allow in the Background” in Login Items & Extensions — that alone usually fixes it. If it isn't listed there, or switching it on changes nothing, macOS's record of this background item is damaged and needs a system-level reset: run “sudo sfltool resetbtm” in Terminal and restart. That clears background-item approvals for every app, so you'll re-approve the others too.")
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
        //
        // ⚠️ Do NOT "improve" this by tearing an already-enabled record down first,
        // however tempting: on a live service `register()` is a no-op, so it looks
        // like the gentle order simply cannot repair the enabled-but-dead case.
        // Tried exactly that on 2026-08-17 and it made a working machine worse —
        // `unregister()` DID dislodge the stale daemon, and then `register()` came
        // back "Operation not permitted", leaving the item switched off with no way
        // back short of `sudo sfltool resetbtm` + a restart. The enabled-but-dead
        // case has no in-app cure; `MASError.helperUnresponsive` says so honestly.
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
        // Off the main thread on purpose: the authorization panel stays up for as
        // long as the user takes to answer it, and `waitUntilExit()` would hold the
        // main thread for exactly that long — a frozen window behind the password
        // prompt. Callers guard against a second press while this is in flight.
        let label = HelperConfig.machServiceName
        // nil means it ran and succeeded; a string is why it didn't.
        let failure: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            let shell = "/bin/launchctl kickstart -k system/\(label)"
            let script = "do shell script \"\(shell)\" with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errPipe = Pipe()
            process.standardError = errPipe
            do { try process.run() } catch {
                return "could not run: \(error.localizedDescription)"
            }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return String(data: errData, encoding: .utf8) ?? "unknown error"
            }
            return nil
        }.value
        if let message = failure {
            // Dismissing the panel lands here too, and is a decision rather than a
            // fault: nothing ran, so nothing is claimed.
            log.error("helper kickstart failed: \(message, privacy: .public)")
            return false
        }
        log.notice("helper kickstarted — launchd will start the copy in the current bundle")
        // The install path owns its own XPC connection and drops a dead one on the
        // first failure, so there is nothing to tear down from here.
        refreshStatus()
        return true
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
        // Fail fast (and let the UI fall back to the store redirect / guidance) if
        // the helper isn't approved.
        guard SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled else {
            throw MASInstaller.MASError.helperNotApproved
        }
        // Prove the helper actually answers BEFORE handing it the install. The
        // install call's reply doesn't arrive until `mas` has finished — minutes for
        // an Office update — so it can't carry a timeout of its own, and a helper
        // that never launches makes it hang forever instead of failing: the row sits
        // at 0%, the single-slot App Store gate is never released, and every queued
        // App Store update behind it waits on a reply that will never come. Observed
        // exactly that: `launchd: service inactive: com.duoupdater.helper` repeating
        // every 10s while the batch sat frozen, no error anywhere.
        // A silent peer lands here, not in the `isConnectionFailure` catch below: the
        // connection is accepted and the reply simply never comes. Replacing the app
        // bundle in place (a self-update, `make install`) leaves the OLD helper process
        // holding launchd's slot while BTM still reads `.enabled`, so every App Store
        // install timed out and — until the error was split — told the user to go
        // switch on something that was already on.
        //
        // No repair is attempted for it, deliberately: `register()` cannot re-resolve a
        // live record and the unregister-first alternative was measured to leave the
        // item switched off and unregisterable (see `repairRegistration`). So this
        // throws `helperUnresponsive`, whose message names the one thing that does
        // work, rather than burning a second 10s timeout pretending otherwise.
        try await ensureReachable()
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
                try await ensureReachable()
                return try await send(adamID: adamID, uid: uid, gid: gid,
                                      userName: userName, logPath: logPath)
            } catch let retryError as NSError where Self.isConnectionFailure(retryError) {
                // Still unreachable after rebuilding the record. Which advice is right
                // depends on where the rebuild left the item: back in "pending
                // approval" means Login Items really is the answer, while still
                // `.enabled` means it is on and simply not coming up — say that
                // instead of sending the user to a switch they'd find already flipped.
                // Either way, never let the raw XPC message ("Couldn't communicate
                // with a helper application") reach the row; it names nothing the user
                // can act on.
                throw SMAppService.daemon(plistName: HelperConfig.plistName).status == .enabled
                    ? MASInstaller.MASError.helperUnresponsive
                    : MASInstaller.MASError.helperNotApproved
            }
        }
    }

    /// How long a trivial round-trip may take before we call the helper dead. Long
    /// enough for launchd to cold-start a daemon on a busy machine, short enough
    /// that a user watching a stuck row gets an answer.
    private static let reachabilityTimeout = Duration.seconds(10)

    /// Round-trip `helperVersion` — the cheapest call in the protocol — and give up
    /// if nothing comes back in time. A registered-but-unlaunchable daemon accepts
    /// the connection and simply never replies, which no error handler ever fires
    /// for, so a timeout is the only way to tell "working on it" from "never coming".
    /// Does the helper actually answer right now? The same round-trip an install
    /// makes, exposed so the Diagnostics page can tell "switched on" from
    /// "switched on and working" — a distinction that otherwise only surfaces as a
    /// failed update, and that a replaced app bundle creates routinely.
    func isAnswering() async -> Bool {
        do { try await ensureReachable(); return true } catch { return false }
    }

    private func ensureReachable() async throws {
        let answered = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { [self] in await probeVersion() }
            group.addTask {
                try await Task.sleep(for: Self.reachabilityTimeout)
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard answered else {
            // Drop the connection: a fresh one is the only way a later attempt can
            // bind to a helper that did eventually come up.
            clearConnection()
            log.error("helper did not answer within \(Self.reachabilityTimeout, privacy: .public) — treating as unavailable")
            throw MASInstaller.MASError.helperUnresponsive
        }
    }

    /// One `helperVersion` round-trip: true if the helper answered, false if the
    /// connection errored out. Never returns on a peer that stays silent — that's
    /// what `ensureReachable`'s timeout is for.
    private func probeVersion() async -> Bool {
        let conn = connection()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = ResumeGuard()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
                once.once { cont.resume(returning: false) }
            }) as? MASHelperProtocol else {
                once.once { cont.resume(returning: false) }
                return
            }
            proxy.helperVersion { _ in once.once { cont.resume(returning: true) } }
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
        // ⚠️ An ALREADY-enabled record is the one case this repair cannot fix, and it
        // must not try: `register()` is a no-op on a live service, but tearing the
        // record down first to force a re-resolve is strictly worse. Measured
        // 2026-08-17 — `unregister()` did dislodge the stale daemon, then `register()`
        // returned "Operation not permitted" and the background item was left switched
        // off, recoverable only by `sudo sfltool resetbtm` + a restart. Enabled-but-dead
        // is reported as `MASError.helperUnresponsive` instead of being "repaired".
        //
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
        guard let requirement = HelperConfig.helperRequirement else {
            // We can't read our own team, so we can't state who the helper must be.
            // Hand back an invalidated connection: every call on it fails, which is
            // the correct outcome — talking to an unpinned root daemon is worse than
            // not talking to one.
            //
            // Not cached, but that costs only a wasted allocation per attempt:
            // `OwnTeamIdentifier.current` is resolved once per process, so this can
            // never start succeeding later. Leaving it uncached keeps `cachedConnection`
            // meaning "a usable connection" rather than holding a dead one.
            log.error("helper: own team identifier unavailable — refusing to connect unpinned")
            c.invalidate()
            return c
        }
        if #available(macOS 13.0, *) {
            c.setCodeSigningRequirement(requirement)
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
