import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// The app's command-line tool rows in `duo list`, `check` and `install`
/// (`CLIToolRows`). Every path is invented and every provider scripted: nothing
/// here reads the host's tools or runs one.
@Suite struct CLIToolRowsTests {

    static func status(
        _ kind: CLIToolKind, _ path: String, name: String? = nil, installed: String? = "1.0.0",
        latest: String? = "1.1.0", state: CLIToolState = .updateAvailable, oneClick: Bool = true,
        withheld: CLIToolWithheld? = nil, manual: String? = nil, administrator: Bool = false
    ) -> CLIToolStatus {
        CLIToolStatus(
            kind: kind, path: path, installedVersion: installed, latestVersion: latest, channel: nil, state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["update"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil,
            manualCommand: manual.map { CLIToolCommand(executable: $0, arguments: [], pathPrefix: nil) },
            name: name, detail: .fx(FxInstall(path: path, version: installed)), needsAdministrator: administrator)
    }

    static func app(_ name: String, _ path: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "com.zzfixture.\(name.lowercased())", shortVersion: "2.0", buildVersion: "1",
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    static let uv = status(.uv, "/ZZFixture-home/.local/bin/uv")
    static let codexCLI = status(.codex, "/ZZFixture-home/.local/bin/codex")
    static let mcpRemote = status(.npm, "/ZZFixture-home/.config/nvm/versions/node/v24.13.0/lib/node_modules/mcp-remote",
                                  name: "mcp-remote")
    static let helm = status(.helm, "/ZZFixture-usr/local/bin/helm", manual: "curl -fsSL https://zz.invalid/get-helm-3 | bash",
                             administrator: true)
    static let zoxide = status(.zoxide, "/ZZFixture-home/.local/bin/zoxide", oneClick: false, withheld: .unverified,
                               manual: "curl -sSfL https://zz.invalid/install.sh | sh")
    static let deno = status(.deno, "/ZZFixture-home/.deno/bin/deno", latest: "1.0.0", state: .upToDate, oneClick: false)

    static let tools = [uv, codexCLI, mcpRemote, helm, zoxide, deno].map(CLIToolRows.Row.init)
    static let apps = [app("Codex", "/ZZFixture-Applications/Codex.app"), app("Cursor", "/ZZFixture-Applications/Cursor.app")]

    // MARK: - Naming

    @Test func aToolIsNamedByItsPath() throws {
        let picked = try Inventory.select(Self.apps, tools: Self.tools, matching: [Self.uv.path]).get()
        #expect(picked.apps.isEmpty)
        #expect(picked.tools.map(\.path) == [Self.uv.path])
    }

    @Test func aToolIsNamedByItsToolName() throws {
        let picked = try Inventory.select(Self.apps, tools: Self.tools, matching: ["UV"]).get()
        #expect(picked.tools.map(\.tool) == ["uv"])
    }

    /// An npm package goes by its own name, not "npm".
    @Test func aPackageIsNamedByItsOwnName() throws {
        let picked = try Inventory.select(Self.apps, tools: Self.tools, matching: ["mcp-rem"]).get()
        #expect(picked.tools.map(\.name) == ["mcp-remote"])
    }

    /// The apps' rule over apps and tools together: Codex the app and Codex the
    /// CLI both answer to "codex", and duo does not pick one.
    @Test func aPrefixMatchingAnAppAndAToolIsRefused() {
        let result = Inventory.select(Self.apps, tools: Self.tools, matching: ["codex"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("/ZZFixture-Applications/Codex.app"))
        #expect(failure.description.contains(Self.codexCLI.path))
        #expect(failure.description.contains("They share a name, so pass the path of the one you mean."))
    }

    @Test func twoToolsMatchingOnePrefixAreRefused() {
        let twin = CLIToolRows.Row(Self.status(.npm, "/ZZFixture-home/.npm-global/lib/node_modules/mcp-remote",
                                               name: "mcp-remote"))
        let result = Inventory.select(Self.apps, tools: Self.tools + [twin], matching: ["mcp-remote"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("matches 2 installs"))
    }

    @Test func aMissSaysToolsWereLookedAt() {
        guard case .failure(let failure) = Inventory.select(Self.apps, tools: Self.tools, matching: ["zzz"]) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(failure.description == "no installed app or command-line tool matches 'zzz'")
    }

    /// An abandoned app scan cannot rule out an app by that name — but a path
    /// is a path.
    @Test func anAbandonedScanStillResolvesAToolPathButNoName() throws {
        #expect(try Inventory.select(nil, tools: Self.tools, matching: [Self.uv.path]).get().tools.count == 1)
        guard case .failure(let failure) = Inventory.select(nil, tools: Self.tools, matching: ["uv"]) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(failure.description.contains("the app scan was abandoned"))
    }

    @Test func onlyAnAppPathOrBundleIDSparesTheToolCheck() {
        #expect(!Inventory.queriesMayNameTools(Self.apps, ["/ZZFixture-Applications/Cursor.app", "com.zzfixture.codex"]))
        #expect(Inventory.queriesMayNameTools(Self.apps, ["Cursor"]))
        #expect(Inventory.queriesMayNameTools(Self.apps, []))
        #expect(Inventory.queriesMayNameTools(nil, ["com.zzfixture.codex"]))
    }

    // MARK: - What install runs

    /// The guards: a held-back copy and one needing an administrator password
    /// are not run; each is skipped with the app's reason and its command.
    @Test func installRunsOnlyWhatUpdateAllWould() {
        let (run, skip) = CLIToolRows.plan(Self.tools)
        #expect(run.map(\.path) == [Self.uv.path, Self.codexCLI.path, Self.mcpRemote.path])
        #expect(skip.map { $0.0.path } == [Self.helm.path, Self.zoxide.path])
        let helm = skip.first { $0.0.kind == .helm }
        #expect(helm?.1 == CLIToolRows.administratorReason)
        #expect(helm?.2 == "curl -fsSL https://zz.invalid/get-helm-3 | bash")
        let zoxide = skip.first { $0.0.kind == .zoxide }
        #expect(zoxide?.1 == "Not the build its developer published")
        #expect(zoxide?.2 == "curl -sSfL https://zz.invalid/install.sh | sh")
    }

    /// End to end through `apply`: only the planned copies reach a provider's
    /// `update`, each its own tool's.
    @Test func skippedCopiesNeverReachAProvider() async {
        let calls = Calls()
        let providers: [any CLIToolProvider] = CLIToolKind.allCases.map { kind in
            ScriptedProvider(kind: kind, calls: calls) { status in .updated(version: status.latestVersion) }
        }
        let (run, _) = CLIToolRows.plan(Self.tools)
        var tally = Install.Tally()
        await CLIToolRows.apply(run, providers: providers, json: false, tally: &tally, out: { _ in }, err: { _ in })
        #expect(calls.paths == [Self.uv.path, Self.codexCLI.path, Self.mcpRemote.path])
        #expect(calls.kinds == [.uv, .codex, .npm])
        #expect(tally.installed == 3)
    }

    /// A failure says the vendor's line and how its command exited; a run that
    /// exited 0 and left the version is a failure too, as on the app's row.
    @Test func aFailureCarriesTheVendorsLineAndExitStatus() async {
        let calls = Calls()
        let failing = ScriptedProvider(kind: .uv, calls: calls) { _ in
            CLIToolExit.observer?(CLIToolExit.Status(executable: "/ZZFixture-home/.local/bin/uv", status: 2,
                                                     signal: false, timedOut: false))
            return .failed(message: "error: Failed to fetch the release", output: "…")
        }
        let stuck = ScriptedProvider(kind: .codex, calls: calls) { _ in .updated(version: "1.0.0") }
        let lines = Lines()
        var tally = Install.Tally()
        await CLIToolRows.apply([Self.uv, Self.codexCLI], providers: [failing, stuck], json: false, tally: &tally,
                                out: { lines.add($0) }, err: { lines.add($0) })
        #expect(tally.failed == 2)
        #expect(lines.all.contains("   failed: error: Failed to fetch the release"))
        #expect(lines.all.contains("   uv exited with status 2"))
        #expect(lines.all.contains("   failed: still 1.0.0 after the update"))
    }

    @Test func progressGoesToStderr() async {
        let provider = ScriptedProvider(kind: .uv, calls: Calls(), progressLine: "downloading uv 1.1.0") { _ in
            .updated(version: "1.1.0")
        }
        let out = Lines(), err = Lines()
        var tally = Install.Tally()
        await CLIToolRows.apply([Self.uv], providers: [provider], json: false, tally: &tally,
                                out: { out.add($0) }, err: { err.add($0) })
        #expect(err.all == ["   downloading uv 1.1.0"])
        #expect(out.all == ["→ uv  \(Self.uv.path)", "   updated: 1.0.0 → 1.1.0"])
    }

    /// A cancel before a tool started: none of them runs, and each is counted
    /// as cancelled — not dropped from the summary, and not a failure.
    /// Mutation: `break` without recording them → `cancelled == 0`, red.
    @Test func toolsNotStartedAfterACancelAreCountedCancelled() async {
        let calls = Calls()
        let provider = ScriptedProvider(kind: .uv, calls: calls) { _ in .updated(version: "1.1.0") }
        let codex = ScriptedProvider(kind: .codex, calls: calls) { _ in .updated(version: "1.1.0") }
        let out = Lines()
        let tally = await Task { () -> Install.Tally in
            withUnsafeCurrentTask { $0?.cancel() }
            var tally = Install.Tally()
            await CLIToolRows.apply([Self.uv, Self.codexCLI], providers: [provider, codex], json: false,
                                    tally: &tally, out: { out.add($0) }, err: { out.add($0) })
            return tally
        }.value
        #expect(calls.paths.isEmpty)
        #expect(tally.cancelled == 2)
        #expect(tally.failed == 0)
        #expect(out.all.contains("   cancelled before it started — not updated"))
    }

    @Test func outcomesMapToInstallsOwn() {
        #expect(CLIToolRows.result(of: .busy("rustup is running"), before: "1", after: nil, exit: nil)
            == CLIToolRows.Result(outcome: .skipped, reason: "rustup is running"))
        #expect(CLIToolRows.result(of: .notOffered, before: "1", after: nil, exit: nil).outcome == .skipped)
        #expect(CLIToolRows.result(of: .updated(version: nil), before: "1", after: nil, exit: nil)
            == CLIToolRows.Result(outcome: .failed, reason: "couldn't read the version after the update"))
        #expect(CLIToolRows.result(of: .updated(version: "2"), before: "1", after: "2", exit: nil)
            == CLIToolRows.Result(outcome: .installed, version: "2"))
    }

    @Test func aSkippedToolsJSONRowHasNoAppKey() {
        let row = CLIToolRows.skippedPayload(Self.helm, reason: "r", command: "c")
        #expect(row["app"] == nil)
        #expect(row["tool"] as? String == "helm")
        #expect(row["outcome"] as? String == "skipped")
        #expect(row["command"] as? String == "c")
    }

    // MARK: - list / check output

    /// `check` exits 1 for a tool's update as for an app's, whether or not the
    /// app would run it.
    @Test func aToolUpdateMakesCheckExit1() {
        let quiet = { (_: String) in }
        let held = [CLIToolRows.Row(Self.zoxide)]
        #expect(Check.finish([], tools: held, command: "check", json: false, scanAbandoned: false,
                             testFlightGap: nil, out: quiet, err: quiet) == 1)
        #expect(Check.finish([], tools: [CLIToolRows.Row(Self.deno)], command: "check", json: false,
                             scanAbandoned: false, testFlightGap: nil, out: quiet, err: quiet) == 0)
    }

    @Test func checkTextSaysWhyAndWhatToRun() {
        let lines = Lines()
        Check.emitText([], tools: [CLIToolRows.Row(Self.uv), CLIToolRows.Row(Self.helm), CLIToolRows.Row(Self.zoxide)],
                       checked: true, print: { lines.add($0) })
        let text = lines.all.joined(separator: "\n")
        #expect(text.contains("Command-line tools:"))
        #expect(text.contains("1.0.0  →  1.1.0  \(Self.uv.path)"))
        #expect(text.contains("      \(CLIToolRows.administratorReason)"))
        #expect(text.contains("      to update it yourself: curl -fsSL https://zz.invalid/get-helm-3 | bash"))
        #expect(text.contains("      held back: Not the build its developer published"))
        #expect(text.contains("3 updates available of 0 apps and 3 command-line tools shown."))
    }

    /// The runtimes' security lines (`RuntimeSecurityReport.englishLines`) end
    /// the tools' section — and open it when no tool is shown, even under
    /// "Everything is up to date.". They are not updates: the exit code and the
    /// summary don't count them.
    @Test func securityLinesEndTheToolsSection() {
        let security = ["  nvm node 24.13.0: 4 security releases since (latest 24.22.1) — https://nodejs.org/en/blog/release/v24.22.1/"]
        let lines = Lines()
        Check.emitText([], tools: [CLIToolRows.Row(Self.uv)], securityLines: security, checked: true,
                       print: { lines.add($0) })
        let tools = lines.all.firstIndex(of: "Command-line tools:")
        #expect(tools != nil)
        #expect(lines.all.firstIndex(of: security[0]).map { $0 > (tools ?? .max) } == true)
        #expect(lines.all.last == "\n  1 update available of 0 apps and 1 command-line tool shown.")

        let empty = Lines()
        Check.emitText([], securityLines: security, checked: true, print: { empty.add($0) })
        #expect(empty.all == ["Everything is up to date.", "", "Command-line tools:", security[0]])
        let quiet = { (_: String) in }
        #expect(Check.finish([], securityLines: security, command: "check", json: false, scanAbandoned: false,
                             testFlightGap: nil, out: quiet, err: quiet) == 0)
    }

    /// Schema 2, and a tool row says it is one.
    @Test func jsonRowsCarryTheToolAndTheSchemaSays2() throws {
        let lines = Lines()
        Check.emitJSON([], tools: [CLIToolRows.Row(Self.helm)], command: "check", print: { lines.add($0) })
        #expect(lines.all.first == #"{"command":"check","schemaVersion":2}"#)
        let row = try JSONSerialization.jsonObject(with: Data(lines.all[1].utf8)) as? [String: Any]
        #expect(row?["tool"] as? String == "helm")
        #expect(row?["bundleID"] == nil)
        #expect(row?["needsAdministrator"] as? Bool == true)
        #expect(row?["command"] as? String == "curl -fsSL https://zz.invalid/get-helm-3 | bash")
        #expect(row?["names"] == nil)
        #expect(row?["status"] == nil)
    }

    // MARK: - Who runs it

    /// A copy current on disk whose processes started before its update: the
    /// row says so in text and JSON, though there is no update to offer.
    @Test func aCurrentCopyWithStaleProcessesSaysSo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-duo-running-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("deno")
        try Data("x".utf8).write(to: binary)
        let current = Self.status(.deno, binary.path, latest: "1.0.0", state: .upToDate, oneClick: false)
        let idle = Self.status(.uv, directory.appendingPathComponent("missing-uv").path, state: .upToDate, oneClick: false)

        let rows = await CLIToolRows.withUsage([CLIToolRows.Row(current), CLIToolRows.Row(idle)]) { targets in
            Dictionary(uniqueKeysWithValues: targets.map {
                ($0, CLIToolUsage(current: [7], stale: [.init(pid: 3, version: nil)]))
            })
        }
        #expect(rows[0].running?.current == [7])
        #expect(rows[0].running?.stale.map(\.pid) == [3])
        // Not a binary on disk: nothing to match, so nothing said.
        #expect(rows[1].running == nil)

        let lines = Lines()
        Check.emitText([], tools: rows, checked: true, print: { lines.add($0) })
        let text = lines.all.joined(separator: "\n")
        #expect(text.contains("(running)  \(binary.path)"))
        #expect(text.contains("      1 running process still runs a copy that has since been replaced (pid 3) — restart to use the version installed now"))
        #expect(!text.contains("installed now:"))

        let json = Lines()
        Check.emitJSON([], tools: rows, command: "check", print: { json.add($0) })
        let row = try JSONSerialization.jsonObject(with: Data(json.all[1].utf8)) as? [String: Any]
        let running = row?["running"] as? [String: Any]
        #expect(running?["current"] as? [Int] == [7])
        #expect((running?["stale"] as? [[String: Any]])?.first?["pid"] as? Int == 3)
    }

    // MARK: - What a tool is built with

    static let readings: [String: CLIRuntimeReading] = [
        uv.path: CLIRuntimeReading(runtime: .rust, binary: uv.path, evidence: .cargoAuditable),
        // An npm package's Node.js bin that starts its Go platform binary:
        // read as Go, what runs.
        mcpRemote.path: CLIRuntimeReading(runtime: .go, binary: "/ZZFixture-platform/bin/x",
                                          evidence: .goBuildInfo(goVersion: nil)),
        helm.path: CLIRuntimeReading(runtime: .shell, binary: helm.path, evidence: .shebang(interpreter: "sh")),
    ]

    static func withRuntimes() async -> [CLIToolRows.Row] {
        await CLIToolRows.withRuntimes([uv, mcpRemote, helm, deno].map(CLIToolRows.Row.init),
                                       read: { readings[$0] })
    }

    /// Each row carries the app's reading of its own path; a path that proves
    /// nothing carries none.
    @Test func rowsCarryWhatTheyAreBuiltWith() async {
        let rows = await Self.withRuntimes()
        #expect(rows.map(\.runtime) == ["rust", "go", "shell", nil])
        #expect(rows.map(\.builtWith) == ["Rust", "Go", "Shell", nil])
    }

    @Test func jsonCarriesRuntime() async throws {
        let rows = await Self.withRuntimes()
        let lines = Lines()
        Check.emitJSON([], tools: rows, command: "list", print: { lines.add($0) })
        let objects = try lines.all.dropFirst().map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        #expect(objects.map { $0?["runtime"] as? String } == ["rust", "go", "shell", nil])
        // The text form stays out of the JSON — `runtime` says it — and so does
        // the Node.js bin that starts the Go row's binary.
        #expect(objects.allSatisfy { $0?["builtWith"] == nil && $0?["launcher"] == nil })
    }

    @Test func textSaysWhatEachIsBuiltWith() async {
        let rows = await Self.withRuntimes()
        let lines = Lines()
        Check.emitText([], tools: rows, checked: false, print: { lines.add($0) })
        let text = lines.all.joined(separator: "\n")
        #expect(text.contains("→  1.1.0  [Rust]  \(Self.uv.path)"))
        #expect(text.contains("[Go]  \(Self.mcpRemote.path)"))
        #expect(!text.contains("Node.js"))
        #expect(text.contains("[Shell]  \(Self.helm.path)"))
        #expect(text.contains("1.0.0  \(Self.deno.path)"))
    }

    /// `list`'s rows read the real file each sighting names, through the
    /// production detector — here a `#!/bin/sh` script in a scratch directory.
    @Test func scannedRowsReadTheirFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-duo-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("tool")
        try Data("#!/bin/sh\necho\n".utf8).write(to: script)
        let rows = await CLIToolRows.scannedRows([SightingProvider(path: script.path)])
        #expect(rows.map(\.runtime) == ["shell"])
        #expect(rows.map(\.builtWith) == ["Shell"])
        // `check`'s rows the same way.
        let checked = await CLIToolRows.checkedRows([SightingProvider(path: script.path)])
        #expect(checked.map(\.runtime) == ["shell"])
    }

    struct SightingProvider: CLIToolProvider {
        let kind = CLIToolKind.junie
        let path: String
        func scan() async -> [CLIToolSighting] { [CLIToolSighting(kind: kind, path: path, version: "1")] }
        func check() async -> CLIToolReport {
            CLIToolReport(kind: kind, statuses: [CLIToolRowsTests.status(kind, path)], context: .fx(FxSettings()))
        }
        func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
            .notOffered
        }
        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    }

    // MARK: - Breaking changes

    /// An update row whose notes mark a version in its range carries it, says
    /// so under itself and in `--json`; a current row's notes are not fetched.
    @Test func anUpdateRowCarriesTheVersionsItsNotesMarkBreaking() async throws {
        let notes = Changelog(entries: [
            Changelog.Entry(version: "1.1.0", date: nil, items: ["Breaking change: the flag is gone"]),
            Changelog.Entry(version: "1.0.5", date: nil, items: ["Fix"], content: [.heading("Breaking Changes")]),
            Changelog.Entry(version: "1.0.0", date: nil, items: ["**BREAKING**: the install's own"]),
        ])
        let fetches = Calls()
        let provider = NotesProvider(statuses: [
            Self.status(.fx, "/ZZFixture-a/fx"),
            Self.status(.fx, "/ZZFixture-b/fx", installed: "1.1.0", state: .upToDate),
        ], notes: { _ in notes }, fetches: fetches)
        let rows = await CLIToolRows.checkedRows([provider])
        #expect(rows.map(\.breakingIn) == [["1.0.5", "1.1.0"], nil])
        #expect(fetches.paths == ["/ZZFixture-a/fx"])
        #expect(CLIToolRows.details(rows[0]).first == "The release notes mark breaking changes in 1.0.5, 1.1.0")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows[0])) as? [String: Any]
        #expect(json?["breakingIn"] as? [String] == ["1.0.5", "1.1.0"])
    }

    /// Notes that fail to load give no hint, and one document is asked once
    /// for every copy that reads it.
    @Test func notesThatFailGiveNoHintAndAreAskedOnce() async {
        struct Down: Error {}
        let fetches = Calls()
        let provider = NotesProvider(statuses: [
            Self.status(.fx, "/ZZFixture-a/fx"), Self.status(.fx, "/ZZFixture-b/fx"),
        ], notes: { _ in throw Down() }, fetches: fetches)
        let rows = await CLIToolRows.checkedRows([provider])
        #expect(rows.map(\.breakingIn) == [nil, nil])
        #expect(fetches.paths.count == 1)
        #expect(CLIToolRows.details(rows[0]).isEmpty)
    }

    struct NotesProvider: CLIToolProvider {
        let kind = CLIToolKind.fx
        let statuses: [CLIToolStatus]
        let notes: @Sendable (CLIToolStatus) throws -> Changelog
        let fetches: Calls
        func scan() async -> [CLIToolSighting] { [] }
        func check() async -> CLIToolReport { CLIToolReport(kind: kind, statuses: statuses, context: .fx(FxSettings())) }
        func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
            .notOffered
        }
        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
            fetches.add(status)
            return try notes(status)
        }
    }

    // MARK: - Fixtures

    struct ScriptedProvider: CLIToolProvider {
        let kind: CLIToolKind
        let calls: Calls
        var progressLine: String? = nil
        let outcome: @Sendable (CLIToolStatus) -> CLIToolUpdateOutcome

        init(kind: CLIToolKind, calls: Calls, progressLine: String? = nil,
             outcome: @escaping @Sendable (CLIToolStatus) -> CLIToolUpdateOutcome) {
            self.kind = kind
            self.calls = calls
            self.progressLine = progressLine
            self.outcome = outcome
        }

        func scan() async -> [CLIToolSighting] { [] }
        func check() async -> CLIToolReport { CLIToolReport(kind: kind, statuses: [], context: .fx(FxSettings())) }
        func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
            calls.add(status)
            if let progressLine { progress(progressLine) }
            return outcome(status)
        }
        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [CLIToolStatus] = []
        func add(_ status: CLIToolStatus) { lock.withLock { statuses.append(status) } }
        var paths: [String] { lock.withLock { statuses.map(\.path) } }
        var kinds: [CLIToolKind] { lock.withLock { statuses.map(\.kind) } }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    // MARK: - Managed rows

    static let zzManager = ManagerDescriptor(id: ManagerID("zz-fake"), displayName: "ZZ Fake tools", signer: nil,
                                             logo: nil, tint: .label, lane: "zz-fake")

    static func managed(
        key: String = "node@20", installed: String = "20.10.0", latest: String = "20.20.2", overall: String? = "26.12.1",
        state: CLIToolState = .updateAvailable, effects: [ManagedItem.Effect] = [.oldKept(for: "24h")]
    ) -> CLIToolStatus {
        let root = "/ZZFixture-home/.local/share/zz"
        let item = ManagedItem(
            descriptor: zzManager, root: root, key: key, name: String(key.prefix { $0 != "@" }),
            installPath: root + "/installs/node/" + installed, shape: .request,
            request: ManagedItem.Request(kind: .range, spelled: "20"), installed: installed,
            latestWithinRequest: latest, latestOverall: overall, effects: effects)
        let command = CLIToolCommand(executable: "/ZZFixture-home/.local/bin/zz", arguments: ["upgrade", "-y", item.name], pathPrefix: nil)
        return CLIToolStatus(
            kind: .managed, path: item.installPath, identity: item.identity, installedVersion: installed,
            latestVersion: latest, channel: nil, state: state, oneClick: state == .updateAvailable ? command : nil,
            withheld: nil, note: nil,
            manualCommand: state == .upToDate ? CLIToolCommand(executable: "/ZZFixture-home/.local/bin/zz", arguments: ["upgrade", "--bump", item.name], pathPrefix: nil) : nil,
            name: item.name, detail: .managed(item))
    }

    /// A managed row carries its manager, item, root, request and effects
    /// beside the shared keys, under `tool: "managed"`; the schema stays 2
    /// (added keys are not a bump, D-B). Mutation: drop any of the keys from
    /// `CodingKeys`.
    @Test func aManagedRowCarriesItsManagerAndItem() throws {
        let lines = Lines()
        Check.emitJSON([], tools: [CLIToolRows.Row(Self.managed())], command: "check", print: { lines.add($0) })
        #expect(lines.all.first == #"{"command":"check","schemaVersion":2}"#)
        let row = try JSONSerialization.jsonObject(with: Data(lines.all[1].utf8)) as? [String: Any]
        #expect(row?["tool"] as? String == "managed")
        #expect(row?["manager"] as? String == "zz-fake")
        #expect(row?["item"] as? String == "node@20")
        #expect(row?["root"] as? String == "/ZZFixture-home/.local/share/zz")
        #expect(row?["request"] as? String == "20")
        #expect(row?["name"] as? String == "node")
        #expect(row?["path"] as? String == "/ZZFixture-home/.local/share/zz/installs/node/20.10.0")
        #expect(row?["effects"] as? [String] == ["keeps the old version for 24h"])
        #expect(row?["latestBeyondRequest"] == nil)
        #expect(row?["hasUpdate"] as? Bool == true)
        // A row of any other kind carries none of them.
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CLIToolRows.Row(Self.uv))) as? [String: Any]
        #expect(plain?["manager"] == nil)
        #expect(plain?["item"] == nil)
    }

    /// A managed row answers to its key, to "<manager>/<key>" and to its name:
    /// `duo install zz-fake/node` names one row where `node` could be several
    /// (`Inventory.select`'s "never a guess" rule). Mutation: name it by
    /// `status.name` alone.
    @Test func aManagedRowIsNamedByItsKeyAndItsManager() throws {
        let row = CLIToolRows.Row(Self.managed())
        #expect(row.names == ["node@20", "zz-fake/node@20", "node"])
        let picked = try Inventory.select(Self.apps, tools: Self.tools + [row], matching: ["zz-fake/node"]).get()
        #expect(picked.tools.map(\.name) == ["node"])
        // `list`'s row, from the scan alone, is named the same way.
        let sighting = CLIToolSighting(kind: .managed, path: Self.managed().path, version: "20.10.0",
                                       identity: Self.managed().identity, name: "node")
        let listed = CLIToolRows.Row(sighting)
        #expect(listed.name == "node")
        #expect(listed.manager == "zz-fake")
        #expect(listed.item == "node@20")
        #expect(listed.names == row.names)
    }

    /// The text under a managed row: what the update does, and under a current
    /// row held inside its request, what lies beyond it with the command that
    /// lifts the request (D2). Mutation: drop the effects loop from `details`.
    @Test func managedTextSaysWhatTheUpdateDoesAndWhatLiesBeyond() {
        let update = CLIToolRows.Row(Self.managed())
        #expect(CLIToolRows.details(update) == ["the update keeps the old version for 24h"])
        let held = CLIToolRows.Row(Self.managed(installed: "20.20.2", state: .upToDate))
        #expect(held.latestBeyondRequest == "26.12.1")
        #expect(CLIToolRows.details(held)
            == ["26.12.1 available beyond the request — /ZZFixture-home/.local/bin/zz upgrade --bump node"])
        let payload = CLIToolRows.payload(Self.managed(), CLIToolRows.Result(outcome: .installed, version: "20.20.2"))
        #expect(payload["manager"] as? String == "zz-fake")
        #expect(payload["item"] as? String == "node@20")
        #expect(payload["request"] as? String == "20")
    }
}
