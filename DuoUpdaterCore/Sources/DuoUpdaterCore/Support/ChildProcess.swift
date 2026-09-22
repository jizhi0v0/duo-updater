import Foundation
internal import Subprocess
#if canImport(System)
internal import System
#else
internal import SystemPackage
#endif

/// Launch a child process and wait for it **without parking a thread**.
///
/// Every child process that anything waits on in `DuoUpdaterCore`, `duo` and the
/// menu-bar app goes through here (the privileged helper under `App/Helper` is
/// its own synchronous daemon and does not). It replaces `Foundation.Process` + `waitUntilExit()` /
/// `readDataToEndOfFile()`, whose waits each held a thread for the child's whole
/// lifetime — on the cooperative pool that is the #351 failure (see
/// `offCooperativePool`), and off it, one Dispatch thread per wait.
/// swift-subprocess monitors exit with kqueue (`EVFILT_PROC`/`NOTE_EXIT`) and
/// reads the pipes through the same kqueue, so an `await` here suspends and the
/// thread goes back to the pool.
///
/// One function rather than a framework: it encodes the handful of per-site
/// policies the old call sites spelled out by hand, and nothing else.
///
/// ## What it preserves from the `Process` call sites it replaced
///
/// - **Both pipes drain concurrently**, always. Neither can fill its ~64 KB buffer
///   while we wait on the other — the deadlock the old sites each worked around on
///   their own, with a background drain, a `nullDevice` or a temporary file.
/// - **No output limit.** The old sites read to EOF unbounded, so this does too:
///   swift-subprocess's `limit:` throws `outputLimitExceeded` rather than
///   truncating, which would have turned a verbose tool into a launch failure.
/// - **`terminationStatus` means what `Process.terminationStatus` meant**: the
///   exit code, or the signal number when the child died of one
///   (`uncaughtSignal` tells the two apart). Error strings built from it — "tar
///   failed (15)", "unzip exited 9" — read the same.
/// - **stdin is inherited** unless `standardInput` supplies bytes, which is
///   `Process`'s default too. A process started with no fd 0 at all
///   (`duo … <&-`) must call `ensureStandardInputIsOpen()` first thing, or its
///   children start with no stdin — see there. `duo` does; the app does not
///   need to. Nothing here fills it per spawn, because that races.
/// - **The environment is inherited** unless `environment` is non-nil, in which
///   case it replaces the whole environment, as assigning `Process.environment`
///   did. Entries POSIX does not allow (a key containing `=` or NUL, or starting
///   with a digit; a value containing NUL) are dropped and their KEYS logged:
///   `Process` passed them through, while swift-subprocess refuses to spawn at
///   all, so one odd variable in a user's shell would otherwise fail every `brew`.
/// - **The child gets its own process group**, as `Process` gave it. Measured: a
///   `Process` child's pgid is its own pid; a swift-subprocess child shares ours by
///   default and so dies with us on a terminal Ctrl-C — `ditto`, `BinaryDelta`,
///   the swap's `osascript` included.
///
/// ## What it does differently
///
/// The reads end when the child exits, even if a grandchild it left running still
/// holds the pipe (swift-subprocess cancels them on `NOTE_EXIT`). A
/// `readDataToEndOfFile()` waited for the grandchild: measured, `sh -c 'sleep 5 &
/// echo hi'` returned after 5.08 s through `Process` and after 0.01 s here.
///
/// ## Deadline
///
/// `Deadline(terminateAfter:killAfter:)` is the ladder the old call sites built
/// from two `DispatchWorkItem`s armed right after `Process.run()`: SIGTERM once
/// `terminateAfter` has passed since the child LAUNCHED, then SIGKILL if it is
/// still there `killAfter - terminateAfter` later (the grace runs from when SIGTERM
/// is sent). `timedOut` reports that the deadline fired before the child exited.
///
/// The clock starts at launch, not at this call, because the wait before launch
/// is not the child's: swift-subprocess performs every `posix_spawn` in this
/// process on ONE shared worker thread, so a spawn queues behind every other.
/// There is deliberately no guard on that pre-launch wait: there is no child to
/// signal yet, so a timer could only abandon the call, and the old sites had
/// no such bound either.
///
/// That single spawn thread is also a risk this type does not measure: an `exec`
/// that is slow to return would hold up every other spawn in the process. Not
/// measured — an attempt used a quarantined binary, which put a Gatekeeper dialog
/// on the user's screen, and was abandoned.
///
/// ## Cancellation — chosen per call, never defaulted
///
/// This is the biggest behaviour change, so every call site has to spell it:
///
/// - `.runToCompletion` — the child runs to its end even if the calling task is
///   cancelled, and the outcome is returned as if nothing happened. That is what
///   the old `offCooperativePool` hop did (it is not cancellable) and it is the
///   only safe choice for anything that writes: a half-copied bundle, a
///   half-applied delta, a DMG left mounted, an `osascript` swap cut between its
///   two renames. The run happens in an unstructured task whose cancellation the
///   caller's does not reach. (SE-0504's `withTaskCancellationShield` would say
///   this directly but is not back-deployed, and this ships to macOS 15.)
/// - `.terminateChild` — cancelling the calling task tears the child down (the
///   deadline's ladder if there is one, otherwise SIGKILL straight away) and this
///   throws `CancellationError`; a task already cancelled does not spawn at all.
///   For read-only queries, where nobody is left to want the answer.
///
/// ## Two things it does not protect against
///
/// - **SIGPIPE in this process.** Bytes given as `standardInput` are written with
///   `write(2)`; a child that exits without reading them raises SIGPIPE here, and
///   nothing in this repository ignores it. No call site passes bytes today.
/// - **A failed pipe read.** swift-subprocess answers an error thrown while
///   reading by tearing the child down, `.runToCompletion` or not.
public enum ChildProcess {

    /// What happens to the child's standard output.
    public enum OutputPolicy: Sendable {
        /// Read and dropped. The pipe is still drained, so the child never blocks
        /// writing to it.
        case discard
        /// Collected into `Outcome.standardOutput`.
        case capture
    }

    /// What happens to the child's standard error.
    public enum ErrorPolicy: Sendable {
        case discard
        case capture
        /// The same pipe as standard output (`2>&1`), in the order the child wrote
        /// it. `Outcome.standardError` is then empty.
        case mergeIntoOutput
    }

    public enum Cancellation: Sendable {
        case runToCompletion
        case terminateChild
    }

    public struct Deadline: Sendable, Equatable {
        public let terminateAfter: Duration
        public let killAfter: Duration

        /// `terminateAfter` from the child's launch; `killAfter` on the same
        /// scale, so the grace is the difference. It must not precede
        /// `terminateAfter`.
        public init(terminateAfter: Duration, killAfter: Duration) {
            precondition(killAfter >= terminateAfter, "SIGKILL cannot precede SIGTERM")
            self.terminateAfter = terminateAfter
            self.killAfter = killAfter
        }
    }

    public struct Outcome: Sendable {
        /// The exit code, or the signal number when `uncaughtSignal` — the same
        /// convention as `Process.terminationStatus`.
        public let terminationStatus: Int32
        public let uncaughtSignal: Bool
        /// The deadline fired before the child had exited.
        public let timedOut: Bool
        public let standardOutput: Data
        public let standardError: Data

        /// Exited, with status 0.
        public var succeeded: Bool { !uncaughtSignal && terminationStatus == 0 }
    }

    /// Run `executablePath` with `arguments` and wait for it to exit.
    ///
    /// - Parameter onOutputChunk: called with each chunk of standard output as it
    ///   arrives, before the child has exited — for `brew`'s streamed log. With
    ///   `standardOutput: .capture` the chunks are also collected.
    /// - Parameter onLaunch: called once with the child's pid, after the spawn and
    ///   before anything is read. For a caller that must signal more than the
    ///   child itself (`LoginShellEnvironment`'s process-tree kill); the pid stays
    ///   the child's until this call returns, because the child is not reaped
    ///   before then.
    /// - Throws: when the child cannot be launched (a missing executable, say), or
    ///   `CancellationError` under `.terminateChild`. A non-zero exit is an
    ///   `Outcome`, never a throw.
    public static func run(
        _ executablePath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardInput: Data? = nil,
        standardOutput: OutputPolicy = .capture,
        standardError: ErrorPolicy = .capture,
        deadline: Deadline? = nil,
        onCancel: Cancellation,
        onOutputChunk: (@Sendable (Data) -> Void)? = nil,
        onLaunch: (@Sendable (pid_t) -> Void)? = nil
    ) async throws -> Outcome {
        try await run(
            executablePath, arguments, environment: environment,
            workingDirectory: workingDirectory, standardInput: standardInput,
            standardOutput: standardOutput, standardError: standardError,
            deadline: deadline, onCancel: onCancel, onOutputChunk: onOutputChunk,
            onLaunch: onLaunch, beforeSpawn: nil)
    }

    /// Point this process's fd 0 at `/dev/null` if it has none. Call it at process
    /// start, before other threads exist.
    ///
    /// Without an fd 0 a child gets none either (swift-subprocess passes the hole
    /// on), where a `Process` child got `/dev/null` — measured under `<&-`. And a
    /// hole at 0 is worse than that: the next descriptor this process opens lands
    /// on it, and when that is a spawn's own pipe end, swift-subprocess's file
    /// actions close it in the child after setting up stdin. Filling it per spawn
    /// was tried and races other threads' `open`/`pipe` for the same number.
    ///
    /// `duo` calls it first thing in `main.swift`. The app does not: a launched
    /// app already has `/dev/null` as fd 0 from launchd (measured with `lsof` on
    /// the running DuoUpdater and on Finder), and the earliest code the SwiftUI
    /// `App` runs comes after `AppListModel`, which starts threads, is built.
    public static func ensureStandardInputIsOpen() {
        fillWithDevNullIfClosed(STDIN_FILENO)
    }

    /// Test seam: `beforeSpawn` runs after the deadline race has started and before
    /// the spawn (so a test can make the pre-launch wait long), and `deadlineSleep`
    /// is the deadline's clock (so a test can tell whether it started before or
    /// after the launch without racing it against real time).
    static func run(
        _ executablePath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardInput: Data? = nil,
        standardOutput: OutputPolicy = .capture,
        standardError: ErrorPolicy = .capture,
        deadline: Deadline? = nil,
        onCancel: Cancellation,
        onOutputChunk: (@Sendable (Data) -> Void)? = nil,
        onLaunch: (@Sendable (pid_t) -> Void)? = nil,
        beforeSpawn: (@Sendable () async -> Void)?,
        deadlineSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> Outcome {
        let request = Request(
            executablePath: executablePath, arguments: arguments,
            environment: environment, workingDirectory: workingDirectory,
            standardInput: standardInput, standardOutput: standardOutput,
            standardError: standardError, deadline: deadline,
            onOutputChunk: onOutputChunk, onLaunch: onLaunch,
            beforeSpawn: beforeSpawn, deadlineSleep: deadlineSleep)
        switch onCancel {
        case .runToCompletion:
            // Unstructured on purpose: awaiting `.value` does not forward the
            // caller's cancellation into the task, so the child is never torn
            // down on the caller's account. The deadline still applies — it
            // cancels from inside.
            return try await Task.detached(priority: Task.currentPriority) {
                try await request.raceDeadline(teardownOnCancel: request.ladder)
            }.value
        case .terminateChild:
            // A task that is already cancelled never spawns. Without this the child
            // is launched and then SIGKILLed a few task hops later, and a quick one
            // can finish first — which made "this site must not be torn down" tests
            // pass or fail by a race instead of by the policy.
            try Task.checkCancellation()
            let outcome = try await request.raceDeadline(teardownOnCancel: request.ladder)
            try Task.checkCancellation()
            return outcome
        }
    }

    // MARK: - Implementation

    /// Point `descriptor` at `/dev/null` if it is closed; leave it alone if it is
    /// open. Not thread-safe with respect to other threads opening descriptors —
    /// hence `ensureStandardInputIsOpen`'s "at process start". For fd 0 `open` itself lands there (the lowest free descriptor);
    /// `dup2` covers any other number, and is skipped if something else took the
    /// descriptor in the meantime rather than clobbering it.
    static func fillWithDevNullIfClosed(_ descriptor: Int32) {
        guard fcntl(descriptor, F_GETFD) == -1 else { return }
        let opened = open("/dev/null", O_RDONLY)
        guard opened >= 0, opened != descriptor else { return }
        if fcntl(descriptor, F_GETFD) == -1 { dup2(opened, descriptor) }
        close(opened)
    }

    private static let closedStandardInputReported = Flag()

    /// Once per process: a spawn found fd 0 closed, so the child starts without
    /// stdin. Reported rather than repaired — see `ensureStandardInputIsOpen`.
    private static func reportClosedStandardInput(_ executablePath: String) {
        guard closedStandardInputReported.setIfUnset() else { return }
        Log.app.error(
            "child process \((executablePath as NSString).lastPathComponent, privacy: .public): this process has no fd 0, so the child starts without stdin — ChildProcess.ensureStandardInputIsOpen() was not called at startup")
    }

    /// The environment swift-subprocess will accept: POSIX-invalid entries removed.
    /// Returns what is left and the keys that were dropped.
    static func spawnableEnvironment(_ environment: [String: String]) -> (kept: [String: String], dropped: [String]) {
        var kept: [String: String] = [:]
        var dropped: [String] = []
        for (key, value) in environment {
            let keyBytes = key.utf8
            let invalid = keyBytes.isEmpty
                || keyBytes.contains(UInt8(ascii: "=")) || keyBytes.contains(0)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(keyBytes.first!)
                || value.utf8.contains(0)
            if invalid { dropped.append(key) } else { kept[key] = value }
        }
        return (kept, dropped.sorted())
    }

    private struct Request: Sendable {
        let executablePath: String
        let arguments: [String]
        let environment: [String: String]?
        let workingDirectory: URL?
        let standardInput: Data?
        let standardOutput: OutputPolicy
        let standardError: ErrorPolicy
        let deadline: Deadline?
        let onOutputChunk: (@Sendable (Data) -> Void)?
        let onLaunch: (@Sendable (pid_t) -> Void)?
        let beforeSpawn: (@Sendable () async -> Void)?
        let deadlineSleep: @Sendable (Duration) async throws -> Void

        /// The steps swift-subprocess runs when the task driving the child is
        /// cancelled — by the deadline below, or (under `.terminateChild`) by the
        /// caller. It always appends a final SIGKILL.
        var ladder: [TeardownStep] {
            guard let deadline else { return [] }
            return [.gracefulShutDown(
                allowedDurationToNextStep: deadline.killAfter - deadline.terminateAfter)]
        }

        private enum Event: Sendable {
            case finished(Outcome)
            case deadlinePassed
            case deadlineAbandoned
        }

        func raceDeadline(teardownOnCancel steps: [TeardownStep]) async throws -> Outcome {
            guard let deadline else {
                return try await launch(teardown: steps, launched: nil, timedOut: { false })
            }
            let fired = Flag()
            let launched = LaunchSignal()
            return try await withThrowingTaskGroup(of: Event.self) { group in
                group.addTask {
                    .finished(try await launch(
                        teardown: steps, launched: launched, timedOut: { fired.value }))
                }
                group.addTask {
                    do {
                        // From launch, not from here: see "Deadline".
                        try await launched.wait()
                        try await deadlineSleep(deadline.terminateAfter)
                        return .deadlinePassed
                    } catch {
                        return .deadlineAbandoned
                    }
                }
                while let event = try await group.next() {
                    switch event {
                    case .deadlinePassed:
                        fired.set()
                        // Cancels the launch task, which swift-subprocess answers
                        // with `steps`: SIGTERM, the grace, then SIGKILL.
                        group.cancelAll()
                    case .deadlineAbandoned:
                        continue
                    case .finished(let outcome):
                        group.cancelAll()
                        return outcome
                    }
                }
                // The launch task either returns `.finished` or throws out of
                // `next()`; the loop cannot end without one of them.
                throw CancellationError()
            }
        }

        private func launch(
            teardown steps: [TeardownStep], launched: LaunchSignal?,
            timedOut: @escaping @Sendable () -> Bool
        ) async throws -> Outcome {
            var options = PlatformOptions()
            options.teardownSequence = steps
            // Its own group (pgid = its pid), as `Process` gave it: a terminal's
            // Ctrl-C goes to our foreground group and must not reach a `ditto` or an
            // `osascript` halfway through a swap. Teardown signals the pid alone, so
            // nothing else changes.
            options.processGroupID = 0
            let env: Subprocess.Environment
            if let environment {
                let spawnable = ChildProcess.spawnableEnvironment(environment)
                if !spawnable.dropped.isEmpty {
                    Log.app.error(
                        "child process \((executablePath as NSString).lastPathComponent, privacy: .public): dropped environment entries POSIX does not allow, keys: \(spawnable.dropped.joined(separator: ", "), privacy: .public)")
                }
                var custom: [Subprocess.Environment.Key: String] = [:]
                for (key, value) in spawnable.kept {
                    if let key = Subprocess.Environment.Key(rawValue: key) { custom[key] = value }
                }
                env = .custom(custom)
            } else {
                env = .inherit
            }
            let configuration = Configuration(
                executable: .path(FilePath(executablePath)),
                arguments: Arguments(arguments),
                environment: env,
                workingDirectory: workingDirectory.map { FilePath($0.path) },
                platformOptions: options)
            let sink = Sink(keepOutput: standardOutput == .capture,
                            keepError: standardError == .capture,
                            onOutputChunk: onOutputChunk)
            let onLaunch = self.onLaunch
            let started: @Sendable (pid_t) -> Void = { pid in
                onLaunch?(pid)
                launched?.fire()
            }
            await beforeSpawn?()

            if standardInput == nil, fcntl(STDIN_FILENO, F_GETFD) == -1 {
                ChildProcess.reportClosedStandardInput(executablePath)
            }
            let status: TerminationStatus
            if let standardInput {
                status = try await spawn(configuration, input: .data(standardInput), sink: sink, started: started)
            } else {
                status = try await spawn(configuration, input: .currentStandardInput, sink: sink, started: started)
            }

            let code: Int32
            let signaled: Bool
            switch status {
            case .exited(let exitCode): (code, signaled) = (exitCode, false)
            case .signaled(let signal): (code, signaled) = (signal, true)
            }
            return Outcome(
                terminationStatus: code, uncaughtSignal: signaled, timedOut: timedOut(),
                standardOutput: sink.output, standardError: sink.error)
        }

        /// Two spellings of one call: swift-subprocess's error type is static, and
        /// stderr is either its own pipe or merged into stdout's.
        private func spawn<Input: InputProtocol>(
            _ configuration: Configuration, input: Input, sink: Sink,
            started: @escaping @Sendable (pid_t) -> Void
        ) async throws -> TerminationStatus {
            if standardError == .mergeIntoOutput {
                return try await Subprocess.run(
                    configuration, input: input, output: .sequence, error: .combinedWithOutput
                ) { execution in
                    started(execution.processIdentifier.value)
                    try await sink.drain(output: execution.standardOutput, error: nil)
                }.terminationStatus
            }
            return try await Subprocess.run(
                configuration, input: input, output: .sequence, error: .sequence
            ) { execution in
                started(execution.processIdentifier.value)
                try await sink.drain(output: execution.standardOutput, error: execution.standardError)
            }.terminationStatus
        }
    }

    /// Fires once, when the child has launched; `wait` returns then, or throws
    /// `CancellationError` if the waiting task is cancelled first (a launch that
    /// throws ends the race, which cancels the waiter).
    private final class LaunchSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        private var waiter: CheckedContinuation<Void, Never>?

        func fire() {
            let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                fired = true
                defer { waiter = nil }
                return waiter
            }
            resume?.resume()
        }

        func wait() async throws {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let now: Bool = lock.withLock {
                        if fired || Task.isCancelled { return true }
                        waiter = continuation
                        return false
                    }
                    if now { continuation.resume() }
                }
            } onCancel: {
                let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                    defer { waiter = nil }
                    return waiter
                }
                resume?.resume()
            }
            try Task.checkCancellation()
        }
    }

    /// Where the two pipes' bytes go while the child runs. Written only from
    /// `drain`'s two child tasks, one per stream, and read after both finish.
    private final class Sink: @unchecked Sendable {
        let keepOutput: Bool
        let keepError: Bool
        let onOutputChunk: (@Sendable (Data) -> Void)?
        private let lock = NSLock()
        private var outputBytes = Data()
        private var errorBytes = Data()

        init(keepOutput: Bool, keepError: Bool, onOutputChunk: (@Sendable (Data) -> Void)?) {
            self.keepOutput = keepOutput
            self.keepError = keepError
            self.onOutputChunk = onOutputChunk
        }

        var output: Data { lock.withLock { outputBytes } }
        var error: Data { lock.withLock { errorBytes } }

        /// Read both streams to their end at the same time — never one after the
        /// other, which is the 64 KB deadlock.
        ///
        /// In an unstructured task, so the reads do not see the cancellation that
        /// starts a teardown. They wait on an `AsyncStream`, whose iterator ends
        /// the moment its task is cancelled: read inline, a deadline's SIGTERM
        /// closed both pipes on the spot, so a child that wrote anything while
        /// shutting down died of SIGPIPE (status 13) and what it wrote was lost —
        /// measured, not guessed: `aChildHonouringSIGTERMExitsOnItsOwnTerms`.
        /// The old `Process` sites kept draining through the grace period, and so
        /// does this. The reads still end: at EOF, or when swift-subprocess
        /// cancels them itself once the child has exited.
        func drain(
            output: SubprocessOutputSequence, error: SubprocessOutputSequence?
        ) async throws {
            try await Task { try await self.drainNow(output: output, error: error) }.value
        }

        private func drainNow(
            output: SubprocessOutputSequence, error: SubprocessOutputSequence?
        ) async throws {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await buffer in output {
                        let chunk = Data(buffer: buffer)
                        self.onOutputChunk?(chunk)
                        if self.keepOutput { self.lock.withLock { self.outputBytes.append(chunk) } }
                    }
                }
                if let error {
                    group.addTask {
                        for try await buffer in error {
                            guard self.keepError else { continue }
                            let chunk = Data(buffer: buffer)
                            self.lock.withLock { self.errorBytes.append(chunk) }
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var value: Bool { lock.withLock { raised } }
        func set() { lock.withLock { raised = true } }
        /// Raises it; true only for the call that did.
        func setIfUnset() -> Bool {
            lock.withLock {
                defer { raised = true }
                return !raised
            }
        }
    }
}
