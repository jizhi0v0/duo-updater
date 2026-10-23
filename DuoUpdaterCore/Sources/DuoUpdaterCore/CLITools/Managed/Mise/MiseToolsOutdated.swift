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
    /// The tools mise could not read a newest version of, by name. mise leaves
    /// such a tool out of the map and still exits 0, so its absence is not
    /// "nothing newer". Measured offline on 2026.10.7
    /// (`offline-outdated*.stderr.txt`): `{}` on stdout, exit 0, and on stderr
    /// `mise WARN  Error getting latest version for node: error sending
    /// request: …` — from plain `outdated` for the range request, and from
    /// `--bump` for every tool, exact pins included (jq: "no latest version
    /// found"; prettier: "timed out after 20.00s").
    var unresolved: Set<String> = []

    /// Empty output is "nothing outdated" (before 2025.2.8 mise printed
    /// nothing then); nil when the output is not mise's map. `stderr` names the
    /// tools mise could not read (`unresolved`).
    static func parse(_ data: Data, stderr: Data = Data()) -> MiseToolsOutdated? {
        let unresolved = Self.unresolved(stderr)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return MiseToolsOutdated(entries: [:], unresolved: unresolved)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var entries: [String: Entry] = [:]
        for (name, value) in object {
            guard let json = try? JSONSerialization.data(withJSONObject: value),
                  let entry = try? JSONDecoder().decode(Entry.self, from: json)
            else { continue }
            entries[name] = entry
        }
        return MiseToolsOutdated(entries: entries, unresolved: unresolved)
    }

    /// The tool names of mise's "Error getting latest version for <tool>: …"
    /// warnings (`OutdatedInfo::resolve`, v2026.10.7).
    static func unresolved(_ stderr: Data) -> Set<String> {
        let marker = "Error getting latest version for "
        var tools: Set<String> = []
        for line in String(decoding: stderr, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let text = CLIToolCommandRunner.stripEscapes(String(line))
            guard let start = text.range(of: marker) else { continue }
            let rest = text[start.upperBound...]
            guard let end = rest.range(of: ": ") else { continue }
            let tool = String(rest[..<end.lowerBound])
            if !tool.isEmpty { tools.insert(tool) }
        }
        return tools
    }

    // MARK: - The join

    /// What one check of mise read, for `rows`.
    struct Reading: Sendable {
        let ls: MiseToolsLs
        /// Nil when `mise outdated --json` failed: every row is unknown.
        let outdated: MiseToolsOutdated?
        /// Nil when `--bump` failed: nothing is known beyond the requests.
        let bump: MiseToolsOutdated?
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
                    outdated: reading.outdated, bump: reading.bump)
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
        outdated: MiseToolsOutdated?, bump: MiseToolsOutdated?
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
        if outdated.unresolved.contains(tool) {
            decided.blocker = .channelUnreadable("mise could not read the newest \(tool)")
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
            // it (a listing names one, whichever collapsed).
            decided.vendorWouldUpgrade = false
            decided.latestWithinRequest = entry.version
        } else {
            decided.blocker = .notRequested(
                "mise outdated reports one request per tool, and named \(tool)@\(plain?.requested ?? "?")")
            return decided
        }

        // An exact pin is told from a current row by `--bump` alone: plain
        // `outdated` never looks up its newest.
        let bumpRead = bump.map { !$0.unresolved.contains(tool) } ?? false
        if !bumpRead, kind == .exact {
            decided.vendorWouldUpgrade = nil
            decided.blocker = .channelUnreadable("mise outdated --bump could not read the newest \(tool)")
            return decided
        }
        let beyond = bump?.entries[tool]
        if let own = mine(beyond) {
            decided.latestOverall = own.latest
            decided.releaseURL = decided.releaseURL ?? own.releaseURL
        } else if bumpRead, beyond == nil {
            // Nothing newer beyond any request of this tool.
            decided.latestOverall = decided.latestWithinRequest
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
