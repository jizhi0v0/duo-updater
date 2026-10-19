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
///   Progress within one stage (a download's fraction, a command's output line)
///   is shown as it comes.
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
            if current.stage.name == stage.name {
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
}
