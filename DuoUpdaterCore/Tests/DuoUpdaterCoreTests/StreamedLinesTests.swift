import Testing
import Foundation
@testable import DuoUpdaterCore

/// `StreamedLines` is what the two `brew` streaming runners
/// (`BrewFormulaService.run`, `HomebrewInstaller.upgrade`) feed pipe chunks into.
/// A pipe hands over whatever bytes are there, so these tests split real output at
/// every byte offset instead of trusting that a chunk ends at a line.
@Suite struct StreamedLinesTests {

    /// Measured 2026-09-13, Homebrew 7.0.0, `brew upgrade --formula xz`. The
    /// success line starts with the 4-byte `🍺`, so the offsets below include
    /// every boundary inside that character.
    /// (Pure bytes — the paths here never reach the filesystem.)
    private static let lines = [
        "🍺  /opt/homebrew/Cellar/xz/5.8.4: 96 files, 2.7MB",
        "Removing: /opt/homebrew/Cellar/xz/5.8.3... (96 files, 2.7MB)",
    ]
    private static let bytes = Data((lines.joined(separator: "\n") + "\n").utf8)

    /// Feed `chunks` the way the readability handler does, then end the stream.
    private static func stream(_ chunks: [Data]) -> (lines: [String], text: String) {
        let s = StreamedLines()
        var out = chunks.flatMap { s.append($0) }
        if let tail = s.finish() { out.append(tail) }
        return (out, s.text)
    }

    /// The per-chunk decode dropped both halves of a chunk pair split inside `🍺`,
    /// and the per-chunk split turned a line straddling two chunks into two
    /// fragments — neither of which the bulk upgrade counts as a success line.
    @Test func everyTwoChunkSplitYieldsTheSameLines() {
        for cut in 0...Self.bytes.count {
            let chunks = [Self.bytes.prefix(cut), Self.bytes.dropFirst(cut)].map { Data($0) }
            let result = Self.stream(chunks)
            #expect(result.lines == Self.lines, "cut at byte \(cut)")
            #expect(result.text == String(decoding: Self.bytes, as: UTF8.self), "cut at byte \(cut)")
        }
    }

    /// Two boundaries at once, so a line can span three chunks (or one chunk be a
    /// lone continuation byte of `🍺`).
    @Test func everyThreeChunkSplitYieldsTheSameLines() {
        let n = Self.bytes.count
        for a in 0...n {
            for b in a...n {
                let chunks = [0..<a, a..<b, b..<n].map { Data(Self.bytes[$0]) }
                #expect(Self.stream(chunks).lines == Self.lines, "cuts at \(a), \(b)")
            }
        }
    }

    /// Output that ends without a newline still delivers its last line — once,
    /// and only when the stream ends.
    @Test func anUnterminatedLastLineArrivesAtFinish() {
        let s = StreamedLines()
        #expect(s.append(Data("first\nlast wit".utf8)) == ["first"])
        #expect(s.append(Data("hout newline".utf8)) == [])
        #expect(s.finish() == "last without newline")
        #expect(s.finish() == nil)
    }

    /// The per-chunk `split(separator:)` never emitted empty lines; blank lines in
    /// brew's output must not start reaching the status label now.
    @Test func blankLinesAreNotEmitted() {
        #expect(Self.stream([Data("a\n\n\nb\n".utf8)]).lines == ["a", "b"])
    }

    // MARK: - End of stream
    //
    // The failure these guard against is a wait that never returns, so each one
    // runs under `finishing(within:)`. Not `.timeLimit`: measured 2026-09-13, a
    // wait stuck on a never-resumed continuation ran past ten minutes with a
    // one-minute limit (0.23 s CPU, not moving) — a continuation can't be
    // cancelled, so the limit never took effect, and a regression would have hung
    // the suite instead of failing it. The watchdog abandons the stuck task and
    // fails. Its bounds only decide how long a broken run takes to report; they
    // are not performance assertions, so they are generous.
    //
    // Raised from 10 and 30 on 2026-09-19: `theCapReleasesAWaitThatNeverEnds`
    // failed twice on CI (#763) while the suite was running two ~60 s cases
    // beside it. Both the cap under test and this watchdog armed on
    // `DispatchQueue.global()`, and the reading then was that for the 30 s timer
    // to beat a 0.05 s one the machine had to be starved for thirty seconds.
    // It was the process, not the machine: that queue gets no thread while every
    // cooperative thread is blocked, which is what the cap needs to survive. The
    // cap now has its own queue; see `theCapFiresWhileEveryCooperativeThreadIsBlocked`.

    /// How long a hung wait takes to be reported. Long, deliberately: the only
    /// thing it may not do is fire on a machine that is merely busy.
    private static let watchdogSeconds: Double = 120

    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<T?, Never>?
        init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }
        func resume(_ value: T?) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: value)
        }
    }

    /// `body`'s result, or nil if it had not finished after `seconds`.
    private static func finishing<T: Sendable>(
        within seconds: Double, _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let result: Result<T, Error>? = await withCheckedContinuation { cont in
            let once = Once<Result<T, Error>>(cont)
            Task.detached {
                do { once.resume(.success(try await body())) } catch { once.resume(.failure(error)) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(nil) }
        }
        return try result?.get()
    }

    /// `end()` before anyone waits: the wait returns at once, not on the timer.
    @Test func anEndBeforeTheWaitReturnsAtOnce() async throws {
        let s = StreamedLines()
        s.end()
        let done = try await Self.finishing(within: Self.watchdogSeconds) { await s.waitForEnd(atMost: 3600) }
        #expect(done != nil)
    }

    /// `end()` while a wait is suspended resumes it. `hasWaiter` makes sure this
    /// exercises the resume, not the early return above.
    @Test func anEndDuringTheWaitResumesIt() async throws {
        let s = StreamedLines()
        let done = try await Self.finishing(within: Self.watchdogSeconds) {
            let waiting = Task { await s.waitForEnd(atMost: 3600) }
            while !s.hasWaiter { await Task.yield() }
            s.end()
            s.end()  // a second EOF callback must not resume twice
            await waiting.value
        }
        #expect(done != nil)
    }

    /// No EOF ever (a child kept the pipe open): the cap releases the wait.
    @Test func theCapReleasesAWaitThatNeverEnds() async throws {
        let s = StreamedLines()
        let done = try await Self.finishing(within: Self.watchdogSeconds) { await s.waitForEnd(atMost: 0.05) }
        #expect(done != nil)
        #expect(!s.hasWaiter)
    }

    /// Every cooperative thread is blocked in the same process (here on purpose;
    /// on CI, by tests calling Security synchronously): the cap still fires.
    ///
    /// It used to be armed on `DispatchQueue.global()`, which is not an overcommit
    /// queue, and such a queue gets no thread while the cooperative pool is all
    /// blocked. Measured 2026-10-07, release build, 14-core Mac: a 0.05 s
    /// `global().asyncAfter` ran 19.5 s late, when the blocking tasks let go.
    /// That is how `theCapReleasesAWaitThatNeverEnds` failed on CI (run
    /// 37498589321): it returned at 130 s, together with the two signature checks
    /// that had held the 3-core runner's pool.
    ///
    /// The test registers the wait itself, with no helper task and no spinning:
    /// `waitForEnd` arms the cap before it suspends, and the blocking tasks take
    /// this thread once it has. (The first version had a helper task register it
    /// and spun on `Task.yield()` until it had. On CI's 3-core runner, with the
    /// other two threads in Security calls, the helper never ran and the yield
    /// never let it: Swift's `Task.yield()` "immediately resumes" a task that is
    /// the highest-priority one, and "isn't necessarily a way to avoid resource
    /// starvation". The job hung until its 1200 s limit, run 37508268328.)
    ///
    /// A plain `Thread`, which needs neither a cooperative nor a Dispatch thread
    /// to run, releases the pool once the cap has released the wait, or after
    /// 30 s. The 30 s is only how long a broken build takes to fail.
    /// Mutation: arm the cap on `DispatchQueue.global()` again → red at 30 s.
    @Test func theCapFiresWhileEveryCooperativeThreadIsBlocked() async throws {
        let s = StreamedLines()
        let pool = BlockedPool(tasks: 2 * ProcessInfo.processInfo.activeProcessorCount)
        let released = pool.release(within: 30) { s.waitsReleasedByCap > 0 }
        await s.waitForEnd(atMost: 0.5)
        let outcome = await released.value
        #expect(outcome.conditionMet, "the cap had not fired after 30 s with the pool blocked")
        // More blocking tasks than threads, so some were still queued: the pool
        // was full when the cap fired, or this test showed nothing.
        #expect(outcome.saturated, "the pool was not full when the cap fired")
    }

    /// `tasks` tasks that each block a cooperative thread until `release`.
    private final class BlockedPool: @unchecked Sendable {
        let tasks: Int
        private let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var started = 0

        init(tasks: Int) {
            self.tasks = tasks
            for _ in 0..<tasks {
                Task.detached(priority: .high) { [self] in block() }
            }
        }

        private func block() {
            lock.withLock { started += 1 }
            gate.wait()
        }

        /// On a plain `Thread`: wait for `condition()` to turn true, or for
        /// `seconds`, then let every blocked task go. `saturated` is whether some
        /// tasks were still queued at that moment.
        func release(
            within seconds: Double, until condition: @escaping @Sendable () -> Bool
        ) -> Promise<(conditionMet: Bool, saturated: Bool)> {
            let promise = Promise<(conditionMet: Bool, saturated: Bool)>()
            Thread.detachNewThread { [self] in
                let deadline = Date().addingTimeInterval(seconds)
                while !condition(), Date() < deadline { usleep(1_000) }
                let met = condition()
                let saturated = lock.withLock { started } < tasks
                for _ in 0..<tasks { gate.signal() }
                promise.fulfill((met, saturated))
            }
            return promise
        }
    }

    /// A value set once from any thread and awaited from a task.
    private final class Promise<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: T?
        private var waiter: CheckedContinuation<T, Never>?

        func fulfill(_ value: T) {
            lock.lock()
            result = value
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume(returning: value)
        }

        var value: T {
            get async {
                await withCheckedContinuation { cont in
                    lock.lock()
                    if let result {
                        lock.unlock()
                        cont.resume(returning: result)
                    } else {
                        waiter = cont
                        lock.unlock()
                    }
                }
            }
        }
    }

    // MARK: - run(_:) against a real pipe
    //
    // `/bin/sh` and `seq` are part of macOS itself, not something a machine may or
    // may not have installed, and these scripts read no host state.

    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var got: [String] = []
        func add(_ line: String) { lock.lock(); got.append(line); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return got }
    }

    private struct Ran: Sendable {
        let lines: [String]
        let text: String
        let status: Int32
    }

    private static func sh(_ script: String, within: Double = 60) async throws -> Ran? {
        try await finishing(within: within) {
            let sink = Sink()
            let (outcome, text) = try await StreamedLines.run(
                "/bin/sh", ["-c", script], environment: ProcessInfo.processInfo.environment,
                onOutput: sink.add)
            return Ran(lines: sink.lines, text: text, status: outcome.terminationStatus)
        }
    }

    /// A burst written just before exit. Clearing the handler when the process
    /// exited lost whatever was still in the pipe — measured on `brew formulae`,
    /// every run. `seq` writes its ~209 KB in a few block-sized writes, far more than
    /// the pipe's buffer, and exits the moment the last one lands.
    @Test func outputWrittenJustBeforeExitIsNotLost() async throws {
        let r = try #require(try await Self.sh("seq -f 'line %g' 0 19999; exit 3"))
        #expect(r.status == 3)
        #expect(r.lines.count == 20000)
        #expect(r.lines.last == "line 19999")
        #expect(r.text.utf8.count == r.lines.reduce(0) { $0 + $1.utf8.count + 1 })
    }

    /// A pause inside `🍺` puts a chunk boundary there, and the output ends without
    /// a newline — the line still arrives whole, and so does the tail.
    @Test func aLineSplitAcrossWritesArrivesWhole() async throws {
        let r = try #require(try await Self.sh(#"printf '\360\237'; sleep 0.2; printf '\215\272  /opt/homebrew/Cellar/zzfixture-alpha/1.0: 9 files, 1MB\nno newline'"#))
        #expect(r.lines == ["🍺  /opt/homebrew/Cellar/zzfixture-alpha/1.0: 9 files, 1MB", "no newline"])
        let first = try #require(r.lines.first)
        #expect(BrewFormulaService.pouredFormula(fromLine: first) == "zzfixture-alpha")
    }

    /// brew's `Error:` lines go to stderr, and they are what `BrewError.failed`
    /// reports, so stderr has to arrive in the same stream as stdout, in order.
    /// Mutation: `standardError: .discard` in `run` → the error line is missing.
    @Test func standardErrorArrivesInTheSameStream() async throws {
        let r = try #require(try await Self.sh("echo progress; echo 'Error: zzfixture-broken' >&2; exit 1"))
        #expect(r.status == 1)
        #expect(r.lines == ["progress", "Error: zzfixture-broken"])
        #expect(r.text.contains("Error: zzfixture-broken"))
    }

    /// A background child inherits stdout and outlives the shell: no EOF until it
    /// exits. The run returns anyway once the shell has exited and what it printed
    /// is drained (`ChildProcess` stops waiting for EOF at the exit). The child
    /// outlives the watchdog, so a run that waited for EOF fails here rather than
    /// passing late.
    @Test func aChildHoldingThePipeOpenDoesNotHangTheRun() async throws {
        let r = try #require(try await Self.sh("sleep 60 & echo parent-done", within: 30))
        #expect(r.lines == ["parent-done"])
    }
}
