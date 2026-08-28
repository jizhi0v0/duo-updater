import Foundation

/// The in-memory, per-formula release-notes state the workbench renders — the UI
/// layer above `BrewFormulaReleaseService`'s cross-launch disk cache.
///
/// Lives here rather than as a bare dictionary on `AppListModel` for one reason:
/// the version has to be part of the state, and every read/write has to agree on
/// that. The disk cache underneath is version-keyed (`fileURL` includes the
/// version, because a released version's notes never change), but the in-memory
/// layer used to be keyed by formula NAME alone and was never cleared — so once a
/// formula's notes had been loaded, every later request for that formula was taken
/// for a hit no matter which version it asked about, and the pane rendered the old
/// version's notes for the rest of the session.
///
/// Note which paths actually move the version, because it is NOT the obvious one:
/// both writers key on `availableVersion ?? installedVersion`, and a plain
/// `brew upgrade` leaves that string unchanged (1.2→1.3 outdated keys on the
/// available "1.3"; afterwards `BrewFormulaService.merge` reports installed "1.3"
/// with no available, which keys the same). What does move it:
///   * an up-to-date formula whose notes loaded at installed 1.2 later gaining an
///     available 1.3;
///   * the available version bumping again (1.3→1.4) on a later `brew update`
///     before the user upgrades;
///   * `brew upgrade`'s implicit `brew update` landing a version other than the one
///     `brew outdated` had reported — see `BrewFormulaService`'s doc comment, which
///     documents that the pre-count is deliberately allowed to be conservative.
///
/// The version is carried on the entry rather than folded into the dictionary key
/// so a formula holds at most ONE entry: moving to a new version REPLACES the
/// stale one instead of leaving it to accumulate for every version seen this
/// session. Nothing ever wants the old version's notes back.
///
/// There is deliberately no way to release a claimed slot. A claim is a promise to
/// `finish` it: the pane's `.task(id:)` fires once per version and has no reason to
/// fire again, so a slot claimed and then handed back leaves an open pane spinning
/// on an entry nobody will fill. Callers that might not load must decide that
/// BEFORE they claim — see `prewarmFormulaReleases`.
public struct FormulaReleaseStore: Sendable {
    public enum State: Sendable, Equatable {
        case loading
        case loaded(FormulaRelease)
    }

    private struct Entry: Sendable {
        let version: String
        let state: State
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// The state for a formula AT a version, or nil when nothing is in flight or
    /// held for that version — which is also what an entry left over from a
    /// different version reads as, so a stale entry can never be rendered.
    public func state(name: String, version: String) -> State? {
        guard let entry = entries[name], entry.version == version else { return nil }
        return entry.state
    }

    /// Claim the slot for `name` at `version`, returning whether the caller should
    /// go on to load it. Claiming marks it `.loading` SYNCHRONOUSLY so a concurrent
    /// claimant (the pre-warm and a user selecting the same row) can't both pass and
    /// double-fetch. A claim at a DIFFERENT version than the entry holds wins — that
    /// is the upgrade case, and the old version's notes are worthless now.
    public mutating func claim(name: String, version: String) -> Bool {
        guard entries[name]?.version != version else { return false }
        entries[name] = Entry(version: version, state: .loading)
        return true
    }

    /// Record a finished load. Ignored when the slot has since been re-claimed at
    /// another version: a slow fetch for the version we just upgraded away from
    /// must not clobber the fresh `.loading` that replaced it.
    public mutating func finish(name: String, version: String, release: FormulaRelease) {
        guard entries[name]?.version == version else { return }
        entries[name] = Entry(version: version, state: .loaded(release))
    }
}
