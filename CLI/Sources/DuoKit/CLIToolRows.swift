import Foundation
import DuoUpdaterCore

/// The menu-bar app's command-line tool rows — the workbench CLI tab's and the
/// popover's "Other tools" — in `duo list`, `duo check` and `duo install`.
///
/// Nothing here decides anything about a tool: which tools there are and in
/// what order (`CLITools.providers`), what each install's verdict is and which
/// command updates it (each `CLIToolProvider`), why one is held back
/// (`CLIToolWording`), which command the user is handed instead
/// (`CLIToolStatus.commandToCopy`), what Update All runs
/// (`CLIToolStatus.joinsUpdateAll`) and whether an update that exited 0 moved
/// the version (`CLITools.settle`) are all the app's own code in
/// DuoUpdaterCore. This file only lays them out and runs them one at a time.
enum CLIToolRows {

    /// One install of one tool, as `duo` prints it and names it. From a check
    /// (`init(_ status:)`) or, for `list`, from the local scan
    /// (`init(_ sighting:)`), which has no verdict.
    struct Row: Encodable, Equatable {
        /// The tool, `CLIToolKind`'s raw value: "uv", "claude-code", "npm".
        let tool: String
        /// What the app's list calls it: the install's own name when its tool's
        /// group holds several kinds of thing (an npm package, "rustup"), else
        /// the tool's.
        let name: String
        let path: String
        let installedVersion: String?
        var latestVersion: String? = nil
        var channel: String? = nil
        /// `CLIToolState`'s raw value; nil in `list`, which checks nothing.
        var state: String? = nil
        var hasUpdate = false
        /// The command a one-click update stands for, when one is offered.
        var oneClick: String? = nil
        /// The one-click runs as root behind an administrator password, which
        /// `duo` does not ask for.
        var needsAdministrator: Bool? = nil
        /// `CLIToolWithheld`'s raw value: the gate that held the update back.
        var withheld: String? = nil
        /// Why, as the app's popover says it.
        var reason: String? = nil
        /// The check's own English note, for the log.
        var note: String? = nil
        /// The command for the user to run themselves, as the app's row hands
        /// it out to copy.
        var command: String? = nil
        /// The versions the update brings whose release notes mark breaking
        /// changes (`CLIToolChangelog.breakingVersions`), oldest first; nil
        /// when none do, or the notes could not be read.
        var breakingIn: [String]? = nil
        /// What the install is built with, `CLIRuntime`'s raw value ("go",
        /// "rust", "bun"), as the app's CLI tab marks it; nil where its file
        /// proves nothing (`CLIRuntimeDetector`). For an npm package whose
        /// Node.js bin starts its platform package's native binary, that
        /// binary's — nil when it carries no marker.
        var runtime: String? = nil
        /// The runtime's name — "Rust", "Go" — for the text output, which
        /// cannot draw the app's mark.
        var builtWith: String? = nil
        /// Who runs the install's binary now, as the app's running dot and its
        /// "still on the old version" line read it (`CLIToolProcesses`); nil
        /// when nothing does, or the install is not a binary to match.
        var running: Running? = nil
        /// What a name argument is matched against: the install's own name when
        /// it has one, else the tool's display name and raw value.
        let names: [String]
        /// The verdict this row was made from; nil for `list`'s.
        let status: CLIToolStatus?

        enum CodingKeys: String, CodingKey {
            case tool, name, path, installedVersion, latestVersion, channel, state, hasUpdate, oneClick,
                 needsAdministrator, withheld, reason, note, command, runtime, breakingIn, running
        }

        struct Running: Encodable, Equatable {
            /// Processes on the file on disk now.
            let current: [Int32]
            /// Processes still on a copy from before an update.
            let stale: [Stale]
            /// The app's line for them; nil when none is stale.
            let message: String?

            struct Stale: Encodable, Equatable {
                let pid: Int32
                /// The version it runs, when the install's layout names it.
                let version: String?
            }

            init(_ usage: CLIToolUsage, kind: CLIToolKind) {
                current = usage.current
                stale = usage.stale.map { Stale(pid: $0.pid, version: $0.version) }
                message = CLIToolWording.stillRunning(usage, of: kind)
            }
        }

        init(_ status: CLIToolStatus) {
            tool = status.kind.rawValue
            name = status.name ?? status.kind.displayName
            path = status.path
            installedVersion = status.installedVersion
            latestVersion = status.latestVersion
            channel = status.channel
            state = status.state.rawValue
            hasUpdate = status.state == .updateAvailable
            oneClick = status.oneClick?.display
            needsAdministrator = status.oneClick == nil ? nil : status.needsAdministrator
            withheld = status.withheld?.rawValue
            reason = status.withheld.map { CLIToolWording.reason($0, of: status) }
            note = status.note
            command = status.commandToCopy?.display
            names = status.name.map { [$0] } ?? [status.kind.displayName, status.kind.rawValue]
            self.status = status
        }

        init(_ sighting: CLIToolSighting) {
            tool = sighting.kind.rawValue
            name = sighting.kind.displayName
            path = sighting.path
            installedVersion = sighting.version
            names = [sighting.kind.displayName, sighting.kind.rawValue]
            status = nil
        }

        /// A check that gave no verdict: broken, not the vendor's, unreadable,
        /// or its channel did not answer. Not "current" — nothing was learned.
        var unchecked: Bool { state == CLIToolState.unknown.rawValue }

        /// This row with what `reading` says it is built with.
        func with(_ reading: CLIRuntimeReading?) -> Row {
            var row = self
            row.runtime = reading?.runtime.rawValue
            row.builtWith = reading?.runtime.displayName
            return row
        }
    }

    /// `rows`, each with what its path is built with — the same reading the
    /// app's CLI tab tags it with. Reads files (load commands, a bounded
    /// section, a `#!` line), so it runs off the cooperative pool. `read` is
    /// injected for tests; production reads the real files.
    static func withRuntimes(
        _ rows: [Row], read: @escaping @Sendable (String) -> CLIRuntimeReading? = CLIRuntimeDetector.read(path:)
    ) async -> [Row] {
        guard !rows.isEmpty else { return rows }
        return await offCooperativePool(qos: .utility) { rows.map { $0.with(read($0.path)) } }
    }

    /// `rows`, each with who runs its binary now — one read of the process
    /// table for all of them. `read` is injected for tests.
    static func withUsage(
        _ rows: [Row],
        read: @escaping @Sendable ([CLIToolProcesses.Target]) -> [CLIToolProcesses.Target: CLIToolUsage]
            = { CLIToolProcesses.usage(of: $0) }
    ) async -> [Row] {
        guard !rows.isEmpty else { return rows }
        return await offCooperativePool(qos: .utility) {
            let targets = rows.map { row -> CLIToolProcesses.Target? in
                if let status = row.status { return CLIToolProcesses.target(of: status) }
                guard let kind = CLIToolKind(rawValue: row.tool) else { return nil }
                return CLIToolProcesses.target(of: CLIToolSighting(kind: kind, path: row.path, version: nil))
            }
            let usage = read(targets.compactMap { $0 })
            return zip(rows, targets).map { row, target in
                guard let target, let found = usage[target], found.isRunning,
                      let kind = CLIToolKind(rawValue: row.tool) else { return row }
                var row = row
                row.running = Row.Running(found, kind: kind)
                return row
            }
        }
    }

    // MARK: - Reading

    /// Every install the providers find, without the network: `list`'s rows.
    static func scan(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [Row] {
        await CLITools.inProviderOrder(providers, Array(providers.indices)) { await $0.scan() }
            .flatMap { $0.1 }.map(Row.init)
    }

    /// `check`'s verdicts as rows, with what each install is built with and
    /// which versions of its update its release notes mark breaking.
    static func checkedRows(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [Row] {
        let statuses = await check(providers)
        let breaking = await breakingVersions(of: statuses, providers: providers)
        return await withUsage(await withRuntimes(statuses.map { status in
            var row = Row(status)
            row.breakingIn = breaking[status.kind.rawValue + ":" + status.path]
            return row
        }))
    }

    /// Per update row, the versions its notes mark breaking — the app's hint
    /// (`CLIToolsModel.loadBreaking`). Each document is fetched once, one after
    /// another; a row whose notes fail to load gets no hint.
    static func breakingVersions(
        of statuses: [CLIToolStatus], providers: [any CLIToolProvider]
    ) async -> [String: [String]] {
        // Nil for a document that failed, so it is not asked again for the next copy.
        var documents: [String: Changelog?] = [:]
        var found: [String: [String]] = [:]
        for status in statuses where CLIToolChangelog.readsForBreaking(status) {
            guard let provider = providers.first(where: { $0.kind == status.kind }) else { continue }
            let key = status.releaseNotesKey
            if documents[key] == nil {
                documents[key] = .some(try? await RequestAttribution.withApp(CLITools.attributionID(status)) {
                    try await provider.releaseNotes(for: status, force: false)
                })
            }
            guard let notes = documents[key] ?? nil else { continue }
            let versions = CLIToolChangelog.breakingVersions(
                in: notes, installed: status.installedVersion, latest: status.latestVersion)
            if !versions.isEmpty { found[status.kind.rawValue + ":" + status.path] = versions }
        }
        return found
    }

    /// `scan`'s rows, with what each install is built with: `list`'s.
    static func scannedRows(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [Row] {
        await withUsage(await withRuntimes(await scan(providers)))
    }

    /// Every install with its verdict, each tool's requests filed under it as
    /// the app files them (`CLIToolsModel.check`).
    ///
    /// A one-click whose vendor command would ask GitHub's API on a budget
    /// this process has found closed is held back, as the app holds it back
    /// (`CLIToolStatus.applyingGitHubPause`): the command asks from its own
    /// process, where the gate cannot stop it. What this process knows is what
    /// its own requests learned — the checks that read the API probe it first.
    static func check(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [CLIToolStatus] {
        let statuses = await CLITools.inProviderOrder(providers, Array(providers.indices)) { provider in
            await RequestAttribution.withApp(provider.kind.displayName) { await provider.check() }
        }.flatMap { $0.1.statuses }
        guard let gate = GitHubRateLimitGate.active,
              statuses.contains(where: { $0.oneClick != nil && $0.kind.updaterSpendsGitHubAPI != nil })
        else { return statuses }
        let pause = await gate.pause()
        guard !pause.isEmpty else { return statuses }
        let ourToken = await CLITools.vendorUpdatersGetOurToken()
        return statuses.map { $0.applyingGitHubPause(pause, updatersGetOurToken: ourToken, now: Date()) }
    }

    // MARK: - Text

    /// `check`'s and `list`'s lines for the tools, under a heading of their
    /// own after the apps. The path is printed whole: it is what names one copy
    /// among several to `duo install`.
    static func emitText(_ rows: [Row], checked: Bool, print: (String) -> Void) {
        guard !rows.isEmpty else { return }
        print("")
        print("Command-line tools:")
        let width = min(28, rows.map(\.name.count).max() ?? 10)
        for row in rows {
            let name = row.name.count > width
                ? String(row.name.prefix(width - 1)) + "…"
                : row.name.padding(toLength: width, withPad: " ", startingAt: 0)
            var line = "  \(name)  \(row.installedVersion ?? "?")"
            if row.hasUpdate, let latest = row.latestVersion {
                line += "  →  \(latest)"
            } else if checked, let latest = row.latestVersion, row.state != CLIToolState.unknown.rawValue {
                line += "  (latest \(latest))"
            }
            if let builtWith = row.builtWith { line += "  [\(builtWith)]" }
            if row.running != nil { line += "  (running)" }
            line += "  \(row.path)"
            if row.unchecked { line += "  — not checked: \(row.reason ?? row.note ?? "no verdict")" }
            if row.state == CLIToolState.pinned.rawValue, let status = row.status, let pinned = CLIToolWording.pinned(status) {
                line += "  — \(pinned)"
            }
            print(line)
            for detail in details(row) { print("      \(detail)") }
        }
    }

    /// What an update row adds under itself: that its notes mark breaking
    /// changes, why it is not offered, and the command the app hands out
    /// instead.
    static func details(_ row: Row) -> [String] {
        // Said whatever the verdict: the case it is for is the copy that reads
        // current on disk while its old processes do not.
        var lines: [String] = []
        if let running = row.running, let message = running.message {
            let usage = CLIToolUsage(current: running.current, stale: running.stale.map { .init(pid: $0.pid, version: $0.version) })
            let groups = usage.staleByVersion
            if groups.count == 1, groups[0].version == nil {
                // Nothing to break down: the sentence is the one group.
                let pids = groups[0].pids.map(String.init).joined(separator: ", ")
                lines.append("\(message) (pid \(pids)) — restart to use the version installed now")
            } else {
                lines.append("\(message) — restart to use the version installed now:")
                let kind = CLIToolKind(rawValue: row.tool) ?? .codex
                for group in groups {
                    let pids = group.pids.map(String.init).joined(separator: ", ")
                    lines.append("  \(CLIToolWording.stillRunning(group.pids.count, on: group.version, of: kind)) (pid \(pids))")
                }
            }
        }
        if row.state == CLIToolState.pinned.rawValue {
            return lines + (row.command.map { ["to follow new releases again: \($0)"] } ?? [])
        }
        guard row.hasUpdate else { return lines }
        if let breaking = row.breakingIn, !breaking.isEmpty { lines.append(CLIToolWording.breaking(breaking)) }
        if row.needsAdministrator == true {
            lines.append(administratorReason)
        } else if row.oneClick == nil {
            lines.append("held back: \(row.reason ?? row.note ?? "no one-click update")")
        }
        if let command = row.command { lines.append("to update it yourself: \(command)") }
        return lines
    }

    /// Said of a copy whose update the app runs as root after an administrator
    /// password (`CLIToolStatus.needsAdministrator`): `duo` asks for none.
    static let administratorReason =
        "needs an administrator password, which duo does not ask for — run the command below yourself"

    // MARK: - Installing

    /// What `duo install` does with one outdated copy.
    enum Decision: Equatable {
        /// Run its provider's `update`, as the row's Update button does.
        case run
        /// Not run; `command` is the one the app hands out to copy, if any.
        case skip(reason: String, command: String?)
    }

    /// The app's rule: a copy runs when Update All would run it
    /// (`CLIToolStatus.joinsUpdateAll`). One the app holds back is not run, and
    /// neither is one whose update needs an administrator password — the app
    /// asks for that on the row's own click, and `duo` never elevates.
    static func decide(_ status: CLIToolStatus) -> Decision {
        if status.joinsUpdateAll { return .run }
        let command = status.commandToCopy?.display
        if status.oneClick != nil, status.needsAdministrator {
            return .skip(reason: administratorReason, command: command)
        }
        let reason = status.withheld.map { CLIToolWording.reason($0, of: status) }
            ?? status.note ?? "no one-click update"
        return .skip(reason: reason, command: command)
    }

    /// `rows`' outdated copies, split by `decide`: those to run, in order, and
    /// those skipped with the reason and the command to copy. A copy without an
    /// update is neither — `install` says nothing of it, as of a current app.
    static func plan(_ rows: [Row]) -> (run: [CLIToolStatus], skip: [(CLIToolStatus, String, String?)]) {
        var run: [CLIToolStatus] = []
        var skip: [(CLIToolStatus, String, String?)] = []
        for status in rows.compactMap(\.status) where status.state == .updateAvailable {
            switch decide(status) {
            case .run: run.append(status)
            case .skip(let reason, let command): skip.append((status, reason, command))
            }
        }
        return (run, skip)
    }

    /// How one run update ended, as `duo install` reports and counts it.
    struct Result: Equatable {
        let outcome: Install.RowOutcome
        /// The version on disk afterwards, when it moved.
        var version: String? = nil
        /// Why it did not install, for the row.
        var reason: String? = nil
        /// How the vendor's command ended, when one ran and failed.
        var exit: CLIToolExit.Status? = nil
    }

    /// Map a provider's outcome the way the app settles a row: exit 0 counts
    /// only when the version moved (`CLITools.settle`); a failure carries the
    /// vendor's line; nothing ran when the gates changed since the check.
    static func result(
        of outcome: CLIToolUpdateOutcome, before: String?, after: String?, exit: CLIToolExit.Status?
    ) -> Result {
        switch outcome {
        case .updated:
            switch CLITools.settle(before: before, after: after) {
            case .updated(let version): return Result(outcome: .installed, version: version)
            case .unchanged(let version):
                return Result(outcome: .failed, reason: "still \(version) after the update")
            case .unreadable:
                return Result(outcome: .failed, reason: "couldn't read the version after the update")
            }
        case .busy(let why):
            return Result(outcome: .skipped, reason: why)
        case .notOffered:
            return Result(outcome: .skipped,
                          reason: "no longer offered: something changed since the check (run duo check)")
        case .failed(let message, _):
            return Result(outcome: .failed, reason: message, exit: exit)
        case .declined:
            return Result(outcome: .declined, reason: "administrator access was declined")
        }
    }

    /// "uv exited with status 2": how the vendor's command ended.
    static func describe(_ exit: CLIToolExit.Status) -> String {
        let name = (exit.executable as NSString).lastPathComponent
        if exit.timedOut { return "\(name) was stopped at its deadline" }
        return exit.signal ? "\(name) was terminated by signal \(exit.status)"
            : "\(name) exited with status \(exit.status)"
    }

    /// Update each copy in `plan` with its own tool's provider, one after
    /// another — the app's lanes only say which copies must not run at once, and
    /// one at a time honours every one of them. Not under `ProcessInstallLock`:
    /// the app takes none for these either. Progress goes to stderr, line by
    /// line, as the vendor's command prints it.
    static func apply(
        _ plan: [CLIToolStatus], providers: [any CLIToolProvider], json: Bool, tally: inout Install.Tally,
        out: (String) -> Void = { Swift.print($0) },
        err: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async {
        for (index, status) in plan.enumerated() {
            // `SignalGate`'s first signal: the next tool is not started. The
            // ones not started are reported as cancelled, as `Install.apply`
            // reports its items, so the summary still accounts for each.
            if Task.isCancelled {
                for rest in plan[index...] {
                    if json {
                        var row = payload(rest, Result(outcome: .cancelled))
                        row["stage"] = InstallStage.queued.name
                        NDJSON.emit(row)
                    } else {
                        out("→ \(rest.name ?? rest.kind.displayName)  \(rest.path)")
                        out("   \(Install.cancelledLine(.queued))")
                    }
                    tally.record(.cancelled)
                }
                break
            }
            let name = status.name ?? status.kind.displayName
            if !json { out("→ \(name)  \(status.path)") }
            guard let provider = providers.first(where: { $0.kind == status.kind }) else { continue }
            // A job of its own (`InstallJobs.run`), as the app's row runs it
            // (`CLIToolsModel.run`): `SignalGate`'s cancel reaches the update
            // only before its command's `InstallCommit`, so a signal during the
            // preparation — a token exchange, a check, a download — stops it
            // there. Once the command started, the cancel is refused and the
            // update finishes with the re-read that verifies it (uv's, Deno's,
            // fx's, mise's `--version`), which is `.terminateChild` and which a
            // cancelled task would refuse to spawn: the update would be reported
            // failed after it had succeeded.
            let jobID = "cli-tool:\(status.kind.rawValue):\(status.path)"
            let (outcome, after, exit, cancelStopped) = await InstallJobs.run(jobID) {
                () -> (CLIToolUpdateOutcome, String?, CLIToolExit.Status?, Bool) in
                let exits = ExitLog()
                let outcome = await CLIToolExit.$observer.withValue({ exits.append($0) }) {
                    await RequestAttribution.withApp(CLITools.attributionID(status)) {
                        await provider.update(status) { line in err("   \(line)") }
                    }
                }
                var after: String?
                if case .updated(let version) = outcome {
                    // The updater's own re-read first, a fresh check's when it had
                    // none — the app's order (`CLIToolsModel.settle`).
                    after = version
                    if after == nil {
                        after = await provider.check().statuses.first { $0.path == status.path }?.installedVersion
                    }
                }
                // Asked while the job is still registered: it is forgotten when it ends.
                return (outcome, after, exits.last, InstallJobs.cancelStoppedSomething(jobID))
            }
            // The signal kept the command from starting: whatever the provider
            // made of the refused commit ("could not start") is no failure. A
            // cancel accepted only after the command had run and failed stopped
            // nothing, and that failure is the result.
            if cancelStopped {
                if json {
                    var row = payload(status, Result(outcome: .cancelled))
                    row["stage"] = InstallStage.runningCommand("").name
                    NDJSON.emit(row)
                } else {
                    out("   cancelled before its command started — not updated")
                }
                tally.record(.cancelled)
                continue
            }
            let result = result(of: outcome, before: status.installedVersion, after: after, exit: exit)
            tally.record(result.outcome)
            if json {
                NDJSON.emit(payload(status, result))
            } else {
                switch result.outcome {
                case .installed:
                    out("   updated: \(status.installedVersion ?? "?") → \(result.version ?? "?")")
                case .failed:
                    err("   failed: \(result.reason ?? "?")")
                    if let exit = result.exit { err("   \(describe(exit))") }
                default:
                    out("   skipped: \(result.reason ?? "?")")
                }
            }
        }
    }

    /// The `--json` row for a tool `install` ran or skipped. `tool` in place of
    /// an app row's `app`; `outcome` and `applied` as an app row has them.
    static func payload(_ status: CLIToolStatus, _ result: Result) -> [String: Any] {
        var payload: [String: Any] = [
            "tool": status.kind.rawValue, "name": status.name ?? status.kind.displayName, "path": status.path,
            "applied": result.outcome == .installed, "outcome": result.outcome.rawValue,
        ]
        if let version = result.version { payload["version"] = version }
        if let reason = result.reason { payload["reason"] = reason }
        if let exit = result.exit {
            payload["exitStatus"] = Int(exit.status)
            if exit.signal { payload["signal"] = true }
        }
        return payload
    }

    /// The `--json` row for a copy the plan skipped.
    static func skippedPayload(_ status: CLIToolStatus, reason: String, command: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "tool": status.kind.rawValue, "name": status.name ?? status.kind.displayName, "path": status.path,
            "applied": false, "outcome": Install.RowOutcome.skipped.rawValue, "reason": reason,
        ]
        if let command { payload["command"] = command }
        return payload
    }

    /// The exit statuses an update's commands ended with, gathered from
    /// whichever thread `CLIToolExit.observer` is called on.
    private final class ExitLog: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [CLIToolExit.Status] = []
        func append(_ status: CLIToolExit.Status) { lock.withLock { statuses.append(status) } }
        var last: CLIToolExit.Status? { lock.withLock { statuses.last } }
    }
}
