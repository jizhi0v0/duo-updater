import Foundation

/// Fallback source for apps with no Sparkle feed and not from the App Store.
/// Matches the installed bundle to a Homebrew cask by its `.app` filename,
/// falling back to bundle identifier for casks that install via `pkg` (and so
/// declare no `.app` artifact), then reports the cask's version.
public struct HomebrewCaskSource: UpdateSource {
    public let name = "Homebrew"

    private let catalog: HomebrewCaskCatalog

    public init(catalog: HomebrewCaskCatalog = .shared) {
        self.catalog = catalog
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // App Store apps are managed by the store; a same-named/-id cask is a
        // different distribution channel (often with an unrelated version
        // scheme), so never resolve a MAS app to Homebrew.
        guard !app.isMASApp else { return nil }

        let filename = app.path.lastPathComponent  // e.g. "TablePlus.app"
        var match = try await catalog.entry(forAppFilename: filename)
        if match == nil, let bundleID = app.bundleID {
            match = try await catalog.entry(forBundleID: bundleID)
        }
        guard let entry = match else { return nil }

        // Cask versions are sometimes "version,revision" or "version:build";
        // use the leading marketing portion for comparison/display.
        let marketing = entry.version
            .split(separator: ",").first
            .map(String.init) ?? entry.version

        return RemoteVersion(
            shortVersion: marketing,
            version: nil,
            downloadURL: entry.url,
            sourceName: name,
            sourceIdentifier: entry.token,
            requiresManualInstaller: entry.isPkg
        )
    }
}
