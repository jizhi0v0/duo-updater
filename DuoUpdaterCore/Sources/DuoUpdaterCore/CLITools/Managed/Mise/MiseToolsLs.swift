import Foundation

/// What `mise ls --json` says is installed and requested: tool name → one
/// entry per version mise knows of.
///
/// The shape, measured on 2026.10.7 (2026-10-23, an isolated home with
/// `jq = "1.6"`, `node = "20"`, `"npm:prettier" = "2.0.0"` in the global
/// config; `Tests/…/Fixtures/managed/mise/ls.json`):
///
///     "node": [
///       { "version": "20.10.0", "install_path": "…/installs/node/20.10.0",
///         "scheduled_for_pruning": true, "prune_after": "2026-10-24T10:07:47Z",
///         "installed": true, "active": false },
///       { "version": "20.20.2", "requested_version": "20",
///         "install_path": "…/installs/node/20.20.2",
///         "source": { "type": "mise.toml", "path": "…/.config/mise/config.toml" },
///         "installed": true, "active": true } ]
///
/// - A version the config requests carries `requested_version` and `source`;
///   one nothing requests has neither (`active: false`).
/// - A request whose version is not installed has `installed: false`.
/// - A version `mise upgrade` moved away from waits in mise's purgatory for
///   24 hours (≥2026.8.15): `scheduled_for_pruning: true`, no request.
/// - `symlinked_to` marks a version `mise link` pointed elsewhere.
/// - An install that was interrupted (its `installs/<tool>/<version>`
///   directory left half-written, measured with SIGINT and SIGTERM during
///   the download and the extraction) is not listed at all.
struct MiseToolsLs: Sendable, Equatable {

    struct Tool: Sendable, Equatable {
        /// As the config spells it: "node", "jq", "npm:prettier".
        let name: String
        /// In mise's order.
        let entries: [Entry]
    }

    struct Entry: Sendable, Equatable, Decodable {
        let version: String
        let requestedVersion: String?
        let installPath: String
        /// The config file the request came from.
        let source: String?
        let installed: Bool
        let active: Bool
        let scheduledForPruning: Bool
        let symlinkedTo: String?

        enum CodingKeys: String, CodingKey {
            case version, source, installed, active
            case requestedVersion = "requested_version"
            case installPath = "install_path"
            case scheduledForPruning = "scheduled_for_pruning"
            case symlinkedTo = "symlinked_to"
        }

        enum SourceKeys: String, CodingKey { case path }

        init(
            version: String, requestedVersion: String?, installPath: String, source: String?,
            installed: Bool = true, active: Bool = true, scheduledForPruning: Bool = false, symlinkedTo: String? = nil
        ) {
            self.version = version
            self.requestedVersion = requestedVersion
            self.installPath = installPath
            self.source = source
            self.installed = installed
            self.active = active
            self.scheduledForPruning = scheduledForPruning
            self.symlinkedTo = symlinkedTo
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            requestedVersion = try container.decodeIfPresent(String.self, forKey: .requestedVersion)
            installPath = try container.decode(String.self, forKey: .installPath)
            source = try? container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                .decodeIfPresent(String.self, forKey: .path)
            // Every build measured writes both; a build that left one out
            // listed nothing it had not installed.
            installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? true
            active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
            scheduledForPruning = try container.decodeIfPresent(Bool.self, forKey: .scheduledForPruning) ?? false
            symlinkedTo = try container.decodeIfPresent(String.self, forKey: .symlinkedTo)
        }

        /// What makes a row (design §4.1): requested by the config, installed,
        /// not waiting in purgatory.
        var isRow: Bool { requestedVersion != nil && installed && !scheduledForPruning }
    }

    /// Sorted by name: a JSON object keeps no order, and the rows must not
    /// change places from one check to the next.
    let tools: [Tool]

    /// Nil when `data` is not mise's map of arrays. An entry that is not one
    /// (a field of a newer mise's shape) leaves its tool out, never the rest.
    static func parse(_ data: Data) -> MiseToolsLs? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var tools: [Tool] = []
        for (name, value) in object {
            guard let array = value as? [Any],
                  let json = try? JSONSerialization.data(withJSONObject: array),
                  let entries = try? JSONDecoder().decode([Entry].self, from: json)
            else { continue }
            tools.append(Tool(name: name, entries: entries))
        }
        return MiseToolsLs(tools: tools.sorted { $0.name < $1.name })
    }
}
