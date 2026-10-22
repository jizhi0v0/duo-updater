import AppKit
import CoreGraphics
import Foundation

/// An app held at macOS's first-open prompt ("X is an app downloaded from the
/// Internet. Are you sure you want to open it?").
///
/// Until the user clicks Open the process exists — `NSRunningApplication`
/// lists it, so a restart finds it — but it is held: it does not answer a quit
/// request, and the restart used to wait that out and call it "likely a save
/// prompt". Measured 2026-10-22 on macOS 27.2 with a cask fresh from
/// `brew install --cask` (quarantine `0181`, no user-approved bit), at t+4 s
/// and t+12 s: `isFinishedLaunching` false and no window of its own in
/// `CGWindowListCopyWindowInfo(.optionAll)`. After the user clicked Open, the
/// same pid read finished and owned 7 windows; a running app stopped with
/// SIGSTOP (the stand-in for "won't quit") read finished, 7 windows.
///
/// Both conditions, never either alone. Normal launches measured the same day,
/// three runs each under load: Hoppscotch finished at 0.67–0.75 s with its
/// first window at 0.67–0.70 s, but ImageOptim's first window (0.25–0.28 s)
/// came *before* it finished (0.37–0.40 s) — so "not finished" alone reads a
/// normal launch as held, and "no windows" alone reads every hidden or
/// windowless app as held. UNVERIFIED: heavy apps (Xcode), which may stay
/// unfinished and windowless for several seconds of a normal launch; a restart
/// asked for then is told the app hasn't finished opening, which is true.
///
/// Judged per process, not over the screen: with two apps held at once only
/// one prompt window was on screen, while each app's own reading was right.
///
/// Known gap, from Apple's documentation of `isFinishedLaunching`: "Some
/// applications do not post this notification … and so are never reported as
/// finished launching" — those that do not rely on `NSApplication`. Such an
/// app with no window of its own would read as held for as long as it runs.
/// No such app is known among what DuoUpdater restarts; not measured.
public enum OpenConfirmationHold {

    /// The test itself: not finished launching, and no window of its own.
    public static func isHeld(finishedLaunching: Bool, windows: Int) -> Bool {
        !finishedLaunching && windows == 0
    }

    /// One process's reading, as `isHeld` takes it.
    public struct Reading: Sendable, Equatable {
        public let finishedLaunching: Bool
        public let windows: Int
        public init(finishedLaunching: Bool, windows: Int) {
            self.finishedLaunching = finishedLaunching
            self.windows = windows
        }
    }

    /// Whether any of these processes is held. One held instance is enough to
    /// stop a restart before its quit: the quit would reach the held one too.
    public static func anyHeld(_ readings: [Reading]) -> Bool {
        readings.contains { isHeld(finishedLaunching: $0.finishedLaunching, windows: $0.windows) }
    }

    /// `anyHeld` over live processes. The window count is only read for a
    /// process that has not finished launching — the common case costs no
    /// window-server query.
    public static func anyHeld(_ instances: [NSRunningApplication]) -> Bool {
        anyHeld(instances.map { instance in
            let finished = instance.isFinishedLaunching
            return Reading(
                finishedLaunching: finished,
                windows: finished ? 0 : StagedRelaunch.ownedWindowCount(pids: [instance.processIdentifier]))
        })
    }
}
