import Foundation
import SQLite3

/// What TestFlight has *told the user about* — read out of the notification
/// store, as a second witness to what `TestFlightInventory` holds.
///
/// The point is one comparison: a build TestFlight announced whose id is **greater
/// than anything the store holds** for that app proves the store is behind. No
/// timestamp, no threshold, no prose — the same self-evident shape as the gate in
/// `UpdateChecker` that refuses an up-to-date verdict when the installed build
/// outruns the store.
///
/// ⚠️ **"Not in the store" is the wrong test, and it was the first one written
/// here.** Measured 2026-09-10 against the live stores: of 5 announcements, **3
/// named a build the store did not hold** — and in all three the store was *ahead*
/// (announced 234414114 vs held 234615396; 234696688 vs 234839053; 234026569 vs
/// 234783351). The store holds no history of its own, so an announcement older than
/// what it currently carries fails a membership test. (It is not one row per
/// platform either — measured 2026-09-12, opening an app's version list in
/// TestFlight left 20 rows for that one app at once, and a cold launch collapsed it
/// back to two. See the next warning: depth is a property of the route.) That rule would have fired on 3 of 5 live rows, all wrong. Comparing
/// against the store's maximum fires on **none** of them, which is the right answer
/// for a machine whose store is current.
///
/// ⚠️ **"No history" is a property of the *route*, not of the store.** Measured
/// 2026-09-10 on two Macs: a **cold launch** rewrites the store — its write-ahead
/// log is truncated to the same size on both machines — and leaves the current
/// build plus whatever is installed; an **activation appends** without pruning. The
/// second Mac held builds 1310, 1311 and 1314 at once after an activation, and a
/// single build after the next cold launch. Comparing against the maximum is robust
/// to both shapes, which is the point — but do not repeat the sentence above as
/// though the store were always one row deep.
///
/// ⚠️ **That comparison assumes build ids increase over time, and the sample is
/// small.** Sorted by the notification store's own `delivered_date`, the five
/// announcements are strictly increasing (233627973, 234026569, 234414114,
/// 234696688, 234839053 across 09-07 to 09-09). **n=5** — enough to prefer this
/// rule over membership, not enough to call it a documented property.
///
/// ⚠️ **Do not reach for `CFBundleVersion` ordering as extra support for it.** It
/// looks like it should corroborate and it does not: measured 2026-09-10 over the
/// 14 comparable same-app pairs in this store, **2 disagree** — one app has
/// `CFBundleVersion` 12 at build id 227551062 and `CFBundleVersion` 2 at
/// 227941721. That is the two-build-namespaces problem this repository already
/// documents (mac and iOS number independently), not a counter-example to the
/// sequence itself, but it means the proxy is unusable.
///
/// If the monotonicity assumption is wrong, the cost is a refusal we should not
/// have made: the row says "TestFlight manages this" instead of "up to date". It
/// can never invent an update.
///
/// ⚠️ **A refusal is not free, and one shape of it can stick.** `.testFlightManaged`
/// is not in `UpdatePolicy.settledRowIDs`, so a refused row never settles and any
/// in-flight install note pinned to it is never retracted. The way to get stuck
/// there is a build that is expired or rolled back: the store's maximum *drops*
/// back to the earlier build while the announcement for the withdrawn one stays in
/// the notification window — measured at 5 records spanning three days — so the
/// comparison stays true for as long as that record lives. The neighbouring gate
/// argues expiry needs no special case because its discriminator is the disk; that
/// argument does **not** carry over here, where the discriminator is a notification
/// that outlives what it announced.
///
/// **Why a second witness is needed at all.** The store is refreshed by a Duet
/// activity registered `Require Device Inactivity`, so on a Mac in use it does not
/// run: measured 2026-09-09, a published build sat unseen for four hours while
/// `dasd` answered `MNP` every 30–60 seconds (#478). Notifications arrive on a
/// different path and are not gated that way — the machine that was six weeks
/// stale still received them.
///
/// **The payload is structured; nothing here parses the sentence.** Each record
/// carries `durl` (`https://testflight.apple.com/v1/app/<appAdamId>`) and, inside
/// `usda`, an archived dictionary with the numeric build id under `b`.
///
/// That the two live in one id space is *measured*, on two machines and two ways.
/// **On the second Mac, 2026-09-09**: 7 announcements, 6 exact matches against
/// `ZBUILDID`, and the seventh's store row had no build id at all. That count does
/// **not** reproduce on this machine — 5 records here, 2 exact — because the
/// notification store is a rolling window and the rest have aged out, so it is
/// evidence from that machine on that day, not a standing property.
/// **Reproducible here, 2026-09-10**: 111 store rows carry 97 distinct `ZBUILDID`s
/// and **not one is reused across two different apps**, which is what a global
/// sequence looks like and what a per-app counter does not.
///
/// ⚠️ **One-directional: the absence of an announcement proves nothing.** That still
/// holds. The *reason* recorded here on 2026-09-10 — "on this vendor path the 'a
/// build is waiting' announcement does not appear to exist" — is wrong, and a
/// controlled run says so.
///
/// Measured 2026-09-13, four consecutive builds of one app pushed 10-25 minutes
/// apart, two Macs signed into the same Apple Account, both with that app installed
/// and Automatic Updates switched off, so the only difference was the OS:
///
///   - **macOS 26.6 (25G72)** — all four arrived as *pre-install* "Ready to Test",
///     3-5 minutes after upload, each carrying the new `ZBUILDID`. That is exactly
///     the input this witness was written to consume.
///   - **macOS 27.0 (26A428)** — none of the four arrived. Not a delivery failure:
///     the same Mac took a "Ready to Test" for a *different* app it does NOT have
///     installed that evening, `apsd` logged unrelated pushes throughout each
///     window, and its own TestFlight listed the new build as installable once cold
///     launched. `appstoreagent` was never spawned for any of the four.
///
/// So the witness works where the notification arrives, and on macOS 27 it has no
/// input for an app that is already installed. **Nothing here is version-gated on
/// purpose**: with no announcement it simply never fires, and if the notification
/// comes back it works again with no code change. Re-measure before trusting either
/// version of this note — one of them is already wrong.
///
/// ⚠️ **It is a rolling window, not a log.** Records are pruned: the mini held 13
/// spanning three days while the same database kept 652 records for other apps
/// going back nine months.
public struct TestFlightAnnouncements: Sendable {

    /// One "there is a build" notice: which app, and which build id.
    public struct Announcement: Sendable, Hashable {
        /// The App Store id, taken from the notification's default-action URL.
        public let appAdamID: Int64
        /// TestFlight's own build id — the same space as `ZTFAPPBUNDLEMODEL.ZBUILDID`,
        /// and NOT `CFBundleVersion`.
        public let buildID: Int64

        public init(appAdamID: Int64, buildID: Int64) {
            self.appAdamID = appAdamID
            self.buildID = buildID
        }
    }

    public let announcements: [Announcement]

    /// Whether the notification store was opened at all. `false` means missing or
    /// blocked — and because this witness only ever refuses claims, a false here
    /// must leave every verdict exactly as it was.
    public let accessible: Bool

    /// Notification Center's per-user store. A different container from
    /// TestFlight's own, so it is a separate read and a separate way to be denied.
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    /// Bundle id of the app whose notifications these are. Lowercase in this
    /// database, unlike the bundle id TestFlight.app itself carries — measured, and
    /// the reason this is a constant rather than something derived from
    /// `TestFlightRefresh.bundleID`.
    static let notifyingApp = "com.apple.testflight"

    /// How long to wait for the notification store before treating it as
    /// unreachable. Same value and same reason as `TestFlightInventory.openTimeout`:
    /// a local sqlite open is milliseconds, so anything near this is a gate, not
    /// slow disk.
    static let openTimeout: TimeInterval = 5

    /// The bound, shared with nothing. This store is a **different container behind
    /// a different permission** from TestFlight's own, so it is a separate way to be
    /// denied and gets its own key space; one unreadable store must never suppress
    /// reads of the other.
    ///
    /// ⚠️ Without this the read was unbounded, and `Task.detached` is not a
    /// substitute — a detached task still runs on the cooperative pool, so a read
    /// that never returns parks one of very few threads forever. A timeout on the
    /// *caller's wait* does not help: it stops us waiting, not the thread being
    /// held.
    private static let bounded = BoundedBlockingWork(label: "notification store open")

    public init(databaseURL: URL? = nil) {
        let (rows, opened) = Self.read(at: databaseURL ?? Self.defaultDatabaseURL)
        self.announcements = rows
        self.accessible = opened
    }

    /// Test seam: inject the parsed announcements directly.
    public init(announcements: [Announcement], accessible: Bool = true) {
        self.announcements = announcements
        self.accessible = accessible
    }

    /// Build ids announced for one app.
    public func buildIDs(forAppAdamID id: Int64?) -> Set<Int64> {
        guard let id else { return [] }
        return Set(announcements.filter { $0.appAdamID == id }.map(\.buildID))
    }

    /// The newest build id announced for one app, or nil when none was.
    ///
    /// Nil is not "up to date": see the type's note — the absence of an
    /// announcement proves nothing at all, so a caller may only ever use this to
    /// refuse a claim.
    public func latestAnnouncedBuild(forAppAdamID id: Int64?) -> Int64? {
        buildIDs(forAppAdamID: id).max()
    }

    /// Whether TestFlight has announced a build newer than anything this store
    /// holds — the one question this type exists to answer.
    ///
    /// Deliberately takes the frontier rather than reading the store itself: the
    /// two databases live behind different permissions and are read by different
    /// code, and folding them together here would make one failure look like the
    /// other's answer.
    public func isBehind(_ frontier: TestFlightInventory.Frontier?) -> Bool {
        guard let frontier,
              let announced = latestAnnouncedBuild(forAppAdamID: frontier.adamID)
        else { return false }
        return announced > frontier.maxBuildID
    }

    // MARK: - Reading

    private static func read(at url: URL) -> ([Announcement], Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], false) }
        // nil covers both give-up modes — this open timed out, or an earlier one for
        // this path is still stranded — and both mean the same to the caller: we
        // never got in, so `accessible` is false rather than "read it, nothing there".
        return bounded.run(key: url.path, timeout: openTimeout) {
            openAndRead(at: url)
        } ?? ([], false)
    }

    /// The actual read. Only ever called from `read(at:)`'s worker thread.
    private static func openAndRead(at url: URL) -> ([Announcement], Bool) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            Log.scan.error("notification store open failed at \(url.path, privacy: .public)")
            return ([], false)
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT record.data FROM record
            JOIN app ON app.app_id = record.app_id
            WHERE app.identifier = ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            Log.scan.error("notification store prepare failed — schema changed")
            return ([], true)  // we opened it; the schema just didn't match
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, notifyingApp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var out: [Announcement] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: bytes, count: count)
            if let announcement = parse(record: data) { out.append(announcement) }
        }
        return (out, true)
    }

    /// One notification record — a binary plist — into an announcement, or nil when
    /// it is not one (a record with no build id, a shape we do not recognise).
    ///
    /// Deliberately total: every failure is a `nil`, never a throw and never a
    /// partial answer, because this witness's whole job is to refuse claims and a
    /// half-parsed record must not be able to refuse one.
    static func parse(record data: Data) -> Announcement? {
        guard let root = (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)) as? [String: Any],
            let request = root["req"] as? [String: Any],
            let adamID = appAdamID(fromDefaultActionURL: request["durl"] as? String),
            let payload = request["usda"] as? Data,
            let buildID = self.buildID(fromArchivedPayload: payload)
        else { return nil }
        return Announcement(appAdamID: adamID, buildID: buildID)
    }

    /// `https://testflight.apple.com/v1/app/6760637748` → 6760637748.
    ///
    /// The last path component, not a pattern match on the host: the id is what we
    /// need, and a URL shaped differently enough to break this yields nil, which
    /// costs a refusal we would otherwise have made — never a wrong one.
    static func appAdamID(fromDefaultActionURL raw: String?) -> Int64? {
        guard let raw, let url = URL(string: raw) else { return nil }
        return Int64(url.lastPathComponent)
    }

    /// The `b` value out of the archived APNs payload.
    ///
    /// `NSKeyedUnarchiver` rather than walking `$objects` by hand: the payload is a
    /// plain dictionary of strings and numbers, and reading the key by name is the
    /// difference between "the build id" and "some big integer that happened to be
    /// in the archive" — the app id is in there too, and is also a big integer.
    static func buildID(fromArchivedPayload payload: Data) -> Int64? {
        let allowed: [AnyClass] = [
            NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSNull.self,
        ]
        guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: allowed, from: payload) as? [String: Any] else { return nil }
        return (unarchived["b"] as? NSNumber)?.int64Value
    }
}
