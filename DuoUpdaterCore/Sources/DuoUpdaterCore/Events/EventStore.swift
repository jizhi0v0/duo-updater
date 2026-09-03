import Foundation
import SQLite3

/// Everything DuoUpdater did, kept as events in a SQLite database.
///
/// ## Why events rather than counters
///
/// Aggregates answer only the questions you thought to ask when you wrote them.
/// A counter can say "2.1 MB went to formulae.brew.sh" and can never say "and
/// every one of those fetches re-resolved DNS", because the summing threw that
/// away at write time. Keeping the events means a later question — a timeline, a
/// per-host latency plot, what happened right before a failed install — is a
/// query rather than a new counter and a month of waiting for it to fill. So the
/// rule is: **record everything the platform hands us, derive nothing at write
/// time**, and drop only secrets (see ``RequestEvent/path``).
///
/// ## Why SQLite rather than a log file
///
/// The menu-bar app and `duo` run as the same user against the same store, and
/// an append-only text log makes that everyone's problem: interleaved writes,
/// half-written trailing lines, rotation, per-file size caps so that retention
/// has something it can delete whole, and a reader that has to count the lines
/// it could not parse. WAL mode is exactly this case, and it also collapses two
/// files into one — the ``RequestTotal`` rollups are updated **in the same
/// transaction as the event that feeds them**, so the raw record and the totals
/// cannot come to disagree about a transfer.
///
/// The trade accepted in exchange: a corrupt database loses everything, where a
/// corrupt text log loses one line. This is a diagnostic log rather than a
/// ledger of record — the install history and the download totals live
/// elsewhere — so that is the cheaper failure.
///
/// ## The one pragma that has to be right on day one
///
/// `auto_vacuum = INCREMENTAL` **must be set before the first table is created**;
/// the default is `NONE`, under which `DELETE` frees pages inside the file and
/// never returns them to the filesystem, so retention would stop the database
/// growing but never shrink it. Switching afterwards needs a full `VACUUM`,
/// which rewrites the whole file. Hence ``open`` sets it first, and
/// ``schemaProblems`` reports it if a database ever turns up without it.
public actor EventStore {

    /// The process-wide store. Everything on `URLSession.updates`, the installer
    /// downloader and the self-updater reports here.
    public static let shared = EventStore()

    // MARK: Policy

    /// Oldest event kept.
    ///
    /// Paired with ``retentionBytes`` because which one binds depends entirely on
    /// a setting the user picks, and neither alone is safe. Measured on this
    /// machine — 50 000 real request events, payload plus envelope columns plus
    /// the three indexes — **1504 bytes per event**, against a full sweep of
    /// roughly 200 hops:
    ///
    /// | Check frequency | Per day  | 64 MB holds |
    /// |-----------------|----------|-------------|
    /// | Every 6 h (default) | 1.2 MB | ~55 days   |
    /// | Hourly          | 6.9 MB   | ~9 days     |
    /// | Every 5 min     | 83 MB    | ~19 hours   |
    ///
    /// So on the default the day budget is what binds and the byte budget never
    /// fires; at five-minute checks the byte budget is the only thing standing
    /// between a diagnostic log and a gigabyte. Both are real; neither is
    /// decoration. Recompute this table if the event grows fields — it is a
    /// measurement, not an estimate, and it should stay one.
    public let retentionDays: Int
    /// Ceiling for the database file. **Wins over the day budget** — when the
    /// file is over it, the oldest events go regardless of age, down to
    /// ``retentionFloor``. Totals are never pruned and are not counted against
    /// this.
    public let retentionBytes: Int64

    // MARK: Buffering

    /// Events are written in batches inside one transaction: a fan-out completes
    /// requests faster than a commit each is worth, and nothing here is worth an
    /// fsync per row. The cost of a crash is the last few seconds of a
    /// diagnostic log.
    private let flushEventCount: Int
    private let flushDelay: Duration
    /// How often retention may run. **Not once per process**: the menu-bar app
    /// runs for weeks, so a once-at-startup sweep would let the store grow
    /// unbounded for the entire rest of its life — a `duo`-shaped assumption
    /// applied to the process that actually writes most of the events. Hourly is
    /// far cheaper than the fan-out that fills it and still bounds the file.
    private let pruneInterval: Duration
    /// How long a writer waits for the other one's lock. **Not the default 0**:
    /// two processes share this file and a writer holding the lock for the length
    /// of one batch is normal, not an error. A seam so a test can force the
    /// contention rather than hope for it.
    private let busyTimeoutMilliseconds: Int
    private var buffer: [DuoEvent] = []
    private var pendingFlush: Task<Void, Never>?

    // MARK: State

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var connection: Connection?
    private var lastPrune: Date?

    /// Events handed over by a delegate callback, before the actor has seen them.
    ///
    /// The metrics callback runs on the session's delegate queue and cannot
    /// `await`, so the obvious shape is `Task { await store.append(…) }` — and
    /// that loses events. `duo` evaluates `EventStore.hasRecorded` and exits the
    /// moment its command returns; a Task created but not yet run means the flag
    /// reads false, the flush is skipped, and the request is never recorded. Even
    /// with the flag already true, the in-flight tail is dropped.
    ///
    /// Staging closes the window: ``stage(_:)`` is synchronous, so by the time
    /// `data(for:delegate:)` resumes, the events are held here and the flag is
    /// set. The actor moves them out on its own schedule, and `flush()` drains
    /// this first so nothing can be left behind.
    private let staging = Staging()

    private final class Staging: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [DuoEvent] = []

        func add(_ incoming: [DuoEvent]) { lock.withLock { events += incoming } }

        func drain() -> [DuoEvent] {
            lock.withLock { defer { events = [] }; return events }
        }
    }

    /// Owns the sqlite handle so ARC closes it.
    ///
    /// An actor's `deinit` is nonisolated and cannot touch isolated state, so the
    /// handle cannot be closed there. A box with its own `deinit` can, and it also
    /// means a store that goes out of scope in a test does not leak a descriptor.
    private final class Connection: @unchecked Sendable {
        let db: OpaquePointer
        init(_ db: OpaquePointer) { self.db = db }
        deinit { sqlite3_close_v2(db) }
    }

    /// Events accepted, for tests that need to wait for the writer without
    /// sleeping a fixed amount.
    public private(set) var appendedCount = 0
    /// Events refused because a raw payload could have forged a record.
    public private(set) var rejectedCount = 0
    /// How many times retention has run. Pinned by a test — pruning walks the
    /// table and must not happen on the append path.
    public private(set) var pruneRunCount = 0

    public init(
        fileURL: URL? = nil,
        retentionDays: Int = 30,
        retentionBytes: Int64 = 64 * 1024 * 1024,
        flushEventCount: Int = 64,
        flushDelay: Duration = .seconds(3),
        pruneInterval: Duration = .seconds(3600),
        busyTimeoutMilliseconds: Int = 5000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.retentionDays = retentionDays
        self.retentionBytes = retentionBytes
        self.flushEventCount = flushEventCount
        self.flushDelay = flushDelay
        self.pruneInterval = pruneInterval
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        self.now = now
    }

    /// Whether this process has recorded anything yet.
    ///
    /// For `duo`, which exits long before a coalesced write would fire and so has
    /// to `flush()` — but must not open a database for a command like `list` that
    /// never touched the network.
    public private(set) nonisolated(unsafe) static var hasRecorded = false
    private static let recordedLock = NSLock()
    private nonisolated static func markRecorded() {
        recordedLock.lock(); hasRecorded = true; recordedLock.unlock()
    }

    // MARK: - Writing

    /// Hand events over from a context that cannot `await` — a `URLSession`
    /// delegate callback.
    ///
    /// Synchronous on purpose: see ``staging``. Returns once the events are
    /// safely held and ``hasRecorded`` is set, so a caller that exits
    /// immediately afterwards still flushes them.
    public nonisolated func stage(_ events: [DuoEvent]) {
        guard !events.isEmpty else { return }
        staging.add(events)
        Self.markRecorded()
        Task { await self.absorbStaged() }
    }

    private func absorbStaged() {
        for event in staging.drain() { append(event) }
    }

    /// Record one event. Buffered; committed by ``flush()`` or the coalescing
    /// timer, whichever comes first.
    public func append(_ event: DuoEvent) {
        // A `.unknown` payload is stored as the JSON it was read as, and is the
        // one field in the whole model that is not built here. Only a hand-built
        // value can carry something that is not an object (a decoded one came
        // from a real row by construction) — which is exactly the case worth
        // refusing rather than trusting.
        if case .unknown(_, let json) = event.payload, !Self.isJSONObject(json) {
            rejectedCount += 1
            Log.app.error("events: refused an unknown-kind event whose payload is not a JSON object")
            return
        }
        // A download that moved no bytes is not a download. Refused here rather
        // than at the call site because it is a rule about the ledger — a
        // zero-byte row would inflate an app's update count with an install that
        // never happened — and `App/Sources` has no test target to hold it.
        if let install = event.install, install.bytes <= 0 {
            rejectedCount += 1
            return
        }
        buffer.append(event)
        appendedCount += 1
        Self.markRecorded()

        if buffer.count >= flushEventCount {
            commitBuffer()
        } else {
            scheduleFlush()
        }
    }

    /// Commit now, and wait for it. For the CLI, which exits before the
    /// coalescing timer would fire, and for tests.
    ///
    /// Drains ``staging`` first: an event handed over by a delegate callback may
    /// not have reached the actor yet, and a flush that skipped it would lose
    /// exactly the last request of a run.
    public func flush() {
        absorbStaged()
        pendingFlush?.cancel()
        pendingFlush = nil
        commitBuffer()
    }

    /// Discard the recorded network activity: request events **and** the running
    /// totals they feed.
    ///
    /// Both of those, deliberately — a reset that cleared the events and left the
    /// totals would leave `duo requests summary` reporting traffic that `duo
    /// requests recent` denies ever happened.
    ///
    /// **The install ledger is kept unless `includingInstalls` says otherwise**,
    /// and that default is the whole point. "Clear the network log" is a routine,
    /// low-stakes thing to want; the install events are a user's entire download
    /// history — 115 GB across five years on the machine this was written on — and
    /// they are not diagnostics that anyone would expect a log reset to take with
    /// it. Nothing in the app passes true today; the parameter exists so that a
    /// future caller that means it has to say so.
    public func reset(includingInstalls: Bool = false) {
        pendingFlush?.cancel()
        pendingFlush = nil
        buffer = []
        guard let db = open() else { return }
        // One transaction, because the doc comment above promises the two are
        // cleared together: as three autocommitted statements, a failure between
        // them leaves totals reporting traffic the events deny — the exact state
        // this method exists to prevent.
        //
        // ⚠️ Not covered by a test, and deliberately not faked: reaching the bad
        // state needs a crash between two DELETEs. Correct and free, but nothing
        // will tell you if someone flattens it back into one `exec`.
        guard exec(db, "BEGIN IMMEDIATE;") else { return }
        exec(db, includingInstalls
             ? "DELETE FROM events;"
             : "DELETE FROM events WHERE kind <> 'install';")
        exec(db, "DELETE FROM totals;")
        guard exec(db, "COMMIT;") else { exec(db, "ROLLBACK;"); return }
        // Vacuum then checkpoint, for the reason spelled out in `prune`: the
        // other order leaves the freed pages in the log and the file as large as
        // it ever was, which is how a `reset` that really did empty the store
        // still left 14 MB on disk.
        exec(db, "PRAGMA incremental_vacuum;")
        exec(db, "PRAGMA wal_checkpoint(TRUNCATE);")
        lastPrune = nil
    }

    /// The most events held in memory while commits keep failing. A database
    /// that stays unwritable must not turn a diagnostic log into a memory leak;
    /// the oldest go first, and loudly, because silently discarding them is what
    /// this whole change is meant to stop happening.
    static let maxBufferedEvents = 10_000

    private func trimBufferIfRunaway() {
        guard buffer.count > Self.maxBufferedEvents else { return }
        let dropped = buffer.count - Self.maxBufferedEvents
        buffer.removeFirst(dropped)
        Log.app.error("events: database unwritable; dropped \(dropped, privacy: .public) buffered events")
    }

    private func scheduleFlush() {
        guard pendingFlush == nil else { return }
        pendingFlush = Task { [weak self, flushDelay] in
            try? await Task.sleep(for: flushDelay)
            guard !Task.isCancelled else { return }
            await self?.flushFromTimer()
        }
    }

    private func flushFromTimer() {
        pendingFlush = nil
        commitBuffer()
    }

    private func commitBuffer() {
        guard !buffer.isEmpty, let db = open() else { return }

        // The transaction opens *before* the buffer is taken, and the buffer is
        // only cleared once it has. Written the other way round, a `BEGIN` that
        // lost the race for the write lock — the other writer holding it past
        // `busy_timeout`, which a `duo verify` sweep really can do — left the
        // events nowhere: already dropped from the buffer, never committed. Worse,
        // the inserts then ran in autocommit, one statement at a time, so an event
        // could land without its rollup. That is precisely the disagreement the
        // single transaction exists to rule out.
        guard exec(db, "BEGIN IMMEDIATE;") else {
            trimBufferIfRunaway()
            return   // keep the events; the next flush tries again
        }
        let batch = buffer
        buffer = []

        for event in batch {
            insert(event, into: db)
            // The rollup rides along in the same transaction as the row it
            // summarises. That is the whole reason there is no second file: the
            // two cannot disagree about a transfer, because a crash between them
            // is not a state the database can be in.
            if let request = event.request {
                upsertTotal(request, client: event.client, into: db)
            }
        }
        guard exec(db, "COMMIT;") else {
            exec(db, "ROLLBACK;")
            buffer.insert(contentsOf: batch, at: 0)
            trimBufferIfRunaway()
            return
        }

        // After a commit, never inside one, and at most once per `pruneInterval`.
        // A short-lived `duo` therefore sweeps exactly once; a menu-bar app that
        // stays up for a month sweeps hourly instead of never again.
        let elapsed = lastPrune.map { now().timeIntervalSince($0) } ?? .infinity
        if elapsed >= Double(pruneInterval.components.seconds) {
            lastPrune = now()
            prune(db)
        }
    }

    private func insert(_ event: DuoEvent, into db: OpaquePointer) {
        let sql = """
            INSERT OR REPLACE INTO events
              (id, at, client, kind, purpose, host, app_id, status,
               bytes_in, bytes_out, payload)
            VALUES (?,?,?,?,?,?,?,?,?,?,?);
            """
        guard let statement = prepare(db, sql) else { return }
        defer { sqlite3_finalize(statement) }

        // The envelope columns are denormalised out of the payload so the common
        // filters (time, kind, host) are index lookups rather than a JSON parse
        // per row. The payload stays authoritative and complete — these are a
        // copy for the query planner, never the only place a value lives.
        bind(statement, 1, event.id.uuidString)
        sqlite3_bind_int64(statement, 2, Self.micros(event.date))
        bind(statement, 3, event.client.rawValue)
        bind(statement, 4, event.kind)
        for column in Int32(5)...Int32(10) { sqlite3_bind_null(statement, column) }
        if let request = event.request {
            bind(statement, 5, request.purpose.rawValue)
            bind(statement, 6, request.host)
            if let status = request.status {
                sqlite3_bind_int64(statement, 8, Int64(status))
            }
            sqlite3_bind_int64(statement, 9, request.bytesReceived)
            sqlite3_bind_int64(statement, 10, request.bytesSent)
        } else if let install = event.install {
            // `purpose` is deliberately left null. The installer bytes are already
            // in the network rollups: `Downloader` files request events with
            // purpose `.install` for the very same transfer. Stamping this row
            // with the same purpose would count one download twice on the Network
            // Activity panel, and would make `--purpose install` return two rows
            // per download that mean different things — a wire measurement and a
            // ledger entry. `kind` is the discriminator; `app_id` is what this row
            // adds.
            bind(statement, 7, install.appID)
            sqlite3_bind_int64(statement, 9, install.bytes)
        }
        guard let payload = try? event.payloadJSON() else { return }
        bind(statement, 11, payload)
        step(db, statement)
    }

    private func upsertTotal(
        _ request: RequestEvent, client: RequestClient, into db: OpaquePointer
    ) {
        let sql = """
            INSERT INTO totals
              (client, purpose, host, requests, cached, not_modified, failures,
               bytes_sent, bytes_received, first_seen, last_seen)
            VALUES (?,?,?,1,?,?,?,?,?,?,?)
            ON CONFLICT(client, purpose, host) DO UPDATE SET
              requests      = requests + 1,
              cached        = cached + excluded.cached,
              not_modified  = not_modified + excluded.not_modified,
              failures      = failures + excluded.failures,
              bytes_sent    = bytes_sent + excluded.bytes_sent,
              bytes_received= bytes_received + excluded.bytes_received,
              first_seen    = min(first_seen, excluded.first_seen),
              last_seen     = max(last_seen, excluded.last_seen);
            """
        guard let statement = prepare(db, sql) else { return }
        defer { sqlite3_finalize(statement) }
        let when = Self.micros(request.responseEnd ?? request.fetchStart ?? now())
        bind(statement, 1, client.rawValue)
        bind(statement, 2, request.purpose.rawValue)
        bind(statement, 3, request.host)
        sqlite3_bind_int64(statement, 4, request.fromCache ? 1 : 0)
        sqlite3_bind_int64(statement, 5, request.isNotModified ? 1 : 0)
        sqlite3_bind_int64(statement, 6, request.failed ? 1 : 0)
        sqlite3_bind_int64(statement, 7, request.bytesSent)
        sqlite3_bind_int64(statement, 8, request.bytesReceived)
        sqlite3_bind_int64(statement, 9, when)
        sqlite3_bind_int64(statement, 10, when)
        step(db, statement)
    }

    // MARK: - Retention

    /// Age first, then size. The size pass is not optional: at realistic event
    /// sizes a machine checking hourly outgrows any sensible footprint long
    /// before the day budget expires.
    ///
    /// **Install events are exempt from both passes.** Retention exists to bound a
    /// diagnostic log; an install event is the answer to "what has keeping this
    /// machine up to date cost me" and has to outlive any window. It can afford to:
    /// one real machine had 586 of them across the app's whole life, against
    /// thousands of request events a day.
    private func prune(_ db: OpaquePointer) {
        pruneRunCount += 1
        let cutoff = Self.micros(
            Calendar.current.date(byAdding: .day, value: -retentionDays, to: now())
                ?? .distantPast)
        if let statement = prepare(db, """
            DELETE FROM events WHERE at < ? AND kind <> 'install';
            """) {
            sqlite3_bind_int64(statement, 1, cutoff)
            step(db, statement)
            sqlite3_finalize(statement)
        }

        // Trim in blocks rather than one row at a time: the file only shrinks
        // when freed pages are handed back, and asking after every row would run
        // the vacuum hundreds of times to learn the same thing. A tenth of what
        // is left per pass, so it converges near the budget instead of
        // overshooting to empty on a coarse block size.
        var guardCount = 0
        while fileBytes() > retentionBytes, guardCount < 64 {
            guardCount += 1
            let remaining = eventCount(db)
            // Never trim below the floor. A budget too small to meet — one set
            // absurdly low, or a database whose fixed overhead already exceeds it
            // — must leave the most recent events rather than silently emptying
            // the store and reporting that nothing ever happened.
            guard remaining > Self.retentionFloor else { break }
            // The floor clamp goes last. Written the other way round —
            // `max(100, min(remaining - floor, …))` — the 100-row minimum wins
            // over the clamp on the final pass and steps straight through the
            // floor it was supposed to stop at.
            let batch = min(remaining - Self.retentionFloor, max(100, remaining / 10))
            if let statement = prepare(db, """
                DELETE FROM events WHERE id IN (
                  SELECT id FROM events WHERE kind <> 'install'
                  ORDER BY at ASC, rowid ASC LIMIT ?
                );
                """) {
                sqlite3_bind_int64(statement, 1, Int64(batch))
                step(db, statement)
                sqlite3_finalize(statement)
            }
            let deleted = changes(db)
            // Vacuum, *then* checkpoint — in that order, and it is not cosmetic.
            // `incremental_vacuum` truncates the file, but in WAL mode that
            // truncation is written to the log and only reaches the database when
            // something checkpoints. Done the other way round the vacuum's result
            // is stranded: measured on the real store, an emptied database still
            // occupied 14 897 152 bytes on disk with a `page_count` of 126 — 516 KB
            // of content — and one checkpoint brought the file down to exactly
            // that. Since this loop steers by the file size, the stale figure also
            // made it keep deleting rows it did not need to.
            exec(db, "PRAGMA incremental_vacuum;")
            exec(db, "PRAGMA wal_checkpoint(TRUNCATE);")
            if deleted == 0 { break }   // nothing left to give up
        }
        exec(db, "PRAGMA incremental_vacuum;")
        exec(db, "PRAGMA wal_checkpoint(TRUNCATE);")
    }

    /// The fewest events retention will leave behind, whatever the budget says.
    static let retentionFloor = 200

    /// Prunable events only. Installs are excluded from both retention passes —
    /// they are the permanent download ledger, not diagnostics, and counting them
    /// here would let a machine with a long install history exhaust the floor and
    /// stop the size pass giving up request events it should.
    private func eventCount(_ db: OpaquePointer) -> Int {
        guard let statement = prepare(db, "SELECT count(*) FROM events WHERE kind <> 'install';"),
              sqlite3_step(statement) == SQLITE_ROW
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// The whole on-disk footprint, **including the write-ahead log**.
    ///
    /// The main file alone under-reports: measured here at 2.6 MB of database
    /// against 0.95 MB of `-wal`, i.e. 36% low. Enforcing the budget against the
    /// smaller half means the ceiling that is supposed to stand between a
    /// diagnostic log and a gigabyte is not the ceiling anyone thinks it is, and
    /// `duo events --status` would report a size the user could contradict with
    /// `du`.
    private func fileBytes() -> Int64 {
        ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
            let path = fileURL.path + suffix
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    // MARK: - Reading

    /// Totals for every (client, purpose, host) triple, heaviest first.
    public func totals() -> RequestTotalsSnapshot {
        guard let db = open(),
              let statement = prepare(db, """
                SELECT client, purpose, host, requests, cached, not_modified,
                       failures, bytes_sent, bytes_received, first_seen, last_seen
                FROM totals;
                """)
        else { return .empty }
        defer { sqlite3_finalize(statement) }

        var rows: [RequestTotal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let client = RequestClient(rawValue: text(statement, 0) ?? ""),
                  let purpose = RequestPurpose(rawValue: text(statement, 1) ?? "")
            else { continue }
            rows.append(RequestTotal(
                client: client, purpose: purpose, host: text(statement, 2) ?? "",
                requests: Int(sqlite3_column_int64(statement, 3)),
                cachedRequests: Int(sqlite3_column_int64(statement, 4)),
                notModified: Int(sqlite3_column_int64(statement, 5)),
                failures: Int(sqlite3_column_int64(statement, 6)),
                bytesSent: sqlite3_column_int64(statement, 7),
                bytesReceived: sqlite3_column_int64(statement, 8),
                firstSeen: Self.date(sqlite3_column_int64(statement, 9)),
                lastSeen: Self.date(sqlite3_column_int64(statement, 10))))
        }
        return RequestTotalsSnapshot(totals: rows)
    }

    /// Events matching `query`, oldest first.
    public func events(_ query: EventQuery = .init()) -> [DuoEvent] {
        rawRows(query).compactMap(DuoEvent.init(row:))
    }

    /// The stored rows themselves — envelope columns plus the payload JSON
    /// **exactly as written**.
    ///
    /// Separate from ``events(_:)`` because a dump must not launder rows through
    /// this build's `RequestEvent`: a newer writer's extra fields would silently
    /// vanish on the way out, which is the one thing a raw dump exists not to do.
    public func rawRows(_ query: EventQuery = .init()) -> [EventRow] {
        guard let db = open() else { return [] }
        var conditions: [String] = []
        if query.since != nil { conditions.append("at >= ?") }
        if query.until != nil { conditions.append("at <= ?") }
        if query.kind != nil { conditions.append("kind = ?") }
        if query.client != nil { conditions.append("client = ?") }
        if query.host != nil { conditions.append("host = ?") }
        if query.purpose != nil { conditions.append("purpose = ?") }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        // Newest-first with a LIMIT so the tail is an index walk of `limit` rows
        // rather than a scan of the table, then reversed for display. Doing it
        // the readable way round (ASC, then take the last n) reads the whole
        // history to print twenty lines.
        //
        // `rowid` breaks ties rather than `id`: the id is a random UUID, so two
        // events sharing a timestamp would come back in an order that changes
        // between runs. The rowid is insertion order, across both writers.
        let sql = """
            SELECT id, at, client, kind, payload FROM events
            \(whereClause) ORDER BY at DESC, rowid DESC LIMIT ?;
            """
        guard let statement = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        var column: Int32 = 1
        func next() -> Int32 { defer { column += 1 }; return column }
        if let since = query.since { sqlite3_bind_int64(statement, next(), Self.micros(since)) }
        if let until = query.until { sqlite3_bind_int64(statement, next(), Self.micros(until)) }
        if let kind = query.kind { bind(statement, next(), kind) }
        if let client = query.client { bind(statement, next(), client.rawValue) }
        if let host = query.host { bind(statement, next(), host) }
        if let purpose = query.purpose { bind(statement, next(), purpose.rawValue) }
        sqlite3_bind_int64(statement, next(), Int64(query.limit))

        var rows: [EventRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0).flatMap(UUID.init(uuidString:)),
                  let client = RequestClient(rawValue: text(statement, 2) ?? ""),
                  let kind = text(statement, 3),
                  let payload = text(statement, 4)
            else { continue }
            rows.append(EventRow(
                id: id, date: Self.date(sqlite3_column_int64(statement, 1)),
                client: client, kind: kind, payloadJSON: payload))
        }
        return rows.reversed()
    }

    /// Per-app download totals, rebuilt from the install events, heaviest first.
    ///
    /// **Aggregated on read rather than kept in a totals table**, and that is what
    /// makes importing `traffic.json` safe to repeat: an incremental total is
    /// doubled by a second import, a `SUM` over rows with stable ids is not.
    /// Affordable because install events are never pruned and there are a few
    /// hundred of them — one real machine had 586 across the app's entire life.
    public func appTrafficStats() -> [AppTrafficStat] {
        guard let db = open(),
              let statement = prepare(db, """
                SELECT at, payload FROM events
                WHERE kind = 'install' ORDER BY at ASC, rowid ASC;
                """)
        else { return [] }
        defer { sqlite3_finalize(statement) }

        let decoder = DuoEvent.decoder()
        var byApp: [String: AppTrafficStat] = [:]
        var order: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let date = Self.date(sqlite3_column_int64(statement, 0))
            guard let json = text(statement, 1),
                  let event = try? decoder.decode(InstallEvent.self, from: Data(json.utf8))
            else { continue }
            if byApp[event.appID] == nil {
                byApp[event.appID] = AppTrafficStat(
                    appID: event.appID, appName: event.appName, bundleID: event.bundleID)
                order.append(event.appID)
            }
            // Newest name and bundle id win: the app may have been renamed since
            // the earliest event, and the row should read as it is called now.
            byApp[event.appID]?.appName = event.appName
            byApp[event.appID]?.bundleID = event.bundleID
            byApp[event.appID]?.totalBytes += event.bytes
            byApp[event.appID]?.events.append(event.trafficEvent(at: date))
        }
        return order.compactMap { byApp[$0] }.sorted { a, b in
            if a.totalBytes != b.totalBytes { return a.totalBytes > b.totalBytes }
            return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
        }
    }

    /// Import a legacy `traffic.json` once, and record that it happened.
    ///
    /// Safe to call on every launch, and safe to call twice: every migrated event
    /// takes ``InstallEvent/migrationID(appID:date:bytes:)``, so a second import
    /// replaces its own rows rather than doubling a lifetime total, and the totals
    /// are summed from those rows rather than incremented. The marker is a second
    /// belt, not the mechanism.
    ///
    /// The source file is **never modified or deleted** — it stays as the user's
    /// own copy of a history this build is now responsible for.
    ///
    /// - Returns: how many events were imported, or nil when there was nothing to
    ///   do (no file, or already imported).
    @discardableResult
    public func importLegacyTraffic(from fileURL: URL? = nil, force: Bool = false) -> Int? {
        guard let db = open() else { return nil }
        if !force, metaValue(db, "traffic.json") != nil { return nil }
        let url = fileURL ?? TrafficStore.defaultFileURL()
        let stats = TrafficStore.loadStats(from: url)
        guard !stats.isEmpty else {
            // Nothing to import is still a completed migration: without recording
            // it, a machine that never had a traffic.json re-reads a missing file
            // on every launch forever.
            setMeta(db, "traffic.json", "empty")
            return nil
        }

        var imported = 0
        guard exec(db, "BEGIN IMMEDIATE;") else { return nil }
        for stat in stats.values {
            for legacy in stat.events {
                let event = InstallEvent(
                    appID: stat.appID, appName: stat.appName, bundleID: stat.bundleID,
                    fromVersion: legacy.fromVersion, toVersion: legacy.toVersion,
                    fromBuild: legacy.fromBuild, toBuild: legacy.toBuild,
                    sourceName: legacy.sourceName, bytes: legacy.bytes,
                    downloadKind: legacy.downloadKind,
                    // Never recorded by the old store, and nil is the honest answer
                    // rather than a guess about a decade of mostly-successful
                    // installs.
                    applied: nil)
                insert(DuoEvent(
                    id: InstallEvent.migrationID(
                        appID: stat.appID, date: legacy.date, bytes: legacy.bytes),
                    date: legacy.date, client: .app, payload: .install(event)),
                    into: db)
                imported += 1
            }
        }
        // Count what actually landed before claiming the migration happened. An
        // insert can fail for reasons the loop cannot see — a schema older than
        // this build, a disk that filled — and a marker written anyway means the
        // next launch skips a migration that never ran, permanently. Cheap
        // (`kind` is indexed) against the thing it protects.
        let stored = installEventCount(db)
        guard stored >= imported else {
            exec(db, "ROLLBACK;")
            Log.install.error(
                "events: traffic.json import wrote \(stored, privacy: .public) of \(imported, privacy: .public) events; not marking it done")
            return nil
        }
        setMeta(db, "traffic.json", ISO8601DateFormatter.duoEvent.string(from: now()))
        guard exec(db, "COMMIT;") else { exec(db, "ROLLBACK;"); return nil }
        Log.install.notice(
            "events: imported \(imported, privacy: .public) install events from traffic.json")
        return imported
    }

    private func installEventCount(_ db: OpaquePointer) -> Int {
        guard let statement = prepare(db, "SELECT count(*) FROM events WHERE kind = 'install';"),
              sqlite3_step(statement) == SQLITE_ROW
        else { return 0 }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// The stored value for a `meta` key, or nil. Internal so a test can ask
    /// whether a migration recorded itself.
    func metaMarker(_ key: String) -> String? {
        guard let db = open() else { return nil }
        return metaValue(db, key)
    }

    private func metaValue(_ db: OpaquePointer, _ key: String) -> String? {
        guard let statement = prepare(db, "SELECT value FROM meta WHERE key = ?;") else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func setMeta(_ db: OpaquePointer, _ key: String, _ value: String) {
        guard let statement = prepare(db, "INSERT OR REPLACE INTO meta VALUES (?, ?);")
        else { return }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, key)
        bind(statement, 2, value)
        step(db, statement)
    }

    /// How many events are stored, and the span they cover.
    public func coverage() -> (count: Int, oldest: Date?, newest: Date?) {
        guard let db = open(),
              let statement = prepare(db, "SELECT count(*), min(at), max(at) FROM events;"),
              sqlite3_step(statement) == SQLITE_ROW
        else { return (0, nil, nil) }
        defer { sqlite3_finalize(statement) }
        let count = Int(sqlite3_column_int64(statement, 0))
        guard count > 0 else { return (0, nil, nil) }
        return (count,
                Self.date(sqlite3_column_int64(statement, 1)),
                Self.date(sqlite3_column_int64(statement, 2)))
    }

    /// Size of the database on disk, for `duo doctor` and the retention tests.
    public func databaseBytes() -> Int64 { fileBytes() }

    /// Anything about an existing database that would quietly misbehave — today,
    /// only the vacuum mode, which cannot be fixed after the fact without
    /// rewriting the whole file.
    public func schemaProblems() -> [String] {
        guard let db = open() else { return ["database could not be opened"] }
        var problems: [String] = []
        if intPragma(db, "auto_vacuum") != 2 {
            problems.append("auto_vacuum is not INCREMENTAL — deletes will not return space")
        }
        if text(pragma: "journal_mode", db) != "wal" {
            problems.append("journal_mode is not WAL — concurrent readers will block")
        }
        return problems
    }

    // MARK: - SQLite plumbing

    private static let transient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self)

    private func open() -> OpaquePointer? {
        if let connection { return connection.db }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            Log.app.error("events: cannot open the store at \(self.fileURL.path, privacy: .public)")
            if let db { sqlite3_close_v2(db) }
            return nil
        }
        // Order matters: `auto_vacuum` is only settable on an empty database, so
        // it has to precede the schema. See the type's doc comment.
        exec(db, "PRAGMA auto_vacuum=INCREMENTAL;")
        exec(db, "PRAGMA journal_mode=WAL;")
        exec(db, "PRAGMA busy_timeout=\(busyTimeoutMilliseconds);")
        // NORMAL rather than FULL: a diagnostic log is not worth an fsync per
        // commit, and WAL's NORMAL only risks the last transactions on power loss.
        exec(db, "PRAGMA synchronous=NORMAL;")
        createSchema(db)
        // 0600 for the same reason the directory is 0700: Application Support is
        // readable by anything running as the user and lands in every unencrypted
        // backup.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        connection = Connection(db)
        return db
    }

    private func createSchema(_ db: OpaquePointer) {
        exec(db, """
            CREATE TABLE IF NOT EXISTS events (
              id        TEXT PRIMARY KEY,
              at        INTEGER NOT NULL,
              client    TEXT    NOT NULL,
              kind      TEXT    NOT NULL,
              purpose   TEXT,
              host      TEXT,
              app_id    TEXT,
              status    INTEGER,
              bytes_in  INTEGER,
              bytes_out INTEGER,
              payload   TEXT    NOT NULL
            );
            CREATE INDEX IF NOT EXISTS events_at        ON events(at);
            CREATE INDEX IF NOT EXISTS events_kind_at   ON events(kind, at);
            CREATE INDEX IF NOT EXISTS events_host_at   ON events(host, at);
            CREATE INDEX IF NOT EXISTS events_app_at    ON events(app_id, at);

            CREATE TABLE IF NOT EXISTS totals (
              client         TEXT    NOT NULL,
              purpose        TEXT    NOT NULL,
              host           TEXT    NOT NULL,
              requests       INTEGER NOT NULL DEFAULT 0,
              cached         INTEGER NOT NULL DEFAULT 0,
              not_modified   INTEGER NOT NULL DEFAULT 0,
              failures       INTEGER NOT NULL DEFAULT 0,
              bytes_sent     INTEGER NOT NULL DEFAULT 0,
              bytes_received INTEGER NOT NULL DEFAULT 0,
              first_seen     INTEGER NOT NULL,
              last_seen      INTEGER NOT NULL,
              PRIMARY KEY (client, purpose, host)
            );

            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        // `CREATE TABLE IF NOT EXISTS` does nothing to a table that is already
        // there, so a column added after the first release has to be added
        // explicitly. Found the hard way: `app_id` arrived with the install
        // events, every INSERT against an older database failed on the unknown
        // column, and the import marked itself done having written nothing.
        addColumnIfMissing(db, table: "events", column: "app_id", type: "TEXT")

        if let statement = prepare(db, "INSERT OR IGNORE INTO meta VALUES ('schema', ?);") {
            bind(statement, 1, String(DuoEvent.schemaVersion))
            step(db, statement)
            sqlite3_finalize(statement)
        }
    }

    private func addColumnIfMissing(
        _ db: OpaquePointer, table: String, column: String, type: String
    ) {
        guard let statement = prepare(db, "PRAGMA table_info(\(table));") else { return }
        var present = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(statement, 1) == column { present = true; break }
        }
        sqlite3_finalize(statement)
        guard !present else { return }
        exec(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
        Log.app.notice("events: added the \(column, privacy: .public) column")
    }

    @discardableResult
    private func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            Log.app.error("events: \(message, privacy: .public)")
            return false
        }
        return true
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Log.app.error("events: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return nil
        }
        return statement
    }

    private func step(_ db: OpaquePointer, _ statement: OpaquePointer) {
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            Log.app.error("events: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
        }
    }

    private func bind(_ statement: OpaquePointer, _ column: Int32, _ value: String) {
        sqlite3_bind_text(statement, column, value, -1, Self.transient)
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private func changes(_ db: OpaquePointer) -> Int { Int(sqlite3_changes(db)) }

    private func intPragma(_ db: OpaquePointer, _ name: String) -> Int? {
        guard let statement = prepare(db, "PRAGMA \(name);"),
              sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func text(pragma name: String, _ db: OpaquePointer) -> String? {
        guard let statement = prepare(db, "PRAGMA \(name);"),
              sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        defer { sqlite3_finalize(statement) }
        return text(statement, 0)
    }

    /// Microseconds since the epoch. Integers rather than a text timestamp so
    /// range scans use the index and comparisons cannot depend on a format, and
    /// **microseconds rather than milliseconds** because a fan-out completes
    /// several requests inside one millisecond: at that resolution their order
    /// collapses into whatever the tiebreaker says, and the tiebreaker used to be
    /// a random UUID. Matches the payload timestamps, so the envelope and the
    /// event it wraps cannot disagree about which of two events came first.
    static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    static func date(_ micros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(micros) / 1_000_000)
    }

    private static func isJSONObject(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return false }
        return object is [String: Any]
    }

    /// Where ``shared`` writes.
    ///
    /// `DUO_STATE_DIR` wins, as it does for every other store. With no override
    /// **and a test process**, this goes to a scratch directory rather than to
    /// Application Support — and that is a fix for something that actually
    /// happened, not a precaution: after one `make test` the developer's real
    /// store held 1643 `cli` events, including 252 to `127.0.0.1` from the
    /// suites' loopback servers and 48 to `example.com`, a host nothing ever
    /// contacted. Those rows also land in `totals`, which is never pruned, so
    /// they inflate every later `duo requests` figure permanently — in a log
    /// whose entire claim is that it records what really happened.
    ///
    /// Unlike the other stores, this one is written by *any* code path that makes
    /// a request, which is most of the suite; that is why the guard lives here
    /// and not in ``DuoStateDirectory``, whose fallback several tests assert.
    public static func defaultFileURL() -> URL {
        let base = isTestProcess && ProcessInfo.processInfo.environment["DUO_STATE_DIR"] == nil
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-events-tests", isDirectory: true)
            : DuoStateDirectory.base
        return base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("events.sqlite")
    }

    /// Whether this is a test host. Both runners are named because they differ:
    /// SwiftPM runs the suite as `swiftpm-testing-helper` with no XCTest
    /// environment at all (measured), while Xcode uses `xctest` and an
    /// `.xctest` bundle.
    static var isTestProcess: Bool {
        let name = ProcessInfo.processInfo.processName
        return name == "swiftpm-testing-helper" || name == "xctest"
            || Bundle.main.bundleURL.pathExtension == "xctest"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// What to select. Every field narrows in SQL, against an index — nothing is
/// filtered after the fact, so a month of history costs the same as a day to
/// print twenty lines from.
public struct EventQuery: Sendable {
    public var since: Date?
    public var until: Date?
    public var kind: String?
    public var client: RequestClient?
    public var host: String?
    public var purpose: RequestPurpose?
    /// Newest `limit` matches. The default is a screenful, not the table.
    public var limit: Int

    public init(
        since: Date? = nil, until: Date? = nil, kind: String? = nil,
        client: RequestClient? = nil, host: String? = nil,
        purpose: RequestPurpose? = nil, limit: Int = 50
    ) {
        self.since = since
        self.until = until
        self.kind = kind
        self.client = client
        self.host = host
        self.purpose = purpose
        self.limit = limit
    }
}

/// One stored row, with its payload JSON untouched.
public struct EventRow: Sendable, Hashable {
    public let id: UUID
    public let date: Date
    public let client: RequestClient
    public let kind: String
    public let payloadJSON: String

    public init(id: UUID, date: Date, client: RequestClient, kind: String, payloadJSON: String) {
        self.id = id
        self.date = date
        self.client = client
        self.kind = kind
        self.payloadJSON = payloadJSON
    }

    /// The whole event as one JSON object, envelope included — what a dump emits
    /// and what a visualiser reads.
    public var json: String {
        """
        {"v":\(DuoEvent.schemaVersion),"id":"\(id.uuidString)",\
        "at":"\(ISO8601DateFormatter.duoEvent.string(from: date))",\
        "client":"\(client.rawValue)","kind":"\(kind)","payload":\(payloadJSON)}
        """
    }
}
