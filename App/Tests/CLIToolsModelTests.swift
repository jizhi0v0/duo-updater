import Foundation
import Testing
import DuoUpdaterCore

/// `CLIToolsModel`'s state machine, driven by an injected check, scan and
/// updater — so nothing here reaches the network, reads the host's installs or
/// runs an installer. The user's real Claude Code copies must not change because
/// a test ran.
///
/// Each case names the single-line mutation it must fail under.
@MainActor
struct CLIToolsModelTests {

    // MARK: fixtures

    static let native = "/Users/u/.local/bin/claude"
    static let npm = "/Users/u/.nvm/versions/node/v24.11.0/lib/node_modules/@anthropic-ai/claude-code"

    /// A status as the check would return it. Built through `Codable` because the
    /// memberwise initializer is internal to Core — the same shape `duo
    /// claude-code --json` prints, so no field here is one the check cannot produce.
    static func status(
        _ path: String, method: String = "native", version: String = "2.1.274",
        state: String = "updateAvailable", latest: String = "2.1.285",
        oneClick: Bool = true, withheld: String? = nil, nodePrefix: String? = nil
    ) -> ClaudeCodeStatus {
        var install: [String: Any] = [
            "path": path, "method": method, "origin": "conventional",
            "executable": path, "version": version, "signature": "anthropic",
        ]
        if let nodePrefix { install["nodePrefix"] = nodePrefix }
        var json: [String: Any] = [
            "install": install, "channel": "latest", "latestVersion": latest, "state": state,
        ]
        if oneClick {
            json["oneClick"] = ["executable": path, "arguments": ["update"]]
        }
        if let withheld { json["withheld"] = withheld }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(ClaudeCodeStatus.self, from: data)
    }

    static func report(_ statuses: ClaudeCodeStatus...) -> ClaudeCodeReport {
        ClaudeCodeReport(settings: ClaudeCodeSettings(), statuses: statuses)
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
        private var script: [(ClaudeCodeReport, Gate?)]
        private(set) var calls = 0

        init(_ script: [(ClaudeCodeReport, Gate?)]) { self.script = script }

        func next() -> (ClaudeCodeReport, Gate?) {
            calls += 1
            return script.count > 1 ? script.removeFirst() : script[0]
        }

        nonisolated var closure: CLIToolsModel.Check {
            { let (report, gate) = await self.next(); await gate?.wait(); return report }
        }
    }

    /// Records every update it is asked to run and how many ran at once.
    actor FakeUpdater {
        var outcomes: [String: ClaudeCodeUpdater.Outcome] = [:]
        var linesBeforeReturn: [String] = []
        var gate: Gate?
        private(set) var calls: [String] = []
        private(set) var maxRunning = 0
        private var running = 0
        /// The progress callback of the latest call, kept past its return.
        private(set) var lastProgress: (@Sendable (String) -> Void)?

        func set(_ path: String, _ outcome: ClaudeCodeUpdater.Outcome) { outcomes[path] = outcome }
        func setGate(_ gate: Gate?) { self.gate = gate }
        func setLines(_ lines: [String]) { linesBeforeReturn = lines }

        func run(_ status: ClaudeCodeStatus, _ progress: @escaping @Sendable (String) -> Void) async
            -> ClaudeCodeUpdater.Outcome
        {
            calls.append(status.install.path)
            running += 1
            maxRunning = max(maxRunning, running)
            lastProgress = progress
            for line in linesBeforeReturn { progress(line) }
            await gate?.wait()
            // Long enough that a second update started alongside this one would be
            // counted as running at the same time.
            try? await Task.sleep(for: .milliseconds(20))
            running -= 1
            return outcomes[status.install.path] ?? .updated(version: nil)
        }

        nonisolated var closure: CLIToolsModel.Update {
            { status, progress in await self.run(status, progress) }
        }
    }

    static func model(check: FakeCheck, updater: FakeUpdater = FakeUpdater(),
                      scan: CLIToolsModel.Scan? = nil) -> CLIToolsModel {
        CLIToolsModel(check: check.closure, scan: scan ?? { [] }, update: updater.closure)
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
    /// Mutation: drop `&& !updating.contains($0.install.path)` from `oneClickable`.
    @Test func aCopyBeingUpdatedIsNotOfferedAgain() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        #expect(model.oneClickable.count == 1)

        let first = Task { await model.update(path: Self.native) }
        await until { await gate.arrived == 1 }
        #expect(model.oneClickable.isEmpty)
        // In a task of its own: were it let through, it would wait at the same
        // closed gate as the first.
        let second = Task { await model.update(path: Self.native) }
        try? await Task.sleep(for: .milliseconds(30))
        await gate.open()
        await first.value
        await second.value

        #expect(await updater.calls == [Self.native])
    }

    /// A copy the check withheld one-click from (auto-update off) is reported,
    /// never updated.
    ///
    /// Mutation: drop `$0.oneClick != nil &&` from `oneClickable`.
    @Test func aWithheldCopyIsNeverUpdated() async {
        let withheld = Self.status(Self.native, oneClick: false, withheld: "autoUpdateOff")
        let check = FakeCheck([(Self.report(withheld), nil)])
        let updater = FakeUpdater()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        #expect(model.outdated.count == 1)
        #expect(model.oneClickable.isEmpty)
        await model.update(path: Self.native)
        await model.updateAll()
        #expect(await updater.calls.isEmpty)
    }

    // MARK: outcomes

    /// A failed update puts its one line on the row and its whole output in the
    /// log — not the other way round — and releases the row.
    ///
    /// Mutation: swap `message` and `output` in the `.failed` case.
    @Test func aFailedUpdateMapsToTheRowLineAndTheLog() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.native, .failed(message: "EACCES", output: "line 1\nEACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(path: Self.native)

        #expect(model.errors[Self.native] == "EACCES")
        #expect(model.errorLogs[Self.native] == "line 1\nEACCES")
        #expect(model.updating.isEmpty)
        #expect(model.progress[Self.native] == nil)
        #expect(model.justUpdated.isEmpty)
    }

    /// A retry clears the previous failure before it runs.
    ///
    /// Mutation: drop `errors[path] = nil` at the top of `update(path:)`.
    @Test func aRetryClearsThePreviousFailure() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.native, .failed(message: "EACCES", output: "EACCES"))
        let gate = Gate()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(path: Self.native)
        #expect(model.errors[Self.native] == "EACCES")

        await updater.setGate(gate)
        let retry = Task { await model.update(path: Self.native) }
        await until { await gate.arrived == 1 }
        #expect(model.errors[Self.native] == nil)
        await gate.open()
        await retry.value
    }

    /// Success records the version the copy now reads as, then re-checks.
    ///
    /// Mutation: drop `await refresh()` from the `.updated` case.
    @Test func anUpdateRecordsItsVersionAndRechecks() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(path: Self.native)

        #expect(model.justUpdated[Self.native] == "2.1.285")
        #expect(model.outdated.isEmpty)
        #expect(await check.calls == 2)
    }

    /// When the updater could not read the new version, the re-check's does.
    ///
    /// Mutation: `justUpdated[path] = version ?? ""`.
    @Test func anUpdateWithoutAVersionTakesTheRechecksVersion() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .updated(version: nil))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(path: Self.native)

        #expect(model.justUpdated[Self.native] == "2.1.285")
    }

    /// The row stays "updating" through the re-check that follows a success: that
    /// check waits on the network, and releasing the row earlier shows the old
    /// "outdated" verdict with a live Update button for its whole length.
    ///
    /// Mutation: move `updating.remove(path)` from the `defer` to right after
    /// `runUpdate` returns.
    @Test func theRowStaysUpdatingThroughTheRecheck() async {
        let recheck = Gate()
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), recheck),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(path: Self.native) }
        await until { await recheck.arrived == 1 }
        #expect(model.updating.contains(Self.native))
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
            (Self.report(Self.status(Self.native, oneClick: false, withheld: "busy")), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .busy(.updateCommand(4242)))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.update(path: Self.native)

        #expect(await check.calls == 2)
        #expect(model.outdated.first?.withheld == .busy)
        #expect(model.errors.isEmpty)
        #expect(model.justUpdated.isEmpty)
    }

    // MARK: progress

    /// Output lines reach the row while the update runs…
    ///
    /// Mutation: drop `self.progress[path] = line` in the progress callback.
    @Test func progressLinesReachTheRow() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        let gate = Gate()
        await updater.setGate(gate)
        await updater.setLines(["Downloading 2.1.285"])
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        let running = Task { await model.update(path: Self.native) }
        await until { model.progress[Self.native] == "Downloading 2.1.285" }
        await gate.open()
        await running.value
        #expect(model.progress[Self.native] == nil)
    }

    /// …but one that arrives after the update finished is dropped, instead of
    /// pinning a stale line on a row that is no longer updating.
    ///
    /// Mutation: drop `self.updating.contains(path)` from the callback's guard.
    @Test func aLateProgressLineIsDropped() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.native, .failed(message: "x", output: "x"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(path: Self.native)

        let late = await updater.lastProgress
        late?("late line")
        // Let the main-actor hop the callback schedules run.
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))

        #expect(model.progress[Self.native] == nil)
    }

    // MARK: updateAll

    /// One copy at a time, each of them.
    ///
    /// Mutation: run the loop's `update(path:)` calls in a `withTaskGroup`.
    @Test func updateAllRunsOneAtATime() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let check = FakeCheck([(Self.report(Self.status(Self.native), npm), nil)])
        let updater = FakeUpdater()
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.native, Self.npm])
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
    /// Mutation: in `update(path:)`, look the status up in `claudeCode` instead of
    /// `oneClickable`.
    @Test func updateAllHonoursAnOfferWithdrawnMidway() async {
        let npm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let npmOff = Self.status(Self.npm, method: "npm", oneClick: false, withheld: "autoUpdateOff",
                                 nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0")
        let check = FakeCheck([
            (Self.report(Self.status(Self.native), npm), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false), npmOff), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()

        await model.updateAll()

        #expect(await updater.calls == [Self.native])
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
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), nil),
        ])
        let model = Self.model(check: check)

        let older = Task { await model.refresh() }
        await until { await slow.arrived == 1 }
        await model.refresh()
        await slow.open()
        await older.value

        #expect(model.outdated.isEmpty)
        #expect(model.claudeCode.first?.install.version == "2.1.285")
        #expect(!model.checking)
    }

    /// The launch scan only reserves the row; a check that already landed is
    /// newer and keeps its installs.
    ///
    /// Mutation: drop `guard !checked else { return }` from `scanInstalls`.
    @Test func aLateScanDoesNotOverwriteACheck() async {
        let scanGate = Gate()
        let stale = [Self.status(Self.native).install, Self.status(Self.npm).install]
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let model = Self.model(check: check, scan: { await scanGate.wait(); return stale })

        let scan = Task { await model.scanInstalls() }
        await until { await scanGate.arrived == 1 }
        await model.refresh()
        await scanGate.open()
        await scan.value

        #expect(model.claudeCodeInstalls.map(\.path) == [Self.native])
    }

    /// Before any check, the scan alone is what reserves the row.
    ///
    /// Mutation: drop `claudeCodeInstalls = installs` from `scanInstalls`.
    @Test func theScanReservesTheRowBeforeAnyCheck() async {
        let check = FakeCheck([(Self.report(), nil)])
        let installs = [Self.status(Self.native).install]
        let model = Self.model(check: check, scan: { installs })

        await model.scanInstalls()

        #expect(model.claudeCodeInstalls.map(\.path) == [Self.native])
        #expect(!model.checked)
    }

    /// An error is about an update still on offer. Once the copy is current (say,
    /// updated from a terminal) it goes.
    ///
    /// Mutation: drop the loop in `apply` that clears `errors`.
    @Test func anErrorGoesOnceTheCopyIsCurrent() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .failed(message: "EACCES", output: "EACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(path: Self.native)
        #expect(model.errors[Self.native] == "EACCES")

        await model.refresh()

        #expect(model.errors[Self.native] == nil)
        #expect(model.errorLogs[Self.native] == nil)
    }

    /// …but stays while it is still behind.
    ///
    /// Mutation: clear `errors` unconditionally in `apply`.
    @Test func anErrorStaysWhileTheCopyIsBehind() async {
        let check = FakeCheck([(Self.report(Self.status(Self.native)), nil)])
        let updater = FakeUpdater()
        await updater.set(Self.native, .failed(message: "EACCES", output: "EACCES"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(path: Self.native)

        await model.refresh()

        #expect(model.errors[Self.native] == "EACCES")
    }

    /// "Updated to X" is dropped once the copy reads as something else.
    ///
    /// Mutation: drop the `now.install.version != version` clause in `apply`.
    @Test func justUpdatedGoesWhenTheVersionMoves() async {
        let check = FakeCheck([
            (Self.report(Self.status(Self.native)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.285", state: "upToDate", oneClick: false)), nil),
            (Self.report(Self.status(Self.native, version: "2.1.290", state: "upToDate", oneClick: false)), nil),
        ])
        let updater = FakeUpdater()
        await updater.set(Self.native, .updated(version: "2.1.285"))
        let model = Self.model(check: check, updater: updater)
        await model.refresh()
        await model.update(path: Self.native)
        #expect(model.justUpdated[Self.native] == "2.1.285")

        await model.refresh()

        #expect(model.justUpdated[Self.native] == nil)
    }

    // MARK: wording

    /// The summary names each copy by its installer, and an nvm prefix by its
    /// node major version.
    ///
    /// Mutation: return "npm" for every npm install in `label`.
    @Test func theSummaryNamesEachInstaller() {
        let native = Self.status(Self.native).install
        let nvm = Self.status(Self.npm, method: "npm", nodePrefix: "/Users/u/.nvm/versions/node/v24.11.0").install
        let brew = Self.status("/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code", method: "npm",
                               nodePrefix: "/opt/homebrew").install

        #expect(CLIToolsModel.summary([native, nvm, brew])
            == "Claude Code ×3 — native, npm (node v24), npm (Homebrew)")
        #expect(CLIToolsModel.summary([native]) == "Claude Code — native")
    }
}
