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
            deadline: .init(terminateAfter: .seconds(2), killAfter: .seconds(3)),
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
            deadline: .init(terminateAfter: .seconds(2), killAfter: .seconds(20)),
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
