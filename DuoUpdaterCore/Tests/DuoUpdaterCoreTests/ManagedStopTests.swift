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

    /// A process that hands over to a fresh child and exits, again and again,
    /// ignoring SIGINT and SIGTERM: one of it is alive at every instant, but
    /// a table read followed by each entry's `getsid` can miss all of them.
    /// The group it stays in is asked about at once (`killpg(group, 0)`),
    /// and the ladder's SIGKILL ends it; the run returns only then, as
    /// stopped. Mutation: no `groups` (the scan reads empty; `waitUntilGone`
    /// returns with the relay running — seen 6 times in 6 in review).
    @Test func aForkAndExitRelayIsWaitedForAndKilled() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/relay.pl", """
            $SIG{INT} = 'IGNORE'; $SIG{TERM} = 'IGNORE';
            open(G, '>\(root)/group'); print G getpgrp(); close G;
            my $until = time + 600;
            while (time < $until) {
                my $p = fork(); die "fork: $!" unless defined $p;
                if ($p) { exit 0 }
                select(undef, undef, undef, 0.002);
            }
            open(F, '>\(root)/ended'); close F;
            """)
        let command = CLIToolCommand(
            executable: "/bin/sh", arguments: ["-c", "perl \(root)/relay.pl & sleep 600; wait"], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.stoppableRunner(termAfter: .milliseconds(300), killAfter: .seconds(2), giveUpAfter: .seconds(20))(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(20), killAfter: .seconds(25)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: root + "/group") {
            // cancel-ok: test polling for the relay's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        // cancel-ok: let the relay hand over a few times
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        let group = pid_t(read(root + "/group")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        #expect(group > 0)
        let left = killpg(group, 0) == 0
        #expect(!left, "the relay's group still had a process when the run returned")
        if left { killpg(group, SIGKILL) }
        #expect(result.stopped)
        #expect(result.failureMessage == "stopped")
    }

    /// A relay (fork, parent exits, every 2 ms, ignoring SIGINT and SIGTERM)
    /// that, 1.5 s in, moves into a group of its own and keeps writing. One
    /// scan can miss every link of it (the listed one gone, the new one not
    /// listed yet); a session dropped then was never looked for again, and
    /// the survivor's new group was never found — it ran on through the
    /// put-back, 5 in 5 (local adversarial review, 2026-10-27). The run must
    /// end it (the ladder's SIGKILL at 2 s) before it says stopped. No clock
    /// is read. Mutation: the old drop rule (a session dropped on its first
    /// empty scan, its groups not counted); either half alone it survives —
    /// `oneEmptyScanDropsNoSession` and `aSessionWithAGroupLeftIsKept` pin
    /// those (local adversarial review 2).
    @Test func aRelayThatMovesToAGroupOfItsOwnIsStillStopped() async throws {
        for round in 0..<3 {
            let root = try scratch()
            defer { try? FileManager.default.removeItem(atPath: root) }
            try write(root + "/relay.pl", """
                use Time::HiRes qw(time);
                $SIG{INT} = 'IGNORE'; $SIG{TERM} = 'IGNORE';
                open(G, '>\(root)/group'); close G;
                my $start = time;
                while (time - $start < 1.5) {
                    my $p = fork(); die "fork: $!" unless defined $p;
                    if ($p) { exit 0 }
                    select(undef, undef, undef, 0.002);
                }
                setpgrp(0, 0);
                open(P, '>\(root)/pid.tmp'); print P $$; close P; rename('\(root)/pid.tmp', '\(root)/pid');
                my $until = time + 60;
                while (time < $until) { select(undef, undef, undef, 0.05); }
                """)
            let command = CLIToolCommand(
                executable: "/bin/sh", arguments: ["-c", "perl \(root)/relay.pl >/dev/null 2>&1 & sleep 600; wait"],
                pathPrefix: nil)
            let task = Task {
                await ManagedProvider.stoppableRunner(termAfter: .milliseconds(300), killAfter: .seconds(2), giveUpAfter: .seconds(20))(
                    command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                    .init(terminateAfter: .seconds(30), killAfter: .seconds(35)), { _ in })
            }
            while !FileManager.default.fileExists(atPath: root + "/group") {
                // cancel-ok: test polling for the relay's start
                try? await Task.sleep(for: .milliseconds(20))
            }
            // cancel-ok: let the relay hand over a few times
            try? await Task.sleep(for: .milliseconds(200))
            task.cancel()
            let result = await task.value
            let pid = pid_t(read(root + "/pid")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            let alive = pid > 0 && kill(pid, 0) == 0
            if alive { kill(pid, SIGKILL) }
            #expect(result.stopped, "round \(round)")
            #expect(!alive, "round \(round): the relay ran on in a group of its own after the run said stopped")
        }
    }

    /// Once a stop finds nothing left, nothing is followed any more: an empty
    /// session's id is free for the kernel to hand out, and the ladder's
    /// later steps must not find a stranger under it. Mutation: no pruning of
    /// `sessions` (an emptied session stays tracked).
    @Test func aStopThatFindsNothingLeftFollowsNothingMore() async throws {
        let stop = ManagedStop(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))
        let run = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", "sleep 30"], standardOutput: .discard, standardError: .discard,
                onCancel: .runToCompletion, onLaunch: { stop.launched($0) }, newSession: true)
        }
        while stop.trackedSessions.isEmpty {
            // cancel-ok: test polling for the launch
            try? await Task.sleep(for: .milliseconds(20))
        }
        stop.interrupt()
        _ = try? await run.value
        #expect(await stop.waitUntilGone())
        #expect(stop.trackedSessions.isEmpty)
        #expect(stop.members() == [])
        #expect(!stop.alive())
    }

    /// A stop asked for before the child starts — Cancel between the runner's
    /// own check and the spawn — reaches it as it starts: it dies of the
    /// SIGINT, not at its 20 s, and the wait sees it go. Mutation: a scan
    /// before the launch latching `gone` (review round 4: the child got no
    /// signal and ran to its end).
    @Test func aStopAskedForBeforeTheLaunchReachesTheChild() async throws {
        let stop = ManagedStop(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))
        stop.interrupt()
        let outcome = try await ChildProcess.run(
            "/bin/sleep", ["20"], standardOutput: .discard, standardError: .discard,
            onCancel: .runToCompletion, onLaunch: { stop.launched($0) }, newSession: true)
        #expect(outcome.uncaughtSignal && outcome.terminationStatus == SIGINT, "the child ran to its end")
        #expect(await stop.waitUntilGone())
        stop.finish()
    }

    /// No process table is read before the launch: one read then cannot list
    /// the child, and if the launch lands before that scan takes the lock, the
    /// scan drops the child's session and latches "gone" — the round-4 outcome
    /// by another path (review round 5). Mutation: the table read before the
    /// launch check (`interrupt` reads it once).
    @Test func noTableIsReadBeforeTheLaunch() {
        let reads = Locked(0)
        // The ladder looks at 50 ms, finds nothing launched, and ends.
        let stop = ManagedStop(termAfter: .milliseconds(50), killAfter: .seconds(600), giveUpAfter: .seconds(20),
                               table: { reads.set(reads.value + 1); return [] })
        stop.interrupt()
        #expect(stop.members() == [])
        #expect(reads.value == 0)
        stop.finish()
    }

    /// Two looks that each find none of a session count as two only
    /// `missGap` apart: two back to back can both fall inside a relay's hops
    /// (local adversarial review 2's probe: 2 in 20 got through with
    /// back-to-back looks). Mutation: no gap.
    @Test func missesCountOnlyAGapApart() async {
        let stop = ManagedStop(missGap: .milliseconds(200), table: { [] })
        stop.finish()
        stop.launched(99_996)
        _ = stop.members()
        _ = stop.members()
        #expect(stop.trackedSessions == [99_996])
        // cancel-ok: a test waiting out the gap
        try? await Task.sleep(for: .milliseconds(250))
        _ = stop.members()
        #expect(stop.trackedSessions.isEmpty)
    }

    /// `alive` looks until the session is found or dropped, not a fixed
    /// number of times: its own two looks miss the member, and another scan
    /// (the tracker, the ladder, `waitUntilGone`) finds it between them, so
    /// its second look counts only one miss — the session is still followed
    /// and its member runs. The other scan runs, and ends, inside `alive`'s
    /// second table read; `alive` sleeps `missGap` between its looks, but
    /// either timing leaves one miss at most, and the third look finds the
    /// member (20 in 20 at load 104–142, review 4). Local adversarial
    /// review 3. Mutation: `alive` giving up after two empty looks.
    @Test func aliveLooksUntilTheSessionIsFoundOrDropped() async throws {
        let started = Locked<pid_t>(0)
        let run = Task {
            try await ChildProcess.run(
                "/bin/sleep", ["30"], standardOutput: .discard, standardError: .discard,
                onCancel: .runToCompletion, onLaunch: { started.set($0) }, newSession: true)
        }
        while started.value == 0 {
            // cancel-ok: test polling for the launch
            try? await Task.sleep(for: .milliseconds(10))
        }
        let pid = started.value
        defer { kill(pid, SIGKILL) }
        var ghost: pid_t = 99_990
        while kill(ghost, 0) == 0 || errno != ESRCH { ghost -= 1 }
        let group = ghost
        let (answered, alive, found) = await offCooperativePool { () -> (Bool, Bool, [pid_t]) in
            let looks = Locked(0)
            let otherFound = Locked<[pid_t]>([])
            let box = Locked<ManagedStop?>(nil)
            let stop = ManagedStop(table: {
                if Thread.current.name == "other scan" {
                    return [ManagedStop.Member(pid: pid, ppid: getpid(), pgid: group, started: 0)]
                }
                let look = looks.value
                looks.set(look + 1)
                switch look {
                case 0: return []
                case 1:
                    let done = DispatchSemaphore(value: 0)
                    let other = Thread { otherFound.set((box.value?.members() ?? []).map(\.pid)); done.signal() }
                    other.name = "other scan"
                    other.start()
                    done.wait()
                    return []
                default: return ManagedStop.processes()
                }
            })
            box.set(stop)
            stop.finish()
            stop.launched(pid)
            let answered = DispatchSemaphore(value: 0)
            let result = Locked(false)
            Thread { result.set(stop.alive()); answered.signal() }.start()
            return (answered.wait(timeout: .now() + 5) == .success, result.value, otherFound.value)
        }
        #expect(found == [pid])
        #expect(answered)
        #expect(alive, "alive() said none left while \(pid) of a followed session ran")
        kill(pid, SIGKILL)
        _ = try? await run.value
    }

    /// The read that counted a miss — its end, not its start — is what the
    /// next must begin `missGap` after: a counting read held open past the
    /// gap (a preempted scan), and one begun while it was open, count one
    /// miss. `overlappingScansCountOneMiss` holds the other order (the
    /// later-begun read ends first). Local adversarial review 3. Mutation:
    /// `missedAt` set to the counting read's start.
    @Test func aReadBegunDuringACountingReadCountsNoSecondMiss() async {
        let tracked = await offCooperativePool { () -> Set<pid_t> in
            let aEntered = DispatchSemaphore(value: 0), aRelease = DispatchSemaphore(value: 0)
            let bEntered = DispatchSemaphore(value: 0), bRelease = DispatchSemaphore(value: 0)
            let calls = Locked(0)
            let stop = ManagedStop(missGap: .milliseconds(50), table: {
                let call = calls.value
                calls.set(call + 1)
                if call == 0 { aEntered.signal(); aRelease.wait() }
                if call == 1 { bEntered.signal(); bRelease.wait() }
                return []
            })
            stop.finish()
            stop.launched(99_995)
            let aDone = DispatchSemaphore(value: 0), bDone = DispatchSemaphore(value: 0)
            Thread { _ = stop.members(); aDone.signal() }.start()
            aEntered.wait()
            usleep(80_000)
            Thread { _ = stop.members(); bDone.signal() }.start()
            bEntered.wait()
            aRelease.signal()
            aDone.wait()
            bRelease.signal()
            bDone.wait()
            return stop.trackedSessions
        }
        #expect(tracked == [99_995])
    }

    /// Before the launch nothing is followed: `alive` answers none at once.
    /// It looks again while a scan finds nothing and drops nothing, and
    /// before the launch every scan is such — a stop asked for then whose
    /// launch never comes would keep the ladder's thread looking forever.
    /// Waited for on a thread of its own, with a bound, off the cooperative
    /// pool. Mutation: no launch check.
    @Test func nothingIsAliveBeforeTheLaunch() async {
        let stop = ManagedStop(table: { [] })
        stop.finish()
        let alive = Locked(true)
        let answered = await offCooperativePool {
            let answered = DispatchSemaphore(value: 0)
            Thread { alive.set(stop.alive()); answered.signal() }.start()
            return answered.wait(timeout: .now() + 5) == .success
        }
        #expect(answered)
        #expect(!alive.value)
    }

    /// One scan that finds none of a session is not enough to drop it: a
    /// fork-and-exit chain can be missed by one. Two in a row are. No tracker
    /// runs (`finish` first), so only these scans count; no gap is asked
    /// between them. Mutation: drop on the first empty scan.
    @Test func oneEmptyScanDropsNoSession() {
        let stop = ManagedStop(missGap: .zero, table: { [] })
        stop.finish()
        stop.launched(99_998)
        _ = stop.members()
        #expect(stop.trackedSessions == [99_998])
        _ = stop.members()
        #expect(stop.trackedSessions.isEmpty)
    }

    /// A session keeps its place while a group of it is left, however many
    /// scans miss its members: the group is in that session and nowhere
    /// else, and `killpg(group, 0)` asks the kernel about all of it at once.
    /// Here the table lists the member once, then never again, while it
    /// lives. Mutation: drop a session whose group is still there.
    @Test func aSessionWithAGroupLeftIsKept() async throws {
        let started = Locked<pid_t>(0)
        let run = Task {
            try await ChildProcess.run(
                "/bin/sleep", ["30"], standardOutput: .discard, standardError: .discard,
                onCancel: .runToCompletion, onLaunch: { started.set($0) }, newSession: true)
        }
        while started.value == 0 {
            // cancel-ok: test polling for the launch
            try? await Task.sleep(for: .milliseconds(10))
        }
        let pid = started.value
        let listed = Locked(true)
        let stop = ManagedStop(missGap: .zero, table: {
            defer { listed.set(false) }
            return listed.value ? [ManagedStop.Member(pid: pid, ppid: getpid(), pgid: pid, started: 0)] : []
        })
        stop.finish()
        stop.launched(pid)
        for _ in 0..<4 { _ = stop.members() }
        #expect(stop.trackedSessions == [pid])
        kill(pid, SIGKILL)
        _ = try? await run.value
        _ = stop.members()
        _ = stop.members()
        #expect(stop.trackedSessions.isEmpty)
        #expect(!stop.alive())
    }

    /// One empty scan is no verdict while a session is still followed. A
    /// member that left for a group of its own (`setpgrp`) is in no group
    /// recorded, and a scan that missed it — here the table leaves it out
    /// once, as a relay's hop can — said none left: the run put back under
    /// it (local adversarial review 2, 2 in 10 with a relay changing group
    /// on every hop). `alive` looks again. Mutation: `alive` trusting one
    /// scan.
    @Test func oneEmptyScanIsNoVerdictWhileASessionIsFollowed() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let started = Locked<pid_t>(0)
        let run = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", "perl -e 'setpgrp(0, 0); open(P, \">\(root)/m.tmp\"); print P $$; close P; rename(\"\(root)/m.tmp\", \"\(root)/m\"); sleep 30' & wait"],
                standardOutput: .discard, standardError: .discard,
                onCancel: .runToCompletion, onLaunch: { started.set($0) }, newSession: true)
        }
        while started.value == 0 || read(root + "/m") == nil {
            // cancel-ok: test polling for the launch
            try? await Task.sleep(for: .milliseconds(10))
        }
        let leader = started.value
        let member = pid_t(read(root + "/m")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        defer { if member > 0 { kill(member, SIGKILL) } }
        #expect(member > 0 && getsid(member) == leader && getpgid(member) == member)
        // The leader alone, then nothing once, then the real table.
        let calls = Locked(0)
        let stop = ManagedStop(table: {
            let call = calls.value
            calls.set(call + 1)
            switch call {
            case 0: return [ManagedStop.Member(pid: leader, ppid: getpid(), pgid: leader, started: 0)]
            case 1: return []
            default: return ManagedStop.processes()
            }
        })
        stop.finish()
        stop.launched(leader)
        _ = stop.members()
        kill(leader, SIGKILL)
        _ = try? await run.value
        let alive = await offCooperativePool { stop.alive() }
        #expect(alive, "one empty scan read as none left while \(member) ran")
    }

    /// Two scans reading the table at once see the same moment: their two
    /// misses are one look, not two in a row, and drop nothing. Here one
    /// read is held open while another runs to its end. No tracker runs
    /// (`finish` first); no gap is asked. Off the cooperative pool: the
    /// reads are held with semaphores. Mutation: every miss counted.
    @Test func overlappingScansCountOneMiss() async {
        let (kept, dropped) = await offCooperativePool { () -> (Set<pid_t>, Set<pid_t>) in
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let first = Locked(true)
            let stop = ManagedStop(missGap: .zero, table: {
                if first.value {
                    first.set(false)
                    entered.signal()
                    release.wait()
                }
                return []
            })
            stop.finish()
            stop.launched(99_997)
            let done = DispatchSemaphore(value: 0)
            Thread { _ = stop.members(); done.signal() }.start()
            entered.wait()
            _ = stop.members()
            release.signal()
            done.wait()
            let kept = stop.trackedSessions
            _ = stop.members()
            return (kept, stop.trackedSessions)
        }
        #expect(kept == [99_997])
        #expect(dropped.isEmpty)
    }

    /// A process table that cannot be read is never "nothing left": the run
    /// waits, and gives up rather than put anything back. Mutation:
    /// `processes` answering [] on failure, or `alive` taking nil for none.
    @Test func anUnreadableProcessTableIsNotNothingLeft() async throws {
        let stop = ManagedStop(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .milliseconds(300),
                               table: { nil })
        stop.launched(getpid())
        #expect(stop.alive())
        stop.interrupt()
        #expect(await stop.waitUntilGone() == false)
        stop.finish()
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
                "/bin/sh", ["-c", "/usr/bin/top -l 600 -s 1 > /dev/null 2> \(root)/top.err & echo $! > \(root)/top; wait"],
                standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion,
                onLaunch: { stop.launched($0); leader.set($0) }, newSession: true)
        }
        while !FileManager.default.fileExists(atPath: root + "/top") {
            // cancel-ok: test polling for the child's start
            try? await Task.sleep(for: .milliseconds(20))
        }
        let top = pid_t(read(root + "/top")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        // Wait for the forked shell to have exec'd the setuid `top` (the pid
        // is written before): the kernel's table shows it running as root.
        var asRoot = false
        for _ in 0..<500 where !asRoot {
            var kinfo = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, top]
            asRoot = sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 && size > 0 && kinfo.kp_eproc.e_ucred.cr_uid == 0
            // cancel-ok: test polling for the exec
            if !asRoot { try? await Task.sleep(for: .milliseconds(20)) }
        }
        try #require(asRoot, "top never ran as root: \(read(root + "/top.err") ?? "")")
        // The premise: as this user, proc_pidinfo cannot read it.
        var info = proc_bsdinfo()
        #expect(proc_pidinfo(top, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) <= 0)
        // The launch callback can come after the child has already run on a
        // loaded machine: wait for it, then for a scan that lists `top`.
        var seen: [ManagedStop.Member]?
        for _ in 0..<250 {
            seen = stop.members()
            if leader.value != 0, seen?.contains(where: { $0.pid == top }) == true { break }
            // cancel-ok: test polling for the launch callback
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(seen?.contains { $0.pid == top } == true,
                "members \(seen.map { $0.map(\.pid) } ?? []), tracked \(stop.trackedSessions), leader \(leader.value) sid \(getsid(leader.value)), top sid \(getsid(top)) pgid \(getpgid(top))")
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
    /// A run its deadline stopped says so: a failure, not a cancel.
    /// Mutation: the runner's reason always "stopped".
    @Test func aDeadlinesStopIsAFailureNotACancel() async throws {
        let command = CLIToolCommand(executable: "/bin/sh", arguments: ["-c", "sleep 600"], pathPrefix: nil)
        let result = await ManagedProvider.stoppableRunner(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))(
            command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
            .init(terminateAfter: .milliseconds(300), killAfter: .seconds(25)), { _ in })
        #expect(result.stopped)
        #expect(result.failureMessage != "stopped")
        #expect(!result.succeeded)
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

    /// A stopped run's changes are put back and the row says so. The command
    /// gets no `TMPDIR` of ours: its temporary files go where they went
    /// before D15 (a scratch of ours lost a daemon's files under it, local
    /// adversarial review 5). Mutations: `update` ignoring `stopped`;
    /// `putBack` not calling `restore`; a `TMPDIR` set for the run.
    @Test func aStoppedUpgradeIsPutBack() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        let tmp = Locked<String?>(nil)
        let outcome = await provider(adapter) { _, environment, _, _, _ in
            tmp.set(environment["TMPDIR"])
            try? self.write(root + "/venv/receipt", "2.0")
            return ManagedProvider.RunResult(succeeded: false, failureMessage: "stopped", lines: ["Compiling"], stopped: true)
        }.update(ManagedModelTests.status(), progress: { _ in })
        guard case .stopped(let message, _, let complete) = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(message == "stopped; ZZ Fake tools's changes were put back")
        #expect(complete)
        #expect(read(root + "/venv/receipt") == "1.0")
        #expect(tmp.value == nil)
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

    /// A cancel that lands after the command finished, while something it
    /// started still runs, puts nothing back: the update stands, the snapshot
    /// is kept, and the row fails saying so. Mutation: ignore `leftovers`
    /// (the put-back runs under the live process).
    @Test func aLateCancelWithProcessesLeftPutsNothingBack() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        let jobID = "managed-stop-test:\(UUID().uuidString)"
        let provider = provider(adapter) { _, _, _, _, _ in
            try? self.write(root + "/venv/receipt", "2.0")
            #expect(InstallJobs.cancel(jobID) == .cancelled)
            return ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["Updated"], leftovers: true)
        }
        let outcome = await InstallJobs.run(jobID) { await provider.update(ManagedModelTests.status(), progress: { _ in }) }
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

    /// A stop that could not end every process starts nothing more — not
    /// mise's token retry, whose run would also discard the kept snapshot.
    /// Mutation: retry on `stuck` too.
    @Test func aStuckStopIsNotRetried() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        adapter.tokenRetry = ManagedTokenRetry(variable: "ZZ_TOKEN", marker: "No GitHub token was found")
        let runs = Locked(0)
        let provider = ManagedProvider(
            adapter, home: ManagedModelTests.home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { "zz-token" },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: false, failureMessage: "unused", lines: []) },
            stoppableRunner: { _, _, _, _, _ in
                runs.set(runs.value + 1)
                return ManagedProvider.RunResult(
                    succeeded: false, failureMessage: "stopped; some of its processes are still running",
                    lines: ["No GitHub token was found"], stuck: true)
            })
        let outcome = await provider.update(ManagedModelTests.status(), progress: { _ in })
        #expect(runs.value == 1)
        guard case .stopped(let message, _, false) = outcome else {
            Issue.record("expected an incomplete .stopped, got \(outcome)")
            return
        }
        if let kept = message.components(separatedBy: "kept in ").last { try? FileManager.default.removeItem(atPath: kept) }
    }

    /// A run that fails by itself while a process it started still runs is
    /// not retried: a stop of the retry would put back under that process
    /// (local adversarial review: the receipt was rewritten after the
    /// put-back). The runner's own `leftovers` is what says so. Mutations:
    /// `leftovers` read as false in `stoppableRunner`, or dropped from a
    /// failed result, or the retry not checking it (each: two runs).
    @Test func aFailedRunWithProcessesLeftIsNotRetried() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try write(root + "/venv/receipt", "1.0")
        let script = """
            if [ -z "$ZZ_TOKEN" ]; then
              echo "No GitHub token was found"
              sh -c 'echo $$ > \(root)/writer; trap "" INT TERM; sleep 30' >/dev/null 2>&1 &
              while [ ! -s \(root)/writer ]; do sleep 0.01; done
              exit 1
            fi
            touch \(root)/second
            """
        let real = CLIToolCommand(executable: "/bin/sh", arguments: ["-c", script], pathPrefix: nil)
        let adapter = ManagedModelTests.FakeAdapter()
        adapter.interruptionPlan = ManagedInterruption(paths: [root + "/venv"])
        adapter.tokenRetry = ManagedTokenRetry(variable: "ZZ_TOKEN", marker: "No GitHub token was found")
        let inner = ManagedProvider.stoppableRunner(termAfter: .seconds(600), killAfter: .seconds(600), giveUpAfter: .seconds(20))
        let runs = Locked(0)
        let provider = ManagedProvider(
            adapter, home: ManagedModelTests.home,
            proxyEnvironment: { [:] }, processes: { [] }, token: { "zz-token" },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: false, failureMessage: "unused", lines: []) },
            stoppableRunner: { _, environment, _, deadline, progress in
                runs.set(runs.value + 1)
                var env = environment
                env["PATH"] = "/usr/bin:/bin"
                return await inner(real, env, URL(fileURLWithPath: "/"), deadline, progress)
            })
        let outcome = await provider.update(ManagedModelTests.status(), progress: { _ in })
        let writer = pid_t(read(root + "/writer")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        if writer > 0 { kill(writer, SIGKILL) }
        #expect(writer > 0)
        #expect(runs.value == 1)
        #expect(!FileManager.default.fileExists(atPath: root + "/second"))
        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
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
