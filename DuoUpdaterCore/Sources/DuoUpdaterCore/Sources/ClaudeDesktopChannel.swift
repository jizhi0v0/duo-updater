import Foundation

enum ClaudeDesktopChannel {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let firstChannelVersion = "4.29.0"

    enum Management {
        case unmanaged, managed, undetermined
    }

    // Published macOS Enterprise policy keys in Claude's bundled schema.
    // Private or future keys alone don't establish which track Claude picks.
    private static let desktopPolicyKeys: Set<String> = [
        "allowedWorkspaceFolders", "autoUpdaterEnforcementHours", "disableAutoUpdates",
        "forceLoginOrgUUID", "isClaudeCodeForDesktopEnabled",
        "isDesktopExtensionEnabled", "isDesktopExtensionDirectoryEnabled",
        "isLocalDevMcpEnabled", "secureVmFeaturesEnabled",
    ]

    static func resolveCurrent(bundleStrings: [String: String]) -> ResolvedChannel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = home.appendingPathComponent(
            "Library/Application Support/Claude/claude_desktop_config.json")
        let data = try? Data(contentsOf: settings)
        let requested = releaseChannel(in: data)
        return resolve(
            preference: requested,
            installedVersion: bundleStrings["CFBundleShortVersionString"],
            management: requested == "latest" ? managedPreferences() : .unmanaged)
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
        preference: String?, installedVersion: String? = nil, management: Management = .unmanaged
    ) -> ResolvedChannel {
        let supportsPicker = installedVersion.map {
            VersionComparator.compare($0, firstChannelVersion) != .orderedAscending
        } ?? true  // The preference fingerprint is read without a bundle.
        guard preference == "latest", supportsPicker else { return ResolvedChannel(channel: .stable) }
        switch management {
        case .unmanaged: return ResolvedChannel(channel: .latest)
        case .managed: return ResolvedChannel(channel: .stable)
        case .undetermined: return ResolvedChannel(channel: .undetermined)
        }
    }

    static func managedPreferences(
        in root: URL = URL(fileURLWithPath: "/Library/Managed Preferences", isDirectory: true),
        user: String = NSUserName()
    ) -> Management {
        let userDirectory = root.appendingPathComponent(user, isDirectory: true)
        var hasUnrecognizedPolicy = false
        for directory in [root, userDirectory] {
            let plist = directory.appendingPathComponent(bundleID + ".plist")
            let data: Data
            do {
                data = try Data(contentsOf: plist)
            } catch let error as CocoaError
                where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                continue
            } catch {
                // Claude disables Latest when a Desktop policy cannot be read.
                return .managed
            }
            guard let values = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
            else { return .managed }
            if !desktopPolicyKeys.isDisjoint(with: values.keys) { return .managed }
            hasUnrecognizedPolicy = hasUnrecognizedPolicy || values.contains { key, value in
                key != "deploymentMode" || value as? String != "any"
            }
        }
        return hasUnrecognizedPolicy ? .undetermined : .unmanaged
    }
}
