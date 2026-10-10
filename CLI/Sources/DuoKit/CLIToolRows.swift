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
        /// What a name argument is matched against: the install's own name when
        /// it has one, else the tool's display name and raw value.
        let names: [String]
        /// The verdict this row was made from; nil for `list`'s.
        let status: CLIToolStatus?

        enum CodingKeys: String, CodingKey {
            case tool, name, path, installedVersion, latestVersion, channel, state, hasUpdate, oneClick,
                 needsAdministrator, withheld, reason, note, command
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
    }

    // MARK: - Reading

    /// Every install the providers find, without the network: `list`'s rows.
    static func scan(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [Row] {
        await CLITools.inProviderOrder(providers, Array(providers.indices)) { await $0.scan() }
            .flatMap { $0.1 }.map(Row.init)
    }

    /// Every install with its verdict, each tool's requests filed under it as
    /// the app files them (`CLIToolsModel.check`).
    static func check(_ providers: [any CLIToolProvider] = CLITools.providers()) async -> [CLIToolStatus] {
        await CLITools.inProviderOrder(providers, Array(providers.indices)) { provider in
            await RequestAttribution.withApp(provider.kind.displayName) { await provider.check() }
        }.flatMap { $0.1.statuses }
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
            line += "  \(row.path)"
            if row.unchecked { line += "  — not checked: \(row.reason ?? row.note ?? "no verdict")" }
            print(line)
            for detail in details(row) { print("      \(detail)") }
        }
    }

    /// What an update row adds under itself: why it is not offered, and the
    /// command the app hands out instead.
    static func details(_ row: Row) -> [String] {
        guard row.hasUpdate else { return [] }
        var lines: [String] = []
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
        for status in plan {
            let name = status.name ?? status.kind.displayName
            if !json { out("→ \(name)  \(status.path)") }
            guard let provider = providers.first(where: { $0.kind == status.kind }) else { continue }
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
            let result = result(of: outcome, before: status.installedVersion, after: after, exit: exits.last)
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
