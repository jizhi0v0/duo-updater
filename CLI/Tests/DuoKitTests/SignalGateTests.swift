import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// `SignalGate`: what SIGINT/SIGTERM/SIGHUP do to `duo install`, `backups
/// restore` and `restart`. Signals are injected through `run`'s `arm` seam —
/// nothing here signals the test process with INT/TERM/HUP — and the children are
/// `/bin/sh` scripts writing into a scratch directory.
@Suite struct SignalGateTests {

    // MARK: - The state machine

    /// The first signal cancels the command and says so once; every later one,
    /// of any kind, only says "still finishing". Nothing exits early: `run`
    /// returns only after the command has, with 128 + the FIRST signal.
    ///
    /// Mutation: make the first signal call `exitNow` (or return from `run`
    /// without awaiting the task) → `exits` is not empty / `returned` is set
    /// while the command is still finishing.
    @Test func firstSignalCancelsLaterOnesOnlySaySoAndRunWaitsForTheCommand() async {
        let harness = Harness()
        let gate = SignalGate()
        let returned = Flag()
        let finish = Latch()
        let steps = Lines()
        let runner = Task {
            let status = await harness.run(gate) {
                harness.started.open()
                // The step in flight: notices the cancellation, then takes its time.
                await sleepUntilCancelled()
                steps.add("command saw cancellation")
                await finish.wait()
                steps.add("command returned")
                return 0
            }
            returned.set()
            return status
        }
        await harness.started.wait()
        harness.deliver(SIGINT)
        harness.deliver(SIGTERM)
        harness.deliver(SIGINT)
        // Long enough for the command to have seen its cancellation.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!returned.isSet, "run must not return while the command is still finishing")
        finish.open()
        let status = await runner.value

        #expect(status == 130)
        #expect(harness.exits.all.isEmpty)
        #expect(harness.notices.all.count == 3)
        #expect(harness.notices.all.first?.contains("SIGINT received — stopping after the current step") == true)
        #expect(harness.notices.all.first?.contains("already replacing an app finishes first") == true)
        #expect(harness.notices.all.dropFirst().allSatisfy { $0.hasPrefix("duo: still finishing") })
        #expect(steps.all == ["command saw cancellation", "command returned"])
        #expect(harness.hangUps.all.isEmpty)
    }

    /// 128 + the first signal; the command's own status when none arrived.
    @Test(arguments: [(SIGINT, 130), (SIGTERM, 143), (SIGHUP, 129)] as [(Int32, Int32)])
    func exitStatusIsOneHundredTwentyEightPlusTheFirstSignal(signo: Int32, expected: Int32) async {
        let harness = Harness()
        let status = await harness.run(SignalGate()) {
            harness.deliver(signo)
            harness.deliver(SIGINT)
            return 1
        }
        #expect(status == expected)
        #expect(harness.exits.all.isEmpty)
    }

    @Test func noSignalLeavesTheCommandsStatus() async {
        let harness = Harness()
        #expect(await harness.run(SignalGate()) { 1 } == 1)
        #expect(await harness.run(SignalGate()) { 0 } == 0)
        #expect(harness.notices.all.isEmpty)
    }

    /// A signal before the root task exists still cancels it.
    @Test func aSignalBeforeTheTaskStartsCancelsItWhenItDoes() async {
        let gate = SignalGate()
        #expect(gate.receive(SIGTERM) == .stop)
        let saw = Flag()
        let status = await gate.run({
            // Bounded: the cancel can land just after the task starts. A
            // cancelled sleep throws at once.
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { saw.set() }
            return 0
        }, arm: { _ in }, say: { _ in }, hangUp: {}, exitNow: { _ in })
        #expect(saw.isSet)
        #expect(status == 143)
    }

    /// SIGHUP detaches the dead terminal's outputs BEFORE the notice is written:
    /// written first, the notice is the write that aborts `duo`. Other signals
    /// leave the outputs alone.
    ///
    /// Mutation: move `hangUp()` after `say` → the order flips.
    @Test func hangUpDetachesOutputsBeforeTheNotice() async {
        let harness = Harness()
        _ = await harness.run(SignalGate()) {
            harness.deliver(SIGINT)
            harness.deliver(SIGHUP)
            return 0
        }
        #expect(harness.events.all == ["say", "hangUp", "say"])
    }

    // MARK: - Which commands

    /// Only the commands that change the machine. Every read-only command keeps
    /// the default disposition, so a `duo check` can always be killed.
    ///
    /// Mutation: answer true for everything → the read-only rows go red.
    @Test func onlyCommandsThatChangeTheMachineAreHandled() {
        #expect(SignalGate.handles(subcommand: "install", operands: ["Fixture"]))
        #expect(SignalGate.handles(subcommand: "install", operands: []))
        #expect(SignalGate.handles(subcommand: "restart", operands: ["Fixture"]))
        #expect(SignalGate.handles(subcommand: "backups", operands: ["restore", "Fixture"]))
        for (command, operands) in [
            ("check", []), ("list", []), ("doctor", []), ("verify", []), ("events", []),
            ("requests", []), ("storage", []), ("claude-code", []), ("ignore", ["Fixture"]),
            ("backups", []), ("backups", ["list"]), ("backups", ["verify"]),
            ("backups", ["disks"]), ("backups", ["probe", "/ZZFixture"]),
        ] as [(String, [String])] {
            #expect(!SignalGate.handles(subcommand: command, operands: operands), "\(command) \(operands)")
        }
    }

    // MARK: - The prompt

    /// While a y/N prompt blocks, any signal exits at once with 128 + it:
    /// nothing has been changed yet, and `readLine` cannot be cancelled.
    ///
    /// Mutation: drop the `prompting` branch → the reaction is `.stop` and the
    /// user is left pressing Ctrl-C at a prompt that ignores it.
    @Test func aSignalAtThePromptExitsAtOnce() {
        let gate = SignalGate()
        var reaction: SignalGate.Reaction?
        let answer = gate.answer {
            reaction = gate.receive(SIGINT)
            return "y"
        }
        #expect(reaction == .exitNow(status: 130))
        #expect(answer == "y")
    }

    /// After a stop the question is not put at all, and reads as "no".
    @Test func noQuestionIsPutAfterAStop() {
        let gate = SignalGate()
        _ = gate.receive(SIGTERM)
        let asked = Flag()
        let answer = gate.answer {
            asked.set()
            return "y"
        }
        #expect(answer == nil)
        #expect(!asked.isSet)
        // And a later signal is back to "still finishing", not an exit.
        #expect(gate.receive(SIGINT) == .stillFinishing)
    }

    // MARK: - Outputs after a hangup

    /// A pipe goes (its reader got the same hangup); a file on disk stays.
    /// A terminal goes too — `isatty` still answers 1 after the hangup (measured
    /// with a pty), but this suite does not open one.
    @Test func whichOutputsWentWithTheTerminal() throws {
        var ends: [Int32] = [-1, -1]
        #expect(pipe(&ends) == 0)
        defer { close(ends[0]); close(ends[1]) }
        #expect(SignalGate.wentWithTheTerminal(ends[1]))

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalGate-\(UUID().uuidString).log")
        let descriptor = open(file.path, O_WRONLY | O_CREAT, 0o600)
        #expect(descriptor >= 0)
        defer { close(descriptor); try? FileManager.default.removeItem(at: file) }
        #expect(!SignalGate.wentWithTheTerminal(descriptor))
    }

    // MARK: - The property that matters: the child finishes

    /// A child printing a line every 0.2 s, run the way brew is run
    /// (`StreamedLines.run`: `.runToCompletion`, stdout and stderr on one pipe),
    /// under `SignalGate.run` with SIGINT delivered after its first line: every
    /// line is read, it exits 0, and `run` returns only after it has — with 130.
    ///
    /// Mutation: make the first signal return from `run` at once → the lines are
    /// cut short and the `finished` marker is missing when it returns.
    @Test func aChildRunToCompletionPrintsEveryLineAfterTheSignal() async throws {
        let scratch = try Scratch()
        let marker = scratch.url.appendingPathComponent("finished").path
        let harness = Harness()
        let lines = Lines()
        let firstLine = Latch()
        let outcome = OutcomeBox()
        let status = await harness.run(SignalGate()) {
            let started = Task {
                await firstLine.wait()
                harness.deliver(SIGINT)
            }
            defer { started.cancel() }
            do {
                let (result, _) = try await StreamedLines.run(
                    "/bin/sh", ["-c", Self.tenLines(marker: marker)], environment: [:]) { line in
                        lines.add(line)
                        firstLine.open()
                    }
                outcome.set(result)
            } catch {
                Issue.record("StreamedLines.run threw \(error)")
            }
            return 0
        }
        #expect(status == 130)
        #expect(harness.exits.all.isEmpty)
        #expect(harness.notices.all.count == 1)
        #expect(lines.all == (1...10).map { "line \($0)" })
        #expect(outcome.value?.succeeded == true)
        #expect(FileManager.default.fileExists(atPath: marker),
                "run returned before the child had finished")
    }

    /// The same through `ChildProcess.run` directly, in a task cancelled after
    /// the first chunk: the awaiting call returns only after the child exited —
    /// its pid is reaped by then and its last act (the marker) is on disk.
    @Test func aCancelledRunToCompletionCallReturnsOnlyAfterTheChildExits() async throws {
        let scratch = try Scratch()
        let marker = scratch.url.appendingPathComponent("finished").path
        let output = Lines()
        let pid = PidBox()
        let firstChunk = Latch()
        let call = Task {
            try await ChildProcess.run(
                "/bin/sh", ["-c", Self.tenLines(marker: marker)],
                standardOutput: .capture, standardError: .discard,
                onCancel: .runToCompletion,
                onOutputChunk: { chunk in
                    output.add(String(decoding: chunk, as: UTF8.self))
                    firstChunk.open()
                },
                onLaunch: { pid.set($0) })
        }
        await firstChunk.wait()
        call.cancel()
        let started = ContinuousClock.now
        let outcome = try await call.value
        #expect(ContinuousClock.now - started > .milliseconds(1000), "returned before the child could have finished")
        #expect(outcome.succeeded)
        #expect(String(decoding: outcome.standardOutput, as: UTF8.self)
            == (1...10).map { "line \($0)\n" }.joined())
        #expect(FileManager.default.fileExists(atPath: marker))
        // Reaped: no process left under that pid (pid reuse within the test is
        // possible in principle; ESRCH is what an exited, reaped child gives).
        if let child = pid.value {
            #expect(kill(child, 0) == -1 && errno == ESRCH)
        }
    }

    /// The gate ignores SIGPIPE (and its three signals) in `duo`; a child must
    /// not inherit that. swift-subprocess resets every signal to default in the
    /// child (`POSIX_SPAWN_SETSIGDEF` over a full set): a `/bin/sh` that signals
    /// itself dies of it, where an inherited SIG_IGN would let it print
    /// `survived`.
    @Test(arguments: [SIGINT, SIGPIPE])
    func childrenGetDefaultDispositionsBack(signo: Int32) async throws {
        let previous = signal(signo, SIG_IGN)
        defer { signal(signo, previous) }
        let outcome = try await ChildProcess.run(
            "/bin/sh", ["-c", "kill -\(signo) $$; echo survived"],
            standardOutput: .capture, standardError: .discard, onCancel: .terminateChild)
        #expect(outcome.uncaughtSignal)
        #expect(outcome.terminationStatus == signo)
        #expect(outcome.standardOutput.isEmpty)
    }

    /// `nohup duo install …` starts `duo` with SIGHUP ignored, and a
    /// background `duo install … &` in a script with SIGINT ignored: the gate
    /// listens only for the signals not ignored already, so the hangup `nohup`
    /// was for does not stop the batch.
    /// Mutation: arm every one of `signals` whatever `isIgnored` says → red.
    @Test func aSignalStartedIgnoredIsLeftIgnored() {
        #expect(SignalGate.signalsToArm(isIgnored: { $0 == SIGHUP }) == [SIGINT, SIGTERM])
        #expect(SignalGate.signalsToArm(isIgnored: { _ in false }) == SignalGate.signals)
    }

    /// `isIgnored` reads the disposition as it is, and changes nothing.
    /// SIGUSR2, which nothing else here touches, so no other test races it.
    /// Mutation: compare against `SIG_DFL` instead → red.
    @Test func isIgnoredReadsTheDisposition() {
        let previous = signal(SIGUSR2, SIG_IGN)
        defer { signal(SIGUSR2, previous) }
        #expect(SignalGate.isIgnored(SIGUSR2))
        #expect(SignalGate.isIgnored(SIGUSR2))
        signal(SIGUSR2, SIG_DFL)
        #expect(!SignalGate.isIgnored(SIGUSR2))
    }

    // MARK: - Stopping before the next item

    /// A cancelled `CLIToolRows.apply` starts no further tool update, and
    /// counts the one it did not start as cancelled — and as nothing else.
    ///
    /// Mutation: drop the `Task.isCancelled` check → the provider is called.
    @Test func cancelledToolUpdatesStartNoFurtherTool() async {
        let calls = CLIToolRowsTests.Calls()
        let provider = CLIToolRowsTests.ScriptedProvider(kind: .uv, calls: calls) { _ in .updated(version: "1.1.0") }
        let task = Task {
            await sleepUntilCancelled()
            var tally = Install.Tally()
            await CLIToolRows.apply([CLIToolRowsTests.uv], providers: [provider], json: false,
                                    tally: &tally, out: { _ in }, err: { _ in })
            return tally
        }
        task.cancel()
        let tally = await task.value
        #expect(calls.paths.isEmpty)
        var cancelledOnly = Install.Tally()
        cancelledOnly.record(.cancelled)
        #expect(tally == cancelledOnly)
    }

    /// A cancelled `Install.apply` does not start the next item: it is counted
    /// as cancelled, and as nothing else. The item's bundle is invented, so
    /// without the checks the re-check finds nothing there and the row is
    /// counted as skipped.
    ///
    /// Mutation: drop both `Task.isCancelled` checks (before the item, after
    /// its re-check) → counted as skipped, not cancelled, red. Dropping only
    /// the first is caught by the second, which counts it the same way; the
    /// stage they report differs, which this test cannot see.
    @Test func cancelledInstallStartsNoFurtherItem() async {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: "com.zzfixture.signalgate", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-signalgate/ZZFixture.app"), isMASApp: false,
            sparkleFeedURL: nil)
        let result = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil,
                downloadURL: URL(string: "https://zz.invalid/fixture.dmg"),
                sourceName: "Sparkle", appStore: nil,
                requiresManualInstaller: false, vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: "2.0"))
        let settings = Settings(
            updateSettings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            ignoredKeys: [], skippedVersions: [:], customScanPaths: [], maxConcurrency: 1,
            testFlightDetection: .off, keepBackups: false, githubToken: nil, alcove: nil)
        let task = Task {
            await sleepUntilCancelled()
            var tally = Install.Tally()
            let attempted = await Install.apply(
                [Install.Planned(result: result, route: .sparkle)], settings: settings, routes: [],
                json: true, keepBackups: false, installedPopulation: nil, tally: &tally)
            return (tally, attempted.count)
        }
        task.cancel()
        let (tally, attempted) = await task.value
        var cancelledOnly = Install.Tally()
        cancelledOnly.record(.cancelled)
        #expect(tally == cancelledOnly)
        #expect(attempted == 0)
    }

    /// A cancelled `duo restart` quits no further app. The app has no bundle id,
    /// so without the check it is answered `.noBundleID` without touching
    /// anything — and a line is printed.
    ///
    /// Mutation: drop the `Task.isCancelled` check → a line is printed.
    @Test func cancelledRestartQuitsNoFurtherApp() async {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: nil, shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-signalgate/ZZFixture.app"), isMASApp: false,
            sparkleFeedURL: nil)
        let lines = Lines()
        let task = Task {
            await sleepUntilCancelled()
            return await Restart.restartEach(
                [app], staged: [:], keepBackups: false, waitsForAnswer: false, print: { lines.add($0) })
        }
        task.cancel()
        let anyFailed = await task.value
        #expect(lines.all.isEmpty)
        #expect(!anyFailed)
    }

    // MARK: - The item in flight finishes

    /// Cancelled while a restart is in its quit wait, the app is still waited
    /// out and reopened. The injected restarter has `AppRestarter`'s shape: poll
    /// with `try? await Task.sleep` until the app has quit (here: 300 ms after
    /// the wait began), give up as `.stillRunning` when the polls run out.
    ///
    /// Mutation: call the step without `SignalGate.finishing` → the polls return
    /// at once in the cancelled task and the line reads "still running".
    @Test func aRestartCancelledInItsQuitWaitStillReopensTheApp() async {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: "com.zzfixture.signalgate", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-signalgate/ZZFixture.app"), isMASApp: false,
            sparkleFeedURL: nil)
        let inQuitWait = Latch()
        let cancelled = Latch()
        let lines = Lines()
        let task = Task {
            await Restart.restartEach(
                [app], staged: [:], keepBackups: false, waitsForAnswer: false, print: { lines.add($0) },
                restart: { _ in
                    inQuitWait.open()
                    await cancelled.wait()
                    let quitAt = ContinuousClock.now + .milliseconds(300)
                    for _ in 0..<150 {
                        if ContinuousClock.now >= quitAt { return .relaunched(true) }
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    return .stillRunning
                })
        }
        await inQuitWait.wait()
        task.cancel()
        cancelled.open()
        let anyFailed = await task.value
        #expect(lines.all == ["ZZFixture  restarted"])
        #expect(!anyFailed)
    }

    /// Cancelled while a tool's update runs, the update's own verification — a
    /// `.terminateChild` version read, as uv's, Deno's, fx's and mise's are —
    /// still runs, and the row is installed, not failed.
    ///
    /// Mutation: call the step without `SignalGate.finishing` → the re-read
    /// refuses to spawn in the cancelled task and the row is failed.
    @Test func aToolUpdateCancelledMidwayIsReportedAsApplied() async {
        let inUpdate = Latch()
        let cancelled = Latch()
        let provider = VerifyingProvider(kind: .uv, inUpdate: inUpdate, cancelled: cancelled)
        let out = Lines(), err = Lines()
        let task = Task {
            var tally = Install.Tally()
            await CLIToolRows.apply([CLIToolRowsTests.uv], providers: [provider], json: false,
                                    tally: &tally, out: { out.add($0) }, err: { err.add($0) })
            return tally
        }
        await inUpdate.wait()
        task.cancel()
        cancelled.open()
        let tally = await task.value
        #expect(tally.installed == 1)
        #expect(tally.failed == 0)
        #expect(out.all.contains("   updated: 1.0.0 → 1.1.0"))
        #expect(err.all.isEmpty)
    }

    /// A signal while a staged restart waits for the app to quit ends that wait —
    /// the "(Ctrl-C to stop waiting)" the slow-quit line promises — with the
    /// bail line, although the step runs where cancellation does not reach. The
    /// app here never quits; the signal arrives at tick 40 of a 3000-tick wait.
    ///
    /// Mutation: drop `stopWaiting` from `Restart.patience` → the wait runs the
    /// whole hand-off window, red.
    @Test func aSignalDuringAStagedRestartsQuitWaitEndsItWithTheBailLine() async {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: "com.zzfixture.signalgate", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-signalgate/ZZFixture.app"), isMASApp: false,
            sparkleFeedURL: nil)
        let staged = StagedSelfUpdate(
            version: "2.0", buildVersion: "2.0",
            stagedBundlePath: URL(fileURLWithPath: "/ZZFixture-signalgate/update.x/ZZFixture.app"),
            appliesOn: .quit, updater: .shipIt)
        let old = VersionSide(marketing: "1.0", build: "1")
        let gate = SignalGate()
        let ticks = Counter()
        let system = StagedRelaunch.System(
            tick: {
                if ticks.increment() == 40 { _ = gate.receive(SIGINT) }
            },
            isRunning: { true },
            terminate: {},
            diskVersion: { old },
            awaitBundleProcessesGone: {},
            relaunch: { _ in Issue.record("nothing may be launched"); return true },
            installer: ParkedInstallerProbe.System(
                isAlive: { _ in false }, loadedJob: { _ in nil }, sparkleInstallerPIDs: { _ in [] }))
        let ending = await SignalGate.finishing {
            await StagedRelaunch.quitAndAwait(
                app, staged: staged, old: old, wasFrontmost: false,
                quitPatience: Restart.patience(
                    for: app, to: "2.0", waitsForAnswer: true, stopWaiting: { gate.stopRequested }),
                system: system)
        }
        #expect(ending.outcome == .wontQuit)
        #expect(ticks.value == 40)
        #expect(Restart.describe(ending, staged: "2.0", disk: old).text
            == "still running — likely a save prompt, left 2.0 staged")
    }

    /// A signal that arrives before the slow-quit point — during the rollback
    /// copy (`signalAt` 0: before the quit request) or just after the quit
    /// request (1) — while the app quits normally at tick 3: the quit is seen,
    /// the swap is waited for (it lands at tick 10), and the app, whose updater
    /// does not reopen it, is reopened after the landing. The line is the
    /// applied one, not "likely a save prompt".
    ///
    /// Mutation: drop the `quitGraceTicks` floor on `stopWaiting` in
    /// `StagedRelaunch.quitAndAwait` → `.wontQuit` while the app is still
    /// shutting down, no reopen, the bail line, red.
    @Test(arguments: [0, 1])
    func aSignalBeforeTheSlowQuitPointLetsANormalQuitRunOut(signalAt: Int) async {
        let world = StagedWorld(quitsAt: 3, landsAt: 10)
        let gate = SignalGate()
        if signalAt == 0 { _ = gate.receive(SIGINT) }
        let ending = await SignalGate.finishing {
            await StagedRelaunch.quitAndAwait(
                world.app, staged: world.staged, old: world.old, wasFrontmost: false,
                quitPatience: Restart.patience(
                    for: world.app, to: "2.0", waitsForAnswer: true, stopWaiting: { gate.stopRequested }),
                system: world.system(onTick: { if $0 == signalAt { _ = gate.receive(SIGINT) } }))
        }
        #expect(gate.stopRequested)
        #expect(ending.outcome == .applied)
        #expect(world.launches == [10], "reopened once, after the swap landed")
        #expect(Restart.describe(ending, staged: "2.0", disk: world.new).text
            == "quit — its own updater applied \(world.new.text(withBuild: true))")
    }

    /// A signal after the app has quit, while its updater swaps: ignored. The
    /// swap lands at tick 40 — past the slow-quit point, where a stop would
    /// first be honoured — and the reopen comes after it.
    ///
    /// Mutation: consult `stopWaiting` after the quit too → the wait ends at
    /// `quitGraceTicks`, the fallback reopens the app mid-swap, red.
    @Test func aSignalAfterTheQuitIsIgnoredByAStagedRestart() async {
        let world = StagedWorld(quitsAt: 2, landsAt: 40)
        let gate = SignalGate()
        let ending = await SignalGate.finishing {
            await StagedRelaunch.quitAndAwait(
                world.app, staged: world.staged, old: world.old, wasFrontmost: false,
                quitPatience: Restart.patience(
                    for: world.app, to: "2.0", waitsForAnswer: true, stopWaiting: { gate.stopRequested }),
                system: world.system(onTick: { if $0 == 5 { _ = gate.receive(SIGINT) } }))
        }
        #expect(gate.stopRequested)
        #expect(ending.outcome == .applied)
        #expect(world.launches == [40], "reopened once, after the swap landed")
        #expect(Restart.describe(ending, staged: "2.0", disk: world.new).text
            == "quit — its own updater applied \(world.new.text(withBuild: true))")
    }

    /// A ShipIt-staged app that quits at `quitsAt` and whose swap lands at
    /// `landsAt` (ticks counted from 1), without the updater reopening it.
    final class StagedWorld: @unchecked Sendable {
        let app = InstalledApp(
            name: "ZZFixture", bundleID: "com.zzfixture.signalgate", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-signalgate/ZZFixture.app"), isMASApp: false,
            sparkleFeedURL: nil)
        let staged = StagedSelfUpdate(
            version: "2.0", buildVersion: "2.0",
            stagedBundlePath: URL(fileURLWithPath: "/ZZFixture-signalgate/update.x/ZZFixture.app"),
            appliesOn: .quit, updater: .shipIt)
        let old = VersionSide(marketing: "1.0", build: "1")
        let new = VersionSide(marketing: "2.0", build: "2.0")
        private let lock = NSLock()
        private let quitsAt: Int, landsAt: Int
        private var now = 0
        private var terminated = false
        private var running = true
        private var landed = false
        private var launchTicks: [Int] = []

        init(quitsAt: Int, landsAt: Int) { self.quitsAt = quitsAt; self.landsAt = landsAt }

        var launches: [Int] { lock.withLock { launchTicks } }

        /// `onTick` is told each tick's number after the world has moved.
        func system(onTick: @escaping @Sendable (Int) -> Void) -> StagedRelaunch.System {
            StagedRelaunch.System(
                tick: {
                    let tick: Int = self.lock.withLock {
                        self.now += 1
                        if self.terminated && self.now >= self.quitsAt && !self.landed { self.running = false }
                        if !self.landed && !self.running && self.now >= self.landsAt { self.landed = true }
                        return self.now
                    }
                    onTick(tick)
                },
                isRunning: { self.lock.withLock { self.running } },
                terminate: { self.lock.withLock { self.terminated = true } },
                diskVersion: { self.lock.withLock { self.landed ? self.new : self.old } },
                awaitBundleProcessesGone: {},
                relaunch: { _ in
                    self.lock.withLock {
                        self.launchTicks.append(self.now)
                        self.running = true
                    }
                    return true
                },
                installer: ParkedInstallerProbe.System(
                    isAlive: { _ in false }, loadedJob: { _ in nil }, sparkleInstallerPIDs: { _ in [] }))
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() -> Int { lock.withLock { count += 1; return count } }
        var value: Int { lock.withLock { count } }
    }

    /// An update that waits for the test to cancel, then re-reads the version the
    /// way the real updaters do: a `.terminateChild` child process.
    struct VerifyingProvider: CLIToolProvider {
        let kind: CLIToolKind
        let inUpdate: Latch
        let cancelled: Latch

        func scan() async -> [CLIToolSighting] { [] }
        func check() async -> CLIToolReport { CLIToolReport(kind: kind, statuses: [], context: .fx(FxSettings())) }
        func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
            inUpdate.open()
            await cancelled.wait()
            guard let reread = try? await ChildProcess.run(
                "/bin/sh", ["-c", "echo 1.1.0"], standardOutput: .capture, standardError: .discard,
                onCancel: .terminateChild)
            else { return .failed(message: "the re-read was refused", output: "") }
            let version = String(decoding: reread.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .updated(version: version)
        }
        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    }

    // MARK: - Fixtures

    /// Ten lines 0.2 s apart (~2 s), then the marker, then exit 0.
    static func tenLines(marker: String) -> String {
        "i=1; while [ $i -le 10 ]; do echo \"line $i\"; i=$((i+1)); sleep 0.2; done; : > '\(marker)'; exit 0"
    }

    /// Drives `SignalGate.run` with every process-wide seam replaced.
    final class Harness: Sendable {
        let notices = Lines()
        let exits = Lines()
        let hangUps = Lines()
        let events = Lines()
        let started = Latch()
        private let handler = HandlerBox()

        func run(_ gate: SignalGate, _ command: @escaping @Sendable () async -> Int32) async -> Int32 {
            await gate.run(
                command,
                arm: { self.handler.set($0) },
                say: { self.notices.add($0); self.events.add("say") },
                hangUp: { self.hangUps.add("hangUp"); self.events.add("hangUp") },
                exitNow: { self.exits.add("\($0)") })
        }

        /// What a dispatch source does: call the armed handler with the signal.
        func deliver(_ signo: Int32) { handler.value?(signo) }
    }

    final class HandlerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (Int32) -> Void)?
        func set(_ handler: @escaping @Sendable (Int32) -> Void) { lock.withLock { self.handler = handler } }
        var value: (@Sendable (Int32) -> Void)? { lock.withLock { handler } }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        func set() { lock.withLock { raised = true } }
        var isSet: Bool { lock.withLock { raised } }
    }

    final class PidBox: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        func set(_ pid: pid_t) { lock.withLock { self.pid = pid } }
        var value: pid_t? { lock.withLock { pid } }
    }

    final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var outcome: ChildProcess.Outcome?
        func set(_ outcome: ChildProcess.Outcome) { lock.withLock { self.outcome = outcome } }
        var value: ChildProcess.Outcome? { lock.withLock { outcome } }
    }

    /// Opened once; every waiter, before or after, goes through.
    final class Latch: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() {
            let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
                guard !isOpen else { return [] }
                isOpen = true
                defer { waiters = [] }
                return waiters
            }
            for waiter in resumed { waiter.resume() }
        }
        func wait() async {
            await withCheckedContinuation { continuation in
                let now: Bool = lock.withLock {
                    if isOpen { return true }
                    waiters.append(continuation)
                    return false
                }
                if now { continuation.resume() }
            }
        }
    }

    final class Scratch {
        let url: URL
        deinit { try? FileManager.default.removeItem(at: url) }
        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SignalGate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

/// Returns once the current task is cancelled (at once if it already is).
private func sleepUntilCancelled() async {
    while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
    }
}
