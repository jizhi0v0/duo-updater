import Foundation

enum ClaudeDesktopChannel {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let firstChannelVersion = "4.29.0"

    static func resolveCurrent(bundleStrings: [String: String]) -> ResolvedChannel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = home.appendingPathComponent(
            "Library/Application Support/Claude/claude_desktop_config.json")
        let data = try? Data(contentsOf: settings)
        let requested = releaseChannel(in: data)
        return resolve(
            preference: requested,
            installedVersion: bundleStrings["CFBundleShortVersionString"],
            isManaged: requested == "latest" && hasManagedPreferences())
    }

    // Claude Desktop migrates ancientJournal to releaseChannel when the latter
    // is absent or invalid. An explicit Stable wins over the legacy key.
    static func releaseChannel(in data: Data?) -> String? {
        guard let data, data.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let preferences = object["preferences"] as? [String: Any]
        else { return nil }
        if let current = preferences["releaseChannel"] as? String,
           current == "stable" || current == "latest" {
            return current
        }
        return preferences["ancientJournal"] as? String
    }

    static func resolve(
        preference: String?, installedVersion: String? = nil, isManaged: Bool = false
    ) -> ResolvedChannel {
        let supportsPicker = installedVersion.map {
            VersionComparator.compare($0, firstChannelVersion) != .orderedAscending
        } ?? true  // The preference fingerprint is read without a bundle.
        return ResolvedChannel(
            channel: preference == "latest" && supportsPicker && !isManaged ? .latest : .stable)
    }

    private static func hasManagedPreferences() -> Bool {
        let root = URL(fileURLWithPath: "/Library/Managed Preferences", isDirectory: true)
        let domains = [bundleID, "com.anthropic.claudecode"]
        return [root, root.appendingPathComponent(NSUserName(), isDirectory: true)].contains { directory in
            domains.contains { domain in
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(domain + ".plist").path)
            }
        }
    }
}
