import Foundation

enum io_nekohasekai_screensharing {
    static let set = AppRecipeSet(
        family: "io-nekohasekai-screensharing",
        githubRules: [
        // Open Screen Sharing (nekohasekai/open-screen-sharing, Team P8XK3KHB48)
        // — installs as `/Applications/Screen Sharing.app`. The app's own
        // updater (`OpenScreenSharing/Update/UpdateChecker.swift`) reads
        // `/releases/latest` for its stable track, so this rule reads the same.
        //
        // The release asset is a component pkg with no scripts: `PackageInfo`
        // declares `./Screen Sharing.app` (this bundle id) under
        // `install-location="/Applications"`, so it takes the system-installer
        // route XQuartz uses. The release also carries an iOS `.ipa`, an
        // AltStore source and `metadata.json`; the asset pattern is the exact pkg
        // name.
        //
        // The nightly track (a prerelease under the fixed tag `nightly`, ordered
        // by `metadata.json`'s build number, marketing version unchanged) is not
        // wired: see the audit. A nightly copy is read as stable here, and that
        // never downgrades it — its marketing version is never behind the latest
        // stable release, which is a copy of an earlier nightly.
        GitHubReleaseRule(
            bundleID: "io.nekohasekai.screensharing",
            owner: "nekohasekai", repo: "open-screen-sharing",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenScreenSharing\.pkg$"#,
            installerKind: .pkg),
        ])
}
