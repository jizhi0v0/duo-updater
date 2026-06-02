import Foundation

/// Discovers installed `.app` bundles and reads the Info.plist metadata we
/// need for update checks. Pure filesystem work — no network, no UI.
public struct AppScanner: Sendable {

    /// Directories we look in. We deliberately skip `/System/Applications`:
    /// those ship with macOS and are updated by Software Update, not us.
    public let locations: [URL]

    /// Which apps JetBrains Toolbox manages — read once per scan from its
    /// `state.json` so we can tag installs as Toolbox-managed.
    private let toolbox: ToolboxInventory

    public init(locations: [URL]? = nil, toolbox: ToolboxInventory = ToolboxInventory()) {
        self.toolbox = toolbox
        if let locations {
            self.locations = locations
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.locations = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true)
            ]
        }
    }

    /// Scan all configured locations and return the apps found, sorted by name.
    public func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for dir in locations {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                // Resolve symlinks: /Applications/Utilities often links Apple
                // system apps out of /System (e.g. Feedback Assistant). Those are
                // OS-managed by Software Update, not us — skip them, and dedupe on
                // the real path so a symlink can't smuggle one back in.
                let resolved = entry.resolvingSymlinksInPath()
                if resolved.path.hasPrefix("/System/") { continue }
                guard seen.insert(resolved.path).inserted else { continue }
                if let app = readApp(at: resolved) {
                    apps.append(app)
                }
            }
        }

        Log.scan.info("scanned \(self.locations.count, privacy: .public) locations → \(apps.count, privacy: .public) apps")
        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Read one `.app` bundle into an `InstalledApp`, or nil if it has no
    /// readable Info.plist.
    func readApp(at bundleURL: URL) -> InstalledApp? {
        let fm = FileManager.default

        // iPhone/iPad apps running on Apple Silicon are "wrapped": the outer
        // `.app` has no `Contents/`, and the real bundle sits at
        // `Wrapper/<Inner>.app` (a flat iOS layout) behind a `WrappedBundle`
        // symlink. Read the Info.plist from there. Without this, the outer
        // bundle has no readable Info.plist and the app is silently dropped.
        let wrappedBundle = bundleURL.appendingPathComponent("WrappedBundle")
        let isiOSAppOnMac = fm.fileExists(atPath: wrappedBundle.path)
        let infoURL: URL = isiOSAppOnMac
            ? wrappedBundle.appendingPathComponent("Info.plist")
            : bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist")

        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
        else { return nil }

        // An app with no marketing version can't be update-checked — these are
        // helper/background bundles (URL handlers, login items) that would only
        // ever show as permanent "unknown" noise. Exclude them.
        guard let shortVersion = (plist["CFBundleShortVersionString"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !shortVersion.isEmpty
        else { return nil }

        let displayName =
            (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        // Wrapped iOS apps can only come from the Mac App Store; native Mac apps
        // carry a `_MASReceipt` when bought there.
        let receiptURL = bundleURL
            .appendingPathComponent("Contents/_MASReceipt/receipt")
        let isMAS = isiOSAppOnMac || fm.fileExists(atPath: receiptURL.path)

        var feedURL: URL?
        if let feed = plist["SUFeedURL"] as? String {
            feedURL = URL(string: feed.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Electron apps that ship Squirrel manage their own updates; flag them
        // so we defer to that channel instead of a (often staler) Homebrew cask.
        let squirrel = bundleURL.appendingPathComponent("Contents/Frameworks/Squirrel.framework")
        let hasSelfUpdater = FileManager.default.fileExists(atPath: squirrel.path)

        // For Toolbox-managed apps, show Toolbox's own `displayVersion`: the
        // on-disk `CFBundleShortVersionString` is either truncated (Android Studio
        // "2025.2" for 2025.2.3) or on a divergent track (Air reports its SHIP
        // runtime build "261.617" while Toolbox manages it as Public Preview
        // "261.474" — and the update comparison runs in the Public Preview line).
        // Aligning the display with Toolbox keeps the "from → to" coherent.
        let toolboxTool = toolbox.tool(forApp: bundleURL)
        let displayShortVersion = toolboxTool
            .map(\.displayVersion).flatMap { $0.isEmpty ? nil : $0 } ?? shortVersion

        return InstalledApp(
            name: displayName,
            bundleID: plist["CFBundleIdentifier"] as? String,
            shortVersion: displayShortVersion,
            buildVersion: plist["CFBundleVersion"] as? String,
            path: bundleURL,
            isMASApp: isMAS,
            isiOSAppOnMac: isiOSAppOnMac,
            isToolboxManaged: toolbox.isManaged(appPath: bundleURL),
            sparkleFeedURL: feedURL,
            sparkleEdPublicKey: (plist["SUPublicEDKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            hasSelfUpdater: hasSelfUpdater
        )
    }
}
