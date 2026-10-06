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
        case .npm: detail = .npm(NpmPackage(path: path, version: version))
        case .boat: detail = .boat(BoatInstall(path: path, version: version))
        case .codex: detail = .codex(CodexInstall(path: path, version: version))
        case .bun: detail = .bun(BunInstall(path: path, version: version))
        case .opencode: detail = .opencode(OpencodeInstall(path: path, version: version))
        case .cursorAgent: detail = .cursorAgent(CursorAgentInstall(path: path, version: version))
        case .amp: detail = .amp(AmpInstall(path: path, version: version))
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
        private(set) var calls: [CLIToolID] = []
        private(set) var maxRunning = 0
        private var running = 0
        /// The progress callback of the latest call, kept past its return.
        private(set) var lastProgress: (@Sendable (String) -> Void)?

        func set(_ id: CLIToolID, _ outcome: CLIToolUpdateOutcome) { outcomes[id] = outcome }
        func setGate(_ gate: Gate?) { self.gate = gate }
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

        func scan() async -> [CLIToolSighting] { await scanner() }

        func check() async -> CLIToolReport {
            let (report, gate) = await checker.next()
            await gate?.wait()
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

    // MARK: updateAll

    /// One copy at a time, each of them.
    ///
    /// Mutation: run the loop's `update(_:)` calls in a `withTaskGroup`.
    @Test func updateAllRunsOneAtATime() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let check = FakeCheck([(Self.report(Self.status(Self.native), npm), nil)])
        let updater = FakeUpdater()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.id(Self.native), Self.id(Self.npm)])
        #expect(await updater.maxRunning == 1)
    }

    /// A second Update All while one runs starts nothing of its own.
    ///
    /// Mutation: drop `guard !updatingAll else { return }`.
    @Test func aSecondUpdateAllJoinsNothing() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let check = FakeCheck([(Self.report(Self.status(Self.native), npm), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let first = Task { await model.updateAll() }
        await until { await gate.arrived == 1 }
        #expect(model.updatingAll)
        let second = Task { await model.updateAll() }
        try? await Task.sleep(for: .milliseconds(30))
        await gate.open()
        await first.value
        await second.value

        #expect(await updater.maxRunning == 1)
        #expect(await updater.calls.count == 2)
        #expect(!model.updatingAll)
    }

    /// Each update ends in a re-check; an offer that re-check withdrew (auto-update
    /// switched off meanwhile) is not taken for the copies still to go.
    ///
    /// Mutation: in `update(_:)`, look the status up in `statuses` instead of
    /// `oneClickable`.
    @Test func updateAllHonoursAnOfferWithdrawnMidway() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let npmOff = Self.status(Self.npm, method: "npm", oneClick: false, withheld: .autoUpdateOff,
                                 nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let check = FakeCheck([
            (Self.report(Self.status(Self.native), npm), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: .upToDate, oneClick: false), npmOff), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.id(Self.native), .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.id(Self.native)])
    }

    // MARK: across tools

    /// Update All covers every tool's offers, still one at a time across them: a
    /// Claude Code copy and an fx copy behind two providers never run together.
    /// And in `CLIToolKind.allCases` order, whatever order the providers came in.
    ///
    /// Mutations: run the loop's `update(_:)` calls in a `withTaskGroup`; keep
    /// `providers` in the order passed to `init`.
    @Test func updateAllCrossesToolsOneAtATime() async {
        let updater = FakeUpdater()
        let claudeCode = FakeProvider(
            kind: .claudeCode, checker: FakeCheck([(Self.report(Self.status(Self.native)), nil)]), updater: updater)
        let fx = FakeProvider(
            kind: .fx,
            checker: FakeCheck([(Self.report(.fx, [Self.status(Self.fx, kind: .fx, version: "0.4.0", latest: "0.5.0")]), nil)]),
            updater: updater)
        let model = Self.model([fx, claudeCode])
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.id(Self.native), Self.id(Self.fx, .fx)])
        #expect(await updater.maxRunning == 1)
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
    /// Mutation: drop `guard let lastChecked else { return await refresh() }`
    /// (and read `lastChecked ?? now()` below it).
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
    /// Mutation: drop `stale ||` from the guard.
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
    /// Mutation: drop `moved ||` from the guard.
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

    /// (d) A report that left a copy unanswered (offline, say) is retried on the
    /// next open rather than kept for fifteen minutes.
    ///
    /// Mutation: drop the `unchecked.contains(where:)` clause from the guard.
    @Test func anUnansweredCopyRechecks() async {
        let status = Self.status(Self.native, state: .unknown, oneClick: false, withheld: .channelUnreadable)
        let found = ScanResult([status])
        let check = FakeCheck([(Self.report(status), nil)])
        let model = Self.model(check: check, scan: { found.sightings })
        await model.refresh()

        await model.refreshOnOpen()

        #expect(await check.calls == 2)
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
}
