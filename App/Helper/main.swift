import Foundation

// Entry point for the privileged helper daemon (`com.duoupdater.helper`). Runs as
// root under launchd, registered by the main app via `SMAppService.daemon`. It
// hosts an XPC listener on the Mach service declared in the daemon plist,
// validates each connecting client's code signature (see HelperPeerGate), and
// vends `MASHelperProtocol`.
//
// No osascript, no password: the app sends a structured install request, the
// helper (already root) runs `mas install` and streams progress to a log file the
// app tails. The whole reason this process exists is to be the one-time-approved
// root that replaces the per-install authorization prompt.

/// Exit once nobody is talking to us.
///
/// The daemon plist asks launchd to start this on demand and nothing else — no
/// `KeepAlive`, no `RunAtLoad` — so exiting costs nothing: the next XPC
/// connection starts it again. Staying alive forever is what costs.
///
/// A helper that never exits keeps holding launchd's slot after the app bundle
/// around it has been replaced — by a Sparkle self-update, or by a rebuild during
/// development — and launchd then never spawns the NEW binary. The background
/// item still reads "enabled" while every App Store install times out talking to
/// a copy that no longer matches the app. Re-registering does not fix it
/// (measured: `register()` on a live record is a no-op), and tearing the
/// registration down to force a re-resolve switches the background item off with
/// no way back from in-app (also measured, on a working machine). That left a
/// reboot as the only cure. Exiting when idle makes the situation heal itself:
/// the stale copy goes away on its own, and the next install starts the current
/// one.
///
/// Live connections keep the daemon up. Accepted package operations also hold
/// it independently, so a client's death cannot trigger idle exit mid-install.
enum IdleExit {
    /// Long enough that the several installs of one "Update All" share a single
    /// process, short enough that a replaced bundle heals within about a minute.
    private static let window: DispatchTimeInterval = .seconds(60)

    private static let lock = NSLock()
    // Both are guarded by `lock` on every access, which is what makes the
    // `unsafe` opt-out honest: the compiler can't see the lock, we can.
    nonisolated(unsafe) private static var liveConnections = 0
    nonisolated(unsafe) private static var livePackageWork = 0
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?

    static func connectionOpened() {
        lock.lock(); defer { lock.unlock() }
        liveConnections += 1
        timer?.cancel()
        timer = nil
    }

    static func connectionClosed() {
        lock.lock(); defer { lock.unlock() }
        liveConnections = max(0, liveConnections - 1)
        if liveConnections == 0, livePackageWork == 0 { armLocked() }
    }

    static func packageWorkStarted() {
        lock.lock(); defer { lock.unlock() }
        livePackageWork += 1
        timer?.cancel()
        timer = nil
    }

    static func packageWorkFinished() {
        lock.lock(); defer { lock.unlock() }
        livePackageWork = max(0, livePackageWork - 1)
        if liveConnections == 0, livePackageWork == 0 { armLocked() }
    }

    /// Armed at launch too: a helper launchd started but nobody ever talked to
    /// (a probe that failed its signature check, say) shouldn't linger either.
    static func arm() {
        lock.lock(); defer { lock.unlock() }
        if liveConnections == 0, livePackageWork == 0 { armLocked() }
    }

    private static func armLocked() {
        timer?.cancel()
        let scheduled = DispatchSource.makeTimerSource(queue: .global())
        scheduled.schedule(deadline: .now() + window)
        scheduled.setEventHandler {
            lock.lock()
            guard liveConnections == 0, livePackageWork == 0 else { lock.unlock(); return }
            // Keep admission locked through exit: a newly accepted package
            // cannot start between the idle decision and process termination.
            NSLog("duo-helper: idle for 60s — exiting so launchd starts a fresh copy on demand")
            exit(0)
        }
        scheduled.resume()
        timer = scheduled
    }
}

let listener = NSXPCListener(machServiceName: HelperService.machServiceName)
// Installs the client code-signing requirement on the listener, attaches itself
// as delegate and resumes the listener. Held here because the listener's
// delegate reference is weak.
let gate = HelperPeerGate.install(
    on: listener,
    interface: NSXPCInterface(with: MASHelperProtocol.self),
    exportedObject: { HelperService(clientIdentity: $0,
        packageWorkStarted: IdleExit.packageWorkStarted, packageWorkFinished: IdleExit.packageWorkFinished) },
    connectionOpened: { IdleExit.connectionOpened() },
    connectionClosed: { IdleExit.connectionClosed() })
IdleExit.arm()
RunLoop.main.run()
