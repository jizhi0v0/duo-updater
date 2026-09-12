import Foundation

/// Whether a change to TestFlight's own store — one the file watcher saw, rather than
/// one we caused — is worth answering the TestFlight rows again for.
///
/// **Why a watcher at all.** On a Mac where TestFlight no longer announces new builds,
/// the user opening TestFlight themselves is the only fast signal left. Measured
/// 2026-09-13 over four consecutive builds, two Macs on one Apple Account with the app
/// installed and Automatic Updates off on both: macOS 26.6 received a pre-install
/// "Ready to Test" every time, macOS 27.0 received none (`TestFlightAnnouncements`
/// carries the comparison). On the second machine nothing local learns of a new build
/// until something launches TestFlight — and when the user does that, this is what
/// notices.
///
/// **Why it can only cover that one case.** Measured 2026-09-12 with two FSEvents
/// streams over the store's directory, against a stat poller as ground truth:
///
///   - A **cold launch** of TestFlight is reported, twice out of twice, within the
///     stream's configured latency (1.0s) — it opens and truncates the files, and that
///     is an inode-level change.
///   - The **WAL appends** that follow are not reported at all. Over the 6.6s in which
///     the log grew by 144 KB the poller saw five changes and both streams stayed
///     silent.
///   - A store update made while TestFlight is **already running** produces nothing
///     whatsoever — no open, no truncate, only appends.
///
/// A control directory in the same run reported create, append and rename normally, so
/// this is a property of the store, not of the stream. Do not extend this type to
/// "notice when TestFlight updates its store"; it cannot.
public enum TestFlightStoreWatch {

    /// Whether to answer the TestFlight rows again, now that the watcher has fired and
    /// the store has stopped moving.
    ///
    /// - Parameters:
    ///   - stamp: the store's write-ahead log date now (`TestFlightRefresh.storeStamp`).
    ///   - lastRead: that same stamp as of the last time we read the store.
    ///   - ourSyncInFlight: whether our own hidden TestFlight is running.
    ///
    /// Three refusals, each for a different reason:
    ///
    /// 1. **Our own sync.** It cold-launches TestFlight, so it trips this watcher on
    ///    every round that syncs, and it already re-checks the rows when it finishes.
    ///    Reacting here would duplicate that work and land it inside the worst possible
    ///    window: measured 2026-09-12, a cold launch empties the store for about a
    ///    second (rows marked installed went 6 → 0 → 7 across one-second samples), and
    ///    #518 records ~6.9s in which the tester query answers for nobody. Rows read in
    ///    there carry "not testing this beta" for every app.
    /// 2. **No stamp.** The store cannot be read at all, so there is nothing to compare
    ///    against and nothing to re-read.
    /// 3. **Not newer than what we already read.** The watcher fires on any change in
    ///    that directory, including ones that leave the store where we last read it —
    ///    a reader touching `-shm` is enough, and our own snapshot reads do exactly
    ///    that.
    ///
    /// A stamp in the future (a clock that moved) reads as newer and costs one extra
    /// local re-read, which is a few milliseconds and no network. That is deliberately
    /// not special-cased here: `TestFlightSyncPolicy` clamps the same arithmetic
    /// because a future stamp there parks the *floor* for as long as the jump, and a
    /// jump of a day costs a day. Here the worst case is one redundant read.
    public static func reacts(stamp: Date?, lastRead: Date?, ourSyncInFlight: Bool) -> Bool {
        if ourSyncInFlight { return false }
        guard let stamp else { return false }
        guard let lastRead else { return true }
        return stamp > lastRead
    }
}
