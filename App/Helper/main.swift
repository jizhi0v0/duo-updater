import Foundation

// Entry point for the privileged helper daemon (`com.duoupdater.helper`). Runs as
// root under launchd, registered by the main app via `SMAppService.daemon`. It
// hosts an XPC listener on the Mach service declared in the daemon plist,
// validates each connecting client's code signature (see HelperService), and
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
/// It cannot interrupt work: a connection stays open for the whole of an install
/// — its reply doesn't arrive until `mas` has finished, which can be minutes — so
/// a running install is a live connection and the count never reaches zero
/// underneath it.
enum IdleExit {
    /// Long enough that the several installs of one "Update All" share a single
    /// process, short enough that a replaced bundle heals within about a minute.
    private static let window: DispatchTimeInterval = .seconds(60)

    private static let lock = NSLock()
    // Both are guarded by `lock` on every access, which is what makes the
    // `unsafe` opt-out honest: the compiler can't see the lock, we can.
    nonisolated(unsafe) private static var liveConnections = 0
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
        if liveConnections == 0 { armLocked() }
    }

    /// Armed at launch too: a helper launchd started but nobody ever talked to
    /// (a probe that failed its signature check, say) shouldn't linger either.
    static func arm() {
        lock.lock(); defer { lock.unlock() }
        if liveConnections == 0 { armLocked() }
    }

    private static func armLocked() {
        timer?.cancel()
        let scheduled = DispatchSource.makeTimerSource(queue: .global())
        scheduled.schedule(deadline: .now() + window)
        scheduled.setEventHandler {
            lock.lock()
            let stillIdle = liveConnections == 0
            lock.unlock()
            // A connection that arrived while the timer was in flight cancels the
            // exit — re-check rather than trusting the schedule.
            guard stillIdle else { return }
            NSLog("duo-helper: idle for 60s — exiting so launchd starts a fresh copy on demand")
            exit(0)
        }
        scheduled.resume()
        timer = scheduled
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperService.machServiceName)
listener.delegate = delegate
listener.resume()
IdleExit.arm()
RunLoop.main.run()
