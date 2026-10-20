import Foundation
import Observation

/// Every click that changes something in the CLI tab — `brew update`, Upgrade
/// All, one formula's upgrade, one tool's update, Update All — in the order it
/// was made, run one at a time.
///
/// Replaces `CLIConcurrency` (#1312), which disabled every button that could
/// clash with a run already going, so the user had to wait for one to finish
/// before clicking the next. Now every click is taken and waits its turn here.
/// Why the runs must not overlap is still true of each pair that table kept
/// apart:
///
/// - Homebrew vs. Homebrew: `brew update` takes a lock of its own; an upgrade
///   locks the formula and all its dependencies, and a second run that needs
///   one of them fails at once, "A `brew …` process has already locked …"
///   (Homebrew 7.0.9: `cmd/update.sh` `lock update`, `FormulaInstaller#lock`,
///   `LockFile` with `LOCK_NB`).
/// - Homebrew vs. a tool: brew guards nothing against a process outside it. It
///   unlinks a formula's old keg (`bin/node` gone) before installing the new
///   one and removes old kegs at the end of the run, and which Homebrew files a
///   tool's update runs on can't be known in full ahead of time (an npm copy on
///   Homebrew's node, which links Homebrew's icu4c, openssl, libuv …).
///
/// One at a time whatever the two are, so there is no table of which pairs may
/// overlap to keep up. Tool against tool loses only the overlap two single-row
/// clicks had; Update All's own lanes still run side by side inside its turn.
///
/// Not here: a tool update that asks for an administrator password. Its panel
/// comes at the click (`CLIToolsModel.update`, `updateAll`) — queued, it came
/// whenever its turn did, minutes later, and held the whole app until
/// answered — and its root shell, `env -i` with the system `PATH`, writes only
/// its own tool's file, so it has no Homebrew run to clash with
/// (`CLIToolAdministratorRun`).
///
/// The same click twice is taken once: while it waits or runs, another is
/// dropped. A waiting click can be taken back (`cancel`); a running one is the
/// caller's to stop, if it can be stopped at all.
///
/// A click taken back is cleaned up inside `cancel`, by the `whenCancelled` its
/// caller gave, not when the caller's task next runs: in between, SwiftUI could
/// draw a frame of a row neither waiting nor released (2026-10-20, a one-frame
/// flicker on Cancel), and a new click on that row could be claimed and then
/// released by the old task.
@MainActor @Observable
public final class CLIRunQueue<Key: Hashable & Sendable> {
    /// The click whose run is going, from its turn until its run returns.
    public private(set) var running: Key?
    /// The clicks waiting, oldest first.
    public private(set) var waiting: [Key] = []
    @ObservationIgnored private var turns: [Key: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var cleanups: [Key: () -> Void] = [:]
    /// The click its turn was handed to, until its task resumes — one
    /// main-actor hop later, and a Cancel pressed in between is still in time
    /// (review, #1498, round 4). `taken` once it was.
    @ObservationIgnored private var handedOver: (key: Key, taken: Bool)?

    public init() {}

    public func isWaiting(_ key: Key) -> Bool { waiting.contains(key) }

    /// Waiting or running — not one taken back as its turn came, which is
    /// only on its way out.
    public func contains(_ key: Key) -> Bool {
        if let handed = handedOver, handed.key == key, handed.taken { return waiting.contains(key) }
        return running == key || waiting.contains(key)
    }

    /// Run `body` once every click taken before this one has finished. Returns
    /// false without running it when the same click is already waiting or
    /// running, or when it was cancelled while it waited — `whenCancelled` has
    /// then run already, inside `cancel`.
    ///
    /// The caller's task is not watched: cancelling it while it waits leaves the
    /// click in the queue. `cancel` is how a click is taken back.
    @discardableResult
    public func perform(
        _ key: Key, whenCancelled: @escaping () -> Void = {}, _ body: () async -> Void
    ) async -> Bool {
        guard !contains(key) else { return false }
        if running != nil {
            waiting.append(key)
            cleanups[key] = whenCancelled
            let go = await withCheckedContinuation { turns[key] = $0 }
            guard go else { return false }
            let taken = handedOver?.taken ?? false
            handedOver = nil
            // Its `whenCancelled` ran inside `cancel`; the turn goes on to the
            // next click, which may be this same click made again.
            if taken {
                advance()
                return false
            }
            cleanups[key] = nil
        }
        running = key
        await body()
        advance()
        return true
    }

    /// Take back a click still waiting, or whose turn has come but whose run
    /// has not started. False otherwise: it never was, or its run started.
    @discardableResult
    public func cancel(_ key: Key) -> Bool {
        // Its turn came, but its run has not started: as good as waiting. It
        // stays `running` until its task resumes and hands the turn on, so a
        // click made in between still queues behind.
        if let handed = handedOver, handed.key == key, !handed.taken {
            handedOver?.taken = true
            cleanups.removeValue(forKey: key)?()
            return true
        }
        guard let index = waiting.firstIndex(of: key) else { return false }
        waiting.remove(at: index)
        cleanups.removeValue(forKey: key)?()
        turns.removeValue(forKey: key)?.resume(returning: false)
        return true
    }

    /// Hand the turn to the oldest waiting click. It is marked running here,
    /// before its task resumes, so a click made in between queues behind it
    /// instead of starting at once.
    private func advance() {
        running = nil
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        running = next
        handedOver = (next, false)
        turns.removeValue(forKey: next)?.resume(returning: true)
    }
}
