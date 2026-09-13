import Foundation
import Testing
@testable import DuoUpdaterCore

/// `ChildProcess` against real children — `/bin/sh` running scripts written into a
/// scratch directory, nothing installed or running on the host.
///
/// No assertion here bounds a duration: this suite runs in parallel with ~2,000
/// others, where wall-clock upper bounds are not sound. Where a broken
/// implementation would HANG rather than fail, the child is written to give up on
/// its own (or the call carries a generous deadline) so the mutation turns into a
/// wrong outcome instead of a stuck run.
@Suite struct ChildProcessTests {

    // MARK: - Pipes

    /// More than a pipe buffer on BOTH streams, interleaved, so reading either one
    /// to its end before starting the other deadlocks: the child blocks writing
    /// the stream nobody is reading.
    ///
    /// Mutation: in `Sink.drain`, read `output` to its end before adding the
    /// `error` task → the child wedges, the 120 s deadline kills it, `timedOut` is
    /// true and both sizes are short.
    @Test func bothStreamsPastAPipeBufferDrainTogether() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let chunk = 100_000
        let script = try write(dir, "noisy.sh", """
            head -c \(chunk) /dev/zero | tr '\\0' e >&2
            head -c \(chunk) /dev/zero | tr '\\0' o
            head -c \(chunk) /dev/zero | tr '\\0' e >&2
            head -c \(chunk) /dev/zero | tr '\\0' o
            """)
        let outcome = try await ChildProcess.run(
            "/bin/sh", [script.path],
            deadline: .init(terminateAfter: .seconds(120), killAfter: .seconds(125)),
            onCancel: .terminateChild)
        #expect(!outcome.timedOut)
        #expect(outcome.succeeded)
        #expect(outcome.standardOutput.count == 2 * chunk)
        #expect(outcome.standardError.count == 2 * chunk)
        #expect(Set(outcome.standardOutput) == [UInt8(ascii: "o")])
        #expect(Set(outcome.standardError) == [UInt8(ascii: "e")])
    }

    /// `2>&1`: one stream, in the order the child wrote it.
    ///
    /// Mutation: give `.mergeIntoOutput` the separate-streams spelling in `launch`
    /// → stderr's line lands in `standardError` (discarded), and the merged text
    /// is missing it.
    @Test func mergedErrorArrivesInOrderOnStandardOutput() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo one; echo two >&2; echo three"],
            standardError: .mergeIntoOutput, onCancel: .terminateChild)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "one\ntwo\nthree\n")
        #expect(outcome.standardError.isEmpty)
    }

    /// `.discard` drops the bytes. Mutation: make `Sink` keep output regardless of
    /// `keepOutput` → the captured stdout is non-empty.
    @Test func discardedStreamsCollectNothing() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo out; echo err >&2"],
            standardOutput: .discard, standardError: .discard, onCancel: .terminateChild)
        #expect(outcome.succeeded)
        #expect(outcome.standardOutput.isEmpty)
        #expect(outcome.standardError.isEmpty)
    }

    /// Bytes given as stdin reach the child and are closed after, so a reader
    /// waiting for EOF finishes. Mutation: pass `.currentStandardInput` in the
    /// bytes spellings → `cat` sees the test runner's stdin, not the payload.
    @Test func standardInputBytesReachTheChild() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/cat", [], standardInput: Data("payload\n".utf8), onCancel: .terminateChild)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "payload\n")
    }

    /// Chunks are delivered as they arrive — before the child exits — which is
    /// what `brew`'s streamed log needs. The child waits for a file the callback
    /// creates, so it can only finish if the chunk was delivered while it ran.
    ///
    /// Mutation: drop the per-buffer `onOutputChunk` call in `Sink.drainNow` →
    /// the child never sees the file and exits 9 when its own 30 s budget runs
    /// out.
    @Test func outputChunksArriveWhileTheChildRuns() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let go = dir.appendingPathComponent("go")
        let script = try write(dir, "stream.sh", """
            echo ready
            i=0
            while [ ! -f '\(go.path)' ]; do
              i=$((i+1)); [ $i -gt 300 ] && exit 9
              sleep 0.1
            done
            echo done
            """)
        let outcome = try await ChildProcess.run(
            "/bin/sh", [script.path], onCancel: .terminateChild,
            onOutputChunk: { chunk in
                if String(decoding: chunk, as: UTF8.self).contains("ready") {
                    FileManager.default.createFile(atPath: go.path, contents: nil)
                }
            })
        #expect(outcome.terminationStatus == 0)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self).contains("done"))
    }

    // MARK: - Environment, directory, status

    /// A non-nil environment REPLACES the inherited one, as assigning
    /// `Process.environment` did. Mutation: `.inherit.updating(custom)` instead of
    /// `.custom` → `HOME` survives into the child.
    @Test func anEnvironmentReplacesTheInheritedOne() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo \"[$ZZ_FIXTURE_VAR][$HOME]\""],
            environment: ["ZZ_FIXTURE_VAR": "set"], onCancel: .terminateChild)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "[set][]\n")
    }

    /// Without one, the child inherits ours. Mutation: `.custom([:])` for nil →
    /// `PATH` is empty in the child.
    @Test func noEnvironmentInheritsOurs() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "printf %s \"$PATH\""], onCancel: .terminateChild)
        let ours = ProcessInfo.processInfo.environment["PATH"] ?? ""
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == ours)
    }

    /// `xar -xf` extracts relative to its working directory. Mutation: drop
    /// `workingDirectory` from the `Configuration` → `pwd` prints ours.
    @Test func theWorkingDirectoryIsTheChilds() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try await ChildProcess.run(
            "/bin/pwd", ["-P"], workingDirectory: dir, onCancel: .terminateChild)
        let printed = String(decoding: outcome.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(printed == realPath(dir))
    }

    /// `/var` → `/private/var`, which `resolvingSymlinksInPath` goes the other way on.
    private func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Exit code and signal number share `terminationStatus`, told apart by
    /// `uncaughtSignal` — `Process`'s convention, which the error strings built
    /// from it depend on. Mutation: report `.signaled` as `uncaughtSignal: false`
    /// → the second pair of expectations fails.
    @Test func exitCodesAndSignalsKeepProcessConventions() async throws {
        let exited = try await ChildProcess.run("/bin/sh", ["-c", "exit 3"], onCancel: .terminateChild)
        #expect(exited.terminationStatus == 3)
        #expect(!exited.uncaughtSignal)
        #expect(!exited.succeeded)

        let signaled = try await ChildProcess.run(
            "/bin/sh", ["-c", "kill -TERM $$"], onCancel: .terminateChild)
        #expect(signaled.terminationStatus == SIGTERM)
        #expect(signaled.uncaughtSignal)
        #expect(!signaled.succeeded)
    }

    /// A missing executable is a throw, not an `Outcome` — the old sites caught
    /// `Process.run()` throwing for exactly this. Mutation: catch the launch error
    /// in `launch` and return status -1 → nothing throws.
    @Test func aMissingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await ChildProcess.run(
                "/nonexistent/ZZFixture-no-such-tool", [], onCancel: .terminateChild)
        }
    }

    // MARK: - Deadline

    /// The ladder's second rung: a child that ignores SIGTERM is SIGKILLed. The
    /// script gives up on its own after ~30 s and exits 7, so an implementation
    /// that never escalates produces a wrong outcome rather than a hang.
    ///
    /// 8 s before SIGTERM is margin, not a measurement: the deadline now starts at
    /// launch, so a spawn queued behind others no longer eats into it, but `sh`
    /// still has to start and run `trap` before SIGTERM lands, on a 3-core runner
    /// with the whole suite in flight.
    ///
    /// Mutations: (a) drop `group.cancelAll()` on `.deadlinePassed` → exits 7,
    /// not signaled; (b) drop the `timedOut` flag (`fired.set()`) → `timedOut`
    /// false.
    @Test func aChildIgnoringSIGTERMIsKilled() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = try write(dir, "stubborn.sh", """
            trap '' TERM
            echo trapped
            i=0
            while [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
            exit 7
            """)
        let outcome = try await ChildProcess.run(
            "/bin/sh", [script.path],
            deadline: .init(terminateAfter: .seconds(8), killAfter: .seconds(9)),
            onCancel: .runToCompletion)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "trapped\n")
        #expect(outcome.timedOut)
        #expect(outcome.uncaughtSignal)
        #expect(outcome.terminationStatus == SIGKILL)
    }

    /// The first rung: SIGTERM comes before SIGKILL, so a child that handles it
    /// gets to exit on its own terms. Mutation: `ladder` returns `[]` (straight to
    /// SIGKILL) → no "got-term", status 9 signaled.
    @Test func aChildHonouringSIGTERMExitsOnItsOwnTerms() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = try write(dir, "polite.sh", """
            trap 'echo got-term; exit 3' TERM
            i=0
            while [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
            exit 7
            """)
        let outcome = try await ChildProcess.run(
            "/bin/sh", [script.path],
            deadline: .init(terminateAfter: .seconds(8), killAfter: .seconds(20)),
            onCancel: .runToCompletion)
        #expect(outcome.timedOut)
        #expect(!outcome.uncaughtSignal)
        #expect(outcome.terminationStatus == 3)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self).contains("got-term"))
    }

    /// A child that finishes inside its deadline is untouched by it. Mutation:
    /// `timedOut: { true }` in `raceDeadline` → true here.
    @Test func aChildInsideItsDeadlineIsNotTimedOut() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo quick"],
            deadline: .init(terminateAfter: .seconds(60), killAfter: .seconds(65)),
            onCancel: .runToCompletion)
        #expect(outcome.succeeded)
        #expect(!outcome.timedOut)
    }

    // MARK: - Cancellation

    /// `.runToCompletion`: cancelling the caller does not reach the child. The
    /// child reports "started" and then needs a further moment; the task is
    /// cancelled in between, and the child must still finish and be reported.
    ///
    /// Mutation: route `.runToCompletion` through the `.terminateChild` branch →
    /// the child is SIGKILLed and the call throws `CancellationError`.
    @Test func runToCompletionOutlivesTheCallersCancellation() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("finished")
        let started = Signal()
        let task = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", "echo started; sleep 1; touch '\(marker.path)'; echo done"],
                onCancel: .runToCompletion,
                onOutputChunk: { chunk in
                    if String(decoding: chunk, as: UTF8.self).contains("started") { started.fire() }
                })
        }
        await started.wait()
        task.cancel()
        let outcome = try await task.value
        #expect(outcome.succeeded)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self).contains("done"))
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// `.terminateChild`: cancelling the caller tears the child down and throws.
    /// The child would create a marker after ~30 s; it must never get there.
    ///
    /// Mutation: route `.terminateChild` through the detached branch → the child
    /// runs to the end, the marker exists and nothing throws.
    @Test func terminateChildTearsTheChildDownOnCancellation() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("finished")
        let started = Signal()
        let task = Task {
            try await ChildProcess.run(
                "/bin/sh",
                ["-c", "echo started; i=0; while [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done; touch '\(marker.path)'"],
                onCancel: .terminateChild,
                onOutputChunk: { chunk in
                    if String(decoding: chunk, as: UTF8.self).contains("started") { started.fire() }
                })
        }
        await started.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    /// A task already cancelled never spawns under `.terminateChild` — observed
    /// through `onLaunch`, which swift-subprocess calls for every child it starts,
    /// cancelled or not.
    ///
    /// Mutation: drop the leading `Task.checkCancellation()` in `run` → the child
    /// is spawned (and then torn down), `onLaunch` fires once.
    @Test func anAlreadyCancelledTaskNeverSpawns() async throws {
        let launches = Counter()
        let task = Task { () async throws -> ChildProcess.Outcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChildProcess.run(
                "/bin/sh", ["-c", "sleep 5"], onCancel: .terminateChild,
                onLaunch: { _ in launches.increment() })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(launches.value == 0)
    }

    // MARK: - Round 1 of review: process group, environment, stdin, deadline clock

    /// The child is the leader of its own process group, as a `Process` child was
    /// (measured), so a terminal's Ctrl-C to our group does not reach it.
    ///
    /// Mutation: drop `options.processGroupID = 0` → the child's pgid is ours.
    @Test func theChildLeadsItsOwnProcessGroup() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo $$; ps -o pgid= -p $$"], onCancel: .terminateChild)
        let fields = String(decoding: outcome.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
        #expect(fields.count == 2)
        #expect(fields.first == fields.last, "the child's pgid is its own pid")
        #expect(fields.last != getpgrp(), "the child is not in our group")
    }

    /// Keys POSIX does not allow are dropped rather than failing the spawn — a
    /// `Process` passed them through, swift-subprocess refuses to spawn.
    ///
    /// Mutation: skip `spawnableEnvironment` (pass the dictionary straight
    /// through) → `run` throws `spawnFailed`.
    @Test func invalidEnvironmentEntriesAreDroppedNotFatal() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "printf '[%s]' \"$ZZ_FIXTURE_GOOD\""],
            environment: ["1BAD": "digit", "A=B": "equals", "ZZ_FIXTURE_GOOD": "kept"],
            onCancel: .terminateChild)
        #expect(outcome.succeeded)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "[kept]")
    }

    /// The rule itself, including the value half. Mutation: stop checking for a
    /// leading digit → `1BAD` is kept.
    @Test func theEnvironmentFilterNamesWhatItDrops() {
        let result = ChildProcess.spawnableEnvironment([
            "1BAD": "x", "A=B": "x", "NUL\u{0}KEY": "x", "VALUE_NUL": "a\u{0}b",
            "GOOD": "x", "_ALSO_GOOD": "x",
        ])
        #expect(result.kept == ["GOOD": "x", "_ALSO_GOOD": "x"])
        #expect(result.dropped == ["1BAD", "A=B", "NUL\u{0}KEY", "VALUE_NUL"].sorted())
    }

    /// What `ensureStandardInputIsOpen` does to fd 0: a closed descriptor is pointed
    /// at `/dev/null`, an open one is left alone. Exercised on a closed high
    /// descriptor, not on fd 0 — closing this process's fd 0 would reach every test
    /// running beside it. fd 0 end to end was measured with a separate probe run
    /// under `<&-` (see the PR).
    ///
    /// Mutations: skip the `dup2` → the descriptor stays closed; drop both checks
    /// that it is closed → the pipe below is replaced by `/dev/null`. (Dropping
    /// only the first changes nothing observable: the re-check before `dup2`
    /// still holds.)
    @Test func aClosedDescriptorIsPointedAtDevNull() throws {
        let closed = try #require((Int32(300)..<Int32(1000)).first { fcntl($0, F_GETFD) == -1 })
        defer { close(closed) }
        ChildProcess.fillWithDevNullIfClosed(closed)
        var filled = stat(), devNull = stat()
        #expect(fstat(closed, &filled) == 0)
        #expect(stat("/dev/null", &devNull) == 0)
        #expect(filled.st_rdev == devNull.st_rdev && (filled.st_mode & S_IFMT) == S_IFCHR)

        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        defer { close(ends[0]); close(ends[1]) }
        ChildProcess.fillWithDevNullIfClosed(ends[0])
        var kept = stat()
        #expect(fstat(ends[0], &kept) == 0)
        #expect((kept.st_mode & S_IFMT) == S_IFIFO)
    }

    /// The deadline counts from launch. Here the wait before the spawn (6 s,
    /// injected) is longer than `terminateAfter` (3 s) and the child itself is
    /// instant, so a clock started at the call would kill it before it ran.
    ///
    /// Mutation: drop `try await launched.wait()` in `raceDeadline` → the deadline
    /// fires during the pre-launch wait, the child is torn down, `timedOut`.
    @Test func theDeadlineClockStartsAtLaunch() async throws {
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "echo ran"],
            deadline: .init(terminateAfter: .seconds(3), killAfter: .seconds(4)),
            onCancel: .runToCompletion,
            beforeSpawn: { try? await Task.sleep(for: .seconds(6)) })
        #expect(!outcome.timedOut)
        #expect(outcome.succeeded)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self) == "ran\n")
    }

    /// A launch that fails never starts the clock, and the race still ends: the
    /// waiting half is cancelled rather than left suspended.
    ///
    /// Mutation: make `LaunchSignal.wait` ignore cancellation (no
    /// `withTaskCancellationHandler`) → this call never returns; the 60 s watchdog
    /// reports it.
    @Test func aFailedLaunchWithADeadlineStillReturns() async {
        let finished = await Self.within(seconds: 60) {
            _ = try? await ChildProcess.run(
                "/nonexistent/ZZFixture-no-such-tool",
                deadline: .init(terminateAfter: .seconds(300), killAfter: .seconds(305)),
                onCancel: .terminateChild)
        }
        #expect(finished)
    }

    /// True when `body` finished within `seconds`; abandons it otherwise.
    private static func within(seconds: Double, _ body: @escaping @Sendable () async -> Void) async -> Bool {
        final class Once: @unchecked Sendable {
            let lock = NSLock()
            var continuation: CheckedContinuation<Bool, Never>?
            func resume(_ value: Bool) {
                let c: CheckedContinuation<Bool, Never>? = lock.withLock {
                    defer { continuation = nil }
                    return continuation
                }
                c?.resume(returning: value)
            }
        }
        let once = Once()
        return await withCheckedContinuation { continuation in
            once.lock.withLock { once.continuation = continuation }
            Task { await body(); once.resume(true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(false) }
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    // MARK: - Helpers

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-childprocess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ dir: URL, _ name: String, _ body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url
    }

    /// Fires once; `wait` returns once it has fired, whenever that was.
    private final class Signal: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func fire() {
            let resume: [CheckedContinuation<Void, Never>] = lock.withLock {
                guard !fired else { return [] }
                fired = true
                defer { waiters = [] }
                return waiters
            }
            resume.forEach { $0.resume() }
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                let now: Bool = lock.withLock {
                    if fired { return true }
                    waiters.append(continuation)
                    return false
                }
                if now { continuation.resume() }
            }
        }
    }
}
