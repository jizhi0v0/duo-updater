import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BoundedBlockingWork` is what stands between one file behind macOS's app-data
/// privacy gate and a wedged process. Every case below names the mutation it
/// exists to catch, and each mutation was applied and watched go red.
///
/// The blocking stand-in is a FIFO, the same one `TestFlightInventoryTests` uses:
/// the file exists, so every "is it there" check passes, and then `open(2)` blocks
/// for a writer that never arrives. That is the shape of the real failure — a
/// consent prompt nobody answers is not a slow read, it is a read with no end —
/// and it is not a cancellation point, so nothing but abandoning it works.
///
/// ⚠️ The stand-in calls `open(2)` directly rather than `Data(contentsOf:)`.
/// Measured 2026-09-09: `Data(contentsOf:)` against a FIFO does **not** block, it
/// throws immediately, so the first version of this file passed in 0.0002s while
/// asserting it had waited half a second. `open(2)` is also the frame the
/// `sample(1)` stack was actually wedged in.
///
/// Timeouts here are deliberately far below the production ones: what is being
/// measured is that a deadline is enforced at all, not what it is set to.
struct BoundedBlockingWorkTests {

    /// The blocking read itself: `open(2)` on a FIFO with no writer parks the
    /// thread indefinitely, which is what a pending consent prompt does to a real
    /// container plist.
    private static func openAndClose(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// A FIFO at a fresh path, plus its directory, cleaned up by the caller.
    private static func blockingFile() throws -> (url: URL, cleanup: () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bounded-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fifo = dir.appendingPathComponent("blocked.plist")
        #expect(mkfifo(fifo.path, 0o600) == 0, "could not create the blocking stand-in")
        return (fifo, {
            // Let the stranded reader's open(2) complete so the thread unwinds
            // instead of outliving the suite.
            let writeEnd = open(fifo.path, O_WRONLY | O_NONBLOCK)
            if writeEnd >= 0 { close(writeEnd) }
            try? FileManager.default.removeItem(at: dir)
        })
    }

    /// Mutation: widen the wait to `.now() + timeout * 10` (2.5s past the ceiling
    /// below, not a hair over it) — the elapsed ceiling fails. Remove the deadline entirely (`done.wait()`) and this case
    /// never returns, which is the failure the whole type exists to prevent and
    /// which `scripts/run-with-hang-report.sh` turns into a report rather than a
    /// mystery.
    @Test func aReadThatNeverReturnsIsAbandonedAtTheDeadline() throws {
        let (fifo, cleanup) = try Self.blockingFile()
        defer { cleanup() }

        let bounded = BoundedBlockingWork(label: "test")
        let started = Date()
        let answer = bounded.run(key: fifo.path, timeout: 0.5) {
            Self.openAndClose(fifo)
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(answer == nil, "an abandoned read must not report an answer")
        #expect(elapsed >= 0.4, "returned too early to have actually waited on the open")
        #expect(elapsed < 2, "did not give up — this is the hang the bound exists to prevent")
        #expect(bounded.isStuck(fifo.path), "giving up must record that the key is stranded")
    }

    /// Mutation: delete the `guard !isStuck(key)` in `run` — the second call pays
    /// the deadline again and the elapsed ceiling fails. Without this the
    /// menu-bar app, which scans on a timer, strands one more thread every pass.
    @Test func aKeyKnownStuckIsAnsweredWithoutStartingMoreWork() throws {
        let (fifo, cleanup) = try Self.blockingFile()
        defer { cleanup() }

        let bounded = BoundedBlockingWork(label: "test")
        _ = bounded.run(key: fifo.path, timeout: 0.5) { Self.openAndClose(fifo) }

        let started = Date()
        let second = bounded.run(key: fifo.path, timeout: 0.5) { Self.openAndClose(fifo) }
        let elapsed = Date().timeIntervalSince(started)

        #expect(second == nil)
        #expect(elapsed < 0.2,
                "a key already known stuck must short-circuit, not wait again")
    }

    /// Mutation: mark the key stuck unconditionally rather than only on the
    /// timeout path — `isStuck` below fails, and in production the first scan
    /// would silence every later one.
    ///
    /// Also the fixture guard for the two cases above: it is what says a
    /// `nil` from `run` means "gave up", because work that finishes does answer.
    @Test func workThatFinishesInTimeAnswersAndLeavesNoMark() {
        let bounded = BoundedBlockingWork(label: "test")
        let answer = bounded.run(key: "quick", timeout: 5) { 41 + 1 }
        #expect(answer == 42)
        #expect(!bounded.isStuck("quick"))
    }

    /// Mutation: delete `mark(key, stuck: false)` from the worker body — the poll
    /// below never sees the mark clear and the case fails. That is the difference
    /// between "granting the permission recovers on the next scan" and "recovers
    /// on the next launch", which for the menu-bar app can be weeks.
    @Test func aStrandedWorkerThatEventuallyReturnsClearsItsMark() {
        let bounded = BoundedBlockingWork(label: "test")
        let release = DispatchSemaphore(value: 0)

        let answer = bounded.run(key: "gated", timeout: 0.3) {
            release.wait()
            return 7
        }
        #expect(answer == nil)
        #expect(bounded.isStuck("gated"))

        release.signal()
        // The worker clears the mark on its own thread; wait for it rather than
        // assuming the signal has been observed.
        let deadline = Date().addingTimeInterval(5)
        while bounded.isStuck("gated") && Date() < deadline {
            usleep(10_000)
        }
        #expect(!bounded.isStuck("gated"),
                "a worker that finally came back must let its key be tried again")
    }

    /// The two orderings of the give-up race, pinned on `Slot` itself because
    /// `run` cannot be made to hit them on purpose: the window is between
    /// `done.wait` reporting `.timedOut` and the very next line.
    ///
    /// Mutation: drop the `guard !abandoned` from `complete` and the
    /// `guard stored == nil` from `abandon` (i.e. let both always succeed) — the
    /// return values below stop discriminating and both cases fail.
    @Test func exactlyOneOfTheWorkerAndTheDeadlineWinsTheSlot() {
        let workFirst = BoundedBlockingWork.Slot<Int>()
        #expect(workFirst.complete(7))
        #expect(workFirst.abandon() == false,
                "the deadline must not claim a give-up over work that already landed")
        #expect(workFirst.value == 7, "and the answer must survive to be returned")

        let deadlineFirst = BoundedBlockingWork.Slot<Int>()
        #expect(deadlineFirst.abandon())
        #expect(deadlineFirst.complete(7) == false,
                "work that finishes after the caller gave up must not resurrect an answer")
        #expect(deadlineFirst.value == nil)
    }

    /// The `run`-level half of the case above: when the worker lands its answer
    /// inside the give-up window, `run` must return that answer rather than nil.
    ///
    /// Held open with `onDeadline`, which is why that hook exists — the real
    /// window is the few instructions between `wait` reporting `.timedOut` and
    /// `abandon()`, and nothing outside `run` can aim at it. The hook releases the
    /// worker and waits until its result is in the slot, so the ordering is
    /// arranged rather than hoped for.
    ///
    /// What it buys beyond a dropped answer: the first version of this code, and
    /// of `TestFlightInventory` where it was extracted from, wrote `stuck = true`
    /// on top of the worker's `stuck = false` here. Nothing clears that mark
    /// afterwards — no thread is stranded to clear it — so on the channel path a
    /// bound app would answer nil for the rest of the process, silently losing its
    /// authoritative channel.
    ///
    /// Mutation: delete `guard slot.abandon() else { return slot.value }` (the
    /// unconditional give-up this replaced) — `run` answers nil and this fails.
    @Test func anAnswerThatLandsInsideTheGiveUpWindowIsReturned() {
        let bounded = BoundedBlockingWork(label: "test")
        let release = DispatchSemaphore(value: 0)

        let answer = bounded.run(
            key: "raced",
            timeout: 0.05,
            onDeadline: { slot in
                release.signal()
                while slot.value == nil { usleep(200) }
            }
        ) { () -> Int in
            release.wait()
            return 7
        }

        #expect(answer == 7,
                "the deadline must not discard an answer that arrived before it claimed the give-up")
    }

    /// Mutation: replace the `Set<String>` memo with a single `Bool` — the second
    /// expectation fails. One gated file must not silence an unrelated resolver,
    /// which on this path means one app's pending prompt deciding another app's
    /// channel.
    @Test func oneStuckKeyDoesNotSilenceAnother() {
        let bounded = BoundedBlockingWork(label: "test")
        bounded.mark("gated", stuck: true)

        #expect(bounded.run(key: "gated", timeout: 5) { 1 } == nil)
        #expect(bounded.run(key: "other", timeout: 5) { 2 } == 2,
                "an unrelated key must still be tried")
    }
}

/// The chokepoint half: `ChannelBinding.resolve` runs its resolver under the
/// bound, and answers nil — not a fabricated channel — when it gives up.
///
/// A fresh `BoundedBlockingWork` per case, never the shared one: the shared
/// instance is process-wide, `swift-testing` runs cases in parallel, and
/// `ChannelGuardTests` asserts that Ghostty resolves. Marking the shared memo
/// would make that case pass or fail on ordering.
struct ChannelBindingBoundTests {

    /// Ghostty is the witness the two cases below need, and this is the fixture
    /// guard that says so: its resolver reads nothing and returns a constant, so
    /// it answers the same on CI, on a machine with Ghostty installed, and on one
    /// without. Every other binding's live answer depends on this Mac's
    /// preferences, and several of them legitimately answer nil — against those,
    /// "stuck ⇒ nil" is `f(X) == f(X)` and measures nothing.
    @Test func ghosttyResolvesToSomethingWhenTheBoundIsNotInTheWay() {
        let resolved = ChannelBinding.resolve(bundleID: GhosttyChannel.bundleID)
        #expect(resolved != nil)
        #expect(resolved?.channel == .stable)
    }

    /// Mutation: in `resolve(bundleID:bounded:)`, call `resolver()` directly
    /// instead of `bounded.run(...)` — Ghostty answers its constant and this
    /// fails. That is the mutation that matters: it is the whole hazard, and it
    /// compiles.
    @Test func aBoundResolverThatIsStuckIsNotRunAndAnswersNil() {
        let bounded = BoundedBlockingWork(label: "test")
        bounded.mark(GhosttyChannel.bundleID.lowercased(), stuck: true)

        let resolved = ChannelBinding.resolve(
            bundleID: GhosttyChannel.bundleID, bounded: bounded)

        #expect(resolved == nil)
    }

    /// The safety half, and the reason nil is the answer rather than `.stable`.
    ///
    /// An authoritative `.stable` from a resolver we could not read would SILENCE
    /// `ReleaseChannel.detect()` — see `CotEditorChannel`'s own comment — pinning
    /// a `7.1.0-beta.6` copy whose container is behind a consent prompt to the
    /// stable line and offering it a downgrade. nil leaves `detect()` reading
    /// `-beta.6` off the version string, which is what an app with no binding at
    /// all already gets.
    ///
    /// Mutation: change `resolve`'s `?? nil` to
    /// `?? ResolvedChannel(channel: .stable)` — the shape somebody reaching for a
    /// "safe default" would write. The case above goes red on it too; this one is
    /// what says which of the two possible nils is being demanded and why.
    @Test func aResolverWeCouldNotReadIsNeverReportedAsStable() {
        let bounded = BoundedBlockingWork(label: "test")
        bounded.mark(GhosttyChannel.bundleID.lowercased(), stuck: true)

        let resolved = ChannelBinding.resolve(
            bundleID: GhosttyChannel.bundleID, bounded: bounded)

        #expect(resolved?.channel != .stable,
                "a channel we failed to read must not be asserted as stable")
    }

    /// Derived from the registry rather than from a hand-written list, the way
    /// `ChannelResolverTests.everyBoundIDHasAResolverBehindIt` is: a binding added
    /// tomorrow is covered by being in `boundBundleIDs`, with nothing to remember.
    ///
    /// Honest about its own strength: for an id whose live resolution is already
    /// nil on this machine, "stuck ⇒ nil" measures nothing. It is a sweep for the
    /// shape — no id may bypass the chokepoint — and
    /// `aBoundResolverThatIsStuckIsNotRunAndAnswersNil` is the case with the real
    /// signal in it.
    ///
    /// Mutation: same as that case (call `resolver()` directly); on a machine with
    /// any bound app installed this goes red too.
    @Test func noBoundIDBypassesTheChokepoint() {
        for id in ChannelBinding.boundBundleIDs {
            let bounded = BoundedBlockingWork(label: "test")
            bounded.mark(id, stuck: true)
            #expect(ChannelBinding.resolve(bundleID: id, bounded: bounded) == nil,
                    "\(id) answered while its resolver was marked stuck")
        }
    }
}
