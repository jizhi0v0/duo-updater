import Foundation

/// Runs one tool's update command and keeps its output — the part every tool's
/// updater shares. Which command, and whether it may run at all, is the tool's
/// own decision (`ClaudeCodeCheck`, …); so is the line a failure is summed up by.
enum CLIToolCommandRunner {

    struct Run: Sendable {
        enum Result: Sendable {
            case couldNotStart(String)
            case finished(ChildProcess.Outcome)
        }
        let result: Result
        /// The output as a terminal would have left it (`OutputLog`).
        let lines: [String]
        var text: String { lines.joined(separator: "\n") }
    }

    /// stdout and stderr merged, each line handed to `progress` as it arrives.
    ///
    /// Runs to completion if the caller is cancelled, as brew's upgrade does: this
    /// replaces what is installed, and a kill halfway is worse than letting it
    /// finish. `deadline` still stops a child that hangs.
    ///
    /// `standardInput` replaces the inherited stdin — a terminal, under a `duo`
    /// run from one — for a tool that asks questions when it has a terminal
    /// (`HerdrUpdater`).
    static func run(
        _ command: CLIToolCommand, environment: [String: String], deadline: ChildProcess.Deadline,
        standardInput: Data? = nil, progress: @escaping @Sendable (String) -> Void
    ) async -> Run {
        let log = OutputLog(onLine: progress)
        let result: Run.Result
        do {
            result = .finished(try await ChildProcess.run(
                command.executable, command.arguments, environment: environment, standardInput: standardInput,
                standardOutput: .discard, standardError: .mergeIntoOutput,
                deadline: deadline, onCancel: .runToCompletion,
                onOutputChunk: { log.append($0) }))
        } catch {
            result = .couldNotStart("\(error)")
        }
        log.finish()
        return Run(result: result, lines: log.lines)
    }

    /// What a launchd-started app gets as `PATH`: `/etc/paths` without
    /// `/usr/local/bin` (where an Intel Homebrew's node lives) and the cryptex
    /// directory. Enough for a `#!/bin/sh` step inside an installer, and nothing
    /// that could pick another interpreter.
    static let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// `prefix` first, so a `#!/usr/bin/env node` (or `python`) inside the update
    /// finds the interpreter of *this* install — not whatever the inherited `PATH`
    /// of a terminal-run `duo` happens to name first.
    static func path(prefix: String?) -> String {
        [prefix, systemPath].compactMap { $0 }.joined(separator: ":")
    }

    /// The last line with any letter in it — a line with no letters is a progress
    /// tick or a rule, not a reason — else the exit status. A tool whose output
    /// ends on something other than its reason applies its own rule first
    /// (`ClaudeCodeUpdater.failureMessage`).
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if outcome.timedOut {
            let seconds = deadline.terminateAfter.components.seconds
            let limit = seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
            return "stopped: still running after \(limit)"
        }
        if let last = lines.last(where: isMeaningful) {
            return last.trimmingCharacters(in: .whitespaces)
        }
        return outcome.uncaughtSignal
            ? "terminated by signal \(outcome.terminationStatus)"
            : "exited with status \(outcome.terminationStatus)"
    }

    static func isMeaningful(_ line: String) -> Bool {
        line.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Everything but printable text: CSI (colours, cursor moves, `ESC[?25l`),
    /// OSC (titles, `ESC]8;;` hyperlinks) and the two-byte escapes.
    static func stripEscapes(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        return s.replacingOccurrences(
            of: "\u{1B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[@-Z\\\\-_])",
            with: "", options: .regularExpression)
    }

    /// The child's output as lines, as a terminal would have left them.
    ///
    /// Split on `\n` and `\r` both, before decoding — neither byte occurs inside a
    /// UTF-8 sequence, so a character straddling two chunks survives (the failure
    /// `StreamedLines` records for brew). A line ended by `\r` is a progress redraw:
    /// it goes to `progress` like any other, and the next line replaces it in the
    /// log, so the detail pane shows the final state of a progress bar rather than
    /// every tick of it.
    final class OutputLog: @unchecked Sendable {
        private let lock = NSLock()
        private let onLine: @Sendable (String) -> Void
        private var pending = Data()
        private var kept: [String] = []
        private var overwrite = false

        init(onLine: @escaping @Sendable (String) -> Void) {
            self.onLine = onLine
        }

        /// Chunks come from one reader, in order, so calling `onLine` outside the
        /// lock keeps their order.
        func append(_ chunk: Data) {
            let completed: [String] = lock.withLock {
                pending.append(chunk)
                var out: [String] = []
                var start = pending.startIndex
                while let end = pending[start...].firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    if let line = commit(pending[start..<end], carriageReturn: pending[end] == 0x0D) {
                        out.append(line)
                    }
                    start = pending.index(after: end)
                }
                pending.removeSubrange(pending.startIndex..<start)
                return out
            }
            completed.forEach(onLine)
        }

        /// The output has ended: a last line without a newline is still a line.
        func finish() {
            let tail: String? = lock.withLock {
                defer { pending.removeAll() }
                return pending.isEmpty ? nil : commit(pending[...], carriageReturn: false)
            }
            if let tail { onLine(tail) }
        }

        var lines: [String] { lock.withLock { kept } }
        var text: String { lines.joined(separator: "\n") }

        /// Under the lock.
        private func commit(_ bytes: Data, carriageReturn: Bool) -> String? {
            var line = CLIToolCommandRunner.stripEscapes(String(decoding: bytes, as: UTF8.self))
            while let last = line.last, last.isWhitespace { line.removeLast() }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                // `\r\n` ends the redraw it follows: the bare `\n` commits it.
                if !carriageReturn { overwrite = false }
                return nil
            }
            if overwrite, !kept.isEmpty {
                kept[kept.count - 1] = line
            } else {
                kept.append(line)
            }
            overwrite = carriageReturn
            return line
        }
    }
}
