import AppKit
import Foundation

/// Asks TestFlight to refresh the local store `TestFlightInventory` reads.
///
/// Why this exists at all: that store is written by TestFlight.app and by nothing
/// else, and the background activity that would refresh it (`com.apple.appstored.
/// activities.TestFlightExtensionSyncActivity`) is registered `Require Device
/// Inactivity`. On a Mac someone is using, Duet answers `MNP` — measured
/// 2026-09-09, every 30–60s for a whole day, while a build sat available for
/// hours and the store never learned it (#478).
///
/// TestFlight asks the server on exactly two occasions — a cold launch, and
/// becoming active — and **this starts its own instance**, so it always gets the
/// first one. A cold launch carries its own become-active, that activation belongs
/// to our process, and our process is launched hidden and never activated. The
/// user's instance, if they have one, is not touched at all.
///
/// **Why not reach the instance the user already has.** Because reaching it means
/// making it active, and on macOS making an app active means giving it the
/// foreground: `activates` is documented as making the system "activate the app and
/// bring it to the foreground", one sentence rather than two switches. A background
/// launch request delivered to a running instance does nothing — measured four
/// times, the store still had not learned an already-published build two minutes
/// later. So the only way to reach it was a brief activation, and that was visible:
/// measured 2026-09-10 with two independent samplers, the menu bar belonged to
/// TestFlight for the hold plus ~10ms, and its window was raised to the top and
/// **left** there. The private `kCPSNoWindows` flag did not prevent either on macOS
/// 26. A second instance makes the whole question go away.
///
/// **What that was measured to cost.** Four trials on two Macs, 2026-09-10: the
/// front process never became TestFlight (13,000+ samples at 6ms, with the user's
/// own app switches as a positive control), the store learned builds it did not
/// have (1316→1317 and 1315→1317), and it came through every integrity check —
/// `integrity_check`, foreign keys, duplicate rows, orphaned rows, row counts, and
/// Core Data's `Z_PRIMARYKEY` ledger against the real `MAX(Z_PK)`, which is where
/// two processes allocating primary keys concurrently would show.
///
/// ⚠️ **Not measured, and worth knowing:** whether the user's own instance shows a
/// stale view of its own UI after we rewrite the store underneath it, and whether
/// any of this disturbs an install already running inside it.
///
/// The deep link is not needed (a trial used no URL at all), so this does not use
/// one: with no URL there is no `/join/<code>` shape nearby to reach for by
/// mistake, and joining a beta is an account-level side effect.
///
/// ⚠️ **A refresh queues TestFlight's own automatic updates.** All three paths that
/// reload the catalogue run the same handler, and that handler is where the
/// auto-update jobs are enqueued; there is no "fetch without queueing" switch.
/// Measured 2026-09-10: 42 activations enqueued 210 jobs, and a control that simply
/// opened TestFlight by hand produced a byte-identical log signature — so this is
/// not something duo does *to* the user, it is what opening TestFlight does.
/// Queueing is not installing: a job needs the per-app Automatic Updates setting
/// and is executed separately by `appstoreagent` on Apple's own schedule, and none
/// of those 210 were claimed while this was measured. Say "may queue", never
/// "will install".
///
/// ⚠️ **And those 210 did not accumulate — they were enqueue attempts, which
/// `appstored` dedups.** Measured 2026-09-12: its install queue is a real table
/// (`app_install` in `~/Library/Caches/com.apple.appstoreagent/storeSystem.db`)
/// carrying a `cancel_if_duplicate` column and a `DetectDuplicateRequestTask`, with
/// log paths for `Skipped duplicate job`, `Skipping duplicate install`, and
/// `Queue check found duplicate items in the queue`. The dedup fired on all seven of
/// that day's real TestFlight installs (`Ignoring duplicate resumption request`), and
/// the table held 0 rows before and after each of four back-to-back hidden launches.
/// The `TestFlightExtensionSyncActivity` registration behaves the same way — it is
/// keyed by identifier, and the binary's own string for re-registering it is
/// "Resetting activity for TestFlight extension due to changed intervals".
///
/// So the cost of repeating this is **the fetch, not a backlog**: 694–705 KB in and
/// 29–34 KB out per launch across those four, with no caching between them (one ran
/// two minutes after the previous and fetched 704 KB anyway). That is what
/// `TestFlightSyncPolicy` rations.
///
/// ⚠️ **This starts an app the user did not start, so no caller may run it on a
/// bare timer.** The system deliberately declines this work while the device is in
/// use, and doing it for the system every few minutes would be overriding that
/// decision on the user's behalf — at the 5-minute default, 288 launches a day.
///
/// What that ruled out was a *timer*, and for a while it was read as ruling out
/// everything but the button. #539 measured the cost of that reading: 20 hours
/// after the last sync, 3 of this Mac's 8 TestFlight rows could not be bounded by
/// the store, and a build published but not yet installed reads as "up to date"
/// with nothing local able to witness it. So there are now three callers, and the
/// two automatic ones are rationed by `TestFlightSyncPolicy` rather than by a
/// clock:
///
/// - `duo check --refresh-testflight` and the menu's refresh button
///   (`RefreshIntent.userRequested`) — the user asking, unconditionally.
/// - A round that saw the store fall provably behind, once per `(bundle, build)`.
/// - A round that finds nothing has written the store in six hours.
///
/// Read `TestFlightSyncPolicy` before adding a fourth. What must not come back is a
/// call that runs every round.
public struct TestFlightRefresh: Sendable {

    /// What one attempt did. Every case is a thing the caller may want to say out
    /// loud — nothing here is a silent no-op.
    public enum Outcome: Sendable, Equatable {
        /// The store changed and then held still for ``settleInterval`` — the
        /// sync finished, and the caller may read the store.
        case refreshed(after: Duration)
        /// The store changed but the deadline arrived before it ever went quiet,
        /// so whether the sync finished is **unknown**. Deliberately not
        /// ``refreshed``: a caller that reads the store on this signal can read it
        /// mid-sync, which is exactly what happened on 2026-09-10 — the refresh
        /// announced success at +10s, the data landed at +40s, and the check in the
        /// same process printed the *previous* build as up to date.
        case changedWithoutSettling(lastChange: Duration)
        /// The instance ran and the store never changed. Usually "already
        /// current"; it can also be a sync that did not happen, and this
        /// deliberately does not claim to know which — the store carries no "last
        /// synced" of its own.
        ///
        /// There is one such case rather than one per route because there is now
        /// one route: whether or not the user has TestFlight open, this starts its
        /// own instance.
        case noChange
        /// TestFlight's store shows no account testing any beta here — signed out,
        /// most likely — so nothing was started. There is nothing to fetch for such
        /// an account, and starting TestFlight only asks the user to sign in:
        /// reported 2026-09-10, a refresh while signed out made the hidden instance
        /// bounce in the Dock for attention. The store only learns of a sign-out the
        /// next time TestFlight runs, so the first refresh after one still starts it.
        ///
        /// Only when the App Store sign-in cannot be read: the store is just as late
        /// to learn of a sign-in, so a known sign-in outranks it.
        case accountTestsNothing
        /// This Mac's Apple Account is not signed in to the App Store, which is what
        /// TestFlight signs in with, so nothing was started — it would only ask the
        /// user to sign in (`AppStoreSignIn`). Unlike `accountTestsNothing`, this is
        /// known right after a sign-out, before TestFlight has run again.
        case notSignedIn
        /// No TestFlight on this Mac.
        case notInstalled
        /// LaunchServices refused or timed out.
        case launchFailed
    }

    /// Bundle id of the app that owns the store.
    public static let bundleID = "com.apple.TestFlight"

    /// How long to wait for the store to change.
    ///
    /// ⚠️ **This was 30s, and 30s is inside the measured spread.** Time from the
    /// trigger to the data actually landing, measured 2026-09-10 across five valid
    /// trials on two Macs (three cold launches, two activations): **2s, 4s, 6s,
    /// 10s, and 40s**. The 40s trial is the one that broke: the loop ran its full
    /// 30 seconds, never saw the store settle, and returned `.refreshed` anyway on
    /// the strength of a write at +4s that turned out to be preliminary.
    ///
    /// 90s is not fitted to that 40 — it is roughly twice it, because five samples
    /// establish that the work is a network round trip whose tail is long, not
    /// where the tail ends. For a store that settles the larger number costs
    /// nothing: the loop returns as soon as it does, so a healthy refresh still
    /// comes back in the 15–25s the same trials measured. Two cases wait all 90s:
    /// a store that keeps moving, and one that never changes at all
    /// (`noChange`), which has no write to
    /// settle after. All five trials above wrote, so that second case is unmeasured.
    public static let defaultDeadline: Duration = .seconds(90)

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
    /// Start our own instance and hand back its pid, or nil if it could not start.
    let spawn: @Sendable (URL) async -> pid_t?
    /// End the instance we started. Takes the pid we were given, never a bundle id.
    let terminate: @Sendable (pid_t) -> Void
    /// A value that changes when the store is written. Production passes the
    /// write-ahead log's modification date; the main file's is not enough on its
    /// own, since SQLite in WAL mode leaves it alone for long stretches.
    let storeStamp: @Sendable () -> Date?
    let sleep: @Sendable (Duration) async -> Void
    /// Whether the store shows no account testing anything (`accountTestsNothing`).
    let testsNothing: @Sendable () async -> Bool
    /// Whether this Mac is signed in to the App Store (`notSignedIn`); nil is no signal.
    let appStoreSignedIn: @Sendable () async -> Bool?

    public init(
        locate: @escaping @Sendable () -> URL? = Self.locateTestFlight,
        spawn: @escaping @Sendable (URL) async -> pid_t? = { await AppRestarter.launchSeparateInstance($0) },
        terminate: @escaping @Sendable (pid_t) -> Void = { AppRestarter.terminateOwnInstance($0) },
        storeStamp: @escaping @Sendable () -> Date? = Self.storeStamp,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        testsNothing: @escaping @Sendable () async -> Bool = Self.storeTestsNothing,
        appStoreSignedIn: @escaping @Sendable () async -> Bool? = Self.appStoreSignIn
    ) {
        self.locate = locate
        self.spawn = spawn
        self.terminate = terminate
        self.storeStamp = storeStamp
        self.sleep = sleep
        self.testsNothing = testsNothing
        self.appStoreSignedIn = appStoreSignedIn
    }

    /// Run one attempt. Never throws: every failure is an `Outcome` the caller can
    /// print, because "we tried to refresh and could not" is information the user
    /// needs before reading a version number.
    public func run(
        deadline: Duration = defaultDeadline,
        settle: Duration = settleInterval
    ) async -> Outcome {
        guard let bundle = locate() else { return .notInstalled }

        // Nothing to fetch without an account, and starting TestFlight then only
        // asks the user to sign in. The App Store sign-in goes first because it is
        // known right after a sign-out (`notSignedIn`); the store only learns of one
        // the next time TestFlight runs (`accountTestsNothing`). A signal that cannot
        // answer lets the refresh through.
        //
        // The store is asked only when the sign-in cannot answer. It learns of a
        // sign-in, too, only the next time TestFlight runs — so after signing back in
        // outside TestFlight, or to another Apple Account, it still shows nobody
        // testing, and trusting it over a known sign-in would keep TestFlight from
        // ever running to catch it up. The cost: a Mac signed in but testing nothing
        // starts, and ends, a hidden TestFlight on each refresh the user asks for.
        let signedIn = await appStoreSignedIn()
        if signedIn == false { return .notSignedIn }
        if signedIn == nil, await testsNothing() { return .accountTestsNothing }

        // Read the store BEFORE anything of ours touches it, so the wait below
        // compares against the state that predates our own writes.
        let before = storeStamp()

        // One route, whether or not the user has TestFlight open: our own instance.
        // There is no branch on `isRunning` any more, and that is the whole change —
        // reaching an already-running instance meant making it active, and making an
        // app active means giving it the foreground.
        guard let pid = await spawn(bundle) else { return .launchFailed }
        // Ours to end, on every path from here on — the wait has several. The two
        // returns above this line have no process to end. Leaving one behind would
        // be worse than the old cold-launch path, which at least had macOS
        // collecting a single instance eventually. The live `terminate` leaves it
        // running if the user has started using it (`AppRestarter.terminateOwnInstance`).
        defer { terminate(pid) }

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
        // nothing happened — but do NOT call it a refresh: the store never held
        // still, so the sync may well be in flight, and the caller is about to
        // read it.
        if let lastChange { return .changedWithoutSettling(lastChange: lastChange) }
        return .noChange
    }

    // MARK: - Live effects

    /// Where TestFlight is, or nil when it is not installed.
    public static let locateTestFlight: @Sendable () -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Whether the store says no account is testing anything here — what a
    /// signed-out store looks like once TestFlight has run (only placeholders
    /// left; see `TestFlightInventory.readTesters`). False whenever the store
    /// cannot say, so an unreadable store never stops a refresh.
    ///
    /// Off the cooperative pool: the read is a bounded but blocking open, and it is
    /// called from `run()`, which is async (see `offCooperativePool`).
    public static let storeTestsNothing: @Sendable () async -> Bool = {
        (try? await offCooperativePool { TestFlightInventory().isTestingNothing }) ?? false
    }

    /// Whether this Mac is signed in to the App Store (`AppStoreSignIn`), read off the
    /// cooperative pool for the same reason. nil when it cannot say.
    public static let appStoreSignIn: @Sendable () async -> Bool? = {
        await AppStoreSignIn.current()
    }

    /// Modification date of the store's write-ahead log.
    public static let storeStamp: @Sendable () -> Date? = {
        let wal = URL(fileURLWithPath: TestFlightInventory.defaultDatabaseURL.path + "-wal")
        let attrs = try? FileManager.default.attributesOfItem(atPath: wal.path)
        return attrs?[.modificationDate] as? Date
    }
}

extension TestFlightRefresh.Outcome {
    /// Whether the store moved during the attempt, so anything read from it
    /// before the attempt may now be stale.
    ///
    /// `changedWithoutSettling` counts. The sync may not have finished, but the
    /// store is no longer the one a pre-sync read saw, and a second read is at
    /// least as current as the first. What must not follow from it is a claim
    /// that the sync finished — that is the caller's wording to get right, and
    /// the reason the case exists.
    public var storeChanged: Bool {
        switch self {
        case .refreshed, .changedWithoutSettling: true
        case .noChange, .notSignedIn, .accountTestsNothing, .notInstalled, .launchFailed: false
        }
    }

    /// Whether an instance of TestFlight was actually started.
    ///
    /// Distinct from ``storeChanged``: `noChange` means it ran and wrote nothing,
    /// which is a real answer about the store, while the four below mean the
    /// question was never put to TestFlight at all. `TestFlightSyncPolicy.Ledger`
    /// needs this one — retiring a row's evidence on an attempt that never spawned
    /// would silence it on the strength of nothing.
    public var testFlightRan: Bool {
        switch self {
        case .refreshed, .changedWithoutSettling, .noChange: true
        case .notSignedIn, .accountTestsNothing, .notInstalled, .launchFailed: false
        }
    }
}

extension TestFlightRefresh {
    /// A round's rows with the ones re-checked after a sync put back in place.
    ///
    /// Matched by `id` (the install path) and kept in the round's own order. A
    /// re-checked row with no counterpart is dropped rather than appended: the
    /// re-check only ever answers for rows the round already holds, and adding
    /// one here would put an app in the list that the scan did not find.
    public static func merging(
        _ checked: [UpdateResult], resynced: [UpdateResult]
    ) -> [UpdateResult] {
        let byID = Dictionary(resynced.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return checked.map { byID[$0.id] ?? $0 }
    }
}
