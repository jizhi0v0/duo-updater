import Foundation

enum com_xbarapp_app {
    static let set = AppRecipeSet(
        family: "com-xbarapp-app",
        githubRules: [
        // xbar (matryer/xbar, Team N3H5B92L5N, notarized, universal) — a Wails
        // menu-bar app with no SUFeedURL. Its own updater (`pkg/update`) reads
        // `/releases/latest` and installs the zip, so every install follows the
        // release GitHub marks Latest; there is no second track.
        //
        // Every xbar 2.x release is tagged `vX.Y.Z-beta` and NOT flagged
        // prerelease: the `-beta` is part of the one track's name, not a
        // channel. `package.sh` stamps `git describe --tags` verbatim into
        // CFBundleShortVersionString, so the installed copy reads
        // `v2.1.7-beta`. The pattern keeps the suffix: without it the remote
        // would read `2.1.7`, which outranks `v2.1.7-beta` forever. The first
        // 2.x tag spelled it `v2.0.4.beta`, hence `[-.]`. Any other suffix
        // (`-rc.1`, `-beta.2`) is refused.
        //
        // The same repo holds BitBar's releases (`com.matryer.BitBar`, another
        // product and Team); the bundle id keeps them apart. Copies before
        // v2.0.40-beta carry a per-release bundle id (`xbar.v2.0.39-beta`) and
        // match no rule; v2.0.40–v2.0.42 are unsigned, so the gate refuses
        // their one-click. See the audit.
        GitHubReleaseRule(
            bundleID: "com.xbarapp.app",
            owner: "matryer", repo: "xbar",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+(?:[-.]beta)?)$"#,
            installAssetPattern: #"^xbar\.v[0-9][0-9A-Za-z.-]*\.dmg$"#,
            installerKind: .dmg),
        ])
}
