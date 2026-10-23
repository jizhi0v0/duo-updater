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

    /// Network and/or spawn, bounded like today's providers (≤15 s per request
    /// — `CLIToolsModel.check`'s rule). One verdict per item it answers for.
    func check(_ scan: ManagedScan) async -> [ManagedVerdict]

    /// The vendor's documented command that moves `item`, spelled in full, and
    /// the environment it needs beyond `HOME`, `PATH` and `NO_COLOR` (the
    /// manager's root variables); nil when there is none.
    func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])?

    /// The command a user runs to lift a pin or move a request; copied, never run.
    func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand?

    /// Whether the manager is already moving `item` (its own install or
    /// upgrade running, by argv — `ManagedActivity`), in English; nil when not.
    /// Asked at the check and again at the click.
    func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String?

    /// Re-read what `item` is after the command, by its key: a line's newest
    /// patch, a package's venv. Nil when it cannot be read.
    func reread(_ item: ManagedItem) async -> String?

    func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog

    /// A second run of the upgrade with the app's GitHub token, when the first
    /// failed for want of one (mise's rule, `MiseUpdater`); nil for a manager
    /// whose upgrade never asks api.github.com.
    var tokenRetry: ManagedTokenRetry? { get }
}

extension ManagerAdapter {
    public func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? { nil }
    public func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? { nil }
    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    public var tokenRetry: ManagedTokenRetry? { nil }
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
