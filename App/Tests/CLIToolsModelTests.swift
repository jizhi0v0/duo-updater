import Foundation
import Testing
import DuoUpdaterCore

/// `CLIToolsModel`'s state machine, driven by injected providers whose check,
/// scan, updater and release notes are scripted — so nothing here reaches the
/// network, reads the host's installs or runs an installer. The user's real
/// command-line tools must not change because a test ran.
///
/// Each case names the single-line mutation it must fail under.
@MainActor
struct CLIToolsModelTests {

    // MARK: fixtures

    static let native = "/Users/u/.local/bin/claude"
    static let npm = "/Users/u/.nvm/versions/node/v24.11.0/lib/node_modules/@anthropic-ai/claude-code"
    static let fx = "/Users/u/.fx/bin/fx"
    static let bub = "/Users/u/.local/bin/bub"

    static func id(_ path: String, _ kind: CLIToolKind = .claudeCode) -> CLIToolID {
        CLIToolID(kind: kind, path: path)
    }

    /// A status as a provider would return it. Claude Code's own detail is built
    /// through `Codable` because its memberwise initializer is internal to Core —
    /// the same shape `duo claude-code --json` prints, so no field here is one the
    /// check cannot produce. Only its install is read (the summary's labels); the
    /// verdict the model acts on is the shared fields'.
    static func status(
        _ path: String, kind: CLIToolKind = .claudeCode, method: String = "native",
        version: String? = "2.1.274", state: CLIToolState = .updateAvailable,
        latest: String? = "2.1.285", oneClick: Bool = true, withheld: CLIToolWithheld? = nil,
        nodePrefix: String? = nil
    ) -> CLIToolStatus {
        let detail: CLIToolStatus.Detail
        switch kind {
        case .claudeCode:
            var install: [String: Any] = [
                "path": path, "method": method, "origin": "conventional",
                "executable": path, "signature": "anthropic",
            ]
            if let version { install["version"] = version }
            if let nodePrefix { install["nodePrefix"] = nodePrefix }
            let json: [String: Any] = ["install": install, "channel": "latest", "state": state.rawValue]
            let data = try! JSONSerialization.data(withJSONObject: json)
            detail = .claudeCode(try! JSONDecoder().decode(ClaudeCodeStatus.self, from: data))
        case .bub: detail = .bub(BubInstall(path: path, method: .installer, executable: path + "/bin/bub", version: version))
        case .fx: detail = .fx(FxInstall(path: path, version: version))
        case .uv: detail = .uv(UvInstall(path: path, version: version))
        case .junie: detail = .junie(JunieInstall(path: path, version: version))
        case .rust: detail = .rust(RustItem(path: path, version: version))
        case .npm, .pnpm, .yarn: detail = .npm(NpmPackage(path: path, version: version))
        case .boat: detail = .boat(BoatInstall(path: path, version: version))
        case .codex: detail = .codex(CodexInstall(path: path, version: version))
        case .bun: detail = .bun(BunInstall(path: path, version: version))
        case .opencode: detail = .opencode(OpencodeInstall(path: path, version: version))
        case .cursorAgent: detail = .cursorAgent(CursorAgentInstall(path: path, version: version))
        case .amp: detail = .amp(AmpInstall(path: path, version: version))
        case .vitePlus: detail = .vitePlus(VitePlusInstall(path: path, layout: .split, version: version))
        case .herdr: detail = .herdr(HerdrInstall(path: path))
        case .luvus: detail = .luvus(LuvusInstall(path: path, version: version))
        case .lorca: detail = .lorca(LorcaInstall(path: path, version: version))
        case .zoxide: detail = .zoxide(ZoxideInstall(path: path, version: version))
        case .nvm: detail = .nvm(NvmInstall(path: path, version: version))
        case .atuin: detail = .atuin(AtuinInstall(path: path, version: version))
        case .ghcup: detail = .ghcup(GhcupInstall(path: path, version: version))
        case .flyctl: detail = .flyctl(FlyctlInstall(path: path, version: version))
        case .helm: detail = .helm(HelmInstall(path: path, version: version))
        case .starship: detail = .starship(StarshipInstall(path: path, version: version))
        case .deno: detail = .deno(DenoInstall(path: path, version: version))
        case .mise: detail = .mise(MiseInstall(path: path, version: version))
        case .obelus: detail = .obelus(ObelusInstall(path: path, version: version))
        }
        return CLIToolStatus(
            kind: kind, path: path, installedVersion: version, latestVersion: latest,
            channel: kind == .bub ? nil : "latest", state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["update"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil, detail: detail)
    }

    static func report(_ statuses: CLIToolStatus...) -> CLIToolReport {
        report(.claudeCode, statuses)
    }

    static func report(_ kind: CLIToolKind, _ statuses: [CLIToolStatus]) -> CLIToolReport {
        let context: CLIToolReport.Context
        switch kind {
        case .claudeCode: context = .claudeCode(ClaudeCodeSettings())
        case .bub: context = .bub
        case .fx: context = .fx(FxSettings())
        case .uv: context = .uv
        case .junie: context = .junie(JunieSettings())
        case .rust: context = .rust(RustupSettings())
        case .npm: context = .npm
        case .boat: context = .boat
        case .codex: context = .codex(CodexSettings())
        case .bun: context = .bun
        case .opencode: context = .opencode(OpencodeSettings())
        case .cursorAgent: context = .cursorAgent(CursorAgentSettings())
        case .amp: context = .amp(AmpSettings())
        case .vitePlus: context = .vitePlus
        case .herdr: context = .herdr
        case .luvus: context = .luvus
        case .lorca: context = .lorca
        case .zoxide: context = .zoxide
        case .nvm: context = .nvm
        case .atuin: context = .atuin
        case .ghcup: context = .ghcup
        case .flyctl: context = .flyctl
        case .helm: context = .helm
        case .starship: context = .starship
        case .deno: context = .deno
        case .mise: context = .mise
        case .obelus: context = .obelus
        case .pnpm: context = .pnpm
        case .yarn: context = .yarn
        }
        return CLIToolReport(kind: kind, statuses: statuses, context: context)
    }

    nonisolated static func sighting(_ status: CLIToolStatus) -> CLIToolSighting {
        CLIToolSighting(kind: status.kind, path: status.path, version: status.installedVersion)
    }

    /// Suspends callers until opened. Counts arrivals, so a test can wait for the
    /// code under test to reach it.
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var arrived = 0

        func wait() async {
            arrived += 1
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    /// Answers each check with the next scripted report (the last one repeats),
    /// optionally held at a gate first.
    actor FakeCheck {
        private var script: [(CLIToolReport, Gate?)]
        private(set) var calls = 0

        init(_ script: [(CLIToolReport, Gate?)]) { self.script = script }

        func next() -> (CLIToolReport, Gate?) {
            calls += 1
            return script.count > 1 ? script.removeFirst() : script[0]
        }
    }

    /// Records every update it is asked to run and how many ran at once. One can
    /// stand behind several providers, so "at once" spans tools.
    actor FakeUpdater {
        var outcomes: [CLIToolID: CLIToolUpdateOutcome] = [:]
        var linesBeforeReturn: [String] = []
        var gate: Gate?
        /// A gate for one copy only, so a lane's later copy can be held while
        /// its earlier one finishes.
        var gates: [CLIToolID: Gate] = [:]
        private(set) var calls: [CLIToolID] = []
        private(set) var maxRunning = 0
        private var running = 0
        /// The progress callback of the latest call, kept past its return.
        private(set) var lastProgress: (@Sendable (String) -> Void)?
        /// Run the "command" as the real runner does, inside `InstallCommit` —
        /// held at `commitGate` while it runs — and answer as it does when a
        /// cancel stops it first ("could not start").
        var commits = false
        var commitGate: Gate?
        func setCommits(gate: Gate?) { commits = true; commitGate = gate }
        /// The command exits by itself with a failure status (the runner's
        /// `landed` says no), then the update holds at `afterCommit` — and,
        /// with `retries`, tries the command once more, as uv's, bun's and
        /// mise's token retry does.
        var commitLands = true
        var afterCommit: Gate?
        var retries = false
        func setRefusedCommand(then gate: Gate, retries: Bool) {
            commits = true; commitLands = false; afterCommit = gate; self.retries = retries
        }

        func set(_ id: CLIToolID, _ outcome: CLIToolUpdateOutcome) { outcomes[id] = outcome }
        func setGate(_ gate: Gate?) { self.gate = gate }
        func setGate(_ id: CLIToolID, _ gate: Gate) { gates[id] = gate }
        func setLines(_ lines: [String]) { linesBeforeReturn = lines }

        func run(_ status: CLIToolStatus, _ progress: @escaping @Sendable (String) -> Void) async
            -> CLIToolUpdateOutcome
        {
            calls.append(status.toolID)
            running += 1
            maxRunning = max(maxRunning, running)
            lastProgress = progress
            for line in linesBeforeReturn { progress(line) }
            await gate?.wait()
            await gates[status.toolID]?.wait()
            if commits {
                let held = commitGate
                let lands = commitLands
                do {
                    try await InstallCommit.run("update command", landed: { _ in lands }) { await held?.wait() }
                    await afterCommit?.wait()
                    if retries {
                        try await InstallCommit.run("update command", landed: { _ in lands }) {}
                    }
                } catch {
                    running -= 1
                    return .failed(message: "could not start: \(error)", output: "")
                }
            }
            // Long enough that a second update started alongside this one would be
            // counted as running at the same time.
            try? await Task.sleep(for: .milliseconds(20))
            running -= 1
            return outcomes[status.toolID] ?? .updated(version: nil)
        }
    }

    /// Counts release-notes fetches and answers each with `changelog`.
    actor FakeNotes {
        let changelog: Changelog
        private(set) var fetches = 0
        init(_ changelog: Changelog) { self.changelog = changelog }
        func fetch() -> Changelog { fetches += 1; return changelog }
    }

    /// One tool, every answer scripted.
    struct FakeProvider: CLIToolProvider {
        let kind: CLIToolKind
        let checker: FakeCheck
        var updater = FakeUpdater()
        var scanner: @Sendable () async -> [CLIToolSighting] = { [] }
        var notes = FakeNotes(Changelog(entries: []))
        var readsGitHubAPI = false
        /// What the check answers when its task was cancelled while it waited —
        /// the real checks' shape: a cancelled request or a killed `--version`
        /// comes back as "couldn't reach" / "couldn't read".
        var whenCancelled: CLIToolReport?

        func scan() async -> [CLIToolSighting] { await scanner() }

        func check() async -> CLIToolReport {
            let (report, gate) = await checker.next()
            await gate?.wait()
            if Task.isCancelled, let whenCancelled { return whenCancelled }
            return report
        }

        func update(
            _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
        ) async -> CLIToolUpdateOutcome {
            await updater.run(status, progress)
        }

        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog { await notes.fetch() }
    }

    static func model(check: FakeCheck, updater: FakeUpdater = FakeUpdater(),
                      scan: (@Sendable () async -> [CLIToolSighting])? = nil, clock: Clock = Clock(),
                      confirmationWindow: Duration = .seconds(3600),
                      others: [FakeProvider] = []) -> CLIToolsModel {
        let claudeCode = FakeProvider(kind: .claudeCode, checker: check, updater: updater, scanner: scan ?? { [] })
        return model([claudeCode] + others, clock: clock, confirmationWindow: confirmationWindow)
    }

    static func model(_ providers: [FakeProvider], clock: Clock = Clock(),
                      confirmationWindow: Duration = .seconds(3600)) -> CLIToolsModel {
        // An hour: the tests that read `justUpdated` right after an update must not
        // race its clearing. `theConfirmationClearsItself` passes a short one.
        CLIToolsModel(providers: providers, now: { clock.now }, confirmationWindow: confirmationWindow)
    }

    /// A settable clock. Written only from the test's main actor, read by the
    /// model on the same actor.
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
    }

    /// What a local scan finds; the test changes it between opens.
    final class ScanResult: @unchecked Sendable {
        var sightings: [CLIToolSighting] = []
        init(_ statuses: [CLIToolStatus]) { self.sightings = statuses.map(CLIToolsModelTests.sighting) }
        func set(_ statuses: [CLIToolStatus]) { sightings = statuses.map(CLIToolsModelTests.sighting) }
    }

    /// Poll until `condition` holds. The deadline only turns a hang into a
    /// failure; no case asserts on how long anything took.
    func until(_ condition: () async -> Bool) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("condition never became true")
    }

    // MARK: oneClickable

    /// The offer excludes a copy DuoUpdater is already updating, and a second
    /// click on it runs nothing.
    ///
    /// Mutation: drop `&& !updating.contains($0.toolID)` from `oneClickable`.
    @Test func aCopyBeingUpdatedIsNotOfferedAgain() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        #expect(model.oneClickable.count == 1)

        let first = Task { await model.update(Self.id(Self.native)) }
        await until { await gate.arrived == 1 }
        #expect(model.oneClickable.isEmpty)
        // In a task of its own: were it let through, it would wait at the same
        // closed gate as the first.
        let second = Task { await model.update(Self.id(Self.native)) }
        try? await Task.sleep(for: .milliseconds(30))
        await gate.open()
        await first.value
        await second.value

        #expect(await updater.calls == [Self.id(Self.native)])
    }

    /// A copy the check withheld one-click from (auto-update off) is reported,
    /// never updated.
    ///
    /// Mutation: drop `$0.oneClick != nil &&` from `oneClickable`.
    @Test func aWithheldCopyIsNeverUpdated() async {
        let withheld = Self.status(Self.native, oneClick: false, withheld: .autoUpdateOff)
        let check = FakeCheck([(Self.report(withheld), nil)])
        let updater = FakeUpdater()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        #expect(model.outdated.count == 1)
        #expect(model.oneClickable.isEmpty)
        await model.update(Self.id(Self.native))
        await model.updateAll()
        #expect(await updater.calls.isEmpty)
    }

    /// An update a gate held back is not an offered one: "updates" counts what
    /// a click updates, and the held-back copy is counted apart.
    ///
    /// Mutations: drop the `oneClick` test from `offered` (2 offered) or from
    /// `heldBack` (2 held back).
    @Test func aHeldBackUpdateIsNotCountedAsOffered() async {
        let offered = Self.status(Self.native)
        let held = Self.status("/Users/ann/.npm-global/bin/claude", oneClick: false, withheld: .runtimeTooOld)
        let check = FakeCheck([(Self.report(offered, held), nil)])
        let model = Self.model(check: check)
        await model.refresh()

        #expect(model.outdated.count == 2)
        #expect(model.offered.map(\.path) == [Self.native])
        #expect(model.heldBack.map(\.path) == ["/Users/ann/.npm-global/bin/claude"])
    }

    // MARK: outcomes

    /// A failed update puts its one line on the row and its whole output in the
    /// log — not the other way round — and releases the row.
    ///
    /// Mutation: swap `message` and `output` in the `.failed` case.
    @Test func aFailedUpdateMapsToTheRowLineAndTheLog() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "line 1\nEACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(Self.id(Self.native))

        #expect(model.errors[Self.id(Self.native)] == "EACCES")
        #expect(model.errorLogs[Self.id(Self.native)] == "line 1\nEACCES")
        #expect(model.updating.isEmpty)
        #expect(model.progress[Self.id(Self.native)] == nil)
        #expect(model.justUpdated.isEmpty)
    }

    /// A retry clears the previous failure before it runs.
    ///
    /// Mutation: drop `errors[id] = nil` at the top of `update(_:)`.
    @Test func aRetryClearsThePreviousFailure() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "EACCES"))
        let gate = Gate()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))
        #expect(model.errors[Self.id(Self.native)] == "EACCES")

        await updater.setGate(gate)
        let retry = Task { await model.update(Self.id(Self.native)) }
        await until { await gate.arrived == 1 }
        #expect(model.errors[Self.id(Self.native)] == nil)
        await gate.open()
        await retry.value
    }

    /// Success records the version the copy now reads as, then re-checks.
    ///
    /// Mutation: drop `await refresh()` from the `.updated` case.
    @Test func anUpdateRecordsItsVersionAndRechecks() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(Self.id(Self.native))

        #expect(model.justUpdated[Self.id(Self.native)] == "2.1.285")
        #expect(model.outdated.isEmpty)
        #expect(await check.calls == 2)
    }

    /// "Updated to X" is a confirmation that goes away by itself, like an app
    /// row's "Updated ✓" — not a state that waits for the copy to change again.
    ///
    /// Mutation: drop the clearing in `confirmUpdate`.
    @Test func theConfirmationClearsItself() async throws {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater, confirmationWindow: .milliseconds(50))
        await model.refresh()

        await model.update(Self.id(Self.native))
        // Not asserted present here: with a 50 ms window, a loaded machine may
        // already have cleared it. `anUpdateRecordsItsVersionAndRechecks` pins that
        // it is set, with the hour-long window.

        // An upper bound on the wait only, never on how soon: a slow machine
        // takes longer to clear, it does not fail.
        for _ in 0..<200 where model.justUpdated[Self.id(Self.native)] != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.justUpdated[Self.id(Self.native)] == nil)
    }

    /// When the updater could not read the new version, the re-check's does.
    ///
    /// Mutation: `justUpdated[id] = version ?? ""`.
    @Test func anUpdateWithoutAVersionTakesTheRechecksVersion() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: nil))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(Self.id(Self.native))

        #expect(model.justUpdated[Self.id(Self.native)] == "2.1.285")
    }

    /// Exit 0 is not an update. `claude update` can exit 0 having stayed on the
    /// version it had (measured by the updater's author), and then reports that
    /// version: no "updated to", a line saying it is still there, and a re-check.
    ///
    /// Mutation: `if let after {` in place of `if let after, after != before {`.
    @Test func anUnchangedVersionIsNotAnUpdate() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.274"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(Self.id(Self.native))

        #expect(model.justUpdated[Self.id(Self.native)] == nil)
        #expect(model.errors[Self.id(Self.native)]?.contains("2.1.274") == true)
        #expect(await check.calls == 2)
    }

    /// The row stays "updating" through the re-check that follows a success: that
    /// check waits on the network, and releasing the row earlier shows the old
    /// "outdated" verdict with a live Update button for its whole length.
    ///
    /// Mutation: move `updating.remove(id)` from the `defer` to right after the
    /// provider's `update` returns.
    @Test func theRowStaysUpdatingThroughTheRecheck() async {
        let recheck = Gate()
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), recheck),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(Self.id(Self.native)) }
        await until { await recheck.arrived == 1 }
        #expect(model.updating.contains(Self.id(Self.native)))
        #expect(model.oneClickable.isEmpty)
        await recheck.open()
        await running.value
        #expect(model.updating.isEmpty)
    }

    /// Something else started updating the copy between the check and the click:
    /// nothing ran, and a re-check lets the row say so.
    ///
    /// Mutation: drop `await refresh()` from the `.busy, .notOffered` case.
    @Test func aBusyCopyIsRechecked() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, oneClick: false, withheld: .busy)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .busy("claude update (pid 4242) is running"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(Self.id(Self.native))

        #expect(await check.calls == 2)
        #expect(model.outdated.first?.withheld == .busy)
        #expect(model.errors.isEmpty)
        #expect(model.justUpdated.isEmpty)
    }

    // MARK: progress

    /// Output lines reach the row while the update runs…
    ///
    /// Mutation: drop `self.progress[id] = line` in the progress callback.
    @Test func progressLinesReachTheRow() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        await updater.setLines(["Downloading 2.1.285"])
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(Self.id(Self.native)) }
        await until { model.progress[Self.id(Self.native)] == "Downloading 2.1.285" }
        await gate.open()
        await running.value
        #expect(model.progress[Self.id(Self.native)] == nil)
    }

    /// …but one that arrives after the update finished is dropped, instead of
    /// pinning a stale line on a row that is no longer updating.
    ///
    /// Mutation: drop `self.updating.contains(id)` from the callback's guard.
    @Test func aLateProgressLineIsDropped() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "x", output: "x"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))

        let late = await updater.lastProgress
        late?("late line")
        // Let the main-actor hop the callback schedules run.
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))

        #expect(model.progress[Self.id(Self.native)] == nil)
    }

    // MARK: Cancel

    /// A path no other case updates. The jobs are `InstallJobs`', which is
    /// process-wide, and these cases run in parallel with the rest of the
    /// suite: another case's update of the same path would register over
    /// this one's job.
    static func ownPath() -> String { "/Users/u/.local/bin/claude-\(UUID().uuidString)" }

    /// Cancelled before its command started: the command never runs, and the
    /// row is not failed — no red line, no log, no re-check — and is released.
    /// Mutation: drop the `cancels[id] == .cancelling` return in `run` → the
    /// "could not start" failure lands on the row, red.
    @Test(.timeLimit(.minutes(1))) func aCopyCancelledBeforeItsCommandIsNotFailed() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let check = FakeCheck([(Self.report(Self.status(path)), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        await updater.setCommits(gate: nil)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        let checksBefore = await check.calls

        let running = Task { await model.update(id) }
        await until { await gate.arrived == 1 }
        #expect(model.cancels[id] == .available)
        model.cancel(id)
        #expect(model.cancels[id] == .cancelling)
        // Its row keeps its line, Cancel greyed, until "Cancelling…" is due
        // (`InstallRowSmoothing`), and says so once it is.
        #expect(model.progressLine(id) != "Cancelling…")
        #expect(model.cancelRows.cancelPending.contains(id))
        await until { model.progressLine(id) == "Cancelling…" }
        #expect(model.cancelRows.cancelPending.isEmpty)
        await gate.open()
        await running.value

        #expect(model.errors[id] == nil)
        #expect(model.errorLogs[id] == nil)
        #expect(model.justUpdated[id] == nil)
        #expect(model.updating.isEmpty)
        #expect(model.cancels.isEmpty)
        #expect(await check.calls == checksBefore)
    }

    /// Once the command started its Cancel greys out, a click does nothing,
    /// and the update finishes as any other.
    /// Mutation: drop the `phaseChanged` hop in `run` → the Cancel stays live,
    /// red.
    @Test(.timeLimit(.minutes(1))) func aCopyWhoseCommandStartedCannotBeCancelled() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let check = FakeCheck([(Self.report(Self.status(path)), nil)])
        let updater = FakeUpdater()
        await updater.set(id, .updated(version: "2.1.285"))
        let commitGate = Gate()
        await updater.setCommits(gate: commitGate)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(id) }
        await until { await commitGate.arrived == 1 }
        await until { model.cancels[id] == .committing }
        model.cancel(id)
        #expect(model.cancels[id] == .committing)
        await commitGate.open()
        await running.value

        #expect(model.justUpdated[id] == "2.1.285")
        #expect(model.errors[id] == nil)
    }

    /// The command ran and exited with a failure status — not landed, so the
    /// Cancel is live again — and the click lands before the update ends, with
    /// nothing left to start (npm's single run). The cancel stopped nothing:
    /// the command's failure is on the row, red line and log, not hidden as
    /// "cancelled before its command started".
    /// Mutation: `cancelStoppedSomething` always true → no red line, red.
    @Test(.timeLimit(.minutes(1))) func aCancelAfterTheCommandFailedLeavesItsFailure() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let check = FakeCheck([(Self.report(Self.status(path)), nil)])
        let updater = FakeUpdater()
        await updater.set(id, .failed(message: "npm ERR! code EACCES", output: "npm ERR! code EACCES"))
        let after = Gate()
        await updater.setRefusedCommand(then: after, retries: false)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(id) }
        await until { await after.arrived == 1 }
        await until { model.cancels[id] == .available }
        model.cancel(id)
        #expect(model.cancels[id] == .cancelling)
        await after.open()
        await running.value

        #expect(model.errors[id] == "npm ERR! code EACCES")
        #expect(model.errorLogs[id] == "npm ERR! code EACCES")
    }

    /// The same, but the click keeps the retry from starting (uv's, bun's,
    /// mise's second try after a rejected token): the cancel stopped the
    /// update, so no failure lands.
    /// Mutation: `cancelStoppedSomething` ignores `refusedACommit` → the
    /// retry's "could not start" lands, red.
    @Test(.timeLimit(.minutes(1))) func aCancelThatStopsTheRetryIsNotAFailure() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let check = FakeCheck([(Self.report(Self.status(path)), nil)])
        let updater = FakeUpdater()
        let after = Gate()
        await updater.setRefusedCommand(then: after, retries: true)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(id) }
        await until { await after.arrived == 1 }
        await until { model.cancels[id] == .available }
        model.cancel(id)
        await after.open()
        await running.value

        #expect(model.errors[id] == nil)
        #expect(model.errorLogs[id] == nil)
        #expect(model.cancels.isEmpty)
    }

    /// A copy waiting its turn under Update All is cancelled at once: its row
    /// is released, and its lane skips it.
    /// Mutation: drop the `cancelledWhileQueued` skip in `runLane` → it runs,
    /// red.
    @Test(.timeLimit(.minutes(1))) func aCopyCancelledWhileQueuedIsSkipped() async {
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([npm])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await gate.arrived == 1 }
        let second = Self.id(Self.tsx, .npm)
        #expect(model.cancels[second] == .available)
        model.cancel(second)
        #expect(!model.updating.contains(second))
        #expect(model.queued.isEmpty)
        #expect(model.cancels[second] == nil)
        await gate.open()
        await all.value

        #expect(await updater.calls == [Self.id(Self.pnpmCLI, .npm)])
        #expect(model.errors[second] == nil)
        #expect(model.updating.isEmpty)
    }

    // MARK: updateAll

    static let prefix = "/Users/u/.nvm/versions/node/v24.11.0"
    static let pnpmCLI = prefix + "/lib/node_modules/pnpm"
    static let tsx = prefix + "/lib/node_modules/tsx"

    /// Copies in different lanes run at the same time: a native Claude Code and an
    /// npm-installed one in a prefix are two lanes.
    ///
    /// Mutation: give every copy the same lane (`lane(of:)` returns `""`).
    @Test func updateAllRunsLanesAtOnce() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: Self.prefix)
        let check = FakeCheck([(Self.report(Self.status(Self.native), npm), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await gate.arrived == 2 }
        await gate.open()
        await all.value

        #expect(Set(await updater.calls) == [Self.id(Self.native), Self.id(Self.npm)])
        #expect(await updater.maxRunning == 2)
    }

    /// One npm prefix is one lane, whatever put the package there — npm has no
    /// lock for a global install, and its update refuses to start while another
    /// npm runs there. Its copies go one after another, in the list's order.
    ///
    /// Mutations: drop the `.npm` case from `lane(of:)`; drop the `.claudeCode`
    /// one.
    @Test func onePrefixIsOneLane() async {
        let updater = FakeUpdater()
        let claudeCode = FakeProvider(
            kind: .claudeCode,
            checker: FakeCheck([(Self.report(Self.status(Self.npm, method: "npm", nodePrefix: Self.prefix)), nil)]),
            updater: updater)
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([claudeCode, npm])
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.id(Self.npm), Self.id(Self.pnpmCLI, .npm), Self.id(Self.tsx, .npm)])
        #expect(await updater.maxRunning == 1)
    }

    /// The lanes, as `lane(of:)` draws them: a prefix whatever the finder's
    /// spelling of it, bub with uv, and every other tool apart.
    ///
    /// Mutations: drop the `.bub` mapping; drop `canonical` on either side.
    @Test func lanesFollowWhatTheUpdatesShare() {
        let lane = CLIToolsModel.lane(of:)
        let claudeNpm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/./v24.11.0")
        #expect(lane(claudeNpm) == lane(Self.status(Self.tsx, kind: .npm)))
        #expect(lane(Self.status(Self.native)) != lane(claudeNpm))
        #expect(lane(Self.status(Self.bub, kind: .bub)) == lane(Self.status("/Users/u/.local/bin/uv", kind: .uv)))
        #expect(lane(Self.status(Self.fx, kind: .fx)) != lane(Self.status("/Users/u/.local/bin/uv", kind: .uv)))
        let other = "/Users/u/.nvm/versions/node/v22.0.0/lib/node_modules/tsx"
        #expect(lane(Self.status(other, kind: .npm)) != lane(Self.status(Self.tsx, kind: .npm)))
    }

    /// A copy waiting for its lane is claimed from the start: "Queued", no live
    /// Update, and a click on it runs nothing — as `installAll` claims an app row.
    ///
    /// Mutation: drop the claiming loop at the top of `updateAll`.
    @Test func aCopyWaitingItsTurnIsQueued() async {
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([npm])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await gate.arrived == 1 }
        let second = Self.id(Self.tsx, .npm)
        #expect(model.queued == [second])
        #expect(model.updating.contains(second))
        #expect(model.oneClickable.isEmpty)
        await model.update(second)
        #expect(await updater.calls == [Self.id(Self.pnpmCLI, .npm)])
        await gate.open()
        await all.value

        #expect(await updater.calls == [Self.id(Self.pnpmCLI, .npm), second])
        #expect(model.queued.isEmpty)
        #expect(model.updating.isEmpty)
    }

    /// A second Update All while one runs starts nothing of its own — not even a
    /// copy a re-check partway through put on offer, which the first did not
    /// claim. Run, it would end by clearing `updatingAll` under the first.
    ///
    /// Mutation: drop `guard !updatingAll else { return }`.
    @Test func aSecondUpdateAllJoinsNothing() async {
        let claudeUpdater = FakeUpdater()
        await claudeUpdater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let claudeCheck = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            // The re-check after its lane finds a copy the first check had not.
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false),
                         Self.status(Self.npm, method: "npm", nodePrefix: Self.prefix)), nil),
        ])
        let fxUpdater = FakeUpdater()
        let fxGate = Gate()
        await fxUpdater.setGate(fxGate)
        let fxCheck = FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")]), nil)])
        let model = Self.model([
            FakeProvider(kind: .claudeCode, checker: claudeCheck, updater: claudeUpdater),
            FakeProvider(kind: .fx, checker: fxCheck, updater: fxUpdater),
        ])
        await model.refresh()

        let first = Task { await model.updateAll() }
        await until { model.oneClickable.map(\.toolID) == [Self.id(Self.npm)] }
        await model.updateAll()
        #expect(model.updatingAll)
        #expect(await claudeUpdater.calls == [Self.id(Self.native)])
        await fxGate.open()
        await first.value

        #expect(!model.updatingAll)
    }

    /// Each tool is re-checked once its own lanes are done — not after every copy,
    /// and not held for a slower tool's install. Until then its finished copy
    /// stays claimed: released, it would show the old verdict with a live Update.
    ///
    /// Mutation: re-check every tool only once every lane is done.
    @Test func eachToolIsRecheckedWhenItsLanesAreDone() async {
        let claudeUpdater = FakeUpdater()
        await claudeUpdater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let claudeCheck = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let fxUpdater = FakeUpdater()
        let fxGate = Gate()
        await fxUpdater.setGate(fxGate)
        let fxCheck = FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")]), nil)])
        let model = Self.model([
            FakeProvider(kind: .claudeCode, checker: claudeCheck, updater: claudeUpdater),
            FakeProvider(kind: .fx, checker: fxCheck, updater: fxUpdater),
        ])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { model.justUpdated[Self.id(Self.native)] == "2.1.285" }
        #expect(await claudeCheck.calls == 2)
        #expect(await fxCheck.calls == 1)
        #expect(!model.updating.contains(Self.id(Self.native)))
        #expect(model.updating.contains(Self.id(Self.fx, .fx)))
        await fxGate.open()
        await all.value

        #expect(await claudeCheck.calls == 2)
        #expect(await fxCheck.calls == 2)
        #expect(model.updating.isEmpty)
    }

    /// A row's line follows its stage as the app rows' does: "Queued" can be
    /// held up by the dwell when "Starting…" follows it fast, and the row moves
    /// on to the newest line once the dwell is up, with nothing else changing
    /// meanwhile — the gated copy below reports nothing more.
    ///
    /// Mutation: drop the wake in `smoothCancelRows` → the row stays on
    /// "Queued" whenever "Starting…" came within the dwell, and `until` never
    /// holds.
    @Test func aHeldLineMovesOnWhenItsDwellIsUp() async {
        let check = FakeCheck([
            (Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil),
            (Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil),
        ])
        let updater = FakeUpdater()
        let tsxGate = Gate()
        await updater.setGate(Self.id(Self.tsx, .npm), tsxGate)
        let model = Self.model([FakeProvider(kind: .npm, checker: check, updater: updater)])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await tsxGate.arrived == 1 }
        let tsx = Self.id(Self.tsx, .npm)
        #expect(model.progress[tsx] == String(localized: "Starting…"))
        await until { model.progressLine(tsx) == String(localized: "Starting…") }
        await tsxGate.open()
        await all.value
        #expect(model.progressLine(tsx) == nil)
    }

    /// A copy whose update has run waits for its tool's re-check — here the
    /// rest of its lane — still claimed, and says so: "Waiting to check", not
    /// "Checking…" while no check runs. "Checking…" once it does.
    ///
    /// Mutations: drop `awaitingCheck.insert(id)`; say "Checking…" in `run`.
    @Test func aCopyDoneBeforeItsLaneWaitsToBeChecked() async {
        let recheck = Gate()
        let check = FakeCheck([
            (Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil),
            (Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), recheck),
        ])
        let updater = FakeUpdater()
        let tsxGate = Gate()
        await updater.setGate(Self.id(Self.tsx, .npm), tsxGate)
        let model = Self.model([FakeProvider(kind: .npm, checker: check, updater: updater)])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await tsxGate.arrived == 1 }
        let first = Self.id(Self.pnpmCLI, .npm)
        #expect(model.awaitingCheck == [first])
        #expect(model.updating.contains(first))
        #expect(model.progress[first] == String(localized: "Waiting to check"))
        #expect(await check.calls == 1)
        await tsxGate.open()
        await until { await recheck.arrived == 1 }
        #expect(model.progress[first] == String(localized: "Checking…"))
        await recheck.open()
        await all.value

        #expect(model.awaitingCheck.isEmpty)
        #expect(model.updating.isEmpty)
    }

    /// Two lanes of one tool: one re-check, once both are done.
    ///
    /// Mutation: drop `run.lanesLeft[provider] == 0` from the readiness test.
    @Test func aToolWithTwoLanesIsRecheckedOnce() async {
        let gate = Gate()
        let updater = FakeUpdater()
        let other = "/Users/u/.nvm/versions/node/v22.0.0/lib/node_modules/tsx"
        let check = FakeCheck([(Self.report(.npm, [Self.status(Self.tsx, kind: .npm), Self.status(other, kind: .npm)]), nil)])
        let model = Self.model([FakeProvider(kind: .npm, checker: check, updater: updater)])
        await model.refresh()
        await updater.setGate(gate)

        let all = Task { await model.updateAll() }
        await until { await gate.arrived == 2 }
        await gate.open()
        await all.value

        #expect(await check.calls == 2)
        #expect(await updater.maxRunning == 2)
    }

    /// A tool whose every copy failed is not re-checked: the failure is on the
    /// row, as for a single update.
    ///
    /// Mutation: always add to `run.ran` in `runLane`.
    @Test func aFailedLaneIsNotRechecked() async {
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "EACCES"))
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.updateAll()

        #expect(await check.calls == 1)
        #expect(model.errors[Self.id(Self.native)] == "EACCES")
        #expect(model.updating.isEmpty)
    }

    // MARK: across tools

    /// One update re-checks its own tool only: the others keep their verdicts,
    /// and their checks — each a network round — are not run for nothing.
    ///
    /// Mutation: `check(Array(providers.indices))` in place of `check([provider])`
    /// in `update(_:)`.
    @Test func anUpdateRechecksOnlyItsOwnTool() async {
        let claudeCheck = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let fxCheck = FakeCheck([
            (Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")]), nil),
            (Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.5.0", state: .upToDate, latest: "0.5.0", oneClick: false)]), nil),
        ])
        let model = Self.model([
            FakeProvider(kind: .claudeCode, checker: claudeCheck),
            FakeProvider(kind: .fx, checker: fxCheck),
        ])
        await model.refresh()

        await model.update(Self.id(Self.fx, .fx))

        #expect(await claudeCheck.calls == 1)
        #expect(await fxCheck.calls == 2)
        #expect(model.statuses.map(\.toolID) == [Self.id(Self.native), Self.id(Self.fx, .fx)])
        #expect(model.oneClickable.map(\.toolID) == [Self.id(Self.native)])
        #expect(model.justUpdated[Self.id(Self.fx, .fx)] == "0.5.0")
    }

    /// A one-tool re-check leaves every other verdict as old as it was, so it
    /// does not restart the clock an open of the popover reads.
    ///
    /// Mutation: stamp `checkedAt` for every provider in `apply`, not only the
    /// ones asked.
    @Test func aOneToolRecheckDoesNotFreshenTheOthers() async {
        let clock = Clock()
        let claude = Self.status(Self.native)
        let fx = Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")
        let claudeCheck = FakeCheck([(Self.report(claude), nil)])
        let fxCheck = FakeCheck([(Self.report(.fx, [fx]), nil)])
        // Scans that agree with the checks, so only the report's age can re-check.
        let claudeScan = [Self.sighting(claude)]
        let fxScan = [Self.sighting(fx)]
        let model = Self.model([
            FakeProvider(kind: .claudeCode, checker: claudeCheck, scanner: { claudeScan }),
            FakeProvider(kind: .fx, checker: fxCheck, scanner: { fxScan }),
        ], clock: clock)
        await model.refresh()
        clock.now += CLIToolsModel.recheckInterval - 60
        await model.update(Self.id(Self.fx, .fx))
        clock.now += 120

        await model.refreshOnOpen()

        #expect(await claudeCheck.calls == 2)
    }

    /// An install is updated by its own tool's provider and never another's: the
    /// command each runs is the one its vendor documents for its own installs.
    ///
    /// Mutation: drop `$0.kind == status.kind` from the provider lookup in
    /// `update(_:)` (taking the first provider, Claude Code's).
    @Test func anInstallIsUpdatedOnlyByItsOwnTool() async {
        let claudeUpdater = FakeUpdater()
        let fxUpdater = FakeUpdater()
        let claudeCode = FakeProvider(
            kind: .claudeCode, checker: FakeCheck([(Self.report(Self.status(Self.native)), nil)]),
            updater: claudeUpdater)
        let fx = FakeProvider(
            kind: .fx,
            checker: FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")]), nil)]),
            updater: fxUpdater)
        let model = Self.model([claudeCode, fx])
        await model.refresh()

        await model.update(Self.id(Self.fx, .fx))

        #expect(await fxUpdater.calls == [Self.id(Self.fx, .fx)])
        #expect(await claudeUpdater.calls.isEmpty)
    }

    /// Two tools at one path are two installs: one's failure is not the other's,
    /// and updating one leaves the other on offer.
    ///
    /// Mutation: `toolID` returns `CLIToolID(kind: .claudeCode, path: path)`.
    @Test func twoToolsAtOnePathAreTwoInstalls() async {
        let shared = "/Users/u/bin/tool"
        let updater = FakeUpdater()
        await updater.set(Self.id(shared, .fx), .failed(message: "EACCES", output: "EACCES"))
        let claudeCode = FakeProvider(
            kind: .claudeCode, checker: FakeCheck([(Self.report(Self.status(shared)), nil)]), updater: updater)
        let fx = FakeProvider(
            kind: .fx, checker: FakeCheck([(Self.report(.fx, [Self.status(shared, kind: .fx)]), nil)]),
            updater: updater)
        let model = Self.model([claudeCode, fx])
        await model.refresh()

        await model.update(Self.id(shared, .fx))

        #expect(model.errors[Self.id(shared, .fx)] == "EACCES")
        #expect(model.errors[Self.id(shared)] == nil)
        #expect(model.oneClickable.map(\.toolID) == [Self.id(shared), Self.id(shared, .fx)])
    }

    /// Verdicts are applied together, when the last tool's check lands: while
    /// one tool is still being asked, the row has no verdict to sum up rather
    /// than a partial one that leaves that tool out of an "up to date".
    ///
    /// Mutation: in `refresh`, apply each provider's report as it lands.
    @Test func verdictsLandTogether() async {
        let slow = Gate()
        let claudeCode = FakeProvider(
            kind: .claudeCode,
            checker: FakeCheck([(Self.report(Self.status(Self.native, state: .upToDate, oneClick: false)), nil)]))
        let fx = FakeProvider(
            kind: .fx, checker: FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx)]), slow)]))
        let model = Self.model([claudeCode, fx])

        let refresh = Task { await model.refresh() }
        await until { await slow.arrived == 1 }
        // Let Claude Code's answer reach the model, were it to be applied alone.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!model.checked)
        #expect(model.statuses.isEmpty)
        await slow.open()
        await refresh.value

        #expect(model.statuses.map(\.toolID) == [Self.id(Self.native), Self.id(Self.fx, .fx)])
    }

    // MARK: refresh

    /// A check started before another must not land after it: the popover's check
    /// racing the re-check at the end of an update would put "outdated" back.
    ///
    /// Mutation: drop `guard generation == refreshGeneration else { return }`.
    @Test func anOlderCheckDoesNotLandLast() async {
        let slow = Gate()
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), slow),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let model = Self.model(check: check)

        let older = Task { await model.refresh() }
        await until { await slow.arrived == 1 }
        await model.refresh()
        await slow.open()
        await older.value

        #expect(model.outdated.isEmpty)
        #expect(model.statuses.first?.installedVersion == "2.1.285")
        #expect(!model.checking)
    }

    /// The launch scan only reserves the row; a check that already landed is
    /// newer and keeps its installs.
    ///
    /// Mutation: drop `guard !checked else { return }` from `scanInstalls`.
    @Test func aLateScanDoesNotOverwriteACheck() async {
        let scanGate = Gate()
        let stale = [Self.status(Self.native), Self.status(Self.npm)].map(Self.sighting)
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let model = Self.model(check: check, scan: { await scanGate.wait(); return stale })

        let scan = Task { await model.scanInstalls() }
        await until { await scanGate.arrived == 1 }
        await model.refresh()
        await scanGate.open()
        await scan.value

        #expect(model.sightings.map(\.path) == [Self.native])
    }

    /// Before any check, the scan alone is what reserves the row — every tool's.
    ///
    /// Mutation: drop `sightings = found` from `scanInstalls`.
    @Test func theScanReservesTheRowBeforeAnyCheck() async {
        let found = [Self.sighting(Self.status(Self.native))]
        let fxFound = [Self.sighting(Self.status(Self.fx, kind: .fx))]
        let fx = FakeProvider(
            kind: .fx, checker: FakeCheck([(Self.report(.fx, []), nil)]), scanner: { fxFound })
        let model = Self.model(check: FakeCheck([(Self.report(), nil)]), scan: { found }, others: [fx])

        await model.scanInstalls()

        #expect(model.sightings.map(\.toolID) == [Self.id(Self.native), Self.id(Self.fx, .fx)])
        #expect(!model.checked)
    }

    /// An error is about an update still on offer. Once the copy is current (say,
    /// updated from a terminal) it goes.
    ///
    /// Mutation: drop the loop in `apply` that clears `errors`.
    @Test func anErrorGoesOnceTheCopyIsCurrent() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "EACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))
        #expect(model.errors[Self.id(Self.native)] == "EACCES")

        await model.refresh()

        #expect(model.errors[Self.id(Self.native)] == nil)
        #expect(model.errorLogs[Self.id(Self.native)] == nil)
    }

    /// …and once no update is offered any more — still behind, but on a release
    /// that needs a newer runtime, say — since the failure was about an offer.
    ///
    /// Mutation: drop `|| byID[id]?.oneClick == nil` from that loop.
    @Test func anErrorGoesOnceNoUpdateIsOffered() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.280", oneClick: false, withheld: .runtimeTooOld)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "EACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))
        #expect(model.errors[Self.id(Self.native)] == "EACCES")

        await model.refresh()

        #expect(model.errors[Self.id(Self.native)] == nil)
    }

    /// …but stays while it is still behind.
    ///
    /// Mutation: clear `errors` unconditionally in `apply`.
    @Test func anErrorStaysWhileTheCopyIsBehind() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .failed(message: "EACCES", output: "EACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))

        await model.refresh()

        #expect(model.errors[Self.id(Self.native)] == "EACCES")
    }

    /// "Updated to X" is dropped once the copy reads as something else.
    ///
    /// Mutation: drop the `installedVersion != version` clause in `apply`.
    @Test func justUpdatedGoesWhenTheVersionMoves() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.290", state: .upToDate, oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(Self.id(Self.native))
        #expect(model.justUpdated[Self.id(Self.native)] == "2.1.285")

        await model.refresh()

        #expect(model.justUpdated[Self.id(Self.native)] == nil)
    }

    // MARK: opening the popover

    /// (a) With no completed check, an open checks — even when the scan finds
    /// nothing to disagree with.
    ///
    /// Mutation: drop `guard !checkedAt.isEmpty else { return await refresh() }`.
    @Test func theFirstOpenChecks() async {
        let check = FakeCheck([(Self.report(), nil)])
        let model = Self.model(check: check, scan: { [] })

        await model.refreshOnOpen()

        #expect(await check.calls == 1)
        #expect(model.checked)
    }

    /// (b) A report younger than the interval is kept; one that old is re-checked.
    /// The first half is the promise itself: an open with nothing changed costs
    /// no network.
    ///
    /// Mutation: `stale` filtering nothing out (every age counted as stale).
    @Test func anOpenRechecksOnlyAStaleReport() async {
        let status = Self.status(Self.native)
        let found = ScanResult([status])
        let clock = Clock()
        let check = FakeCheck([(Self.report(status), nil)])
        let model = Self.model(check: check, scan: { found.sightings }, clock: clock)
        await model.refresh()

        clock.now += CLIToolsModel.recheckInterval - 60
        await model.refreshOnOpen()
        #expect(await check.calls == 1)

        clock.now += 60
        await model.refreshOnOpen()
        #expect(await check.calls == 2)
    }

    /// (c) The scan disagreeing with the report — a version moved (a `claude
    /// update` in a terminal), a copy appeared, or a copy of another tool did —
    /// re-checks at once, and re-checks every tool.
    ///
    /// Mutation: drop `moved ||` from the `refresh()` condition.
    @Test func aScanThatDisagreesRechecks() async {
        let status = Self.status(Self.native)
        let found = ScanResult([status])
        let fxFound = ScanResult([])
        let check = FakeCheck([(Self.report(status), nil)])
        let fxCheck = FakeCheck([(Self.report(.fx, []), nil)])
        let fx = FakeProvider(kind: .fx, checker: fxCheck, scanner: { fxFound.sightings })
        let model = Self.model(check: check, scan: { found.sightings }, others: [fx])
        await model.refresh()

        found.set([Self.status(Self.native, version: "2.1.285")])
        await model.refreshOnOpen()
        #expect(await check.calls == 2)

        found.set([status, Self.status(Self.npm, method: "npm")])
        await model.refreshOnOpen()
        #expect(await check.calls == 3)

        fxFound.set([Self.status(Self.fx, kind: .fx)])
        await model.refreshOnOpen()
        #expect(await check.calls == 4)
        #expect(await fxCheck.calls == 4)
    }

    /// (d) A report that left a copy unanswered (offline, say) is retried on an
    /// open rather than kept for fifteen minutes — but not on every open: only
    /// once `unansweredRecheckInterval` has passed since it was asked. Opened
    /// again and again while rate-limited, the popover re-asked every tool each
    /// time, spending the very budget it was waiting on.
    ///
    /// Mutations: drop the unanswered clause from `onOpen`; drop the
    /// `age >= unansweredRecheckInterval` condition.
    @Test func anUnansweredCopyRechecks() async {
        // GitHub's rate limit too: it ends with the hour, nothing on disk moves.
        // Mutation: drop `.rateLimited` from `mayClearByItself`.
        for withheld in [CLIToolWithheld.channelUnreadable, .rateLimited] {
            let status = Self.status(Self.native, state: .unknown, oneClick: false, withheld: withheld)
            let found = ScanResult([status])
            let clock = Clock()
            let check = FakeCheck([(Self.report(status), nil)])
            let model = Self.model(check: check, scan: { found.sightings }, clock: clock)
            await model.refresh()

            clock.now += CLIToolsModel.unansweredRecheckInterval - 1
            for _ in 0..<3 { await model.refreshOnOpen() }
            #expect(await check.calls == 1, "\(withheld)")

            clock.now += 1
            await model.refreshOnOpen()
            #expect(await check.calls == 2, "\(withheld)")
        }
    }

    /// (e) …but a copy whose reason only a change on disk can clear — not the
    /// vendor's signature, a dev-channel fx — is not re-checked on every open: the
    /// scan already catches the file changing. Found in review: each open re-ran
    /// every tool's network check for a dev-channel fx user.
    ///
    /// Mutation: `mayClearByItself` returning true for every reason.
    @Test func aCopyOnlyADiskChangeCanClearIsNotRecheckedOnOpen() async {
        for withheld in [CLIToolWithheld.wrongSigner, .channelUnsigned, .broken, .unsupportedInstaller,
                         .unverified, .staged, .runtimeTooOld] {
            let status = Self.status(Self.native, state: .unknown, oneClick: false, withheld: withheld)
            let found = ScanResult([status])
            let check = FakeCheck([(Self.report(status), nil)])
            let model = Self.model(check: check, scan: { found.sightings })
            await model.refresh()

            await model.refreshOnOpen()

            #expect(await check.calls == 1, "\(withheld)")
        }
    }

    /// (f) …and a copy repaired in place at the same version — a broken venv
    /// reinstalled — is re-checked: the scan's `state` differs from what the last
    /// check's scan saw. Found by the PR review on #942: comparing kind, path and
    /// version alone kept "An install is broken" for up to fifteen minutes.
    ///
    /// Mutation: comparing sightings without `state` (or against the statuses
    /// instead of the check's own sightings).
    @Test func aCopyRepairedInPlaceAtTheSameVersionRechecks() async {
        let broken = Self.status(Self.native, state: .unknown, oneClick: false, withheld: .broken)
        let sighting = CLIToolSighting(kind: .claudeCode, path: Self.native, version: "2.1.274", state: "problem")
        let report = CLIToolReport(
            kind: .claudeCode, statuses: [broken], context: .claudeCode(ClaudeCodeSettings()), sightings: [sighting])
        let check = FakeCheck([(report, nil)])
        let found = ScanResult([])
        found.sightings = [sighting]
        let model = Self.model(check: check, scan: { found.sightings })
        await model.refresh()

        await model.refreshOnOpen()
        #expect(await check.calls == 1)

        found.sightings = [CLIToolSighting(kind: .claudeCode, path: Self.native, version: "2.1.274", state: "fine")]
        await model.refreshOnOpen()
        #expect(await check.calls == 2)
    }

    /// (g) Closing the popover mid-check — SwiftUI cancels its `.task` — does not
    /// put the cancelled requests' failures on screen: the check runs to the end
    /// and its real answers land. Seen on the real machine (2026-10-14): opening
    /// and closing the popover a few times with the workbench up turned every
    /// tool into "Couldn't reach … release channel" / "Couldn't read the
    /// installed version" until the workbench was focused again.
    ///
    /// Mutation: run the providers in the caller's task in `check` (no `Task {}`).
    @Test func closingThePopoverMidCheckDoesNotLandItsCancellation() async {
        let answered = Self.status(Self.native)
        let unreachable = Self.status(Self.native, state: .unknown, oneClick: false, withheld: .channelUnreadable)
        let gate = Gate()
        let check = FakeCheck([(Self.report(answered), gate)])
        var provider = FakeProvider(kind: .claudeCode, checker: check)
        provider.whenCancelled = Self.report(unreachable)
        let model = Self.model([provider])

        let open = Task { await model.refreshOnOpen() }
        await until { await gate.arrived == 1 }
        open.cancel()
        await gate.open()
        await open.value
        await until { model.checked }

        #expect(model.statuses.map(\.withheld) == [nil])
        #expect(model.statuses.map(\.state) == [.updateAvailable])
    }

    /// (h) An open while another open's check is out waits for it rather than
    /// starting another: with a closed popover no longer cancelling its check,
    /// opening it five times while the first is out would otherwise ask every
    /// tool's channel five times over.
    ///
    /// Mutation: a trigger joining the lane's running pass starting one of its
    /// own (no `running` check in `RefreshLane.handle`).
    @Test func anOpenWhileACheckIsOutAsksNothingMore() async {
        let gate = Gate()
        let check = FakeCheck([(Self.report(Self.status(Self.native)), gate)])
        let model = Self.model(check: check)

        let first = Task { await model.refreshOnOpen() }
        await until { await gate.arrived == 1 }
        // Each in a task of its own: one let through waits at the same closed
        // gate, and awaiting it here would never return.
        let more = (0..<5).map { _ in Task { await model.refreshOnOpen() } }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await check.calls == 1)
        await gate.open()
        await first.value
        for open in more { await open.value }
    }

    /// (i) …but only another open's check holds an open back. An update's
    /// re-check asks its one tool; an open during it still re-checks the other
    /// tools whose report is old. Found in review (#1290): a guard on any check
    /// being out dropped the open, and nothing re-asked the stale tools.
    ///
    /// Mutation: `guard !checking else { return .skip(…) }` at the top of `onOpen`.
    @Test func anUpdatesRecheckDoesNotHoldAnOpenBack() async {
        let recheck = Gate()
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false)), recheck),
        ])
        let fxCheck = FakeCheck([(Self.report(.fx, []), nil)])
        let fx = FakeProvider(kind: .fx, checker: fxCheck)
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let clock = Clock()
        let model = Self.model(check: check, updater: updater, clock: clock, others: [fx])
        await model.refresh()

        clock.now += CLIToolsModel.recheckInterval
        let update = Task { await model.update(Self.id(Self.native)) }
        await until { await recheck.arrived == 1 }
        let open = Task { await model.refreshOnOpen() }
        await until { await fxCheck.calls == 2 }
        #expect(await fxCheck.calls == 2)
        await recheck.open()
        await update.value
        await open.value
    }

    /// While the GitHub budget a tool's own updater would spend is closed, its
    /// one-click is held back — not offered, not counted, not run by a click —
    /// and back the moment the pause is lifted.
    ///
    /// Mutation: `publishStatuses` passing the checks' verdicts through as they are.
    @Test func aClosedGitHubBudgetHoldsBackItsUpdatersOneClick() async {
        let zoxide = Self.status("/Users/u/.local/bin/zoxide", kind: .zoxide)
        let check = FakeCheck([(Self.report(.zoxide, [zoxide]), nil)])
        let updater = FakeUpdater()
        let model = Self.model([FakeProvider(kind: .zoxide, checker: check, updater: updater)])
        await model.refresh()
        #expect(model.oneClickable.count == 1)

        model.gitHubPause = [.anonymous: Date().addingTimeInterval(600)]
        #expect(model.oneClickable.isEmpty)
        #expect(model.statuses.first?.withheld == .rateLimited)
        await model.update(zoxide.toolID)
        #expect(await updater.calls.isEmpty)

        model.gitHubPause = [:]
        #expect(model.oneClickable.count == 1)
    }

    /// (j) The refresh button checks every tool, past the age and unanswered
    /// throttles an open applies: the user asked for a fresh answer.
    ///
    /// Mutation: `.manual` decided as `onOpen()`.
    @Test func theRefreshButtonChecksEveryToolAtOnce() async {
        let status = Self.status(Self.native)
        let found = ScanResult([status])
        let fxCheck = FakeCheck([(Self.report(.fx, []), nil)])
        let fx = FakeProvider(kind: .fx, checker: fxCheck)
        let check = FakeCheck([(Self.report(status), nil)])
        let model = Self.model(check: check, scan: { found.sightings }, others: [fx])
        await model.refresh()

        await model.refreshOnOpen()
        #expect(await check.calls == 1)

        await model.lane.handle(.manual)
        #expect(await check.calls == 2)
        #expect(await fxCheck.calls == 2)
    }

    // MARK: the workbench becoming key again

    /// A tool installed in a terminal while the workbench is open — Helm into
    /// `/usr/local/bin`, seen on the real machine — is found when the window is
    /// focused again, and checked. Focusing again with nothing new asks nothing.
    ///
    /// Mutations: `refreshOnFocus` returning before its scan; dropping the
    /// `Set(found) != Set(checkedSightings)` guard.
    @Test func aFocusFindsAToolInstalledMeanwhile() async {
        let status = Self.status(Self.native)
        let found = ScanResult([status])
        let helmFound = ScanResult([])
        let check = FakeCheck([(Self.report(status), nil)])
        let helm = Self.status("/usr/local/bin/helm", kind: .helm)
        let helmCheck = FakeCheck([(Self.report(.helm, []), nil), (Self.report(.helm, [helm]), nil)])
        let model = Self.model(check: check, scan: { found.sightings },
                               others: [FakeProvider(kind: .helm, checker: helmCheck, scanner: { helmFound.sightings })])
        await model.refreshOnOpen()
        #expect(await helmCheck.calls == 1)

        await model.refreshOnFocus()
        await model.refreshOnFocus()
        #expect(await helmCheck.calls == 1)

        helmFound.set([helm])
        await model.refreshOnFocus()
        #expect(await helmCheck.calls == 2)
        #expect(await check.calls == 2)
        #expect(model.status(helm.toolID) != nil)

        await model.refreshOnFocus()
        #expect(await helmCheck.calls == 2)
    }

    /// Focus is not an open: an old report, or a copy left unanswered (GitHub's
    /// rate limit), is not re-checked on each trip back to the window — that is
    /// the popover's open and the background check's to do.
    ///
    /// Mutation: `refreshOnFocus` calling `refreshOnOpen()` after its guard.
    @Test func aFocusIgnoresAgeAndUnansweredCopies() async {
        let status = Self.status(Self.native, state: .unknown, oneClick: false, withheld: .rateLimited)
        let found = ScanResult([status])
        let clock = Clock()
        let check = FakeCheck([(Self.report(status), nil)])
        let model = Self.model(check: check, scan: { found.sightings }, clock: clock)
        await model.refresh()

        clock.now += CLIToolsModel.recheckInterval * 2
        for _ in 0..<5 { await model.refreshOnFocus() }
        #expect(await check.calls == 1)
    }

    /// Before the first report lands, and while a check is out, a focus asks
    /// nothing: the window's open is already checking, and the report in
    /// flight is about to replace the one a scan would be held against.
    ///
    /// Mutations: drop `!checkedAt.isEmpty`; drop `!checking`.
    @Test func aFocusWaitsForTheCheckUnderWay() async {
        let status = Self.status(Self.native)
        let found = ScanResult([status])
        let gate = Gate()
        // The third answer is not held, so a check the focus wrongly starts
        // returns and is counted, rather than waiting on the gate below.
        let check = FakeCheck([(Self.report(status), nil), (Self.report(status), gate), (Self.report(status), nil)])
        let model = Self.model(check: check, scan: { found.sightings })
        let moved = [Self.status(Self.native, version: "2.1.285")]

        // No report yet: the scan disagrees with nothing, and still no check.
        let fresh = FakeCheck([(Self.report(status), nil)])
        let unopened = Self.model(check: fresh, scan: { found.sightings })
        await unopened.refreshOnFocus()
        #expect(await fresh.calls == 0)

        await model.refresh()
        let second = Task { await model.refresh() }
        await until { await gate.arrived == 1 }
        found.set(moved)
        await model.refreshOnFocus()
        #expect(await check.calls == 2)
        await gate.open()
        await second.value
    }

    // MARK: the background schedule

    /// Answers whether a GitHub token resolves, and counts how often it was asked.
    final class TokenProbe: @unchecked Sendable {
        var hasToken = false
        var asked = 0
        func ask() -> Bool { asked += 1; return hasToken }
    }

    /// Claude Code (no GitHub API) and Bun (its check reads the GitHub API), with
    /// scans that agree with their checks, so an open re-checks for age alone.
    static func scheduled(clock: Clock) -> (CLIToolsModel, claude: FakeCheck, bun: FakeCheck) {
        let claude = Self.status(Self.native)
        let bun = Self.status("/Users/u/.bun/bin/bun", kind: .bun, version: "1.3.0", latest: "1.3.1")
        let claudeCheck = FakeCheck([(Self.report(claude), nil)])
        let bunCheck = FakeCheck([(Self.report(.bun, [bun]), nil)])
        let claudeScan = [Self.sighting(claude)]
        let bunScan = [Self.sighting(bun)]
        let model = Self.model([
            FakeProvider(kind: .claudeCode, checker: claudeCheck, scanner: { claudeScan }),
            FakeProvider(kind: .bun, checker: bunCheck, scanner: { bunScan }, readsGitHubAPI: true),
        ], clock: clock)
        return (model, claudeCheck, bunCheck)
    }

    /// The rule itself: every tool is due on every tick, except one that reads
    /// the GitHub API with no token, which waits out `gitHubFloor` from the start
    /// of its last check.
    ///
    /// Mutations: drop `!hasGitHubToken,` from `isDue`'s guard; return true in
    /// place of the age comparison; drop `readsGitHubAPI,` from the guard.
    @Test func onlyAGitHubReadingToolWithoutATokenWaitsOutTheFloor() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let floor = CLIToolsModel.gitHubFloor
        let recent = now.addingTimeInterval(-(floor - 1))
        let old = now.addingTimeInterval(-floor)
        #expect(CLIToolsModel.isDue(readsGitHubAPI: false, checkedAt: recent, now: now, hasGitHubToken: false))
        #expect(CLIToolsModel.isDue(readsGitHubAPI: true, checkedAt: recent, now: now, hasGitHubToken: true))
        #expect(CLIToolsModel.isDue(readsGitHubAPI: true, checkedAt: nil, now: now, hasGitHubToken: false))
        #expect(!CLIToolsModel.isDue(readsGitHubAPI: true, checkedAt: recent, now: now, hasGitHubToken: false))
        #expect(CLIToolsModel.isDue(readsGitHubAPI: true, checkedAt: old, now: now, hasGitHubToken: false))
    }

    /// At the 5-minute schedule with no token, Claude Code is checked on every
    /// tick and Bun only once 15 minutes have passed; with a token, Bun on every
    /// tick too. The token is asked about only when Bun would otherwise be held
    /// back — never on the first tick, when nothing has been checked yet.
    ///
    /// Mutation: in `backgroundCheck`, check every provider whatever `isDue` says.
    @Test func theBackgroundCheckHoldsBackOnlyTheGitHubReadingTool() async {
        let clock = Clock()
        let (model, claude, bun) = Self.scheduled(clock: clock)
        let token = TokenProbe()
        let tick = { await model.backgroundCheck(interval: 5 * 60) { token.ask() } }

        await tick()
        #expect(await claude.calls == 1)
        #expect(await bun.calls == 1)
        #expect(token.asked == 0)

        clock.now += 5 * 60
        await tick()
        #expect(await claude.calls == 2)
        #expect(await bun.calls == 1)
        #expect(token.asked == 1)

        clock.now += 5 * 60
        token.hasToken = true
        await tick()
        #expect(await claude.calls == 3)
        #expect(await bun.calls == 2)

        clock.now += 5 * 60
        token.hasToken = false
        await tick()
        #expect(await bun.calls == 2)

        clock.now += CLIToolsModel.gitHubFloor - 5 * 60
        await tick()
        #expect(await claude.calls == 5)
        #expect(await bun.calls == 3)
    }

    /// "Only when I check": a tick already under way when the user chose it
    /// checks nothing.
    ///
    /// Mutation: drop `guard interval != nil else { return }`.
    @Test func noBackgroundCheckUnderManual() async {
        let (model, claude, bun) = Self.scheduled(clock: Clock())

        await model.backgroundCheck(interval: nil) { true }

        #expect(await claude.calls == 0)
        #expect(await bun.calls == 0)
        #expect(!model.checked)
    }

    /// An open right after a background check asks nothing again, and an open
    /// once only the held-back tool's report is old re-checks that tool alone.
    ///
    /// Mutations: `refreshOnOpen` calling `refresh()` when any report is stale
    /// (in place of `check(stale)`); `backgroundCheck` not stamping `checkedAt`
    /// (`apply` skipping it).
    @Test func anOpenAfterABackgroundCheckAsksOnlyWhatIsOld() async {
        let clock = Clock()
        let (model, claude, bun) = Self.scheduled(clock: clock)
        let tick = { await model.backgroundCheck(interval: 5 * 60) { false } }
        await tick()

        clock.now += 60
        await model.refreshOnOpen()
        #expect(await claude.calls == 1)
        #expect(await bun.calls == 1)

        // Ticks at +5 and +10 minutes check Claude Code and hold Bun back.
        clock.now += 4 * 60
        await tick()
        clock.now += 5 * 60
        await tick()
        #expect(await claude.calls == 3)
        #expect(await bun.calls == 1)

        // Bun's report is now 15 minutes old, Claude Code's 5.
        clock.now += 5 * 60
        await model.refreshOnOpen()
        #expect(await claude.calls == 3)
        #expect(await bun.calls == 2)
    }

    /// Every check that lands tells the app, whichever path asked — the schedule
    /// or an open of the popover — so a new version is announced either way.
    ///
    /// Mutation: drop `onReport?()` from `apply`.
    @Test func everyLandedCheckIsReported() async {
        let clock = Clock()
        let (model, _, _) = Self.scheduled(clock: clock)
        final class Count: @unchecked Sendable { var value = 0 }
        let reports = Count()
        model.onReport = { reports.value += 1 }

        await model.backgroundCheck(interval: 5 * 60) { false }
        #expect(reports.value == 1)

        clock.now += CLIToolsModel.recheckInterval
        await model.refreshOnOpen()
        #expect(reports.value == 2)
    }

    // MARK: release notes

    /// A tool's release notes are fetched once per session — unless the kept copy
    /// lacks the version the channel now points at, and then they are fetched again.
    ///
    /// Mutation: drop the `status.latestVersion.map { … } ?? true` clause from `releaseNotes`.
    @Test func releaseNotesAreKeptUntilTheChannelMovesPastThem() async throws {
        let notes = FakeNotes(Changelog(entries: [
            .init(version: "2.1.285", date: nil, items: ["a"]),
            .init(version: "2.1.274", date: nil, items: ["b"]),
        ]))
        let claudeCode = FakeProvider(kind: .claudeCode, checker: FakeCheck([(Self.report(), nil)]), notes: notes)
        let model = Self.model([claudeCode])

        _ = try await model.releaseNotes(for: Self.status("/c", latest: "2.1.285"), force: false)
        _ = try await model.releaseNotes(for: Self.status("/c", latest: "2.1.285"), force: false)
        #expect(await notes.fetches == 1)

        _ = try await model.releaseNotes(for: Self.status("/c", latest: "2.1.290"), force: false)
        #expect(await notes.fetches == 2)
    }

    /// Each tool keeps its own: Claude Code's notes never answer for fx's.
    ///
    /// Mutation: read the cache as `releaseNotesCache.values.first`.
    @Test func eachToolKeepsItsOwnReleaseNotes() async throws {
        let claudeNotes = FakeNotes(Changelog(entries: [.init(version: "2.1.285", date: nil, items: ["a"])]))
        let fxNotes = FakeNotes(Changelog(entries: [.init(version: "0.5.0", date: nil, items: ["b"])]))
        let claudeCode = FakeProvider(
            kind: .claudeCode, checker: FakeCheck([(Self.report(), nil)]), notes: claudeNotes)
        let fx = FakeProvider(kind: .fx, checker: FakeCheck([(Self.report(.fx, []), nil)]), notes: fxNotes)
        let model = Self.model([claudeCode, fx])

        _ = try await model.releaseNotes(for: Self.status("/c", latest: nil), force: false)
        let fxChangelog = try await model.releaseNotes(for: Self.status("/f", kind: .fx, latest: nil), force: false)

        #expect(fxChangelog.entries.map(\.version) == ["0.5.0"])
        #expect(await fxNotes.fetches == 1)
    }

    // MARK: breaking changes

    /// An update whose notes mark a version in its range carries the hint once
    /// its check lands. A check that finds the same range reads nothing again —
    /// these notes lack the latest's section, so `releaseNotes` alone would
    /// fetch them every time — and one that finds the copy current drops it.
    ///
    /// Mutation: drop the `breakingRead[status.toolID] != range(status)` filter in
    /// `loadBreaking`; drop the `breakingRead[id] != ranges[id]` clearing loop.
    @Test func anUpdateCarriesTheVersionsItsNotesMarkBreaking() async throws {
        let notes = FakeNotes(Changelog(entries: [
            .init(version: "2.1.280", date: nil, items: ["Breaking change: the flag is gone"]),
            .init(version: "2.1.274", date: nil, items: ["Breaking change: the install's own"]),
        ]))
        let outdated = Self.report(Self.status("/c"))
        let current = Self.report(Self.status("/c", version: "2.1.285", state: .upToDate))
        let check = FakeCheck([(outdated, nil), (outdated, nil), (current, nil)])
        let model = Self.model([FakeProvider(kind: .claudeCode, checker: check, notes: notes)])
        let id = CLIToolID(kind: .claudeCode, path: "/c")

        await model.refresh()
        await until { model.breaking[id] != nil }
        #expect(model.breaking[id] == ["2.1.280"])

        await model.refresh()
        await model.loadBreaking()
        #expect(await notes.fetches == 1)
        #expect(model.breaking[id] == ["2.1.280"])

        await model.refresh()
        await model.loadBreaking()
        #expect(model.breaking[id] == nil)
    }

    /// Notes that mark nothing in the range give no hint. The pass the check
    /// started and this one overlap, and still read the notes once.
    ///
    /// Mutation: in `loadBreaking`, run `readBreaking` without awaiting `previous`.
    @Test func noMarkInRangeGivesNoHint() async throws {
        let notes = FakeNotes(Changelog(entries: [
            .init(version: "2.1.285", date: nil, items: ["Fixed tabs breaking the title"]),
            .init(version: "2.1.274", date: nil, items: ["Breaking change: the install's own"]),
        ]))
        let check = FakeCheck([(Self.report(Self.status("/c")), nil)])
        let model = Self.model([FakeProvider(kind: .claudeCode, checker: check, notes: notes)])

        await model.refresh()
        await model.loadBreaking()
        #expect(await notes.fetches == 1)
        #expect(model.breaking.isEmpty)
    }

    // MARK: wording

    /// The summary names each copy by its installer, and an nvm prefix by its
    /// node major version.
    ///
    /// Mutation: return "npm" for every npm install in `label`.
    @Test func theSummaryNamesEachInstaller() {
        let native = Self.status(Self.native)
        let nvm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let brew = Self.status("/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code", method: "npm",
                               nodePrefix: "/opt/homebrew")

        #expect(CLIToolsModel.summary([native, nvm, brew])
            == "Claude Code ×3 — native, npm (node v24), npm (Homebrew)")
        #expect(CLIToolsModel.summary([native]) == "Claude Code — native")
    }

    /// Every tool once, in `CLIToolKind.allCases` order whatever order the copies
    /// come in, with its count; the scan's line has counts alone.
    ///
    /// Mutation: return only the first tool's part from `summary`.
    @Test func theSummaryListsEveryTool() {
        let fx = Self.status(Self.fx, kind: .fx)
        let bub = Self.status(Self.bub, kind: .bub)
        let nvm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")

        #expect(CLIToolsModel.summary([fx, Self.status(Self.native), bub, nvm])
            == "Claude Code ×2 — native, npm (node v24) · bub · fx")
        #expect(CLIToolsModel.summary([fx, Self.status(Self.native), nvm].map(Self.sighting))
            == "Claude Code ×2 · fx")
    }

    /// "Not signed by" names the tool's own vendor.
    ///
    /// Mutation: return "Anthropic" for every kind from `vendor(of:)`.
    @Test func aWrongSignerNamesTheToolsVendor() {
        #expect(CLIToolsModel.reason(.wrongSigner, of: .claudeCode) == "Not signed by Anthropic")
        #expect(CLIToolsModel.reason(.wrongSigner, of: .fx) == "Not signed by Vercel")
        #expect(CLIToolsModel.reason(.wrongSigner, of: .uv) == "Not signed by Astral")
        #expect(CLIToolsModel.reason(.wrongSigner, of: .junie) == "Not signed by JetBrains")
        // An npm row's signature is its prefix's node's.
        #expect(CLIToolsModel.reason(.wrongSigner, of: F.npm(withheld: .wrongSigner))
            == "Its node isn’t signed by the Node.js Foundation")
    }

    private typealias F = CLIToolFixtures

    /// `.unverified` says which file is not the vendor's: uv's own, rustup's —
    /// or, on a toolchain row, the rustup that would update it — and an npm
    /// prefix's node; a rustup whose hash did match is held back by its
    /// quarantine flag alone, and says so.
    ///
    /// Mutations: drop the `.rustup where item.version != nil` arm (a quarantined
    /// rustup reads as not rust-lang's); drop the `.toolchain` arm (a toolchain
    /// reads as if it were rustup); drop the npm `nodeQuarantined` case.
    @Test func unverifiedNamesTheFileThatIsNotTheVendors() {
        #expect(CLIToolsModel.reason(.unverified, of: F.uv(hashVerdict: .differs))
            == "Not the build Astral published")
        #expect(CLIToolsModel.reason(.unverified, of: F.rustup(version: nil, trusted: false, state: .unknown))
            == "Not a published rustup build")
        #expect(CLIToolsModel.reason(.unverified, of: F.rustup(trusted: false, state: .unknown))
            == "Quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.toolchain())
            == "Its rustup isn’t verified")
        #expect(CLIToolsModel.reason(.unverified, of: F.npm(F.npmInstall(nodeQuarantined: true)))
            == "Its node is quarantined, so not run")
        #expect(CLIToolsModel.reason(.unverified, of: F.npm(F.npmInstall(nodeSignature: .adHoc)))
            == "Its node is neither Node.js’s nor Homebrew’s")
        // A quarantined uv is never run, so its version is unreadable: why.
        #expect(CLIToolsModel.reason(.versionUnreadable, of: F.uv(quarantined: true))
            == "Quarantined, so not run")
    }

    /// A newer npm release this prefix's node cannot run names the package, the
    /// release and the Node it needs — the lowest one when the range says it,
    /// else the range, else npm's.
    ///
    /// Mutation: drop the `minimumNode` line from `requirement(_:of:)` (the
    /// raw range `>=24.16.0 <25 || >=26.1.0` instead of "≥ 24.16.0").
    @Test func runtimeTooOldSaysWhichNodeTheReleaseNeeds() {
        #expect(CLIToolsModel.reason(.runtimeTooOld, of: F.npm(offered: nil))
            == "openclaw 2026.9.7 needs Node ≥ 24.16.0")
        let range = NpmPackage.RuntimeGap(version: "3.0.0", node: ">=26 <27", npm: nil, nodeVersion: "24.13.0",
                                          minimumNode: nil)
        #expect(CLIToolsModel.reason(.runtimeTooOld, of: F.npm(offered: nil, gap: range))
            == "openclaw 3.0.0 needs Node >=26 <27")
        let npm = NpmPackage.RuntimeGap(version: "3.0.0", node: nil, npm: ">=11", nodeVersion: "24.13.0",
                                        minimumNode: nil)
        #expect(CLIToolsModel.reason(.runtimeTooOld, of: F.npm(offered: nil, gap: npm))
            == "openclaw 3.0.0 needs npm >=11")
        #expect(CLIToolsModel.reason(.runtimeTooOld, of: .npm) == "Needs a newer Node")
    }

    /// Junie's staged update names the build it downloaded.
    ///
    /// Mutation: drop the `(.staged, .junie)` case (the build goes unnamed).
    @Test func stagedNamesTheBuildJunieDownloaded() {
        #expect(CLIToolsModel.reason(.staged, of: F.junie(pending: "3612.1"))
            == "Junie installs the downloaded 3612.1 at its next launch")
        #expect(CLIToolsModel.reason(.staged, of: .junie)
            == "Junie installs its downloaded update at its next launch")
    }

    /// The gates every tool shares, said of the right thing: rustup for the Rust
    /// rows, the package or its prefix for npm's, uv's and Junie's own installers.
    ///
    /// Mutations: drop the `(.updaterMissing, .rust)` case (a toolchain blames
    /// "the program that updates it"); drop the `(.autoUpdateOff, .npm)` case
    /// ("npm’s settings" for openclaw's own switch); drop the `.link` check from
    /// `origin(of:)` (a working copy reads as a non-registry release).
    @Test func eachGateNamesWhatItIsAbout() {
        #expect(CLIToolsModel.reason(.updaterMissing, of: F.toolchain())
            == "No rustup in ~/.cargo/bin")
        #expect(CLIToolsModel.reason(.updaterMissing, of: .bub) == "bub updates with uv, and uv wasn’t found")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.rustup()) == "Auto-update is off in rustup’s settings")
        #expect(CLIToolsModel.reason(.autoUpdateOff, of: F.npm()) == "Auto-update is off in openclaw’s settings")
        #expect(CLIToolsModel.reason(.busy, of: F.toolchain()) == "rustup is already running")
        #expect(CLIToolsModel.reason(.busy, of: F.npm()) == "npm is busy in this prefix")
        #expect(CLIToolsModel.reason(.busy, of: F.uv()) == "uv is already being updated")

        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.uv(layout: .link))
            == "A uv tool or pipx link")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.uv(layout: .unreceipted))
            == "Not the copy uv’s installer recorded")
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.junie(channel: "experimental"))
            == "The experimental channel has no installer")

        func npm(_ install: NpmInstall) -> String {
            CLIToolsModel.reason(.unsupportedInstaller, of: F.npm(install))
        }
        #expect(npm(F.npmInstall(linkTarget: "/Users/ann/src/openclaw"))
            == "Linked to a local folder")
        #expect(npm(F.npmInstall("claw", manifestName: "openclaw")) == "Installed as an alias of openclaw")
        #expect(npm(F.npmInstall(ownUpdate: .openclaw(OpenClawSettings(channel: "dev", autoUpdate: nil,
                                                                       supportsTag: true))))
            == "openclaw is on its dev channel")
        #expect(npm(F.npmInstall()) == "Not a release from the npm registry")
    }

    /// A custom registry is only in Core's decoded form (its initializer is
    /// internal), so the install is built from JSON — the shape it encodes to.
    ///
    /// Mutation: drop the `customRegistry` check from `origin(of:)`.
    @Test func aCustomRegistryIsSaid() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(F.npmInstall())) as! [String: Any]
        json["customRegistry"] = ["url": "https://npm.example.com/", "file": "/Users/ann/.npmrc"]
        let install = try JSONDecoder().decode(NpmInstall.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(CLIToolsModel.reason(.unsupportedInstaller, of: F.npm(install))
            == "From a registry other than npm’s")
    }

    /// The popover's line with many npm and Rust rows: each tool once, counted.
    @Test func theSummaryCountsManyRowsOfOneTool() {
        let npm = ["a", "b", "c", "d", "e"].map { F.npm(F.npmInstall($0)) }
        let rust = [F.rustup(), F.toolchain()]
        #expect(CLIToolsModel.summary(npm + rust + [F.uv()]) == "uv · Rust ×2 · npm ×5")
    }

    /// `.staged`, `.unverified` and `.runtimeTooOld` clear only through a disk
    /// change the scan's sighting records (or, for a too-old runtime, a new
    /// release the report's age covers).
    ///
    /// Mutation: add any of the three to `mayClearByItself`'s `true` case.
    @Test func theNewReasonsDoNotClearByThemselves() {
        for withheld in [CLIToolWithheld.staged, .unverified, .runtimeTooOld] {
            #expect(!CLIToolsModel.mayClearByItself(F.rustup(state: .unknown, withheld: withheld)), "\(withheld)")
        }
    }

    // MARK: administrator updates

    static let rootHelm = "/usr/local/bin/helm"

    /// A status whose one-click runs as root behind the administrator panel.
    static func asAdministrator(_ status: CLIToolStatus) -> CLIToolStatus {
        CLIToolStatus(
            kind: status.kind, path: status.path, installedVersion: status.installedVersion,
            latestVersion: status.latestVersion, channel: status.channel, state: status.state,
            oneClick: status.oneClick, withheld: status.withheld, note: status.note,
            manualCommand: status.oneClick, detail: status.detail, needsAdministrator: true)
    }

    /// Update All never raises the administrator panel: a copy whose update needs
    /// it is left to its own row's click, which does run it.
    ///
    /// Mutation: build `updateAll`'s batch from `oneClickable` again.
    @Test func updateAllLeavesAnAdministratorCopyToItsOwnClick() async {
        let updater = FakeUpdater()
        let helm = FakeProvider(
            kind: .helm,
            checker: FakeCheck([(Self.report(.helm, [Self.asAdministrator(Self.status(Self.rootHelm, kind: .helm))]), nil)]),
            updater: updater)
        let fx = FakeProvider(
            kind: .fx, checker: FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx)]), nil)]), updater: updater)
        let model = Self.model([helm, fx])
        await model.refresh()
        #expect(model.offered.count == 2)
        #expect(model.batchOffered.map(\.toolID) == [Self.id(Self.fx, .fx)])
        #expect(model.batchable.map(\.toolID) == [Self.id(Self.fx, .fx)])

        await model.updateAll()
        #expect(await updater.calls == [Self.id(Self.fx, .fx)])

        await model.update(Self.id(Self.rootHelm, .helm))
        #expect(await updater.calls == [Self.id(Self.fx, .fx), Self.id(Self.rootHelm, .helm)])
    }

    /// Dismissing the panel is a decision: no red line on the row, nothing
    /// claimed as updated, and no re-check — nothing ran.
    ///
    /// Mutations: re-check after `.declined` (`needsRecheck`); word it as a failure.
    @Test func aDismissedPanelIsNotAFailure() async {
        let updater = FakeUpdater()
        let id = Self.id(Self.rootHelm, .helm)
        await updater.set(id, .declined)
        let check = FakeCheck([(Self.report(.helm, [Self.asAdministrator(Self.status(Self.rootHelm, kind: .helm))]), nil)])
        let model = Self.model([FakeProvider(kind: .helm, checker: check, updater: updater)])
        await model.refresh()

        await model.update(id)
        #expect(await updater.calls == [id])
        #expect(model.errors[id] == nil)
        #expect(model.errorLogs[id] == nil)
        #expect(model.justUpdated[id] == nil)
        #expect(await check.calls == 1)
        #expect(!model.updating.contains(id))
        #expect(model.oneClickable.map(\.toolID) == [id])
    }

    // MARK: The CLI tab's queue (`CLIRunQueue`)

    /// Hold the queue with another click's run — a Homebrew one, say — until
    /// the gate opens.
    func holdQueue(_ model: CLIToolsModel, _ gate: Gate) async -> Task<Bool, Never> {
        let held = Task { @MainActor in
            await model.runQueue.perform(.upgradeAll) { await gate.wait() }
        }
        await until { await gate.arrived == 1 }
        return held
    }

    /// A row's Update clicked behind another run is taken: claimed at once,
    /// "Queued" with its Cancel live, and run when that one ends (#1312 used
    /// to disable the button instead).
    ///
    /// Mutation: run the update before `runQueue.perform` → it runs while the
    /// queue is held, red.
    @Test(.timeLimit(.minutes(1))) func anUpdateBehindAnotherRunWaitsItsTurn() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let updater = FakeUpdater()
        await updater.set(id, .updated(version: "2.1.285"))
        let model = Self.model(check: FakeCheck([(Self.report(Self.status(path)), nil)]), updater: updater)
        await model.refresh()
        let gate = Gate()
        let held = await holdQueue(model, gate)

        let click = Task { await model.update(id) }
        await until { model.runQueue.isWaiting(.tool(id)) }
        #expect(model.updating.contains(id))
        #expect(model.queued.contains(id))
        #expect(model.progress[id] == "Queued")
        #expect(model.cancels[id] == .available)
        #expect(await updater.calls.isEmpty)

        await gate.open()
        await held.value
        await click.value
        #expect(await updater.calls == [id])
        #expect(model.updating.isEmpty)
        #expect(model.queued.isEmpty)
    }

    /// Its Cancel while it waits takes it out of the queue: released at once,
    /// never run, no red line.
    ///
    /// Mutation: drop the `runQueue.cancel` branch in `cancel` → the click
    /// stays queued and runs, red.
    @Test(.timeLimit(.minutes(1))) func anUpdateCancelledWhileItWaitsNeverRuns() async {
        let path = Self.ownPath()
        let id = Self.id(path)
        let updater = FakeUpdater()
        let model = Self.model(check: FakeCheck([(Self.report(Self.status(path)), nil)]), updater: updater)
        await model.refresh()
        let gate = Gate()
        let held = await holdQueue(model, gate)

        let click = Task { await model.update(id) }
        await until { model.runQueue.isWaiting(.tool(id)) }
        model.cancel(id)
        // Released inside the Cancel, not when the click's task resumes: no
        // frame in between draws a row neither queued nor released.
        #expect(!model.updating.contains(id))
        #expect(!model.queued.contains(id))
        #expect(model.cancels[id] == nil)
        #expect(model.runQueue.waiting.isEmpty)
        await click.value

        await gate.open()
        await held.value
        #expect(await updater.calls.isEmpty)
        #expect(model.errors[id] == nil)
    }

    /// Update All behind another run claims its copies at once, and taking it
    /// back while it waits releases every one of them, none run.
    ///
    /// Mutation: drop the release loop after a `perform` that did not run →
    /// the copies stay claimed, red.
    @Test(.timeLimit(.minutes(1))) func updateAllCancelledWhileItWaitsReleasesItsCopies() async {
        let updater = FakeUpdater()
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([npm])
        await model.refresh()
        let gate = Gate()
        let held = await holdQueue(model, gate)

        let all = Task { await model.updateAll() }
        await until { model.updateAllWaiting }
        #expect(model.queued == [Self.id(Self.pnpmCLI, .npm), Self.id(Self.tsx, .npm)])
        #expect(model.updateAllCancel == .available)
        model.cancelUpdateAll()
        // Inside the Cancel, as a row's.
        #expect(!model.updatingAll)
        #expect(model.updating.isEmpty)
        #expect(model.queued.isEmpty)
        #expect(model.cancels.isEmpty)
        #expect(model.updateAllCancel == nil)
        await all.value

        await gate.open()
        await held.value
        #expect(await updater.calls.isEmpty)
    }

    /// Update All's own Cancel while it runs cancels every copy that still can
    /// be: the one running what comes before its command, and the one waiting
    /// in its lane. Neither fails, and the batch ends.
    ///
    /// Mutation: `cancelUpdateAll` returns once the queue had nothing waiting →
    /// both copies run, red.
    @Test(.timeLimit(.minutes(1))) func updateAllsCancelWhileItRunsCancelsWhatItStillCan() async {
        let prefix = "/Users/u/.nvm/versions/node/v24.11.0-\(UUID().uuidString)"
        let first = prefix + "/lib/node_modules/pnpm"
        let second = prefix + "/lib/node_modules/tsx"
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        await updater.setCommits(gate: nil)
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(first, kind: .npm), Self.status(second, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([npm])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await gate.arrived == 1 }
        #expect(model.updateAllCancel == .available)
        model.cancelUpdateAll()
        // The queued one at once; the running one is cancelling.
        #expect(!model.updating.contains(Self.id(second, .npm)))
        #expect(model.cancels[Self.id(first, .npm)] == .cancelling)
        await gate.open()
        await all.value

        #expect(await updater.calls == [Self.id(first, .npm)])
        #expect(model.errors.isEmpty)
        #expect(model.updating.isEmpty)
        #expect(!model.updatingAll)
    }

    /// A copy cancelled out of a waiting Update All and clicked again waits as
    /// a click of its own: taking Update All back then leaves it claimed,
    /// "Queued" with its Cancel, and it runs at its turn (review, #1498).
    ///
    /// Mutation: release every click-time copy that is still queued (the old
    /// loop) → the copy loses its claim while its click waits, red.
    @Test(.timeLimit(.minutes(1))) func aCopyClickedAgainSurvivesItsUpdateAllsCancel() async {
        let prefix = "/Users/u/.nvm/versions/node/v24.11.0-\(UUID().uuidString)"
        let a = Self.id(prefix + "/lib/node_modules/pnpm", .npm)
        let c = Self.id(prefix + "/lib/node_modules/tsx", .npm)
        let updater = FakeUpdater()
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(a.path, kind: .npm), Self.status(c.path, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model([npm])
        await model.refresh()
        let gate = Gate()
        let held = await holdQueue(model, gate)

        let all = Task { await model.updateAll() }
        await until { model.updateAllWaiting }
        model.cancel(c)
        let click = Task { await model.update(c) }
        await until { model.runQueue.isWaiting(.tool(c)) }
        // Not Update All's any more: its live Cancel would not reach it.
        model.cancelUpdateAll()
        await all.value
        #expect(!model.updating.contains(a))
        #expect(model.updating.contains(c))
        #expect(model.queued.contains(c))
        #expect(model.cancels[c] == .available)
        #expect(model.runQueue.waiting == [.tool(c)])

        await gate.open()
        await held.value
        await click.value
        #expect(await updater.calls == [c])
        #expect(model.updating.isEmpty)
    }

    /// A copy whose update failed inside a running Update All, and was clicked
    /// again, waits as a click of its own: Update All's Cancel neither reaches
    /// it nor counts it — greyed while the copy left in the batch is past its
    /// command (review, #1498, round 2).
    ///
    /// Mutation: drop `batchIDs.remove` from `release` → the Cancel reads live
    /// and takes the retry out of the queue, red.
    @Test(.timeLimit(.minutes(1))) func aRetryClickedDuringUpdateAllIsNotItsToCancel() async {
        let prefix = "/Users/u/.nvm/versions/node/v24.11.0-\(UUID().uuidString)"
        let x = Self.id(prefix + "/lib/node_modules/pnpm", .npm)
        let yPath = Self.ownPath()
        let y = Self.id(yPath)
        let xUpdater = FakeUpdater()
        await xUpdater.set(x, .failed(message: "npm ERR! x", output: "npm ERR! x"))
        let yUpdater = FakeUpdater()
        let commitGate = Gate()
        await yUpdater.setCommits(gate: commitGate)
        let npm = FakeProvider(
            kind: .npm, checker: FakeCheck([(Self.report(.npm, [Self.status(x.path, kind: .npm)]), nil)]),
            updater: xUpdater)
        let model = Self.model(check: FakeCheck([(Self.report(Self.status(yPath)), nil)]), updater: yUpdater, others: [npm])
        await model.refresh()

        let all = Task { await model.updateAll() }
        await until { await commitGate.arrived == 1 }
        await until { model.cancels[y] == .committing && !model.updating.contains(x) }
        #expect(model.errors[x] == "npm ERR! x")
        let retry = Task { await model.update(x) }
        await until { model.runQueue.isWaiting(.tool(x)) }
        #expect(model.updateAllCancel == .committing)
        model.cancelUpdateAll()
        #expect(model.runQueue.isWaiting(.tool(x)))
        #expect(model.cancels[x] == .available)

        await commitGate.open()
        await all.value
        await retry.value
        #expect(await xUpdater.calls == [x, x])
    }

    /// Cancelling every copy of a waiting Update All one by one takes Update
    /// All itself out of the queue: it would have nothing to run. A row's own
    /// click waiting beside it is not one of its copies, and stays.
    ///
    /// Mutations: drop the `cancelUpdateAll()` call in `cancel` → Update All
    /// stays waiting, red; test `queued.isEmpty` instead → the waiting click
    /// keeps it, red.
    @Test(.timeLimit(.minutes(1))) func cancellingEveryCopyOfAWaitingUpdateAllEndsIt() async {
        let path = Self.ownPath()
        let single = Self.id(path)
        let updater = FakeUpdater()
        let npm = FakeProvider(
            kind: .npm,
            checker: FakeCheck([(Self.report(.npm, [Self.status(Self.pnpmCLI, kind: .npm), Self.status(Self.tsx, kind: .npm)]), nil)]),
            updater: updater)
        let model = Self.model(check: FakeCheck([(Self.report(Self.status(path)), nil)]), updater: updater, others: [npm])
        await model.refresh()
        let gate = Gate()
        let held = await holdQueue(model, gate)

        let click = Task { await model.update(single) }
        await until { model.runQueue.isWaiting(.tool(single)) }
        let all = Task { await model.updateAll() }
        await until { model.updateAllWaiting }
        model.cancel(Self.id(Self.pnpmCLI, .npm))
        #expect(model.updateAllWaiting)
        model.cancel(Self.id(Self.tsx, .npm))
        #expect(!model.updateAllWaiting)
        await all.value
        #expect(!model.updatingAll)
        #expect(model.runQueue.waiting == [.tool(single)])

        await gate.open()
        await held.value
        await click.value
        #expect(await updater.calls == [single])
    }
}
