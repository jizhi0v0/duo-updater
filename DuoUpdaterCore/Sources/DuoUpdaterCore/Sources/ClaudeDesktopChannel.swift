import Foundation

enum ClaudeDesktopChannel {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let teamIdentifier = "Q6L2SF6YDW"
    static let latestChannelUUID = "77a14fc4-808e-4345-ac3e-090be671bf94"
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

    /// The installer sweep checks the updater's channel map in the signed ZIP.
    /// The public Stable archive is enough to check this even on a runner with
    /// no device identity for the Squirrel probes. The read is bounded to small
    /// windows, so it doesn't depend on the current hashed JS chunk name.
    static func installerWarnings(asar: URL, version: String?) -> [String] {
        if let version, VersionComparator.compare(version, firstChannelVersion) == .orderedAscending {
            return []
        }
        let unverified = ["claudeLatestChannelUnverified: could not read a unique Stable/Latest channel map in Claude's app.asar"]
        let marker = Data("{stable:null,latest:".utf8)
        let pattern = #"\A\{stable:null,latest:"([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})"[,}]"#
        // A UUID plus its quotes and trailing delimiter takes 39 bytes.
        guard let windows = ExecutableBytes.windows(in: asar, marker: marker, before: 0, after: 39) else {
            return unverified
        }
        let ids = windows.compactMap { bytes in
            VendorProbeRecipe.extractVersion(from: String(decoding: bytes, as: UTF8.self), pattern: pattern)?
                .lowercased()
        }
        guard ids.count == windows.count, let bundled = ids.first, ids.allSatisfy({ $0 == bundled }) else {
            return unverified
        }
        guard bundled == latestChannelUUID else {
            return ["claudeLatestChannelChanged: the bundled map contains \(bundled). The Latest probe uses \(latestChannelUUID)"]
        }
        return []
    }
}
