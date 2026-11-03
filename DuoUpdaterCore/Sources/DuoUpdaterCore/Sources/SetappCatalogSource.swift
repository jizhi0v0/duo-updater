import Foundation

/// Answers for a copy Setapp manages, from Setapp's own catalogue instead of the
/// vendor's feed.
///
/// **The bug this closes.** Setapp builds keep the vendor's `SUFeedURL` even
/// though they ship no Sparkle at all (measured: AlDente Pro 1.40.1 from Setapp
/// has no `Sparkle.framework`, no `SPUUpdater` symbols, and a dead `SUFeedURL`
/// pointing at the vendor's direct appcast). `SparkleAppcastSource` reads that
/// key, offered the direct 1.40.1 DMG, and the install refused at gate 4 with
/// "Bundle identifier mismatch: installed …aldente-pro-setapp vs downloaded
/// …aldente-pro". Before 0.5.18 Setapp copies were invisible; the one-folder-deep
/// scan (#1763) made `/Applications/Setapp/…` visible and the mismatch reachable.
///
/// Answering for every `…-setapp` copy — including ones the catalogue does not
/// list — is the point: the vendor's feed must never be the fallback for an app
/// whose channel is Setapp.
///
/// **What it deliberately does not do is install.** Setapp owns that flow: its
/// agent downloads and swaps the bundle, shows its own progress and cancel, and
/// asks for the account's entitlement. Measured 2026-11-03: `setapp://install/<uid>`
/// is rejected by the agent ("URL is not a valid install-from-URL link"); the
/// valid uuid form (`setapp://install?app_id=<public_id>`) opens the app's page and,
/// for an installed copy, only offers to open it. So the row offers the page, and
/// the MCP `install_app` tool that could trigger an install is behind a GrowthBook
/// flag (`PLATECO-12287`, false in production) we cannot rely on.
public struct SetappCatalogSource: UpdateSource {

    public var name: String { "Setapp" }

    public var answersAppStoreCopies: Bool { false }

    let releases: @Sendable () async throws -> [String: SetappRelease]
    let subscription: @Sendable () -> SetappSubscription.State?
    let now: @Sendable () -> Date
    /// The macOS the compatibility check runs against. Injected so a test can
    /// put this Mac below a release's floor without owning a second Mac.
    let osVersion: @Sendable () -> String

    public init(
        releases: @escaping @Sendable () async throws -> [String: SetappRelease] = {
            try await SetappCatalog.releases()
        },
        subscription: @escaping @Sendable () -> SetappSubscription.State? = {
            SetappSubscription.current()
        },
        now: @escaping @Sendable () -> Date = { Date() },
        osVersion: @escaping @Sendable () -> String = { HostOS.numericVersion() }
    ) {
        self.releases = releases
        self.subscription = subscription
        self.now = now
        self.osVersion = osVersion
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard Self.plausiblySetapp(app) else { return nil }

        let bundleID = app.bundleID?.lowercased()
        // Throws on a real failure. Ownership is what keeps this from falling
        // through to the vendor feed: `UpdateChecker` asks this source alone for
        // a `…-setapp` copy, so the failure becomes the row's error (and a
        // retryable one) rather than Sparkle's answer.
        let catalogue = try await releases()

        if let bundleID, let release = catalogue[bundleID] {
            guard let version = release.newestCompatible(osVersion: osVersion()) else {
                // Every published release needs a newer macOS than this one. Still
                // a Setapp copy, still not the vendor's to answer for.
                Log.source.notice(
                    "setapp: \(bundleID, privacy: .public) — no published release runs on macOS \(osVersion(), privacy: .public); answering as installed")
                return Self.asInstalled(app, name: name)
            }
            return answer(for: app, release: release, version: version)
        }

        // Not in the catalogue. A `-setapp` copy still answers — as installed —
        // rather than nil: nil hands the row to `SparkleAppcastSource`, which is
        // exactly the wrong-channel offer this source exists to stop. A copy
        // that is only *plausibly* Setapp (folder or public key) and not in the
        // catalogue falls through to the other sources.
        guard let bundleID, bundleID.hasSuffix("-setapp") else { return nil }
        Log.source.notice(
            "setapp: \(bundleID, privacy: .public) is not in the catalogue; answering as installed so the vendor feed cannot step in")
        return Self.asInstalled(app, name: name)
    }

    /// The answer that stops the chain without offering anything: the copy is
    /// Setapp's, the channel cannot say a newer version runs here.
    static func asInstalled(_ app: InstalledApp, name: String) -> RemoteVersion {
        RemoteVersion(
            shortVersion: app.shortVersion,
            version: app.buildVersion,
            marketingMatchesBundle: true,
            downloadURL: nil,
            sourceName: name)
    }

    /// One app against one catalogue release: an offer when the subscription
    /// holds, a named-but-locked hold when it does not.
    private func answer(
        for app: InstalledApp, release: SetappRelease, version: SetappVersion
    ) -> RemoteVersion {
        let newer = Self.isNewer(version, than: app)
        let state = subscription()
        let active = state?.isActive(now: now()) ?? false

        guard active else {
            // Show the version Setapp ships, but not as an offer: after the
            // subscription ends Setapp stops delivering (and the apps stop
            // opening), so an Update button would promise something nothing can
            // keep. Surge and TablePlus use the same hold for the same reason.
            guard newer else { return offer(release, version: version) }
            Log.source.notice(
                "setapp: \(release.bundleID, privacy: .public) — \(version.shortVersion ?? "?", privacy: .public) withheld: the subscription is not active")
            return RemoteVersion(
                shortVersion: app.shortVersion,
                version: app.buildVersion,
                marketingMatchesBundle: true,
                downloadURL: nil,
                pageURL: Self.deepLink(for: release) ?? release.pageURL,
                sourceName: name,
                subscriptionHold: SubscriptionHold(
                    version: version.shortVersion ?? version.build ?? "?",
                    coveredBefore: state?.expiresAt,
                    recovery: .setappAccount))
        }

        return offer(release, version: version)
    }

    /// `marketingMatchesBundle` is stated because the catalogue's
    /// `marketing_version` IS the Setapp build's `CFBundleShortVersionString`
    /// (measured on AlDente Pro 1.40.1: both 1.40.1), which is what lets the
    /// checker refuse a build that would walk the marketing number backwards.
    private func offer(_ release: SetappRelease, version: SetappVersion) -> RemoteVersion {
        RemoteVersion(
            shortVersion: version.shortVersion,
            version: version.build,
            marketingMatchesBundle: true,
            downloadURL: nil,
            pageURL: Self.deepLink(for: release) ?? release.pageURL,
            minimumSystemVersion: version.minimumSystemVersion,
            sourceName: name)
    }

    /// `setapp://install?app_id=<public_id>` — the uuid form is the one the
    /// agent accepts (the numeric id is rejected: "URL is not a valid
    /// install-from-URL link", measured 2026-11-03). It opens the app's page in
    /// Setapp; it does not install by itself.
    static func deepLink(for release: SetappRelease) -> URL? {
        var components = URLComponents()
        components.scheme = "setapp"
        components.host = "install"
        components.queryItems = [URLQueryItem(name: "app_id", value: release.publicID)]
        return components.url
    }

    /// Whether this copy could be one of Setapp's, without reading the catalogue.
    ///
    /// The identifier suffix is the documented mark (Setapp mandates
    /// `…-setapp`), but it is not the only evidence a copy can carry: the
    /// install root (`/Applications/Setapp`, `~/Applications/Setapp`) and the
    /// framework's own `setappPublicKey.pem` inside the bundle both say the same
    /// thing, and either can outlive a vendor that ignores the convention. The
    /// point of the gate is only to avoid fetching a 3 MB catalogue for every app
    /// on a Mac that has no Setapp at all; the catalogue lookup itself is the
    /// authority.
    static func plausiblySetapp(_ app: InstalledApp) -> Bool {
        if let id = app.bundleID?.lowercased(), id.hasSuffix("-setapp") { return true }
        if app.path.path.contains("/Setapp/") { return true }
        let publicKey = app.path.appendingPathComponent("Contents/Resources/setappPublicKey.pem")
        return FileManager.default.fileExists(atPath: publicKey.path)
    }

    /// Whether the catalogue's release is newer than the copy on disk. Build
    /// first — Setapp publishes both, and the build is the field its own client
    /// orders on — then the marketing string, then "no version at all counts as
    /// newer", the safe side every other source takes.
    static func isNewer(_ version: SetappVersion, than app: InstalledApp) -> Bool {
        if let build = version.build, let installed = app.buildVersion,
           VersionComparator.compare(build, installed) == .orderedDescending {
            return true
        }
        if let short = version.shortVersion, let installed = app.shortVersion,
           VersionComparator.compare(short, installed) == .orderedDescending {
            return true
        }
        return app.buildVersion == nil && app.shortVersion == nil
    }
}
