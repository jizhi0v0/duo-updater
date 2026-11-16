import Foundation

enum dev_nkzw_tech_codiff {
    static let set = AppRecipeSet(
        family: "dev-nkzw-tech-codiff",
        githubRules: [
        // Codiff's Electron Forge bundle has no declared Sparkle/electron-builder
        // feed. Its own updater checks this repo's latest stable release, then
        // uses Squirrel on macOS. Numeric tag suffixes are historical packaging
        // rebuilds (v0.5.0-2, v1.0.1-1), not prerelease tracks; the ZIP and bundle
        // keep the unsuffixed marketing version. Reject named prerelease suffixes.
        // The public Mac asset is a Developer ID signed arm64 ZIP.
        GitHubReleaseRule(
            bundleID: "dev.nkzw-tech.codiff",
            owner: "nkzw-tech", repo: "codiff",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)(?:-[0-9]+)?$"#,
            installAssetPattern: #"^Codiff-darwin-arm64-[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
