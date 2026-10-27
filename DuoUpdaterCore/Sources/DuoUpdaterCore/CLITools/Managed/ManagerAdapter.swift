import Foundation

/// One manager, answering four questions only: where its roots and items are
/// on disk (no spawn), what the newest for each item is within and beyond the
/// user's request, which vendor command moves an item, and where its notes
/// are. `ManagedCheck` turns the answers into `CLIToolStatus` with the same
/// state rules for every manager, and `ManagedProvider` runs them through the
/// app's scheduling like any other `CLIToolProvider`.
///
/// Common to every adapter (design §4): `home` is injected; `scan` reads only
/// under `home` and the Homebrew prefixes; the manager's binary is run only
/// when its root's trust is runnable (`ManagedRoot.Trust`); the child's
/// environment is built from scratch plus the system proxy; no flags beyond
/// the vendor's documented upgrade command.
public protocol ManagerAdapter: Sendable {
    var descriptor: ManagerDescriptor { get }

    /// Disk only. Never spawns. Roots, items with installed versions and
    /// requests, the binary's trust. A test asserts no `ChildProcess` runs here.
    func scan() async -> ManagedScan

    /// The scan as the check stands on it: what only running the binary can
    /// read, and `scan` may not — mise's `--version`, which decides an
    /// effect and the group's header. Asked once per check, before `check`;
    /// its roots are the ones the check's rows and header read. Default: the
    /// scan as it is.
    func resolve(_ scan: ManagedScan) async -> ManagedScan

    /// Network and/or spawn, bounded like today's providers (≤15 s per request
    /// — `CLIToolsModel.check`'s rule). One verdict per item it answers for.
    func check(_ scan: ManagedScan) async -> [ManagedVerdict]

    /// The vendor's documented command that moves `item`, spelled in full, and
    /// the environment it needs beyond `HOME`, `PATH` and `NO_COLOR` (the
    /// manager's root variables); nil when there is none.
    func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])?

    /// Where the manager's commands run — its upgrade and the check's own
    /// spawns. A manager that reads its config from where it runs (mise)
    /// must see the same directory at the check and at the click, and never
    /// the inherited one: under a `duo` run from a terminal that is the
    /// user's project. Default `/` (design §4: cwd `/` unless stated).
    func workingDirectory(home: URL) -> URL

    /// The command a user runs to lift a pin or move a request; copied, never run.
    func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand?

    /// Whether the manager is already moving `item` (its own install or
    /// upgrade running, by argv — `ManagedActivity`), in English; nil when not.
    /// Asked at the check and again at the click.
    func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String?

    /// `checked` as it is right now, for the click's gate (`ManagedProvider
    /// .update`): nil when it is gone. Default: the scan's item of the same
    /// identity. A manager whose rows the disk alone cannot name — mise, one
    /// row per request in its config — re-reads with its own read-only
    /// command (cancellable: the click has not reached its commit point).
    func current(_ checked: ManagedItem, in scan: ManagedScan) async -> ManagedItem?

    /// Re-read what `item` is after the command, by its key: a line's newest
    /// patch, a package's venv. Nil when it cannot be read.
    func reread(_ item: ManagedItem) async -> String?

    func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog

    /// A second run of the upgrade with the app's GitHub token, when the first
    /// failed for want of one (mise's rule, `MiseUpdater`); nil for a manager
    /// whose upgrade never asks api.github.com.
    var tokenRetry: ManagedTokenRetry? { get }

    /// What `item`'s upgrade may write, so it can be stopped partway and put
    /// back (D15, `ManagedSnapshot`); nil when it must run to completion.
    /// Measured per manager (plans/cli-managers-redesign.md §13.4): a path
    /// left out is one a stop could leave changed.
    func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption?
}

/// An upgrade that may be stopped: every path it may write, and the
/// environment variables pointed at a scratch directory of ours for the run
/// (`TMPDIR`: what a stopped `cargo install` or `ruby-build` leaves there is
/// removed with the directory).
public struct ManagedInterruption: Sendable, Equatable {
    public let paths: [String]
    /// Entries a run may add whose names are not known before it: removed
    /// after a stop when new since the snapshot.
    public let created: [ManagedSnapshot.NewEntries]
    public let scratchVariables: [String]

    public init(paths: [String], created: [ManagedSnapshot.NewEntries] = [], scratchVariables: [String] = []) {
        self.paths = paths
        self.created = created
        self.scratchVariables = scratchVariables
    }

    /// The links in `directory` whose target is inside `target`: a tool's
    /// entry points in a shared `bin`, which an upgrade rewrites.
    public static func links(in directory: String, into target: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let rule = ManagedSnapshot.NewEntries(directory: directory, linkingInto: target)
        return names.sorted().filter { rule.matches($0, in: directory) }.map { directory + "/" + $0 }
    }
}

extension ManagerAdapter {
    public func resolve(_ scan: ManagedScan) async -> ManagedScan { scan }
    public func workingDirectory(home: URL) -> URL { URL(fileURLWithPath: "/") }
    public func current(_ checked: ManagedItem, in scan: ManagedScan) async -> ManagedItem? {
        scan.items.first { $0.identity == checked.identity }
    }
    public func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? { nil }
    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? { nil }
    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    public var tokenRetry: ManagedTokenRetry? { nil }
    public func interruption(_ item: ManagedItem, root: ManagedRoot) -> ManagedInterruption? { nil }
}

/// mise's token handoff (`MiseUpdater.update`), shared: the vendor's command is
/// run again, once, with the app's token in `variable`, only when the first
/// run failed and printed `marker` — the vendor saying it found no token of
/// its own. Handed on up front, a variable would outrank every token of the
/// user's own.
public struct ManagedTokenRetry: Sendable, Equatable {
    public let variable: String
    public let marker: String

    public init(variable: String, marker: String) {
        self.variable = variable
        self.marker = marker
    }

    /// Whether a failed run printed the marker.
    func applies(failed: Bool, lines: [String]) -> Bool {
        failed && lines.contains { $0.contains(marker) }
    }
}
