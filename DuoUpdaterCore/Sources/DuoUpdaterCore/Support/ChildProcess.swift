import Foundation
internal import Subprocess
#if canImport(System)
internal import System
#else
internal import SystemPackage
#endif

/// Launch a child process and wait for it **without parking a thread**.
///
/// Every subprocess in `DuoUpdaterCore`, `duo` and the menu-bar app goes through
/// here. It replaces `Foundation.Process` + `waitUntilExit()` /
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
///   while we wait on the other — the deadlock three separate sites carried their
///   own workaround for.
/// - **No output limit.** The old sites read to EOF unbounded, so this does too:
///   swift-subprocess's `limit:` throws `outputLimitExceeded` rather than
///   truncating, which would have turned a verbose tool into a launch failure.
/// - **`terminationStatus` means what `Process.terminationStatus` meant**: the
///   exit code, or the signal number when the child died of one
///   (`uncaughtSignal` tells the two apart). Error strings built from it — "tar
///   failed (15)", "unzip exited 9" — read the same.
/// - **stdin is inherited** unless `standardInput` supplies bytes, which is
///   `Process`'s default too.
/// - **The environment is inherited** unless `environment` is non-nil, in which
///   case it replaces the whole environment, as assigning `Process.environment`
///   did.
///
/// ## Deadline
///
/// `Deadline(terminateAfter:killAfter:)` is the ladder the old call sites built
/// from two `DispatchWorkItem`s: SIGTERM once `terminateAfter` has passed since
/// launch, SIGKILL at `killAfter` if the child is still there. Both are measured
/// from launch, like the work items were. `timedOut` reports that the deadline
/// fired before the child exited.
///
/// ## Cancellation — chosen per call, never defaulted
///
/// This is the one real behaviour change, so every call site has to spell it:
///
/// - `.runToCompletion` — the child runs to its end even if the calling task is
///   cancelled, and the outcome is returned as if nothing happened. That is what
///   the old `offCooperativePool` hop did (it is not cancellable) and it is the
///   only safe choice for anything that writes: a half-copied bundle, a
///   half-applied delta, a DMG left mounted, an `osascript` swap cut between its
///   two renames. The run happens in an unstructured task whose cancellation the
///   caller's does not reach. (SE-0504's `withTaskCancellationShield` would say
///   this directly but is not back-deployed, and this ships to macOS 14.)
/// - `.terminateChild` — cancelling the calling task tears the child down (the
///   deadline's ladder if there is one, otherwise SIGKILL straight away) and this
///   throws `CancellationError`. For read-only queries, where nobody is left to
///   want the answer.
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

        /// Both measured from launch. `killAfter` must not precede
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
        onOutputChunk: (@Sendable (Data) -> Void)? = nil
    ) async throws -> Outcome {
        let request = Request(
            executablePath: executablePath, arguments: arguments,
            environment: environment, workingDirectory: workingDirectory,
            standardInput: standardInput, standardOutput: standardOutput,
            standardError: standardError, deadline: deadline,
            onOutputChunk: onOutputChunk)
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
            let outcome = try await request.raceDeadline(teardownOnCancel: request.ladder)
            try Task.checkCancellation()
            return outcome
        }
    }

    // MARK: - Implementation

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
            guard let deadline else { return try await launch(teardown: steps, timedOut: { false }) }
            let fired = Flag()
            return try await withThrowingTaskGroup(of: Event.self) { group in
                group.addTask {
                    .finished(try await launch(teardown: steps, timedOut: { fired.value }))
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: deadline.terminateAfter)
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
            teardown steps: [TeardownStep], timedOut: @escaping @Sendable () -> Bool
        ) async throws -> Outcome {
            var options = PlatformOptions()
            options.teardownSequence = steps
            let env: Subprocess.Environment
            if let environment {
                var custom: [Subprocess.Environment.Key: String] = [:]
                for (key, value) in environment {
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

            let status: TerminationStatus
            // Four spellings of one call: swift-subprocess's input and error types are
            // static, and the choices here are inherit-or-bytes for stdin and
            // separate-or-merged for stderr.
            switch (standardInput, standardError) {
            case (nil, .mergeIntoOutput):
                status = try await Subprocess.run(
                    configuration, input: .currentStandardInput,
                    output: .sequence, error: .combinedWithOutput
                ) { execution in
                    try await sink.drain(output: execution.standardOutput, error: nil)
                }.terminationStatus
            case (nil, _):
                status = try await Subprocess.run(
                    configuration, input: .currentStandardInput,
                    output: .sequence, error: .sequence
                ) { execution in
                    try await sink.drain(
                        output: execution.standardOutput, error: execution.standardError)
                }.terminationStatus
            case (let bytes?, .mergeIntoOutput):
                status = try await Subprocess.run(
                    configuration, input: .data(bytes),
                    output: .sequence, error: .combinedWithOutput
                ) { execution in
                    try await sink.drain(output: execution.standardOutput, error: nil)
                }.terminationStatus
            case (let bytes?, _):
                status = try await Subprocess.run(
                    configuration, input: .data(bytes),
                    output: .sequence, error: .sequence
                ) { execution in
                    try await sink.drain(
                        output: execution.standardOutput, error: execution.standardError)
                }.terminationStatus
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
    }
}
