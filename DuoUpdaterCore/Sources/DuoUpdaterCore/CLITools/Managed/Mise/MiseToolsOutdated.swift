import Foundation

/// What `mise outdated --json` (and `--bump`) says, and how it joins
/// `mise ls --json` into one verdict per row.
///
/// The shape, measured on 2026.10.7 (2026-10-23, same isolated home as
/// `MiseToolsLs`; `Tests/…/Fixtures/managed/mise/`):
///
///     "node": { "name": "node", "requested": "20", "current": "20.10.0",
///               "bump": null, "latest": "20.20.2",
///               "source": { "type": "mise.toml", "path": "…/config.toml" } }
///
/// - **Plain**: the newest *within the request* — what `mise upgrade` moves
///   to. An exact pin (`jq = "1.6"`) is not listed; a tool with nothing
///   newer is not listed; nothing outdated at all is `{}` (and was an empty
///   stdout before 2025.2.8, MISE-56).
/// - **`--bump`**: the newest overall, and `bump` the request that would
///   follow it ("26" for `node = "20"`, "1.8" for `jq = "1.6"`).
///   `release_url` (≥2026.8.15) names a GitHub release for some backends —
///   jq's `…/jqlang/jq/releases/tag/jq-1.8.2`; none for `core:node` or `npm:`.
/// - A requested version that is not installed has `current: null`.
/// - **Keyed by tool name, so two requests of one tool collapse**: with
///   `node = ["20", "22"]` both outputs carry the "22" request alone
///   (`two-requests-*.json`, MISE-23). The other request's row cannot be told
///   from them, and says so (`ManagedVerdict.Blocker.notRequested`).
struct MiseToolsOutdated: Sendable, Equatable {

    struct Entry: Sendable, Equatable, Decodable {
        let requested: String?
        let current: String?
        let latest: String
        let releaseURL: String?

        enum CodingKeys: String, CodingKey {
            case requested, current, latest
            case releaseURL = "release_url"
        }
    }

    let entries: [String: Entry]

    /// Empty output is "nothing outdated" (before 2025.2.8 mise printed
    /// nothing then); nil when the output is not mise's map.
    ///
    /// **An absence is not "nothing newer".** A tool mise could not read a
    /// newest version of is left out too, and mise still exits 0 — measured
    /// offline on 2026.10.7 (`offline-outdated*`): `{}` from both reads. What
    /// it says on stderr depends on the backend (`core:node` warns "Error
    /// getting latest version for node", aqua's jq only "Remote versions cannot
    /// be fetched for jqlang/jq") and on the user's `quiet` setting (nothing at
    /// all). So a row the map leaves out is current only once `mise latest`
    /// printed a version for it (`Reading.latest`).
    static func parse(_ data: Data) -> MiseToolsOutdated? {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return MiseToolsOutdated(entries: [:])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var entries: [String: Entry] = [:]
        for (name, value) in object {
            guard let json = try? JSONSerialization.data(withJSONObject: value),
                  let entry = try? JSONDecoder().decode(Entry.self, from: json)
            else { continue }
            entries[name] = entry
        }
        return MiseToolsOutdated(entries: entries)
    }

    // MARK: - The join

    /// What one check of mise read, for `rows`.
    struct Reading: Sendable {
        let ls: MiseToolsLs
        /// Nil when `mise outdated --json` failed: every row is unknown.
        let outdated: MiseToolsOutdated?
        /// Nil when `--bump` failed: nothing is known beyond the requests.
        let bump: MiseToolsOutdated?
        /// What `mise latest` printed, by its argument: "node@20" (the newest
        /// inside a request), "jq" (the newest overall). Asked for what the
        /// two maps leave out (`confirmations`); a key that printed nothing is
        /// absent. Measured on 2026.10.7: online `jq@1.6` → 1.6, `jq` → 1.8.2,
        /// `node@lts` → 24.22.1, 14–400 ms; offline every one printed nothing
        /// (exit 0 for aqua's jq, 1 for node and npm), `quiet` or not.
        var latest: [String: String] = [:]
    }

    /// The `mise latest` arguments a check must ask so that no row is called
    /// current, or held at a pin, on an absence alone: `<tool>@<request>` for
    /// a request plain `outdated` does not list, `<tool>` for a tool `--bump`
    /// does not list.
    static func confirmations(ls: MiseToolsLs, outdated: MiseToolsOutdated?, bump: MiseToolsOutdated?) -> [String] {
        var arguments: [String] = []
        for tool in ls.tools {
            for entry in tool.entries where entry.isRow {
                guard let requested = entry.requestedVersion, outdated?.entries[tool.name] == nil else { continue }
                arguments.append("\(tool.name)@\(requested)")
            }
            if bump?.entries[tool.name] == nil, tool.entries.contains(where: \.isRow) { arguments.append(tool.name) }
        }
        var seen: Set<String> = []
        return arguments.filter { seen.insert($0).inserted }
    }

    /// One verdict per row of `reading.ls` (`MiseToolsLs.Entry.isRow`), in
    /// name order, each made by `item` from what the join decided.
    static func verdicts(
        _ reading: Reading, item: (_ tool: String, _ entry: MiseToolsLs.Entry, _ decided: Decided) -> ManagedItem
    ) -> [ManagedVerdict] {
        var verdicts: [ManagedVerdict] = []
        for tool in reading.ls.tools {
            var seen: Set<String> = []
            // One row per request: the same request read from two config
            // files is one thing mise moves.
            let rows = tool.entries.filter { entry in
                guard entry.isRow, let requested = entry.requestedVersion else { return false }
                return seen.insert(requested).inserted
            }
            guard !rows.isEmpty else { continue }
            let purgatory = tool.entries.filter(\.scheduledForPruning).map(\.version)
            for entry in rows {
                let decided = decide(
                    tool: tool.name, entry: entry, rows: rows, purgatory: purgatory,
                    outdated: reading.outdated, bump: reading.bump, latest: reading.latest)
                verdicts.append(ManagedVerdict(
                    item: item(tool.name, entry, decided), vendorWouldUpgrade: decided.vendorWouldUpgrade,
                    blocker: decided.blocker))
            }
        }
        return verdicts
    }

    /// What the join decided for one row.
    struct Decided: Sendable, Equatable {
        var request: ManagedItem.Request?
        var latestWithinRequest: String?
        var latestOverall: String?
        var vendorWouldUpgrade: Bool?
        var blocker: ManagedVerdict.Blocker?
        var alsoInstalled: [String] = []
        /// The GitHub release mise names for the newest, when it names one.
        var releaseURL: String?
        var notes: [String] = []
    }

    static func decide(
        tool: String, entry: MiseToolsLs.Entry, rows: [MiseToolsLs.Entry], purgatory: [String],
        outdated: MiseToolsOutdated?, bump: MiseToolsOutdated?, latest: [String: String] = [:]
    ) -> Decided {
        let requested = entry.requestedVersion ?? ""
        var decided = Decided()
        decided.alsoInstalled = alsoInstalled(purgatory, for: entry, rows: rows)
        let single = rows.count == 1
        if !single {
            let others = rows.compactMap(\.requestedVersion).filter { $0 != requested }
            decided.notes.append(
                "mise upgrade \(tool) moves every request of \(tool): \(([requested] + others).joined(separator: ", "))")
        }

        guard let kind = requestKind(requested, version: entry.version) else {
            decided.request = ManagedItem.Request(kind: .alias, spelled: requested, source: entry.source)
            decided.blocker = .notIndexed("mise follows \(requested), not a release")
            return decided
        }
        decided.request = ManagedItem.Request(kind: kind, spelled: requested, source: entry.source)
        if let linked = entry.symlinkedTo {
            decided.blocker = .notIndexed("linked to \(linked) with mise link")
            return decided
        }
        guard let outdated else {
            decided.blocker = .channelUnreadable("mise outdated did not answer")
            return decided
        }

        // A tool's one entry is this row's when it is the tool's only row, or
        // when it names this row's request.
        func mine(_ entry: Entry?) -> Entry? {
            guard let entry else { return nil }
            return single || entry.requested == requested ? entry : nil
        }

        let plain = outdated.entries[tool]
        if let own = mine(plain), own.current != nil {
            decided.vendorWouldUpgrade = true
            decided.latestWithinRequest = own.latest
            decided.releaseURL = own.releaseURL
        } else if plain == nil {
            // Not listed: no request of this tool has anything newer inside
            // it (a listing names one, whichever collapsed) — or mise could
            // not read the tool at all, which only `mise latest` tells apart.
            guard latest["\(tool)@\(requested)"] != nil else {
                decided.blocker = .channelUnreadable("mise latest \(tool)@\(requested) printed no version")
                return decided
            }
            decided.vendorWouldUpgrade = false
            decided.latestWithinRequest = entry.version
        } else {
            decided.blocker = .notRequested(
                "mise outdated reports one request per tool, and named \(tool)@\(plain?.requested ?? "?")")
            return decided
        }

        let beyond = bump?.entries[tool]
        if let own = mine(beyond) {
            decided.latestOverall = own.latest
            decided.releaseURL = decided.releaseURL ?? own.releaseURL
        } else if beyond == nil {
            if let newest = latest[tool] {
                // Nothing newer beyond any request of this tool, read for
                // certain: what `mise latest <tool>` printed.
                decided.latestOverall = newest
            } else if kind == .exact {
                // A pin is told from a current row by what lies beyond it
                // alone, and nothing was read of that.
                decided.vendorWouldUpgrade = nil
                decided.blocker = .channelUnreadable("mise latest \(tool) printed no version")
                return decided
            }
        } else if let beyond {
            decided.notes.append(
                "mise outdated --bump reports one request per tool, and named \(tool)@\(beyond.requested ?? "?"): what lies beyond \(requested) was not read")
        }
        return decided
    }

    /// The purgatory versions this row moved away from: those its request
    /// matches as mise matches a fuzzy version (the request, or the request
    /// and a dot before more), and those no row of the tool matches, on the
    /// first row.
    static func alsoInstalled(_ purgatory: [String], for entry: MiseToolsLs.Entry, rows: [MiseToolsLs.Entry]) -> [String] {
        func matches(_ version: String, _ request: String?) -> Bool {
            guard let request else { return false }
            return version == request || version.hasPrefix(request + ".")
        }
        return purgatory.filter { version in
            if matches(version, entry.requestedVersion) { return true }
            return entry == rows.first && !rows.contains { matches(version, $0.requestedVersion) }
        }
    }

    /// How a request follows releases (design §4.1), or nil when it follows
    /// none mise can name a newer one of — a git ref, a local path, the
    /// system's copy. `jq = "1.6"` installed as 1.6 is exact, as is a full
    /// three-part version; `node = "20"` is a range; `latest` and `lts` are
    /// aliases.
    static func requestKind(_ requested: String, version: String) -> ManagedItem.Request.Kind? {
        let lowered = requested.lowercased()
        if lowered == "system" || ["ref:", "path:"].contains(where: { lowered.hasPrefix($0) }) { return nil }
        if lowered == "latest" || lowered == "lts" || lowered.hasPrefix("lts/") || lowered.hasPrefix("lts-") {
            return .alias
        }
        if lowered.hasPrefix("prefix:") { return .range }
        if requested == version { return .exact }
        let parts = requested.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) { return .exact }
        return .range
    }
}
