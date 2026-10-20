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

    public init() {}

    public func isWaiting(_ key: Key) -> Bool { waiting.contains(key) }

    /// Waiting or running.
    public func contains(_ key: Key) -> Bool { running == key || waiting.contains(key) }

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
        }
        running = key
        await body()
        advance()
        return true
    }

    /// Take back a click still waiting. False when it is not waiting: it never
    /// was, or its turn has come.
    @discardableResult
    public func cancel(_ key: Key) -> Bool {
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
        cleanups[next] = nil
        turns.removeValue(forKey: next)?.resume(returning: true)
    }
}
