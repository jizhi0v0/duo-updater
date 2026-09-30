import Foundation

/// Runs the one-click update a `ClaudeCodeStatus` offers — the vendor's own
/// command, in the install's own place — and reports how it went.
///
/// It runs exactly `status.oneClick`, never a command of its own: which command
/// is allowed for which install is `ClaudeCodeCheck`'s decision, made with the
/// gates listed there. The one gate asked again here is "is an update already
/// running", because that one can change between the check and the click.
public struct ClaudeCodeUpdater: Sendable {

    public enum Outcome: Sendable, Equatable {
        /// The command exited 0. `version` is what the install reads as afterwards
        /// (re-scanned), or nil when it could not be read.
        case updated(version: String?)
        /// Something else started updating it between the check and the click;
        /// nothing was run.
        case busy(ClaudeCodeActivity.Busy)
        /// The status offers no one-click (`oneClick == nil`); nothing was run.
        case notOffered
        /// The command ran and failed. `message` is its last meaningful output
        /// line, for the row; `output` the whole log, for the detail pane.
        case failed(message: String, output: String)
    }

    /// Is an update already running for this install? Injected so tests never read
    /// the host's process table or its `~/.cache/claude/staging`.
    typealias BusyCheck = @Sendable (ClaudeCodeInstall) -> ClaudeCodeActivity.Busy?

    let busy: BusyCheck
    /// Re-reads the install after a successful run. Its `home` must be where the
    /// child writes: `claude update` writes under `$HOME/.local`, whatever path it
    /// was invoked by. `ClaudeCodeScanner()`'s home is
    /// `homeDirectoryForCurrentUser`, which does not follow `$HOME` (measured
    /// 2026-09-30: launched with `HOME=/tmp/…`, it still answered `/Users/<name>`);
    /// the two agree unless `HOME` was overridden.
    let scanner: ClaudeCodeScanner
    /// The child's environment before `PATH` is set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The native binary is ~220 MB (2.1.285's `darwin-arm64` file: 223,821,616
    /// bytes, 2026-09-30) and `npm install` fetches the same binary as a platform
    /// package, so a slow link legitimately takes many minutes. The deadline is for
    /// a child that has stopped making progress, not for a slow one: 30 minutes is
    /// ~1 Mbit/s for the whole file. The grace lets it clean up its staging
    /// directory on SIGTERM.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    public init() {
        self.init(
            busy: { ClaudeCodeActivity.busy($0, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: ClaudeCodeScanner(),
            // A GUI app launched by launchd has no proxy variables, and both
            // updaters read them: npm honours `https_proxy` & co. when its own
            // `https-proxy` is unset (npm 11's `config.md`), and
            // `claude update` followed a dead `https_proxy` straight into
            // ECONNREFUSED (measured 2026-09-30). See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: ClaudeCodeScanner,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = ClaudeCodeUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.environment = environment
        self.deadline = deadline
    }

    /// - Parameter progress: each new line of the command's output, as it arrives.
    public func update(
        _ status: ClaudeCodeStatus,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> Outcome {
        guard let command = status.oneClick else { return .notOffered }
        let install = status.install
        // Asked again, not read from `status`: the verdict may be minutes old, and
        // a `claude update` in a terminal or a session's background download
        // started since would race this one.
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running)
        }

        var environment = self.environment()
        environment["PATH"] = Self.path(prefix: Self.pathPrefix(command, install))
        let log = OutputLog(onLine: progress)
        let outcome: ChildProcess.Outcome
        do {
            // Runs to completion if the caller is cancelled, as brew's upgrade
            // does: this replaces what is installed, and a kill halfway is worse
            // than letting it finish — an interrupted `npm install -g` may leave a
            // half-installed package (not measured either way, so the safe side).
            // The deadline still stops a child that hangs.
            outcome = try await ChildProcess.run(
                command.executable, command.arguments, environment: environment,
                standardOutput: .discard, standardError: .mergeIntoOutput,
                deadline: deadline, onCancel: .runToCompletion,
                onOutputChunk: { log.append($0) })
        } catch {
            log.finish()
            return .failed(message: "could not run \(command.executable): \(error)", output: log.text)
        }
        log.finish()

        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(log.lines, outcome, deadline: deadline), output: log.text)
        }
        let scanner = self.scanner
        let after = await offCooperativePool { Self.reread(install, with: scanner) }
        return .updated(version: after?.version)
    }

    // MARK: - Environment

    /// What a launchd-started app gets as `PATH`: `/etc/paths` without
    /// `/usr/local/bin` (where an Intel Homebrew's node lives) and the cryptex
    /// directory. Enough for a `#!/bin/sh` step inside npm, and nothing that could
    /// pick another node.
    static let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// `prefix` first, so an npm install's `#!/usr/bin/env node` (npm itself, the
    /// package's postinstall) finds the node of *its* prefix — not whatever node
    /// the inherited `PATH` of a terminal-run `duo` happens to name first.
    static func path(prefix: String?) -> String {
        [prefix, systemPath].compactMap { $0 }.joined(separator: ":")
    }

    /// The command's own prefix; for a native install, the launcher's directory
    /// (`~/.local/bin`). Without it `claude update` prints "Warning: Native
    /// installation exists but ~/.local/bin is not in your PATH" and a `Fix:` line
    /// telling the user to edit `~/.zshrc` (2.1.280 and 2.1.285, measured
    /// 2026-09-30) — advice about the app's environment, not the user's shell.
    static func pathPrefix(_ command: ClaudeCodeStatus.Command, _ install: ClaudeCodeInstall) -> String? {
        if let prefix = command.pathPrefix { return prefix }
        guard install.method == .native else { return nil }
        return (install.path as NSString).deletingLastPathComponent
    }

    // MARK: - Afterwards

    /// The install at the same path, read from disk again. A full scan rather than
    /// a patch of the old value, so the version comes from the same layout rules
    /// the check used: the launcher's `versions/` target for a native install, the
    /// package's `package.json` for the npm family. The path is passed as a user
    /// path so a user-added install is found too; a conventional one is found
    /// first and the duplicate is dropped.
    static func reread(_ install: ClaudeCodeInstall, with scanner: ClaudeCodeScanner) -> ClaudeCodeInstall? {
        scanner.scan(userPaths: [install.path]).first { $0.path == install.path }
    }

    /// The line the row shows when the command failed.
    ///
    /// Normally the last line with any letter in it — a line with no letters is a
    /// progress tick or a rule, not a reason — except `claude update`'s closing
    /// hint. Its failure path writes three lines to stderr and exits 1 (2.1.285's
    /// source; measured 2026-09-30 in a scratch HOME with a dead proxy):
    ///
    ///     Error: Failed to install native update
    ///     TelemetrySafeError: Failed to fetch version from https://downloads.claude.ai/claude-code-releases/latest after 3 attempt(s): connect ECONNREFUSED 127.0.0.1:9
    ///     Try running "claude doctor" for diagnostics
    ///
    /// The reason is the middle one, shown without its `TelemetrySafeError: `
    /// prefix — the name of an internal error class, not something for the user
    /// to read (`output` keeps it). `claude install` ends on its reason instead,
    /// after a bare `✘ Installation failed`.
    ///
    /// npm needs its own rule. Its last line is always the pointer to its debug log
    /// and the reason is the first `npm error` line that is not a field — measured
    /// 2026-09-30, npm 11 asked for a version that does not exist:
    ///
    ///     npm error code ETARGET
    ///     npm error notarget No matching version found for @anthropic-ai/claude-code@0.0.0-nope.
    ///     npm error notarget In most cases you or one of your dependencies are requesting
    ///     npm error notarget a package version that doesn't exist.
    ///     npm error A complete log of this run can be found in: …/_logs/…-debug-0.log
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if outcome.timedOut {
            let seconds = deadline.terminateAfter.components.seconds
            let limit = seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
            return "stopped: still running after \(limit)"
        }
        if let npm = npmReason(lines) { return npm }
        if let last = lines.last(where: { isMeaningful($0) && !$0.hasPrefix(claudeDoctorHint) }) {
            let line = last.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix(telemetrySafeError) ? String(line.dropFirst(telemetrySafeError.count)) : line
        }
        return outcome.uncaughtSignal
            ? "terminated by signal \(outcome.terminationStatus)"
            : "exited with status \(outcome.terminationStatus)"
    }

    static let claudeDoctorHint = #"Try running "claude doctor""#
    static let telemetrySafeError = "TelemetrySafeError: "

    static func isMeaningful(_ line: String) -> Bool {
        line.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// The first `npm error` line that is not one of npm's key-value fields.
    /// `npm ERR!` is how npm 9 and earlier spelled the prefix; an older node
    /// prefix still ships one of those.
    static func npmReason(_ lines: [String]) -> String? {
        let fields: Set<String> = ["code", "syscall", "path", "errno", "dest"]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let prefix = ["npm error ", "npm ERR! "].first(where: { trimmed.hasPrefix($0) }) else { continue }
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            let key = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            guard !fields.contains(key), isMeaningful(rest) else { continue }
            return trimmed
        }
        return nil
    }

    // MARK: - Output

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
            var line = ClaudeCodeUpdater.stripEscapes(String(decoding: bytes, as: UTF8.self))
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
