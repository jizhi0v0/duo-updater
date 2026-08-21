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

    /// Fold a completed TestFlight inventory into apps that were already scanned.
    ///
    /// The inventory read can block on macOS's app-data privacy prompt, so the app
    /// intentionally scans first with an empty inventory. Once the read succeeds we
    /// only need to correct store provenance: every other field came from the same
    /// bundle and is independent of TestFlight. Rebuilding those fields here avoids
    /// a second full directory/plist/receipt/channel scan.
    /// True when `InstalledApp.buildVersion` for this app is not its `CFBundleVersion`.
    ///
    /// Xcode is the only case: its published build (`27A5237l`) lives in
    /// `version.plist`, and that is the number worth showing, so the scan stores it
    /// in place of the bundle's own. Anything keyed on the raw build — TestFlight's
    /// database is — has to know that and not use the stored value.
    static func buildVersionIsOverridden(bundleID: String?) -> Bool {
        bundleID == "com.apple.dt.Xcode"
    }

    public static func applyingTestFlightInventory(
        _ inventory: TestFlightInventory,
        to apps: [InstalledApp]
    ) -> [InstalledApp] {
        apps.map { app in
            // TestFlight's database is keyed on the raw `CFBundleVersion`, which is
            // what `readApp` matched against. `InstalledApp.buildVersion` is not
            // always that value — where a build is overridden it carries the number
            // the user should see instead, and asking the database with it would be
            // asking a different question than the scan asked. Nothing overridden is
            // distributed through TestFlight today, so this declines rather than
            // guessing; the raw value is not recoverable from an already-scanned app.
            let matchable = !Self.buildVersionIsOverridden(bundleID: app.bundleID)
            let isTestFlight = app.isTestFlightApp || (matchable && inventory.isManaged(
                bundleID: app.bundleID, installedBuild: app.buildVersion))
            guard isTestFlight, !app.isTestFlightApp else { return app }

            return InstalledApp(
                name: app.name,
                bundleID: app.bundleID,
                shortVersion: app.shortVersion,
                buildVersion: app.buildVersion,
                path: app.path,
                isMASApp: false,
                isiOSAppOnMac: app.isiOSAppOnMac,
                isToolboxManaged: app.isToolboxManaged,
                isTestFlightApp: true,
                sparkleFeedURL: app.sparkleFeedURL,
                sparkleFeedHeaders: app.sparkleFeedHeaders,
                sparkleEdPublicKey: app.sparkleEdPublicKey,
                hasSelfUpdater: app.hasSelfUpdater,
                releaseChannel: app.releaseChannel,
                channelIsAuthoritative: app.channelIsAuthoritative,
                toolboxInstalledBuild: app.toolboxInstalledBuild,
                // A receipt-backed app already paid this Spotlight read in the first
                // scan. The fallback covers a DB-matched bundle with no receipt.
                appStoreAdamID: app.appStoreAdamID ?? appStoreAdamID(app.path)
            )
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
        guard let rawShortVersion = (plist["CFBundleShortVersionString"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawShortVersion.isEmpty
        else { return nil }
        var shortVersion = rawShortVersion

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
        var bundleID = plist["CFBundleIdentifier"] as? String
        /// Set only for WeChat DevTools, from its `package.json` (see below).
        var weChatDevToolsChannel: ReleaseChannel?
        let buildVersion = plist["CFBundleVersion"] as? String
        if bundleID == Self.duoUpdaterBundleID { return nil }

        // WeChat DevTools (微信开发者工具) keeps its real identity OUT of Info.plist.
        // Its 2.02 rewrite moved from NW.js to Electron and shipped Electron's stock
        // plist verbatim: every 2.02 build — Stable, RC and Nightly alike — reports
        // `com.github.Electron` and version `36.6.0` (the Electron runtime version,
        // not the tool's). 2.01 at least had `com.tencent.webplusdevtools`, but its
        // own version lives in a different file too. Both the true version
        // ("2.02.2608040") and the channel (`versionType`) sit in the app's bundled
        // `package.json`, the same file the app itself reads — so we read it and
        // file the app under the id its INSTALLER declares
        // (`com.tencent.wechatdevtools`), which is stable across both eras and,
        // unlike `com.github.Electron`, cannot collide with any other Electron app
        // whose vendor was equally careless. Keying the recipes on the stock id
        // instead would make every such app a candidate for WeChat's installer.
        //
        // Scoped to the two known ids plus the bundle name so no other app pays a
        // file probe; the `package.json`'s own `appname` is what actually confirms
        // the match.
        if bundleID == Self.weChatDevToolsElectronBundleID
            || bundleID == Self.weChatDevToolsLegacyBundleID
            || (plist["CFBundleName"] as? String) == Self.weChatDevToolsAppName,
           let identity = Self.weChatDevToolsIdentity(in: bundleURL) {
            bundleID = Self.weChatDevToolsBundleID
            shortVersion = identity.version
            weChatDevToolsChannel = identity.channel
        }
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
        // Xcode's published build (`27A5237l`), which is neither `CFBundleVersion`
        // nor `DTXcodeBuild` — see `effectiveBuildVersion`. nil for everything else.
        let xcodeBuild = Self.buildVersionIsOverridden(bundleID: bundleID)
            ? Self.productBuildVersion(in: bundleURL) : nil

        let toolboxTool = toolbox.tool(forApp: bundleURL)
        let displayShortVersion: String = {
            // Two Xcodes side by side are indistinguishable by marketing version —
            // 27.0 beta 1, 27.0 beta 5 and eventually 27.0 release all say "27.0",
            // and they share a bundle id and a CFBundleName too. The build is the
            // only thing that separates them without asking the network, so it rides
            // along in the row: "27.0 (27A5194q)".
            if let xcodeBuild { return "\(shortVersion) (\(xcodeBuild))" }
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
        // WeChat DevTools states its channel outright in its own `package.json`
        // (`versionType`), which beats every heuristic `detect` has: the three
        // channels share one bundle id, one app name, and a version string with no
        // channel token in it, so nothing else on disk could tell them apart.
        if let channel = weChatDevToolsChannel {
            releaseChannel = channel
            channelIsAuthoritative = true
        }
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
            buildVersion: xcodeBuild ?? buildVersion,
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
    /// Xcode is why `CFBundleVersion` isn't always the build to compare on: its
    /// `CFBundleVersion` is an internal serial (`25183.74.15`) and its `DTXcodeBuild`
    /// (`27A5237k`) is a *different* string again — neither is what Apple publishes.
    /// The published build lives in `Contents/version.plist` as `ProductBuildVersion`
    /// (`27A5237l`), which is also what `xcodebuild -version` prints. Verified on two
    /// installed copies: only `ProductBuildVersion` matched the released beta 1 /
    /// beta 5 builds, so comparing on either of the others would mean a permanent
    /// phantom update.
    /// `ProductBuildVersion` from an app's `Contents/version.plist`, if it has one.
    static func productBuildVersion(in bundleURL: URL) -> String? {
        let url = bundleURL.appendingPathComponent("Contents/version.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let build = (plist["ProductBuildVersion"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !build.isEmpty
        else { return nil }
        return build
    }

    // MARK: - WeChat DevTools identity

    /// Stock Electron bundle id, which WeChat DevTools 2.02+ ships unchanged.
    static let weChatDevToolsElectronBundleID = "com.github.Electron"
    /// The bundle id the 2.01 (NW.js) generation carried.
    static let weChatDevToolsLegacyBundleID = "com.tencent.webplusdevtools"
    /// `CFBundleName` — the one Info.plist field that survived both generations.
    static let weChatDevToolsAppName = "wechatwebdevtools"
    /// The id we file the app under: what its pkg declares
    /// (`PackageInfo identifier="com.tencent.wechatdevtools"`, identical across all
    /// three channels). Unlike `com.github.Electron` it names this product only.
    public static let weChatDevToolsBundleID = "com.tencent.wechatdevtools"

    /// The real version and channel of a WeChat DevTools install.
    public struct WeChatDevToolsIdentity: Sendable, Hashable {
        public let version: String
        public let channel: ReleaseChannel
    }

    /// Read WeChat DevTools' real version + channel out of the `package.json` the
    /// app itself runs on, or nil when this bundle isn't WeChat DevTools (or is a
    /// build whose channel we don't recognize).
    ///
    /// Two locations, because the 2.02 Electron rewrite moved the file:
    /// `Contents/Resources/app.asar.unpacked/package.json` (2.02+) and
    /// `Contents/Resources/package.nw/package.json` (2.01, NW.js). Both carry the
    /// same fields; the `appname` is checked so a stray `package.json` from some
    /// other Electron app can never be read as this one.
    ///
    /// `versionType` is the vendor's own channel enum — `"0"` Stable, `"1"` RC
    /// (预发布版), `"2"` Nightly (开发版) — verified on four real bundles on
    /// 2026-08-18 (installed 2.01.2510290, and the 2.02.2608031 / 2.02.2608040 /
    /// 2.02.2608182 pkg payloads). It is a STRING in every build seen; a number is
    /// accepted too rather than betting on the vendor never changing that.
    /// `window.title` ("… Stable v2.02.2608040") carries the same fact and is the
    /// fallback. An unrecognized value returns nil for the WHOLE identity — the app
    /// then stays on its stock id, matches no recipe, and shows "unknown", which is
    /// the right failure: guessing `.stable` for an unknown future channel is how a
    /// cross-channel install happens.
    public static func weChatDevToolsIdentity(in bundleURL: URL) -> WeChatDevToolsIdentity? {
        let candidates = [
            "Contents/Resources/app.asar.unpacked/package.json",  // 2.02+ (Electron)
            "Contents/Resources/package.nw/package.json",         // 2.01 (NW.js)
        ]
        for relativePath in candidates {
            let url = bundleURL.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard let identity = weChatDevToolsIdentity(fromPackageJSON: json) else { continue }
            return identity
        }
        return nil
    }

    /// The pure half of `weChatDevToolsIdentity(in:)` — decoding one parsed
    /// `package.json`. Split out so it can be unit-tested without a real bundle.
    static func weChatDevToolsIdentity(
        fromPackageJSON json: [String: Any]
    ) -> WeChatDevToolsIdentity? {
        guard (json["appname"] as? String) == weChatDevToolsAppName
                || (json["product_string"] as? String) == weChatDevToolsAppName
        else { return nil }
        guard let version = (json["version"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty
        else { return nil }

        let rawType = (json["versionType"] as? String)
            ?? (json["versionType"] as? NSNumber)?.stringValue
        let title = (json["window"] as? [String: Any])?["title"] as? String
        guard let channel = weChatDevToolsChannel(versionType: rawType, windowTitle: title)
        else { return nil }
        return WeChatDevToolsIdentity(version: version, channel: channel)
    }

    /// Map WeChat DevTools' `versionType` to a channel, falling back to the
    /// Stable/RC/Nightly word in the window title when the field is missing.
    static func weChatDevToolsChannel(
        versionType: String?, windowTitle: String?
    ) -> ReleaseChannel? {
        switch versionType?.trimmingCharacters(in: .whitespaces) {
        case "0": return .stable
        case "1": return .rc
        case "2": return .nightly
        case .some(let other) where !other.isEmpty:
            // A value the vendor added since — don't guess it into an existing
            // channel; the title fallback below can't disambiguate it either.
            return nil
        default: break
        }
        guard let title = windowTitle?.lowercased() else { return nil }
        if title.contains(" nightly ") { return .nightly }
        if title.contains(" rc ") { return .rc }
        if title.contains(" stable ") { return .stable }
        return nil
    }

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
