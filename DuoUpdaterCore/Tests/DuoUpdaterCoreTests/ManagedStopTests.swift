import Darwin
import Foundation
import Testing
@testable import DuoUpdaterCore

/// D15 (plans/cli-managers-redesign.md §13.4): a managed update may be
/// stopped while its command runs, and what the command changed is put back.
/// `ManagedSnapshot` against a scratch directory, `ManagedStop` against real
/// process groups of `/bin/sh` and `sleep`, and `ManagedProvider.update`
/// with a scripted runner that writes into the snapshot's paths.
///
/// Each case names the mutation it fails under.
struct ManagedStopTests {

    private func scratch() throws -> String {
        let base = NSTemporaryDirectory() + "managed-stop-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return (base as NSString).resolvingSymlinksInPath
    }

    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    private func read(_ path: String) -> String? {
        (try? Data(contentsOf: URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Every file under `root` with its bytes, and every link with its target.
    private func listing(_ root: String) -> [String: String] {
        var out: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(atPath: root)
        while let relative = enumerator?.nextObject() as? String {
            let path = root + "/" + relative
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                out[relative] = "-> " + target
            } else if let text = read(path) {
                out[relative] = text
            } else {
                out[relative] = "dir"
            }
        }
        return out
    }

    // MARK: ManagedSnapshot

    /// A file rewritten, a directory with a file added and one removed, a link
    /// moved, a path deleted and a path made: all as they were after
    /// `restore`. Mutations: `restore` skipping the swap for a path that
    /// exists now; skipping the removal of a path that was absent; `take`
    /// without `CLONE_NOFOLLOW` (the link's clone is then its target's file,
    /// and the restored path is no longer a link).
    @Test func restorePutsEveryPathBackAsItWas() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/tracker.toml", "tokei 14.0.0")
        try write(root + "/venv/lib/a.py", "old a")
        try write(root + "/venv/lib/b.py", "old b")
        try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/bin/tool", withDestinationPath: root + "/venv/bin/tool")
        try write(root + "/gone.txt", "kept")
        let before = listing(root)

        let snapshot = try ManagedSnapshot.take([
            root + "/tracker.toml", root + "/venv", root + "/bin/tool", root + "/gone.txt", root + "/new-version",
        ])
        try write(root + "/tracker.toml", "tokei 15.0.0")
        try write(root + "/venv/lib/a.py", "new a")
        try FileManager.default.removeItem(atPath: root + "/venv/lib/b.py")
        try write(root + "/venv/lib/c.py", "new c")
        try FileManager.default.removeItem(atPath: root + "/bin/tool")
        try FileManager.default.createSymbolicLink(atPath: root + "/bin/tool", withDestinationPath: root + "/elsewhere")
        try FileManager.default.removeItem(atPath: root + "/gone.txt")
        try write(root + "/new-version/bin/node", "half")

        #expect(snapshot.restore() == [])
        snapshot.discard()
        #expect(listing(root) == before)
        #expect(!FileManager.default.fileExists(atPath: snapshot.directory))
    }

    /// Two paths where one holds the other cannot both be put back: refused
    /// before anything is cloned. Mutation: drop the overlap check.
    @Test func overlappingPathsAreRefused() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/a/b", "x")
        #expect(throws: ManagedSnapshot.Failure.overlapping(root + "/a", root + "/a/b")) {
            try ManagedSnapshot.take([root + "/a", root + "/a/b"])
        }
    }

    /// `discard` after a finished command leaves its writes alone and the
    /// clones gone. Mutation: `discard` calling `restore`.
    @Test func discardKeepsTheCommandsWrites() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/f", "old")
        let snapshot = try ManagedSnapshot.take([root + "/f"])
        try write(root + "/f", "new")
        snapshot.discard()
        #expect(read(root + "/f") == "new")
        #expect(!FileManager.default.fileExists(atPath: snapshot.directory))
    }

    // MARK: ManagedStop

    /// A cancelled run sends SIGINT to the whole group and returns only once
    /// every member has gone — the inner `sleep` too, which a signal to the
    /// shell alone would leave running. The ladder's SIGTERM and SIGKILL are
    /// put out of reach, so only the SIGINT can end it; a 20 s deadline is
    /// the backstop, and its own message tells it apart: no clock is read.
    /// Mutations: `kill` instead of `killpg` in `interrupt` (the run gives up,
    /// not stopped); `waitUntilGone` returning at once (the sleep is alive).
    @Test func aCancelledRunStopsItsWholeGroup() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let marker = root + "/started"
        // A pipeline, as a build tool runs its compiler: the inner `sleep`
        // (the `sh` that wrote its pid, then exec'd) is a grandchild in the
        // group, which a signal to the outer shell alone would leave running.
        // Not `&`: a non-interactive shell starts those ignoring SIGINT, and
        // only the ladder's SIGTERM ends them (`theLadderEnds…`).
        let inner = "echo $$ > \(marker).child; touch \(marker); exec sleep 600"
        let command = CLIToolCommand(
            executable: "/bin/sh", arguments: ["-c", "sh -c '\(inner)' | cat"], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.stoppableRunner(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(20), killAfter: .seconds(25)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: marker) {
            // cancel-ok: test polling for the child's start, bounded by the child's own 30 s
            try? await Task.sleep(for: .milliseconds(20))
        }
        let child = pid_t(read(marker + ".child")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        task.cancel()
        let result = await task.value
        #expect(result.stopped)
        #expect(!result.succeeded)
        // Ended by the stop, not by the deadline's backstop.
        #expect(result.failureMessage == "stopped")
        #expect(child > 0)
        #expect(kill(child, 0) != 0)
    }

    /// What mise does: on the interrupt, start a process in a group of its
    /// own, then exit. The run returns only once that one has gone too, and
    /// was stopped: it sleeps 600 s, so only the SIGINT ends it before the run
    /// gives up at 20 s (the ladder's SIGTERM and SIGKILL are out of reach).
    /// No clock is read. Mutation: the child not in a session of its own (the
    /// grandchild is not found, and outlives the return), or `waitUntilGone`
    /// not sending SIGINT to a group that started after the stop (the run
    /// gives up: stuck, not stopped).
    @Test func aDescendantInAGroupOfItsOwnIsStoppedAndWaitedFor() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/grandchild.pl", """
            $SIG{INT} = 'DEFAULT'; setpgrp(0, 0);
            open(P, '>\(root)/pid'); print P $$; close P;
            sleep 600;
            """)
        let script = "trap 'perl \(root)/grandchild.pl & sleep 0.3; exit 130' INT; touch \(root)/started; sleep 30"
        let command = CLIToolCommand(executable: "/bin/sh", arguments: ["-c", script], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.stoppableRunner(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(900), killAfter: .seconds(905)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: root + "/started") {
            // cancel-ok: test polling for the child's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        // cancel-ok: let the tracker list the child before the stop
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        #expect(result.stopped)
        let pid = pid_t(read(root + "/pid") ?? "") ?? 0
        #expect(pid > 0)
        #expect(kill(pid, 0) != 0, "the grandchild outlived the run")
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// What pipx does: start its backend in a session of its own, and on the
    /// interrupt stop it — but a grandchild can outlive that. Here the child
    /// starts a grandchild in a new session (`POSIX::setsid`), and on SIGINT
    /// leaves it running and exits. The run returns only once the grandchild
    /// has gone, ended by the ladder's SIGTERM (it is not sent the SIGINT:
    /// that session is the member's to stop). Mutation: no `adoptSessions`
    /// (the grandchild outlives the return); SIGINT to every session (it
    /// writes `sigint`).
    @Test func aDescendantInASessionOfItsOwnIsFollowedAndStopped() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/grandchild.pl", """
            use POSIX (); POSIX::setsid();
            $SIG{INT} = sub { open(F, '>\(root)/sigint'); close F; exit 130 };
            open(P, '>\(root)/pid'); print P $$; close P;
            sleep 600;
            """)
        let script = "trap 'sleep 0.5; exit 130' INT; perl \(root)/grandchild.pl & touch \(root)/started; wait; wait"
        let command = CLIToolCommand(executable: "/bin/sh", arguments: ["-c", script], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.stoppableRunner(termAfter: .milliseconds(300), killAfter: .seconds(600), giveUpAfter: .seconds(20))(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(20), killAfter: .seconds(25)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: root + "/pid") {
            // cancel-ok: test polling for the grandchild's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        // cancel-ok: let the tracker see the new session while its parent lives
        try? await Task.sleep(for: .milliseconds(300))
        let pid = pid_t(read(root + "/pid") ?? "") ?? 0
        #expect(pid > 0)
        #expect(getsid(pid) == pid)
        task.cancel()
        let result = await task.value
        #expect(result.stopped)
        #expect(kill(pid, 0) != 0, "the grandchild in its own session outlived the run")
        #expect(!FileManager.default.fileExists(atPath: root + "/sigint"), "its session was sent the SIGINT")
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// A member running as another user — `/usr/bin/top` is setuid root —
    /// is still a member, and the stop still ends it: the process table is
    /// read through `sysctl`, which `proc_pidinfo` is not for such a process
    /// (EPERM). Mutation: read members with `proc_pidinfo` (`top` is not
    /// found; the run returns while it runs).
    @Test func aMemberRunningAsAnotherUserIsSeenAndStopped() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let stop = ManagedStop(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))
        let leader = Locked<pid_t>(0)
        let run = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", "/usr/bin/top -l 600 -s 1 > /dev/null & echo $! > \(root)/top; wait"],
                standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion,
                onLaunch: { stop.launched($0); leader.set($0) }, newSession: true)
        }
        while !FileManager.default.fileExists(atPath: root + "/top") {
            // cancel-ok: test polling for the child's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        let top = pid_t(read(root + "/top")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        var info = proc_bsdinfo()
        // The premise: as this user, proc_pidinfo cannot read it — once the
        // forked shell has exec'd the setuid `top` (the pid is written before).
        var readable = true
        for _ in 0..<250 where readable {
            readable = proc_pidinfo(top, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0
            // cancel-ok: test polling for the exec
            if readable { try? await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(!readable)
        #expect(stop.members().contains { $0.pid == top })
        stop.interrupt()
        // `top` started in the background ignores SIGINT; the ladder is out
        // of reach, so end it by hand once it is seen, as SIGTERM would.
        kill(top, SIGTERM)
        #expect(await stop.waitUntilGone())
        // Gone may still be a zombie for launchd to reap (orphaned once the
        // shell died of the SIGINT): it runs nothing, and `members` rightly
        // no longer counts it (`getsid` answers ESRCH).
        var reaped = false
        for _ in 0..<250 where !reaped {
            reaped = kill(top, 0) != 0
            // cancel-ok: test polling for launchd's reap
            if !reaped { try? await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(reaped)
        _ = try? await run.value
        _ = leader.value
    }

    /// A command whose own process ignores SIGINT and SIGTERM — and its
    /// `sleep`, which inherits that — is ended by the ladder's SIGKILL, run
    /// through the runner as production runs it: the ladder starts at the
    /// stop, not once the command has exited. Mutations: no SIGKILL step, or
    /// the ladder started only after the command returns (the run gives up,
    /// not stopped).
    @Test func theLadderEndsACommandThatIgnoresTheInterrupt() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let command = CLIToolCommand(
            executable: "/bin/sh", arguments: ["-c", "trap '' INT TERM; touch \(root)/started; sleep 600"], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.stoppableRunner(termAfter: .milliseconds(300), killAfter: .milliseconds(600), giveUpAfter: .seconds(20))(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(20), killAfter: .seconds(25)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: root + "/started") {
            // cancel-ok: test polling for the child's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        let result = await task.value
        #expect(result.stopped)
        #expect(!result.stuck)
        // Ended by the ladder, not by the deadline's backstop.
        #expect(result.failureMessage == "stopped")
    }

    // MARK: ManagedProvider

    private func provider(_ adapter: ManagedModelTests.FakeAdapter, stoppable: @escaping ManagedProvider.Runner) -> ManagedProvider {
        ManagedProvider(
            adapter, home: ManagedModelTests.home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in
                Issue.record("the run-to-completion runner was used for an upgrade that may be stopped")
                return ManagedProvider.RunResult(succeeded: false, failureMessage: "wrong runner", lines: [])
            },
            stoppableRunner: stoppable)
    }

    /// A stopped run's changes are put back, the row says so, and the scratch
    /// `TMPDIR` the command was given is gone. Mutations: `update` ignoring
    /// `stopped`; `putBack` not calling `restore`; the scratch directory not
    /// removed.
    @Test func aStoppedUpgradeIsPutBack() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"], scratchVariables: ["TMPDIR"])
        let tmp = Locked<String?>(nil)
        let outcome = await provider(adapter) { _, environment, _, _, _ in
            tmp.set(environment["TMPDIR"])
            try? self.write(root + "/venv/receipt", "2.0")
            try? self.write((environment["TMPDIR"] ?? root) + "/cargo-install123/big", "x")
            return ManagedProvider.RunResult(succeeded: false, failureMessage: "stopped", lines: ["Compiling"], stopped: true)
        }.update(ManagedModelTests.status(), progress: { _ in })
        guard case .stopped(let message, _, let complete) = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(message == "stopped; ZZ Fake tools's changes were put back")
        #expect(complete)
        #expect(read(root + "/venv/receipt") == "1.0")
        #expect(tmp.value != nil)
        #expect(!FileManager.default.fileExists(atPath: tmp.value ?? "/"))
    }

    /// What cannot be put back is said, and makes the outcome incomplete —
    /// a failure on the row even after a Cancel. Here a new entry in a
    /// directory the run left read-only. Mutation: `complete: true` always.
    @Test func anIncompleteRestoreSaysWhatIsLeft() async throws {
        let root = try scratch()
        defer {
            chmod(root + "/bin", 0o755)
            try? FileManager.default.removeItem(atPath: root)
        }
        try write(root + "/bin/old", "old")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(
            paths: [], created: [ManagedSnapshot.NewEntries(directory: root + "/bin", any: true)])
        let outcome = await provider(adapter) { _, _, _, _, _ in
            try? self.write(root + "/bin/new", "new")
            chmod(root + "/bin", 0o555)
            return ManagedProvider.RunResult(succeeded: false, failureMessage: "stopped", lines: [], stopped: true)
        }.update(ManagedModelTests.status(), progress: { _ in })
        guard case .stopped(let message, _, let complete) = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(!complete)
        #expect(message.contains("could not put back: \(root)/bin/new"))
    }

    /// A stop that left processes running puts nothing back under them,
    /// keeps the snapshot and names it, and is a failure. Mutation: the
    /// snapshot discarded; `complete: true`.
    @Test func aStuckStopKeepsTheSnapshotAndSaysWhere() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        let outcome = await provider(adapter) { _, _, _, _, _ in
            try? self.write(root + "/venv/receipt", "2.0")
            return ManagedProvider.RunResult(
                succeeded: false, failureMessage: "stopped; some of its processes are still running", lines: [], stuck: true)
        }.update(ManagedModelTests.status(), progress: { _ in })
        guard case .stopped(let message, _, let complete) = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(!complete)
        #expect(read(root + "/venv/receipt") == "2.0")
        let kept = try #require(message.components(separatedBy: "kept in ").last)
        defer { try? FileManager.default.removeItem(atPath: kept) }
        #expect(read(kept + "/0/receipt") == "1.0")
    }

    /// A run that finished keeps what it wrote. Mutation: `discard` replaced
    /// by `restore` on the success path.
    @Test func aFinishedUpgradeKeepsItsWrites() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        let outcome = await provider(adapter) { _, _, _, _, _ in
            try? self.write(root + "/venv/receipt", "2.0")
            return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["Updated"])
        }.update(ManagedModelTests.status(), progress: { _ in })
        #expect(outcome == .updated(version: "20.20.2"))
        #expect(read(root + "/venv/receipt") == "2.0")
    }

    /// A Cancel that lands after the command finished but before its result
    /// is taken still means "not updated": the commit refuses it, and the
    /// writes are put back. Mutation: the success path not wrapped in
    /// `InstallCommit.run`.
    @Test func aCancelAfterTheCommandFinishedPutsItBack() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        let jobID = "managed-stop-test:\(UUID().uuidString)"
        let provider = provider(adapter) { _, _, _, _, _ in
            try? self.write(root + "/venv/receipt", "2.0")
            #expect(InstallJobs.cancel(jobID) == .cancelled)
            return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["Updated"])
        }
        let (outcome, stopped) = await InstallJobs.run(jobID) {
            (await provider.update(ManagedModelTests.status(), progress: { _ in }), InstallJobs.cancelStoppedSomething(jobID))
        }
        guard case .stopped = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(stopped)
        #expect(read(root + "/venv/receipt") == "1.0")
    }

    /// An adapter that names no paths runs to completion, as before D15.
    /// Mutation: the stoppable runner chosen whatever the plan.
    @Test func noPlanRunsToCompletion() async throws {
        let adapter = ManagedModelTests.FakeAdapter()
        let ran = Locked(false)
        let provider = ManagedProvider(
            adapter, home: ManagedModelTests.home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in
                ran.set(true)
                return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: [])
            },
            stoppableRunner: { _, _, _, _, _ in
                Issue.record("stoppable runner used without a plan")
                return ManagedProvider.RunResult(succeeded: false, failureMessage: nil, lines: [])
            })
        _ = await provider.update(ManagedModelTests.status(), progress: { _ in })
        #expect(ran.value)
    }
}

/// A value the scripted runners set from a `@Sendable` closure.
final class Locked<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func set(_ value: T) { lock.withLock { stored = value } }
}
