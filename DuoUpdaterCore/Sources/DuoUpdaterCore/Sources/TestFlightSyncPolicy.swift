import Foundation

/// When a round may ask TestFlight to sync its store, beyond the refresh button.
///
/// `TestFlightRefresh` is the only thing that makes that store move, and until
/// #539 its only caller inside the app was `RefreshIntent.userRequested` — the
/// button. The reason was, and still is, that a sync starts an app the user did
/// not start. What #539 measured is what that costs on a Mac nobody clicks:
///
/// - 2026-09-12, 20h13m after the last sync, **3 of 8** TestFlight rows could not
///   be bounded by the store (`Amp` 75 vs 81 on disk, `Mithka` 1153 vs 1155,
///   `Paste` 29814462 vs 29818681). One sync, 8.0s, answered all eight. The three
///   were exactly the three TestFlight had background-installed in that window.
/// - The same store, for an app whose build is published but **not yet
///   installed**, holds `latest == installed` and the row reads `.upToDate`. That
///   one is a confident wrong answer rather than a question mark, and nothing
///   local can witness it: TestFlight's notifications are all *post-install*
///   ("is Now Up to Date"; 5 of 5 here, and four builds published the same day
///   produced e-mail and no notification at all — see `TestFlightAnnouncements`),
///   and the user can switch those notifications off anyway.
///
/// So there are two gaps and they need two different triggers, which is what this
/// type decides:
///
/// - **Evidence** (``Reason/staleStore(_:)``) closes the first. The store is
///   *provably* behind for some app, and the proof is the comparison
///   `UpdateChecker` already runs. Self-limiting: a sync that works makes the
///   proof go away.
/// - **A floor** (``Reason/floor``) closes the second. There is nothing to
///   witness, so the only remaining variable is time.
///
/// ⚠️ **What this deliberately does not do is sync on every tick.** At the 5-minute
/// default that is 288 hidden TestFlight launches a day, and on 2026-09-12 exactly 3
/// of those 288 would have had anything to do. The cost that scales with them is
/// bandwidth: measured over four launches that day, each pulled **694–705 KB in and
/// 29–34 KB out**, burned 1.56–1.75s of CPU, and settled after 7.5–9.1s. There is no
/// caching between launches — the third ran about two minutes after the second and
/// fetched 704 KB anyway — so 288 a day is roughly 207 MB a day, against 17 MB at
/// the hourly floor below.
///
/// ⚠️ **What is NOT a reason, though it was written here first:** that repeated syncs
/// pile up TestFlight's auto-update jobs. They do not. `appstored` keeps its install
/// queue in a real table (`app_install` in `storeSystem.db`) with a
/// `cancel_if_duplicate` column, a `DetectDuplicateRequestTask`, and log paths for
/// `Skipped duplicate job` and `Dropping update request from group because it is a
/// duplicate of an existing install`. Measured 2026-09-12: that dedup fired on all
/// seven of the day's TestFlight installs (`Ignoring duplicate resumption request`),
/// and the queue held 0 rows before and after each of the four launches above. The
/// earlier note of "42 activations → 210 jobs" counted enqueue *attempts* in the log,
/// not work that accumulated. Do not reinstate that argument.
public enum TestFlightSyncPolicy {

    /// One app whose store rows cannot bound the copy on disk, and the build that
    /// makes that true. The build is half the identity because it is what makes a
    /// repeat *new*: a second background install is a second thing to learn, while
    /// the same build asking twice is the same question.
    public struct Evidence: Sendable, Hashable {
        public let bundleID: String
        /// `InstalledApp.buildVersion`, or "" — the same string the verdict compared.
        public let installedBuild: String

        public init(bundleID: String, installedBuild: String) {
            self.bundleID = bundleID
            self.installedBuild = installedBuild
        }
    }

    /// Why a round is about to start a hidden TestFlight. Every case is logged: a
    /// sync is a visible-enough act that "it just happened" is not an acceptable
    /// account of it.
    public enum Reason: Sendable, Equatable {
        /// The store is provably behind for these apps.
        case staleStore([Evidence])
        /// Nothing has synced it in ``floorInterval`` — neither us nor the user
        /// opening TestFlight themselves.
        case floor
    }

    /// How long the store may go unsynced before a round syncs it with no evidence
    /// at all.
    ///
    /// One hour is **24 hidden launches a day** — about 17 MB against the 207 MB the
    /// 5-minute tick would cost at the per-launch figures above, and 1 launch for the
    /// button on a day nobody clicks it. It is not fitted to a measurement: there is
    /// nothing to fit, because the gap it covers is the one with no local witness
    /// (see the type doc — TestFlight announces only what it has already installed,
    /// so a build merely waiting is invisible until something asks). So it is set by
    /// what it costs, and the price it buys is that a published-but-uninstalled build
    /// can read as "up to date" for up to an hour.
    ///
    /// ⚠️ Do not read this as the freshness of a TestFlight row in general. Anything
    /// TestFlight has actually installed is caught by ``Reason/staleStore(_:)`` at the
    /// next round instead, which is a check interval away, not an hour.
    public static let floorInterval: TimeInterval = 60 * 60

    /// Apps whose TestFlight rows the store cannot bound — the same comparison
    /// `UpdateChecker.check` runs, asked of the whole round at once.
    ///
    /// Three shapes count, and they are the three a sync could actually fix:
    ///
    /// 1. The installed build outruns the store's latest
    ///    (`UpdateChecker.testFlightVerdict` → `.testFlightManaged`). This is the
    ///    one #539 measured three of.
    /// 2. The store holds no rows for the bundle at all. A beta installed while the
    ///    store was stale looks like this, and so does one whose testing ended —
    ///    the ledger's per-build guard is what keeps the second from asking twice.
    /// 3. TestFlight announced a build id past everything the store holds
    ///    (`TestFlightAnnouncements.isBehind`). One-directional, like the witness
    ///    itself: it can only ever add evidence.
    ///
    /// **Not** a bundle the signed-in account is not testing. Its rows are
    /// placeholders by design rather than a store that fell behind
    /// (`TestFlightInventory.readTesters`), and a sync has nothing to add — this is
    /// the same gate, in the same order, that `UpdateChecker` applies before it
    /// looks anything up.
    ///
    /// Only ever called with an inventory that was actually read: an inaccessible
    /// one holds nothing, which would read as shape 2 for every beta on the Mac.
    public static func evidence(
        in apps: [InstalledApp],
        inventory: TestFlightInventory,
        announcements: TestFlightAnnouncements?
    ) -> [Evidence] {
        guard inventory.accessible else { return [] }
        return apps.compactMap { app in
            guard app.isTestFlightApp, let bundleID = app.bundleID else { return nil }
            if inventory.isTesting(bundleID: bundleID) == false { return nil }
            let found = Evidence(bundleID: bundleID, installedBuild: app.buildVersion ?? "")
            guard let latest = UpdateChecker.testFlightLatest(for: app, in: inventory) else {
                return found  // shape 2
            }
            let verdict = UpdateChecker.testFlightVerdict(
                installed: app, latestShortVersion: latest.latestShortVersion,
                latestBuild: latest.latestBuild)
            if verdict == .testFlightManaged { return found }  // shape 1
            if announcements?.isBehind(inventory.frontier(forBundleID: bundleID)) == true {
                return found  // shape 3
            }
            return nil
        }
    }

    /// Whether to sync, given what this round saw and what earlier rounds already
    /// spent a sync on.
    ///
    /// `storeStamp` is the store's own write-ahead log date
    /// (`TestFlightRefresh.storeStamp`) — the real "when did TestFlight last write
    /// this", which counts the user opening TestFlight themselves and not just our
    /// own attempts. The floor waits on whichever of that and our last attempt is
    /// more recent, so a store that never writes cannot turn the floor into a
    /// per-tick launcher.
    ///
    /// Evidence outranks the floor: it names something to learn, the floor only
    /// says time has passed.
    ///
    /// ⚠️ **Except after an attempt that never reached TestFlight.** Evidence is not
    /// retired by one of those (see ``Ledger/finish(_:ran:at:)``), so on a Mac where
    /// TestFlight can never be reached — signed out of the App Store, or TestFlight
    /// deleted with a beta still installed — the evidence branch would otherwise
    /// return `.staleStore` on every single round, forever. `run` returns before
    /// spawning in those cases, so nothing is launched, but each round still pays an
    /// accounts-database read and writes two log lines: the per-tick degeneration
    /// this type exists to prevent, reached through a different door than the
    /// expired-build one. So after such an attempt everything waits for the floor,
    /// and the retry that follows still carries its evidence.
    public static func reason(
        evidence: [Evidence], storeStamp: Date?, ledger: Ledger, now: Date
    ) -> Reason? {
        let fresh = evidence.filter { ledger.syncedFor[$0.bundleID] != $0.installedBuild }
        if !fresh.isEmpty, ledger.lastAttemptReachedTestFlight { return .staleStore(fresh) }
        let lastTouched = [storeStamp, ledger.lastAttemptAt].compactMap { $0 }.max()
        // A stamp in the FUTURE is not a freshly written store, it is a clock that
        // moved — an NTP correction, a restored VM, a timezone bug — and reading it
        // as "just synced" would park the floor until real time caught up with it,
        // which for a backwards jump of a day is a day. Out-of-range reads as no
        // information at all, which is the same answer as having no stamp.
        // `CheckSchedule.nextWait` clamps the mirror image of this arithmetic with
        // `max(0, due.timeIntervalSince(now))`.
        let age = lastTouched.map { now.timeIntervalSince($0) }
        guard let age, age >= 0, age < floorInterval else {
            return fresh.isEmpty ? .floor : .staleStore(fresh)
        }
        return nil
    }

    /// What earlier rounds already spent a sync on. **Lives for one process**, and
    /// that is enough because the durable half of the question is already on disk:
    /// `storeStamp` is TestFlight's own write-ahead log date, so a relaunch inherits
    /// a true "when was this store last written" without us recording anything.
    /// What a relaunch does forget is `syncedFor`, which costs at most one extra
    /// sync per launch for a row a sync cannot fix — bounded by how often
    /// DuoUpdater restarts, not by the tick.
    ///
    /// ⚠️ `syncedFor` is what stops evidence from degenerating into a timer. A build
    /// that **expires out of** the store stays on disk, so shape 1's inequality
    /// stays true after a perfectly successful sync — `TestFlightAnnouncements`
    /// records that shape — and without this map every round from then on would
    /// start a TestFlight that cannot help. One sync per `(bundle, build)`: a real
    /// new install brings a new build and asks again, an unfixable row asks once.
    public struct Ledger: Sendable, Equatable {
        /// When we last *started* an attempt — not when one succeeded. The floor is
        /// a bound on how often we launch TestFlight, so it has to count the
        /// launches that achieved nothing too.
        public var lastAttemptAt: Date?
        /// bundleID → the installed build a sync was already spent on.
        public var syncedFor: [String: String]
        /// Whether the last attempt actually started TestFlight. False parks the
        /// evidence branch behind the floor — see ``TestFlightSyncPolicy/reason(evidence:storeStamp:ledger:now:)``
        /// for the Mac that made this necessary. True before any attempt, so the
        /// first round with evidence does not wait.
        public var lastAttemptReachedTestFlight: Bool

        public init(
            lastAttemptAt: Date? = nil,
            syncedFor: [String: String] = [:],
            lastAttemptReachedTestFlight: Bool = true
        ) {
            self.lastAttemptAt = lastAttemptAt
            self.syncedFor = syncedFor
            self.lastAttemptReachedTestFlight = lastAttemptReachedTestFlight
        }

        /// Stamp an attempt as *started*. Separate from ``finish(_:ran:at:)`` because
        /// the caller does not wait for the attempt: a round two seconds later must
        /// already see the floor as satisfied, or it will start a second TestFlight
        /// against the same store.
        public mutating func begin(at now: Date) { lastAttemptAt = now }

        /// Close an attempt out. `ran` is whether TestFlight was actually started —
        /// `TestFlightRefresh` returns before spawning when there is no account to
        /// fetch for, and marking those bundles done would retire the evidence on
        /// the strength of an attempt that never happened.
        ///
        /// `lastAttemptAt` moves either way: the cheap early returns still cost a
        /// sign-in read and a store open, and the floor is what bounds how often a
        /// round pays them.
        public mutating func finish(_ evidence: [Evidence], ran: Bool, at now: Date) {
            lastAttemptAt = now
            lastAttemptReachedTestFlight = ran
            guard ran else { return }
            for item in evidence { syncedFor[item.bundleID] = item.installedBuild }
        }
    }
}
