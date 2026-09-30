import Foundation

/// The update-related settings Claude Code itself obeys, read from the files it
/// reads them from, so DuoUpdater follows the user's choice instead of making one.
///
/// Per https://code.claude.com/docs/en/setup and /docs/en/managed-settings:
/// - `autoUpdatesChannel` is `"latest"` (the default) or `"stable"`;
/// - `minimumVersion` is a floor that updates never go below;
/// - `env.DISABLE_AUTOUPDATER` stops background updates only, `env.DISABLE_UPDATES`
///   blocks `claude update` and `claude install` too;
/// - managed settings beat user settings key by key, and within the managed tier
///   the MDM profile (`com.anthropic.claudecode`) wins over the file-based
///   `managed-settings.json` + `managed-settings.d/*.json`.
///
/// What this cannot see, and so never claims: variables exported in the user's
/// shell (a GUI process has no shell environment), `CLAUDE_CONFIG_DIR` pointing
/// the config somewhere other than `~/.claude`, and server-managed settings.
///
/// `autoUpdates: false` in `~/.claude.json` is deliberately NOT read. It is no
/// longer documented, and measured on 2.1.274 with that key set to false:
/// `claude doctor` still reported "Auto-updates: enabled".
public struct ClaudeCodeSettings: Sendable, Equatable, Codable {

    public enum Channel: String, Sendable, Codable {
        case latest
        case stable
    }

    public var channel: Channel = .latest
    public var minimumVersion: String?
    /// `DISABLE_AUTOUPDATER`: the user turned background updates off. DuoUpdater
    /// then reports updates but offers no one-click install.
    public var autoUpdatesDisabled = false
    /// `DISABLE_UPDATES`: every update path is blocked, `claude update` included.
    public var updatesDisabled = false
    /// The files that contributed, highest precedence first — so a surprising
    /// answer can be traced to where it came from.
    public var sources: [String] = []

    public init() {}

    /// Background updates are on, which is the condition for offering one-click.
    public var autoUpdatesEnabled: Bool { !autoUpdatesDisabled && !updatesDisabled }

    // MARK: - Reading

    /// Where each layer lives. Injected so tests never read the host's settings.
    public struct Locations: Sendable {
        public var userSettings: URL
        public var managedDirectory: URL
        public var managedPreferences: [URL]

        public init(userSettings: URL, managedDirectory: URL, managedPreferences: [URL]) {
            self.userSettings = userSettings
            self.managedDirectory = managedDirectory
            self.managedPreferences = managedPreferences
        }

        public static var standard: Locations {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let managedPrefs = URL(fileURLWithPath: "/Library/Managed Preferences")
            return Locations(
                userSettings: home.appendingPathComponent(".claude/settings.json"),
                managedDirectory: URL(fileURLWithPath: "/Library/Application Support/ClaudeCode"),
                // A configuration profile lands per user, or machine-wide.
                managedPreferences: [
                    managedPrefs.appendingPathComponent(NSUserName())
                        .appendingPathComponent("com.anthropic.claudecode.plist"),
                    managedPrefs.appendingPathComponent("com.anthropic.claudecode.plist"),
                ])
        }

        /// Every file whose change can change the answer — for a watcher.
        public var files: [URL] {
            managedPreferences + [
                managedDirectory.appendingPathComponent("managed-settings.json"),
                managedDirectory.appendingPathComponent("managed-settings.d", isDirectory: true),
                userSettings,
            ]
        }
    }

    public static func read(from locations: Locations = .standard) -> ClaudeCodeSettings {
        var layers: [(source: String, values: [String: Any])] = []
        if let (source, values) = managedLayer(locations) { layers.append((source, values)) }
        if let values = jsonObject(at: locations.userSettings) {
            layers.append((locations.userSettings.path, values))
        }
        return resolve(layers)
    }

    /// The first managed source that sets a policy key wins the whole managed tier —
    /// the documented default, `managedSourcesBehavior: "first-wins"`. The opt-in
    /// `"merge"` is not modelled.
    static func managedLayer(_ locations: Locations) -> (String, [String: Any])? {
        for plist in locations.managedPreferences {
            if let data = try? Data(contentsOf: plist),
               let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               !values.isEmpty {
                return (plist.path, values)
            }
        }
        // `managed-settings.json` first, then `managed-settings.d/*.json` in
        // alphabetical order, hidden files skipped — a later file's value replaces
        // an earlier one's, and `env` merges variable by variable.
        let dropIns = locations.managedDirectory.appendingPathComponent("managed-settings.d")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dropIns.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
        var files = names.map { dropIns.appendingPathComponent($0) }
        files.insert(locations.managedDirectory.appendingPathComponent("managed-settings.json"), at: 0)
        var merged: [String: Any] = [:]
        var used: [String] = []
        for file in files {
            guard let values = jsonObject(at: file) else { continue }
            used.append(file.path)
            for (key, value) in values {
                if key == "env", let env = value as? [String: Any] {
                    merged["env"] = ((merged["env"] as? [String: Any]) ?? [:]).merging(env) { $1 }
                } else {
                    merged[key] = value
                }
            }
        }
        return merged.isEmpty ? nil : (used.joined(separator: " + "), merged)
    }

    /// Highest layer first; the first layer that sets a key decides it.
    static func resolve(_ layers: [(source: String, values: [String: Any])]) -> ClaudeCodeSettings {
        var settings = ClaudeCodeSettings()
        settings.sources = layers.map(\.source)
        func first<T>(_ pick: ([String: Any]) -> T?) -> T? {
            for layer in layers { if let value = pick(layer.values) { return value } }
            return nil
        }
        if let raw = first({ $0["autoUpdatesChannel"] as? String }) {
            // Anything but "stable" is the default channel, as Claude Code treats it.
            settings.channel = raw == "stable" ? .stable : .latest
        }
        settings.minimumVersion = first { $0["minimumVersion"] as? String }
        func env(_ name: String) -> String? {
            first { (($0["env"] as? [String: Any])?[name]).map { "\($0)" } }
        }
        settings.autoUpdatesDisabled = isSet(env("DISABLE_AUTOUPDATER"))
        settings.updatesDisabled = isSet(env("DISABLE_UPDATES"))
        return settings
    }

    /// The docs say "set to `1`". Any other non-empty value that is not an obvious
    /// "off" counts as set too: reading a switch as ON can only withhold one-click
    /// from someone, while reading it as OFF could update a user who said no.
    static func isSet(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else {
            return false
        }
        return !["0", "false", "no", "off"].contains(value)
    }

    static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
