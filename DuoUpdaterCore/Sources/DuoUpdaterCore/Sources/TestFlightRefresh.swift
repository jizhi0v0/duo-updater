import AppKit
import Foundation

/// Asks TestFlight to refresh the local store `TestFlightInventory` reads, by
/// launching it **into the background** while it is not running.
///
/// Why this exists at all: that store is written by TestFlight.app and by nothing
/// else, and the background activity that would refresh it (`com.apple.appstored.
/// activities.TestFlightExtensionSyncActivity`) is registered `Require Device
/// Inactivity`. On a Mac someone is using, Duet answers `MNP` — measured
/// 2026-09-09, every 30–60s for a whole day, while a build sat available for
/// hours and the store never learned it (#478).
///
/// Measured 2026-09-09, three trials, two machines:
///
/// | trial | action | result |
/// |---|---|---|
/// | cold + `-g` + deep link | quit, then open `itms-beta://…/v1/app/<adamId>` | store written in **11s**, foreground untouched |
/// | cold + `-g`, no URL | quit, then just launch the bundle | store written in **9s** |
/// | cold + `-g`, over ssh, second Mac | same | **8s**, 3 rows → 111 rows |
///
/// and the two negatives that fix the shape of the rule:
///
///   * **already running + background launch does nothing.** The URL is delivered,
///     one request goes out, and two minutes later the store still has not learned
///     the build that was already published. That is why ``Outcome/alreadyRunning``
///     is a refusal rather than a launch: there is nothing this can do for a
///     running TestFlight except steal the user's focus.
///   * **already running + foreground activation works in 3s** — and is exactly the
///     thing we will not do behind someone's back.
///
/// The deep link is not needed (trial 2), so this does not use one: with no URL
/// there is no `/join/<code>` shape nearby to reach for by mistake, and joining a
/// beta is an account-level side effect.
///
/// ⚠️ **This is an explicit, user-initiated action.** It starts an app the user did
/// not start — one that creates a window (measured: `count windows` = 1, behind
/// everything else) and lingers until macOS's automatic termination collects it.
/// Do not put it on a periodic check: the system deliberately declines to do this
/// work while the device is in use, and doing it for the system on a timer would
/// be overriding that decision on the user's behalf.
public struct TestFlightRefresh: Sendable {

    /// What one attempt did. Every case is a thing the caller may want to say out
    /// loud — nothing here is a silent no-op.
    public enum Outcome: Sendable, Equatable {
        /// Launched, and the store changed within the deadline.
        case refreshed(after: Duration)
        /// Launched, but the store never changed. Usually "already current"; it can
        /// also be a sync that did not happen, and this deliberately does not claim
        /// to know which — the store carries no "last synced" of its own.
        case launchedWithoutChange
        /// TestFlight was already running, so a background launch would do nothing.
        case alreadyRunning
        /// No TestFlight on this Mac.
        case notInstalled
        /// LaunchServices refused or timed out.
        case launchFailed
    }

    /// Bundle id of the app that owns the store.
    public static let bundleID = "com.apple.TestFlight"

    /// How long to wait for the store to change after the launch. Generous against
    /// the measured 8–11s, because those were three warm-ish samples on two Macs
    /// and the work is a network round trip.
    public static let defaultDeadline: Duration = .seconds(30)

    /// How often to look at the store while waiting.
    public static let pollInterval: Duration = .milliseconds(500)

    /// How long the store has to hold still before the refresh counts as finished.
    ///
    /// ⚠️ **The first write is not the sync.** Measured 2026-09-09, polling every
    /// 500ms from a cold background launch: the log was written at +0.3s, +1s,
    /// +2s (twice), and then again at **+7s**, after which it stayed quiet for the
    /// remaining 13s of the window. Returning on the first change reported success
    /// in 0.5s — before the network round trip had landed — and a caller that read
    /// the store on that signal would read it pre-sync. That is the same
    /// "wrote ≠ learned" trap this whole area is full of (#478), and it shipped in
    /// the first draft of this file.
    ///
    /// Six seconds because the interval has to be **longer than the gap inside the
    /// burst**: in that trace the launch writes stopped at +2s and the sync write
    /// landed at +7s, so anything up to five seconds would have declared the
    /// refresh finished during the pause and reported the +1s write. The first fix
    /// used three and did exactly that — caught by the unit case, not by hand.
    /// One trace, so the margin is deliberate rather than fitted.
    public static let settleInterval: Duration = .seconds(6)

    // Effects, injected so the decision table is testable without launching
    // anything or waiting on a real clock.
    let locate: @Sendable () -> URL?
    let isRunning: @Sendable () -> Bool
    let launch: @Sendable (URL) async -> Bool
    /// A value that changes when the store is written. Production passes the
    /// write-ahead log's modification date; the main file's is not enough on its
    /// own, since SQLite in WAL mode leaves it alone for long stretches.
    let storeStamp: @Sendable () -> Date?
    let sleep: @Sendable (Duration) async -> Void

    public init(
        locate: @escaping @Sendable () -> URL? = Self.locateTestFlight,
        isRunning: @escaping @Sendable () -> Bool = Self.testFlightIsRunning,
        launch: @escaping @Sendable (URL) async -> Bool = { await AppRestarter.launchApp($0, activates: false) },
        storeStamp: @escaping @Sendable () -> Date? = Self.storeStamp,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.locate = locate
        self.isRunning = isRunning
        self.launch = launch
        self.storeStamp = storeStamp
        self.sleep = sleep
    }

    /// Run one attempt. Never throws: every failure is an `Outcome` the caller can
    /// print, because "we tried to refresh and could not" is information the user
    /// needs before reading a version number.
    public func run(
        deadline: Duration = defaultDeadline,
        settle: Duration = settleInterval
    ) async -> Outcome {
        guard let bundle = locate() else { return .notInstalled }
        // Checked BEFORE the launch, not after: this is the case the measurement
        // says we cannot serve, and launching anyway would leave the caller
        // believing a refresh happened.
        guard !isRunning() else { return .alreadyRunning }

        let before = storeStamp()
        guard await launch(bundle) else { return .launchFailed }

        var waited: Duration = .zero
        var seen = before
        var lastChange: Duration?
        while waited < deadline {
            await sleep(Self.pollInterval)
            waited += Self.pollInterval
            let now = storeStamp()
            // `!=` rather than `>`: a checkpoint can shorten or replace the log, and
            // any change at all means TestFlight wrote, which is the question.
            if now != seen {
                seen = now
                lastChange = waited
                continue
            }
            // Quiet for long enough after a write — see `settleInterval` for why
            // the first write is not the answer.
            if let lastChange, waited - lastChange >= settle {
                return .refreshed(after: lastChange)
            }
        }
        // Ran out of time. It still changed, so say so rather than pretending
        // nothing happened; the caller gets the last moment we saw it move.
        if let lastChange { return .refreshed(after: lastChange) }
        return .launchedWithoutChange
    }

    // MARK: - Live effects

    /// Where TestFlight is, or nil when it is not installed.
    public static let locateTestFlight: @Sendable () -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Whether a TestFlight **process** exists.
    ///
    /// `runningApplications(withBundleIdentifier:)` and not the `NSWorkspace`
    /// snapshot: that one is a stale cache in a process with no run loop, which is
    /// exactly what the CLI is. Measured 2026-09-09 that this query agrees with
    /// `pgrep` in both directions — 1 entry carrying the real pid while TestFlight
    /// ran, 0 the moment it quit — including after macOS's automatic termination,
    /// where LaunchServices can still list the app as "open" with no process
    /// behind it.
    public static let testFlightIsRunning: @Sendable () -> Bool = {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Modification date of the store's write-ahead log.
    public static let storeStamp: @Sendable () -> Date? = {
        let wal = URL(fileURLWithPath: TestFlightInventory.defaultDatabaseURL.path + "-wal")
        let attrs = try? FileManager.default.attributesOfItem(atPath: wal.path)
        return attrs?[.modificationDate] as? Date
    }
}
