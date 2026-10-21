import Foundation

/// What an install row draws, smoothed from what the install reports, so a
/// stage that lasts a few milliseconds does not flash across the row.
///
/// Recorded on 2026-10-19 (the owner's screen capture of a workbench row, read
/// frame by frame): a click on Update showed "Queued" for ~20 ms and "Checking"
/// for ~150 ms before "0%", and a Cancel that was answered quickly showed
/// "Cancelling…" for ~0.4 s before the row read "Update" again. The popover row
/// draws the same states.
///
/// Two rules, both display only — what the install does and when its Cancel is
/// refused are untouched:
///
/// - **A stage stays up for at least ``dwell``.** A different stage reported
///   sooner waits until then, and the one shown then is the latest reported.
///   A download's fraction is progress within one stage, shown as it comes.
/// - **So does each line of a command's output.** A line is text to read, not
///   a fraction: the next line, or the next stage, waits until it has been up
///   for ``dwell``. Shown as they came, the last line before "Checking…" was
///   on screen for one to three frames — "run `npm fund` for details" for
///   40–55 ms, "helm installed into /usr/local/bin/helm" for 50–95 ms
///   (window recordings read frame by frame, 2026-10-21) — and the row's
///   width jumped with it.
/// - **"Cancelling…" waits ``cancellingDelay``.** An accepted cancel keeps the
///   row's progress with its Cancel greyed (`cancelPending`) until then; a
///   cancel that has ended the install by then never shows "Cancelling…" at
///   all, and the row goes straight back.
///
/// A row's install starting and ending are shown at once: the click needs its
/// answer, and a finished install's row must not keep a spinner.
public struct InstallRowSmoothing<Key: Hashable & Sendable>: Sendable {
    public typealias Instant = ContinuousClock.Instant

    /// How long a stage stays on the row before a different one replaces it.
    public static var dwell: Duration { .milliseconds(300) }
    /// How long an accepted cancel waits before the row says "Cancelling…".
    public static var cancellingDelay: Duration { .milliseconds(300) }

    /// What the rows draw, and when to ask again.
    public struct Output: Equatable, Sendable {
        public var stages: [Key: InstallStage] = [:]
        public var cancels: [Key: InstallCancelState] = [:]
        /// Rows whose cancel was accepted but that do not say "Cancelling…" yet:
        /// they keep their Cancel, greyed.
        public var cancelPending: Set<Key> = []
        /// When a waiting stage or "Cancelling…" is due; nil when nothing is.
        public var nextWake: Instant?

        public init() {}

        /// What a clicked Cancel All says until its batch ends, read off the
        /// rows as they draw — so it moves when they do, and never says
        /// "Cancelling…" for a cancel the rows never showed. Once no row is
        /// running the batch is only wrapping up, and it keeps saying what it
        /// said, `previous` (greyed if nothing yet): measured 2026-10-19 on the
        /// dev Mac, that wrap-up took 0.6 s after the last row ended, and
        /// "Finishing…" over no running install was a flash and untrue, while
        /// going back to a greyed "Cancel All" after "Cancelling…" read as a
        /// step back.
        public func cancelAllPhase(holding previous: CancelAllPhase?) -> CancelAllPhase {
            if cancels.values.contains(.cancelling) { return .cancelling }
            if !cancelPending.isEmpty { return .pending }
            if stages.isEmpty { return previous ?? .pending }
            return .finishing
        }

        /// One Cancel for the rows `ids` names, as a row that sums them up
        /// draws it — the popover's command-line tools row, over every copy it
        /// is updating, whichever click claimed it: live while any of them can
        /// still be cancelled, and then greyed as theirs are (accepted, being
        /// stopped, past the commit, refused there). Nil once every one says
        /// "Cancelling…", which the row's line then says, or when none has a
        /// Cancel. One being stopped beside one past its commit says
        /// "Cancelling…", as Update All's own Cancel in the workbench header
        /// does (`CLIToolsModel.updateAllCancel`): "can't cancel now" right
        /// after a Cancel it took read as refused (review, 2026-10-20, round 2).
        ///
        /// `running` is what the row's head names, the rest waiting their turn
        /// behind it: when none of those a click stops is among them, the
        /// Cancel says it stops the queued ones (`GroupCancel.queuedOnly`) —
        /// "Upgrading go · Installing…" beside a live "Cancel update" that
        /// took back the Upgrade All queued behind it (review, 2026-10-20).
        ///
        /// `floor` is for a Cancel that must keep its place while its run
        /// goes on — Update All's in the workbench header, whose height is
        /// its button's (#1498): where the rest would give nil it gives a
        /// greyed one instead, "Cancelling…" while one is being stopped and
        /// "can't cancel now" otherwise.
        public func groupCancel(of ids: some Sequence<Key>, running: Set<Key> = [], floor: Bool = false) -> GroupCancel? {
            var live = 0, liveRunning = 0, pending = false, cancelling = false, committing = false, tooLate = false
            for id in ids {
                switch cancels[id] {
                case .available:
                    if cancelPending.contains(id) { pending = true } else {
                        live += 1
                        if running.contains(id) { liveRunning += 1 }
                    }
                case .cancelling: cancelling = true
                case .committing: committing = true
                case .tooLate: tooLate = true
                case nil: break
                }
            }
            if live > 0 {
                return GroupCancel(state: .available, pending: false, live: live,
                                   queuedOnly: !running.isEmpty && liveRunning == 0)
            }
            if pending { return GroupCancel(state: .available, pending: true, live: 0) }
            if cancelling, committing || tooLate { return GroupCancel(state: .cancelling, pending: false, live: 0) }
            if committing { return GroupCancel(state: .committing, pending: false, live: 0) }
            if tooLate { return GroupCancel(state: .tooLate, pending: false, live: 0) }
            if floor { return GroupCancel(state: cancelling ? .cancelling : .committing, pending: false, live: 0) }
            return nil
        }
    }

    /// See ``Output/groupCancel(of:)``: what `InstallCancelButton` draws.
    public struct GroupCancel: Sendable, Equatable {
        public var state: InstallCancelState
        /// Accepted, with "Cancelling…" not shown yet: greyed.
        public var pending: Bool
        /// How many a click stops: its help says so when more than one.
        public var live: Int
        /// Every one a click stops waits its turn behind what the row's head
        /// names, which goes on: its help says it cancels the queued ones.
        public var queuedOnly: Bool

        public init(state: InstallCancelState, pending: Bool, live: Int, queuedOnly: Bool = false) {
            self.state = state
            self.pending = pending
            self.live = live
            self.queuedOnly = queuedOnly
        }
    }

    /// See ``Output/cancelAllPhase(holding:)``.
    public enum CancelAllPhase: Sendable, Equatable {
        /// A cancel was accepted and has not lasted ``cancellingDelay`` yet:
        /// greyed, as the rows' Cancels are.
        case pending
        /// A row is still being stopped: "Cancelling…".
        case cancelling
        /// Nothing is left to stop, and an install is still running: past its
        /// commit point, or not the batch's to stop, it runs to its end —
        /// a swap, a restart: "Finishing…". Said apart because that can take
        /// tens of seconds, and "Cancelling…" for all of it read as stuck.
        case finishing
    }

    private struct Shown: Sendable {
        var stage: InstallStage
        var since: Instant
    }

    private var shown: [Key: Shown] = [:]
    private var cancellingSince: [Key: Instant] = [:]

    public init() {}

    /// The rows to draw for `stages` and `cancels` — the install tables as they
    /// are — at `now`.
    public mutating func update(
        stages: [Key: InstallStage], cancels: [Key: InstallCancelState], now: Instant
    ) -> Output {
        var out = Output()
        var wakes: [Instant] = []

        shown = shown.filter { stages[$0.key] != nil }
        for (id, stage) in stages {
            guard let current = shown[id] else {
                shown[id] = Shown(stage: stage, since: now)
                out.stages[id] = stage
                continue
            }
            if current.stage.name == stage.name, !Self.isNewLine(stage, after: current.stage) {
                // Same stage, new progress: shown as it comes, without restarting
                // the stage's time on the row.
                shown[id]?.stage = stage
                out.stages[id] = stage
            } else if now >= current.since + Self.dwell {
                shown[id] = Shown(stage: stage, since: now)
                out.stages[id] = stage
            } else {
                out.stages[id] = current.stage
                wakes.append(current.since + Self.dwell)
            }
        }

        cancellingSince = cancellingSince.filter { cancels[$0.key] == .cancelling }
        for (id, cancel) in cancels {
            guard cancel == .cancelling else {
                out.cancels[id] = cancel
                continue
            }
            let since = cancellingSince[id] ?? now
            cancellingSince[id] = since
            if now >= since + Self.cancellingDelay {
                out.cancels[id] = .cancelling
            } else {
                out.cancels[id] = .available
                out.cancelPending.insert(id)
                wakes.append(since + Self.cancellingDelay)
            }
        }

        out.nextWake = wakes.min()
        return out
    }

    /// Whether `stage` is another line of a command's output than `shown`:
    /// shown only once `shown` has had its ``dwell``, as a different stage is.
    private static func isNewLine(_ stage: InstallStage, after shown: InstallStage) -> Bool {
        if case .runningCommand = stage, stage != shown { return true }
        return false
    }
}

/// The line a row shows while ``InstallRowSmoothing`` holds its stage back: the
/// one reported for the stage still shown, not the newer one waiting behind it.
///
/// For rows whose progress is a line of text rather than an ``InstallStage``
/// alone — a command-line tool's "Queued", "Starting…", its command's output,
/// "Checking…". Each line is recorded with the stage it belongs to; the
/// stages go through the smoothing, and the line follows the stage it shows.
public struct InstallRowLines<Key: Hashable & Sendable>: Sendable {
    private var latest: [Key: (stage: InstallStage, text: String)] = [:]
    private var byStage: [Key: [String: String]] = [:]

    public init() {}

    /// Each row's newest stage, for ``InstallRowSmoothing/update(stages:cancels:now:)``.
    public var stages: [Key: InstallStage] { latest.mapValues(\.stage) }

    /// `key`'s row now reads `text`, a line of `stage`.
    ///
    /// A command's output line is its stage's payload, so it is not kept by
    /// stage name: the smoothing can hold one line while newer ones arrive
    /// (``InstallRowSmoothing``), and `line(_:shown:)` reads the held one off
    /// the stage itself. Kept by name, the newest line would overwrite what the
    /// held "Starting…" (`.runningCommand("")`) says.
    public mutating func record(_ key: Key, stage: InstallStage, text: String) {
        latest[key] = (stage, text)
        if case .runningCommand(let line) = stage, !line.isEmpty { return }
        byStage[key, default: [:]][stage.name] = text
    }

    /// `key`'s row has no line any more.
    public mutating func clear(_ key: Key) {
        latest[key] = nil
        byStage[key] = nil
    }

    /// What `key`'s row says while the smoothing shows `shown`: the newest line
    /// when that is the stage shown, a held output line itself, else the line
    /// `shown` was last reported with.
    public func line(_ key: Key, shown: InstallStage?) -> String? {
        guard let newest = latest[key] else { return nil }
        guard let shown, shown != newest.stage else { return newest.text }
        if case .runningCommand(let line) = shown, !line.isEmpty { return line }
        return byStage[key]?[shown.name] ?? newest.text
    }

    /// The stage of the line `line(_:shown:)` gives for `key`.
    public func stage(_ key: Key, shown: InstallStage?) -> InstallStage? {
        guard let newest = latest[key] else { return nil }
        guard let shown, shown != newest.stage else { return newest.stage }
        if case .runningCommand(let line) = shown, !line.isEmpty { return shown }
        return byStage[key]?[shown.name] == nil ? newest.stage : shown
    }
}
