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
    /// every member has gone — the background `sleep` too, which a signal to
    /// the shell alone would leave running. Mutations: `kill` instead of
    /// `killpg` in `interrupt`; `waitUntilGone` returning at once.
    @Test func aCancelledRunStopsItsWholeGroup() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let marker = root + "/started"
        // A pipeline, as a build tool runs its compiler: the inner `sleep`
        // (the `sh` that wrote its pid, then exec'd) is a grandchild in the
        // group, which a signal to the outer shell alone would leave running.
        // Not `&`: a non-interactive shell starts those ignoring SIGINT, and
        // only the ladder's SIGTERM ends them (`theLadderEnds…`).
        let inner = "echo $$ > \(marker).child; touch \(marker); exec sleep 30"
        let command = CLIToolCommand(
            executable: "/bin/sh", arguments: ["-c", "sh -c '\(inner)' | cat"], pathPrefix: nil)
        let task = Task {
            await ManagedProvider.interruptibleRunner(
                command, ["PATH": "/usr/bin:/bin"], URL(fileURLWithPath: "/"),
                .init(terminateAfter: .seconds(60), killAfter: .seconds(65)), { _ in })
        }
        while !FileManager.default.fileExists(atPath: marker) {
            // cancel-ok: test polling for the child's start, bounded by the child's own 30 s
            try? await Task.sleep(for: .milliseconds(20))
        }
        let child = pid_t(read(marker + ".child")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        let clock = ContinuousClock()
        let began = clock.now
        task.cancel()
        let result = await task.value
        #expect(result.stopped)
        #expect(!result.succeeded)
        #expect(clock.now - began < .seconds(10))
        #expect(child > 0)
        #expect(kill(child, 0) != 0)
    }

    /// A group member that ignores SIGINT is sent SIGTERM, then SIGKILL, up
    /// the ladder. Mutation: no SIGKILL step (the `trap ''` on TERM outlasts
    /// it, and `waitUntilGone` gives up).
    @Test func theLadderEndsAMemberThatIgnoresTheInterrupt() async throws {
        let stop = ManagedStop(termAfter: .milliseconds(300), killAfter: .milliseconds(600), giveUpAfter: .seconds(10))
        let outcome = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", "trap '' INT TERM; sleep 30 & wait; wait"], standardOutput: .discard, standardError: .discard,
                onCancel: .runToCompletion, onLaunch: { stop.launched($0) })
        }
        // cancel-ok: test waiting for the spawn
        try? await Task.sleep(for: .milliseconds(300))
        stop.interrupt()
        #expect(await stop.waitUntilGone())
        _ = try? await outcome.value
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
        guard case .stopped(let message, _) = outcome else {
            Issue.record("expected .stopped, got \(outcome)")
            return
        }
        #expect(message == "stopped; ZZ Fake tools's changes were put back")
        #expect(read(root + "/venv/receipt") == "1.0")
        #expect(tmp.value != nil)
        #expect(!FileManager.default.fileExists(atPath: tmp.value ?? "/"))
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
