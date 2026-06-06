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

    /// TestFlight's macOS builds — read once per scan from its local DB so we can
    /// tag installs as TestFlight-managed (and keep them out of the MAS path).
    private let testflight: TestFlightInventory

    public init(
        locations: [URL]? = nil,
        toolbox: ToolboxInventory = ToolboxInventory(),
        testflight: TestFlightInventory = TestFlightInventory()
    ) {
        self.toolbox = toolbox
        self.testflight = testflight
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
        // carry a `_MASReceipt` when bought there. TestFlight builds ALSO carry a
        // `_MASReceipt`, so decide TestFlight first (by matching the installed
        // build against TestFlight's DB) and exclude it from the MAS flag — else a
        // TestFlight app would be checked against the App Store's stable track.
        // Wrapped iOS apps have no `Contents/` — their MAS provenance is implied by
        // the wrapper itself, so we never look for a `Contents/_MASReceipt` there
        // (that path can't exist and the check would always be false).
        let bundleID = plist["CFBundleIdentifier"] as? String
        let buildVersion = plist["CFBundleVersion"] as? String
        let isTestFlight = testflight.isManaged(bundleID: bundleID, installedBuild: buildVersion)
        let hasReceipt = !isiOSAppOnMac && fm.fileExists(
            atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        let isMAS = !isTestFlight && (isiOSAppOnMac || hasReceipt)

        var feedURL: URL?
        if let feed = plist["SUFeedURL"] as? String {
            feedURL = URL(string: feed.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Electron apps that ship Squirrel manage their own updates; flag them
        // so we defer to that channel instead of a (often staler) Homebrew cask.
        // Wrapped iOS apps have no `Contents/` and never ship Squirrel.
        let squirrel = bundleURL.appendingPathComponent("Contents/Frameworks/Squirrel.framework")
        let hasSelfUpdater = !isiOSAppOnMac && fm.fileExists(atPath: squirrel.path)

        // For Toolbox-managed apps, show Toolbox's own `displayVersion`: the
        // on-disk `CFBundleShortVersionString` is either truncated (Android Studio
        // "2025.2" for 2025.2.3) or on a divergent track (Air reports its SHIP
        // runtime build "261.617" while Toolbox manages it as Public Preview
        // "261.474" — and the update comparison runs in the Public Preview line).
        // Aligning the display with Toolbox keeps the "from → to" coherent.
        let toolboxTool = toolbox.tool(forApp: bundleURL)
        let displayShortVersion = toolboxTool
            .map(\.displayVersion).flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.cleanedJetBrainsVersion(shortVersion, bundleID: bundleID)

        // Mozilla apps (Firefox/Thunderbird/forks) bake their channel into
        // `Contents/Resources/application.ini` as `RemotingName` (`firefox-esr`,
        // `thunderbird-beta`, …). It's the ONLY reliable channel signal for them —
        // their installed `CFBundleShortVersionString` drops the `b`/`esr` suffix
        // and Beta/ESR can share `org.mozilla.firefox` with Stable. Read it only for
        // Mozilla bundle ids to avoid an extra file probe on every other app.
        let mozillaRemotingName: String? =
            (bundleID?.hasPrefix("org.mozilla") == true)
            ? Self.mozillaRemotingName(in: bundleURL) : nil

        // Release channel (Stable/Beta/Canary/…). Chrome & other Keystone apps
        // declare it explicitly via `KSChannelID`; otherwise we infer it from the
        // bundle id suffix or a channel word in the display name. This gates
        // cross-channel updates downstream (see `ReleaseChannel`).
        var releaseChannel = ReleaseChannel.detect(
            name: displayName,
            bundleID: bundleID,
            keystoneChannel: plist["KSChannelID"] as? String,
            // Use the RAW marketing version (not the Toolbox-aligned display one)
            // so Mozilla's "153.0a1" nightly suffix can be read for channel.
            version: shortVersion,
            mozillaRemotingName: mozillaRemotingName,
            // Android Studio's only on-disk channel signal is the bundle filename
            // (Stable/Canary/Beta share id, CFBundleName, and a truncated version).
            // See `ReleaseChannel.detect` step 0.5.
            bundleFileName: bundleURL.deletingPathExtension().lastPathComponent
        )

        // Some apps hide the user's channel choice in a private preference (no
        // standard Sparkle schema). For those, read it: it gives the authoritative
        // channel and, for feed-swap apps, the channel's feed — otherwise e.g. a
        // Fork Stable user would be checked against the Developer feed and offered
        // a beta build. See `ChannelBinding`.
        var channelIsAuthoritative = false
        var feedHeaders: [String: String] = [:]
        if let bound = ChannelBinding.resolve(bundleID: bundleID) {
            releaseChannel = bound.channel
            channelIsAuthoritative = true
            if let feed = bound.feedOverride { feedURL = feed }
            feedHeaders = bound.feedHTTPHeaders
        }

        return InstalledApp(
            name: displayName,
            bundleID: bundleID,
            shortVersion: displayShortVersion,
            buildVersion: buildVersion,
            path: bundleURL,
            isMASApp: isMAS,
            isiOSAppOnMac: isiOSAppOnMac,
            isToolboxManaged: toolbox.isManaged(appPath: bundleURL),
            isTestFlightApp: isTestFlight,
            sparkleFeedURL: feedURL,
            sparkleFeedHeaders: feedHeaders,
            sparkleEdPublicKey: (plist["SUPublicEDKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            hasSelfUpdater: hasSelfUpdater,
            releaseChannel: releaseChannel,
            channelIsAuthoritative: channelIsAuthoritative
        )
    }

    /// JetBrains EAP bundles report a noisy `CFBundleShortVersionString` —
    /// "EAP IU-262.6653.22" (literally "EAP " + the `CFBundleVersion`). While Toolbox
    /// manages the app we show its clean "2026.2" instead; but with Toolbox absent
    /// (a website install, or Toolbox uninstalled) that fallback is gone, so reduce
    /// the raw string to the bare build ("262.6653.22") rather than surfacing the
    /// noise. Only rewrites JetBrains strings of that exact shape — a clean stable
    /// "2026.1.3" (no "EAP "/product-code prefix) passes through untouched.
    static func cleanedJetBrainsVersion(_ raw: String, bundleID: String?) -> String {
        guard bundleID?.hasPrefix("com.jetbrains.") == true else { return raw }
        var s = raw
        if s.hasPrefix("EAP ") { s.removeFirst(4) }
        if let dash = s.firstIndex(of: "-"), dash != s.startIndex,
           s[..<dash].allSatisfy(\.isLetter) {
            s = String(s[s.index(after: dash)...])
        }
        return s
    }

    /// The `RemotingName` from a Mozilla app's `Contents/Resources/application.ini`
    /// (`firefox-esr`, `thunderbird-beta`, `firefox`, …) — the authoritative
    /// channel marker. `application.ini` is a small INI file; we scan it for the
    /// `RemotingName=` line rather than pulling in a parser. Nil when absent.
    public static func mozillaRemotingName(in bundleURL: URL) -> String? {
        let iniURL = bundleURL.appendingPathComponent("Contents/Resources/application.ini")
        guard let text = try? String(contentsOf: iniURL, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            if line[..<eq].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("RemotingName")
                == .orderedSame {
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
