import Foundation

/// SIGINT, SIGTERM and SIGHUP for the commands that change the machine —
/// `duo install`, `duo backups restore`, `duo restart` — handled in-process
/// instead of killing `duo` on the spot.
///
/// ## Why dying at once is the hazard
///
/// Measured before this existed: `duo check` sent `kill -INT` died within 0.5 s,
/// wait status 130, no `defer` run. Children are spawned in their own process
/// group (`ChildProcess`), so the terminal's Ctrl-C never reaches them — but
/// their stdout is a pipe whose only reader is `duo`. With `duo` gone, the
/// child dies on its next write: simulated with a python parent spawning the
/// way `ChildProcess` does, Homebrew's ruby died of `Errno::EPIPE` and `/bin/sh`
/// of SIGPIPE, neither finished. `brew install --cask --force` on an installed
/// cask (what `HomebrewInstaller` runs) is an upgrade: it copies the old app
/// into the Caskroom backup, removes it from /Applications (`==> Removing
/// App`), then moves the new one in (`==> Moving App`). Its rescue restores
/// the backup only for a StandardError: a signal skips it, and an
/// `Errno::EPIPE` reaches it but the revert starts by printing to the same
/// dead pipe (Homebrew 7.0.9, read from source; the EPIPE path is not
/// measured). A cut landing there leaves /Applications without the app, the
/// old copy only in the Caskroom backup.
///
/// ## What happens instead
///
/// - **First signal:** the root task running the command is cancelled, and one
///   line on stderr says `duo` stops after the current step and that an install
///   already replacing an app finishes first. Everything already running keeps
///   running: `.runToCompletion` children (brew, the swap's `ditto`/`osascript`,
///   vendor CLI updates) are not signalled, and `duo` keeps reading their pipes
///   until they exit — `ChildProcess.run` under `.runToCompletion` returns only
///   then, cancelled caller or not (`SignalGateTests`).
/// - **Every later signal:** a short "still finishing" line. Never a forced exit:
///   forcing is exactly the hazard above. `kill -9` remains, and is not advertised.
/// - **Exit:** only after the root task has returned, with 128 + the FIRST
///   signal's number (130 / 143 / 129), whatever the command returned — the
///   shell convention, and what brew itself exits with on an interrupt.
/// - **At a y/N prompt:** exits at once with that same status. Nothing has been
///   changed yet (both prompts come before the install lock is claimed), and a
///   `readLine` blocked on a terminal cannot be cancelled — with the signal
///   ignored, Ctrl-C at the prompt would otherwise do nothing until Enter.
///
/// Read-only commands are not handled at all: they keep the default disposition
/// and die at once. A `duo check` that cannot be interrupted would be a bug of
/// its own, and there is nothing in one worth finishing.
///
/// ## Output after the terminal has gone (SIGHUP)
///
/// Measured with a pty whose master was closed under a process ignoring SIGHUP
/// (2026-10-18, a Swift probe, `-O`): `write(2)` to fd 1 or 2 then fails with
/// EIO — not SIGPIPE — and `print` + `fflush` returns an error and carries on,
/// but `FileHandle.standardError.write(_:)`, which DuoKit uses for its stderr
/// lines, raises `NSFileHandleOperationException` and aborts the process
/// (SIGABRT). That is the hazard again, through the next error line. So on
/// SIGHUP every one of fd 1 and 2 that went with the terminal is pointed at
/// `/dev/null` (`detachHungUpOutputs`). A pipe whose reader has died does the
/// same with EPIPE (measured the same way): its reader was in the same job and
/// got the same hangup, so a pipe or socket goes too; a file on disk stays.
///
/// SIGPIPE is ignored in these commands for the same reason: `duo install | tee`
/// whose `tee` has died would otherwise kill `duo` on its next `print`. Children
/// do not inherit it — swift-subprocess spawns with `POSIX_SPAWN_SETSIGDEF` over
/// a full signal set and an empty mask (Subprocess+Darwin.swift, `spawnAttributes`),
/// so brew gets default dispositions back (`SignalGateTests`).
///
/// Not covered: a `FileHandle.standardError.write` into a stderr PIPE whose
/// reader died on a SIGINT or SIGTERM rather than a hangup (`duo install 2>&1 |
/// cat`, then Ctrl-C — `cat` dies too). That pipe is left alone because the
/// reader may well still be there (`| less` ignores SIGINT), and swapping out a
/// live reader's output is worse.
public final class SignalGate: @unchecked Sendable {

    /// What one delivered signal does.
    public enum Reaction: Equatable, Sendable {
        /// The first: cancel the command and say so.
        case stop
        /// Any after the first: say it is still finishing; nothing else.
        case stillFinishing
        /// At a y/N prompt, where nothing has been changed yet: exit now.
        case exitNow(status: Int32)
    }

    /// The three that mean "stop": Ctrl-C, a script's or agent's timeout, and
    /// the terminal window closing.
    public static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// The one `main.swift` arms and the prompts consult.
    public static let process = SignalGate()

    private let lock = NSLock()
    private var first: Int32?
    private var prompting = 0
    private var rootTask: Task<Int32, Never>?

    public init() {}

    /// Whether this command line changes the machine, and so gets the gate.
    /// Every other command keeps the default disposition.
    public static func handles(subcommand: String, operands: [String]) -> Bool {
        switch subcommand {
        case "install", "restart": return true
        // Only the restore puts a bundle back. `sync` (moving rollback points
        // between disks) keeps today's behaviour; it was not part of this change.
        case "backups": return operands.first == "restore"
        default: return false
        }
    }

    /// Record one delivered signal and say what it does.
    func receive(_ signo: Int32) -> Reaction {
        lock.withLock {
            if first == nil {
                first = signo
                rootTask?.cancel()
            } else if prompting == 0 {
                return .stillFinishing
            }
            return prompting > 0 ? .exitNow(status: 128 + (first ?? signo)) : .stop
        }
    }

    /// Whether a stop has been asked for — for a wait that is safe to cut short
    /// but runs where the root task's cancellation does not reach
    /// (`Restart.patience`).
    public var stopRequested: Bool { lock.withLock { first != nil } }

    /// The process's exit status once the command has returned `commandStatus`.
    public func status(after commandStatus: Int32) -> Int32 {
        lock.withLock { first.map { 128 + $0 } ?? commandStatus }
    }

    /// Read a y/N answer with a signal meaning "exit now" for as long as `read`
    /// blocks. Nil — read as "no" by both prompts — without asking at all when a
    /// stop was already asked for: a plan built while the user was pressing
    /// Ctrl-C is not one to put to them.
    public func answer(_ read: () -> String?) -> String? {
        let ask: Bool = lock.withLock {
            guard first == nil else { return false }
            prompting += 1
            return true
        }
        guard ask else { return nil }
        defer { lock.withLock { prompting -= 1 } }
        return read()
    }

    /// The stderr line for `reaction`, nil when there is nothing to say.
    static func notice(for reaction: Reaction, signal signo: Int32) -> String? {
        switch reaction {
        case .stop:
            return "duo: \(name(of: signo)) received — stopping after the current step. "
                + "An install that is already replacing an app finishes first; "
                + "duo exits when it has."
        case .stillFinishing:
            // "Or quit and not reopened": `duo restart`'s step replaces nothing
            // itself; what leaving it midway costs is the app's reopen.
            return "duo: still finishing the current step — stopping in the middle of it "
                + "could leave an app half-replaced, or quit and not reopened."
        case .exitNow:
            return nil
        }
    }

    static func name(of signo: Int32) -> String {
        switch signo {
        case SIGINT: return "SIGINT"
        case SIGTERM: return "SIGTERM"
        case SIGHUP: return "SIGHUP"
        default: return "signal \(signo)"
        }
    }

    /// Run `command` as the root task with `signals` handled, and return the
    /// status the process should exit with — only once the task has returned.
    ///
    /// The seams are for the tests: `arm` installs the handlers (the real one
    /// ignores the signals and listens with dispatch sources, and ignores
    /// SIGPIPE), `say` writes a notice, `hangUp` detaches outputs that went with
    /// the terminal, `exitNow` ends the process from a prompt.
    public func run(
        _ command: @escaping @Sendable () async -> Int32,
        arm: (@escaping @Sendable (Int32) -> Void) -> Void = SignalGate.armProcessSignals,
        say: @escaping @Sendable (String) -> Void = SignalGate.writeToStandardError,
        hangUp: @escaping @Sendable () -> Void = SignalGate.detachHungUpOutputs,
        exitNow: @escaping @Sendable (Int32) -> Void = SignalGate.exitImmediately
    ) async -> Int32 {
        // Armed before the command starts, so no signal can find it running with
        // the default disposition; one that lands before the task exists is
        // honoured when it is stored below.
        arm { [self] signo in
            // Before the notice, which would otherwise be the write that aborts.
            if signo == SIGHUP { hangUp() }
            let reaction = receive(signo)
            if case .exitNow(let status) = reaction { exitNow(status) }
            if let line = Self.notice(for: reaction, signal: signo) { say(line) }
        }
        let task = Task { await command() }
        lock.withLock {
            rootTask = task
            if first != nil { task.cancel() }
        }
        let returned = await task.value
        return status(after: returned)
    }

    /// Run a step that has started to its end, out of reach of the root task's
    /// cancellation, and return what it returned.
    ///
    /// The first signal cancels the root task, and a cancelled task does not
    /// merely skip what comes next — it changes what the step in flight does.
    /// Every `try? await Task.sleep` in it returns at once (`AppRestarter`'s quit
    /// wait, `StagedRelaunch`'s swap wait: a quit app given up on and never
    /// reopened, or reopened under ShipIt mid-swap), and every `.terminateChild`
    /// `ChildProcess.run` refuses to spawn (a tool's version re-read after its
    /// update, so a successful update reads as failed). So each item of a gated
    /// command — a restart, a tool update with its verification — runs in here
    /// once it has started; the "stop before the next item" checks stay in the
    /// loops.
    ///
    /// `Task { }` rather than `Task.detached`: an unstructured task is not
    /// cancelled with the task that awaits it, and it still inherits task-locals
    /// (`CLIToolExit.$observer`, `RequestAttribution`) and priority, which a
    /// detached one would drop. Apple's `Task.cancel()` says what a cancel
    /// reaches — "It cancels any child tasks and task groups of the task" —
    /// and The Swift Programming Language (Concurrency, "Unstructured
    /// Concurrency") that an unstructured task "doesn't have a parent task"
    /// and runs with "the same actor isolation, priority, and task-local state
    /// as the current task". `aRestartCancelledInItsQuitWaitStillReopensTheApp`
    /// and `aToolUpdateCancelledMidwayIsReportedAsApplied` go red without it.
    /// The Core side of the same problem — the steps inside
    /// `InstallCoordinator.perform` after its commit point — is
    /// `InstallCommit`'s (#1404); this does not depend on it.
    public static func finishing<T: Sendable>(_ step: @escaping @Sendable () async -> T) async -> T {
        await Task { await step() }.value
    }

    // MARK: - The process-wide pieces

    /// Kept alive for the life of the process: a released source stops listening.
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []
    private static let sourcesLock = NSLock()

    /// Ignore `signals` (so the default action — death — never happens) and
    /// listen for them with dispatch sources instead; ignore SIGPIPE outright.
    /// A source still fires for an ignored signal, and ignoring it is the
    /// documented pairing: macOS `dispatch_source_create(3)` says a signal
    /// source does not "alter the behavior of signal delivery", so
    /// "applications must ignore or at least catch any signal that terminates a
    /// process by default", with `signal(SIGTERM, SIG_IGN)` as its example;
    /// `kqueue(2)` on `EVFILT_SIGNAL`: "The filter will record all attempts to
    /// deliver a signal to a process, even if the signal has been marked as
    /// SIG_IGN."
    public static func armProcessSignals(_ handler: @escaping @Sendable (Int32) -> Void) {
        signal(SIGPIPE, SIG_IGN)
        let queue = DispatchQueue(label: "duo.signals")
        sourcesLock.withLock {
            for signo in signals {
                signal(signo, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signo, queue: queue)
                // Two signals between handler runs coalesce into one event whose
                // `data` counts them; each still gets its line.
                source.setEventHandler { [unowned source] in
                    for _ in 0..<max(1, source.data) { handler(signo) }
                }
                source.resume()
                sources.append(source)
            }
        }
    }

    /// `write(2)`, result ignored — never `FileHandle.write`, which aborts the
    /// process on EIO/EPIPE (see the type's doc comment).
    public static func writeToStandardError(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { write(STDERR_FILENO, $0.baseAddress, $0.count) }
    }

    /// Point fd 1 and 2 at `/dev/null` where they went with the terminal.
    public static func detachHungUpOutputs() {
        let null = open("/dev/null", O_WRONLY)
        guard null >= 0 else { return }
        for descriptor in [STDOUT_FILENO, STDERR_FILENO] where wentWithTheTerminal(descriptor) {
            dup2(null, descriptor)
        }
        close(null)
    }

    /// A terminal, a pipe or a socket: gone, or read by something that got the
    /// same hangup. Not a file on disk (`duo install > log`), which is still
    /// there. `isatty` still answers 1 after the hangup — measured.
    static func wentWithTheTerminal(_ descriptor: Int32) -> Bool {
        if isatty(descriptor) == 1 { return true }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        let type = info.st_mode & S_IFMT
        return type == S_IFIFO || type == S_IFSOCK
    }

    /// From a prompt only. `_exit`, not `exit`: the main thread is inside
    /// `readLine`, holding stdin's stdio lock, and `exit`'s flush of every stream
    /// is not something to bet on not waiting for it. stdout is flushed by hand.
    public static func exitImmediately(_ status: Int32) {
        fflush(stdout)
        _exit(status)
    }
}
