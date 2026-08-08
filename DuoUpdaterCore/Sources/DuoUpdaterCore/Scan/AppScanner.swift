import Foundation
import CoreServices

/// Discovers installed `.app` bundles and reads the Info.plist metadata we
/// need for update checks. Pure filesystem work — no network, no UI.
public struct AppScanner: Sendable {
    /// DuoUpdater updates itself through Sparkle now, via an app-level "Check for
    /// Updates…" flow. Keeping it in the generic scanned-app list creates a
    /// second, conflicting surface ("Restart", "Update") driven by filesystem /
    /// LaunchServices heuristics that were never meant for the host app itself.
    /// Exclude it from the managed-app inventory entirely.
    private static let duoUpdaterBundleID = "com.duoupdater.app"

    /// Directories we look in. We deliberately skip `/System/Applications`:
    /// those ship with macOS and are updated by Software Update, not us.
    public let locations: [URL]

    /// The built-in scan roots. Exposed `static` so the UI can show what's already
    /// covered (and dedupe user-added folders against it) and the FS watcher can
    /// watch the same set, without duplicating the list.
    ///
    /// We deliberately skip `/System/Applications`. Input methods install as `.app`
    /// bundles OUTSIDE `/Applications` — a separate OS class (`/Library/Input
    /// Methods`, system-wide, root-owned; the per-user `~/Library/Input Methods`).
    /// They carry a normal Info.plist with a version, so the same `readApp` filter
    /// applies; we scan them so an IME like WeType (微信输入法) can be version-checked
    /// via its VendorProbe recipe. Sourceless IMEs fall to "unknown" like any other
    /// app without a feed — acceptable noise for the coverage.
    public static var defaultLocations: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true),
            home.appendingPathComponent("Library/Input Methods", isDirectory: true)
        ]
    }

    /// Which apps JetBrains Toolbox manages — read once per scan from its
    /// `state.json` so we can tag installs as Toolbox-managed.
    private let toolbox: ToolboxInventory

    /// TestFlight's macOS builds — read once per scan from its local DB so we can
    /// tag installs as TestFlight-managed (and keep them out of the MAS path).
    private let testflight: TestFlightInventory

    /// - extraLocations: user-added folders appended to the built-in roots (see
    ///   `Preferences.customScanPaths`). Each should be a directory that *contains*
    ///   `.app` bundles, so apps installed outside the standard locations — a
    ///   developer build folder, a third-party tool dir — get version-checked too.
    public init(
        locations: [URL]? = nil,
        extraLocations: [URL] = [],
        toolbox: ToolboxInventory = ToolboxInventory(),
        testflight: TestFlightInventory = TestFlightInventory()
    ) {
        self.toolbox = toolbox
        self.testflight = testflight
        self.locations = (locations ?? Self.defaultLocations) + extraLocations
    }

    /// Strip invisible bidi / zero-width formatting marks that some bundles embed in
    /// their display name (e.g. WhatsApp's leading U+200E LEFT-TO-RIGHT MARK). These
    /// are presentational only — they never belong to the logical name and break any
    /// literal comparison against the same name rendered without them. We remove the
    /// specific bidi controls and zero-width spaces, deliberately leaving ZERO WIDTH
    /// JOINER (U+200D) alone so emoji / Indic-script names keep rendering correctly,
    /// then trim surrounding whitespace.
    static func stripInvisibleMarks(_ name: String) -> String {
        let marks: Set<Unicode.Scalar> = [
            "\u{200B}",  // ZERO WIDTH SPACE
            "\u{200E}", "\u{200F}",                          // LRM / RLM
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",  // bidi embeddings/overrides
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",  // bidi isolates
            "\u{FEFF}"   // ZERO WIDTH NO-BREAK SPACE (BOM)
        ]
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { !marks.contains($0) }))
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Mac App Store receipt environment for a bundle, from Spotlight metadata
    /// (`kMDItemAppStoreReceiptType`): "Production" for a store purchase,
    /// "ProductionSandbox" for a TestFlight build. Returns nil when Spotlight has
    /// no value (indexing off / not yet indexed), so the caller can fall back to
    /// the TestFlight DB rather than mis-tagging.
    static func appStoreReceiptType(_ bundleURL: URL) -> String? {
        guard let item = MDItemCreate(nil, bundleURL.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, "kMDItemAppStoreReceiptType" as CFString) as? String
    }

    /// The App Store track id (`kMDItemAppStoreAdamID`) Spotlight has indexed for
    /// a store-installed bundle, used to deep-link to the product page. Returns
    /// nil when absent or zero (sideloaded copies report 0).
    static func appStoreAdamID(_ bundleURL: URL) -> Int? {
        guard let item = MDItemCreate(nil, bundleURL.path as CFString),
              let id = (MDItemCopyAttribute(item, "kMDItemAppStoreAdamID" as CFString) as? NSNumber)?.intValue,
              id != 0 else { return nil }
        return id
    }

    /// Sidecar copies of an app that sit next to the real bundle: the timestamped
    /// backups an app's OWN updater leaves behind (DuoPaste writes
    /// `DuoPaste.backup-20260716-183428.app` beside `DuoPaste.app` on every
    /// self-update), Finder duplicates, and hand-renamed `.old` spares.
    ///
    /// These are complete bundles — real Info.plist, real marketing version, same
    /// bundle id — so nothing else in `readApp` filters them out. Left in, each one
    /// becomes its own row offering its own "Update" button, which is both noise
    /// (three identical DuoPaste rows) and a hazard: installing into
    /// `DuoPaste.backup-….app` would write a fresh build to a dead path and breed
    /// yet more zombie copies. Match on the bundle FILENAME only — the name is what
    /// marks a copy; its contents are indistinguishable from the original.
    static func isSidecarCopy(_ bundleURL: URL) -> Bool {
        let base = bundleURL.deletingPathExtension().lastPathComponent
        // `Name.backup-<stamp>` / `Name.backup` / `Name.old` — updater and manual spares.
        if base.range(of: #"\.(backup|old)([-_.].*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // Finder duplicates: "Name copy", "Name copy 2", and the zh-Hans forms
        // ("Name 副本", "Name 的副本 2"). Anchored at the end after a separator so an
        // app legitimately named e.g. "Copy" is untouched.
        if base.range(of: #"\scopy(\s\d+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if base.range(of: #"\s(的)?副本(\s?\d+)?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Collapse byte-identical duplicate installs: the SAME app (bundle id +
    /// channel) at the SAME version (marketing + build) found in two places — e.g.
    /// a copy in `~/Applications` shadowing the one in `/Applications`.
    ///
    /// Deliberately narrow. Two installs sharing a bundle id are NOT inherently
    /// duplicates: the JetBrains-Toolbox Android Studio installs (Otter + Koala)
    /// both carry `com.google.android.studio` and both must keep their own row (see
    /// `InstalledApp.id`), as do Firefox Stable and Beta, which share
    /// `org.mozilla.firefox` and are told apart only by channel. Requiring an exact
    /// version match too means those all survive, while a true clone — nothing to
    /// distinguish it but its path — folds into one row. First one wins, so scan
    /// order (`/Applications` before `~/Applications`) decides the keeper.
    static func dedupeIdenticalInstalls(_ apps: [InstalledApp]) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { app in
            guard let bundleID = app.bundleID else { return true }
            let key = [
                bundleID, app.releaseChannel.rawValue,
                app.shortVersion ?? "", app.buildVersion ?? ""
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    /// Scan all configured locations and return the apps found, sorted by name.
    public func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        var skippedSidecars = 0

        for dir in locations {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                // A backup/duplicate bundle parked next to the real app — same id,
                // same everything, just a dead path. Checked on the ORIGINAL entry
                // name (pre-symlink-resolution): that's the name that marks it.
                if Self.isSidecarCopy(entry) {
                    skippedSidecars += 1
                    continue
                }
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

        apps = Self.dedupeIdenticalInstalls(apps)
        if skippedSidecars > 0 {
            Log.scan.info("skipped \(skippedSidecars, privacy: .public) sidecar backup/duplicate bundle(s)")
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

        // Some bundles wrap their display name in invisible bidi/zero-width marks —
        // WhatsApp's `CFBundleDisplayName` is "\u{200E}WhatsApp" (a leading LEFT-TO-RIGHT
        // MARK) so the name renders LTR regardless of locale. Those marks are purely
        // presentational and never part of the logical name, yet they poison every
        // literal comparison against text rendered *without* them — most visibly the
        // App Store AX updater's `pageMentions`/row matching, which then "can't find the
        // update button". Strip them so the canonical name matches everywhere.
        let displayName = Self.stripInvisibleMarks(
            (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        )

        // Wrapped iOS apps can only come from the Mac App Store; native Mac apps
        // carry a `_MASReceipt` when bought there. TestFlight builds ALSO carry a
        // `_MASReceipt`, so we must decide TestFlight first and exclude it from the
        // MAS flag — else a TestFlight app would be checked against the App Store's
        // stable track. Wrapped iOS apps have no `Contents/` — their MAS provenance
        // is implied by the wrapper itself, so we never look for a
        // `Contents/_MASReceipt` there (that path can't exist).
        let bundleID = plist["CFBundleIdentifier"] as? String
        let buildVersion = plist["CFBundleVersion"] as? String
        if bundleID == Self.duoUpdaterBundleID { return nil }
        let hasReceipt = !isiOSAppOnMac && fm.fileExists(
            atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        // Primary TestFlight signal: the receipt ENVIRONMENT. A TestFlight build
        // carries a sandbox receipt ("ProductionSandbox"); an App Store purchase a
        // "Production" one. Unlike matching the installed build against TestFlight's
        // cached DB, this is local and never stale — it still recognizes a
        // TestFlight install whose build has OUTRUN the DB (Paste on 18771 while the
        // DB still lists 18655 → the old DB-only check fell through to the MAS path
        // and got compared against the App Store stable track). It also cleanly
        // distinguishes a TestFlight copy from an App Store copy of an app the user
        // merely has TestFlight access to. Fall back to the DB match when the type
        // is unreadable (e.g. Spotlight indexing off).
        let isTestFlight =
            (hasReceipt && Self.appStoreReceiptType(bundleURL) == "ProductionSandbox")
            || testflight.isManaged(bundleID: bundleID, installedBuild: buildVersion)
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
        //
        // EXCEPT Air/Fleet (no product code): their update is checked against the
        // Sparkle feed in a 3-part BUILD namespace and the latest surfaces as a raw
        // build (262.43.17). Showing the marketing `displayVersion` ("262.43 Public
        // Preview" → "262.43") there makes the row read "262.43 → 262.43.17" — the
        // installed patch (.15) vanishes and .17 reads as appended. Show the
        // installed BUILD (262.43.15, from Toolbox `state.json`, already in the feed
        // namespace) so from→to stay in one namespace: "262.43.15 → 262.43.17".
        let toolboxTool = toolbox.tool(forApp: bundleURL)
        let displayShortVersion: String = {
            guard let tool = toolboxTool else {
                return Self.cleanedJetBrainsVersion(shortVersion, bundleID: bundleID)
            }
            if tool.productCode == nil, !tool.installedBuild.isEmpty {
                return tool.installedBuild
            }
            return tool.displayVersion.isEmpty
                ? Self.cleanedJetBrainsVersion(shortVersion, bundleID: bundleID)
                : tool.displayVersion
        }()

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
            channelIsAuthoritative: channelIsAuthoritative,
            toolboxInstalledBuild: toolboxTool.flatMap {
                $0.installedBuild.isEmpty ? nil : $0.installedBuild
            },
            // Only store-installed bundles carry an adamID; skip the metadata
            // read for everything else.
            appStoreAdamID: (isMAS || isTestFlight) ? Self.appStoreAdamID(bundleURL) : nil
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
