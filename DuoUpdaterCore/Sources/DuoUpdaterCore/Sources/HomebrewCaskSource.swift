import Foundation

/// Update source for apps Homebrew actually installed. Matches the installed
/// bundle to a Homebrew cask by its `.app` filename (falling back to bundle
/// identifier for `pkg` casks that declare no `.app` artifact), then — crucially
/// — only resolves when that cask is present in the local Caskroom.
///
/// The catalog match alone is not enough: many apps share a filename with a cask
/// but were installed straight from the vendor or the App Store. Updating those
/// through `brew` would mix distribution channels — different signing, possibly
/// different data locations — so we gate on `BrewLocalInventory` (provenance).
/// Apps that match a cask but weren't brew-installed simply fall through to the
/// next source (and, lacking one, end up "unknown" until a vendor rule covers
/// them) rather than being silently adopted by Homebrew.
public struct HomebrewCaskSource: UpdateSource {
    public let name = "Homebrew"

    private let catalog: HomebrewCaskCatalog
    private let inventory: BrewLocalInventory

    public init(
        catalog: HomebrewCaskCatalog = .shared,
        inventory: BrewLocalInventory = BrewLocalInventory()
    ) {
        self.catalog = catalog
        self.inventory = inventory
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // App Store apps are managed by the store; a same-named/-id cask is a
        // different distribution channel (often with an unrelated version
        // scheme), so never resolve a MAS app to Homebrew.
        guard !app.isMASApp else { return nil }

        // Nothing in the Caskroom → the provenance gate below can never pass, so
        // decline before pulling the 5 MB catalog over the network.
        guard !inventory.isEmpty else { return nil }

        let filename = app.path.lastPathComponent  // e.g. "TablePlus.app"
        var match = try await catalog.entry(forAppFilename: filename)
        if match == nil, let bundleID = app.bundleID {
            match = try await catalog.entry(forBundleID: bundleID)
        }
        guard let entry = match else { return nil }

        // Provenance gate: only adopt this app if Homebrew actually installed the
        // matched cask here. A filename/id collision with an uninstalled cask is
        // not ours to update.
        guard inventory.isInstalled(caskToken: entry.token) else { return nil }

        // Self-updating gate: an `auto_updates` cask delegates updates to the app's
        // own updater — brew is NOT its update channel, and the cask version
        // routinely LAGS what the app self-installed (Postman: cask 12.12.6 while
        // the running app was already 12.12.7). Offering `brew upgrade` here is
        // wrong twice over: it compares against a stale version, and a
        // `brew install --cask --force` re-adopts an app that updates itself —
        // exactly how a vendor-installed Postman got pulled into brew to begin
        // with. Defer like any self-updater (same spirit as `hasSelfUpdater`):
        // return nil so the app falls through to its real channel (or "unknown"),
        // never to a brew-managed row. So a brew-installed-but-self-updating app
        // is deliberately NOT classified as Homebrew.
        guard !entry.autoUpdates else { return nil }

        // Cask versions are sometimes "version,revision" or "version:build";
        // use the leading marketing portion for comparison/display. Split on BOTH
        // separators — keying only on "," left the ":build" form (e.g. "1.2.3:456")
        // intact, which then mis-compares against the bare installed "1.2.3" and can
        // surface a spurious update.
        let marketing = entry.version
            .split(whereSeparator: { $0 == "," || $0 == ":" }).first
            .map(String.init) ?? entry.version

        return RemoteVersion(
            shortVersion: marketing,
            version: nil,
            downloadURL: entry.url,
            // `entry.url` is the cask's artifact (a dmg/pkg on the vendor's CDN),
            // so the user-facing page is the cask's own listing instead.
            pageURL: URL(string: "https://formulae.brew.sh/cask/\(entry.token)"),
            sourceName: name,
            sourceIdentifier: entry.token,
            requiresManualInstaller: entry.isPkg
        )
    }
}
