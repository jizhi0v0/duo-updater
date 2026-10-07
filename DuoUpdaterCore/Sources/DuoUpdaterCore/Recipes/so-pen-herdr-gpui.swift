import Foundation

enum so_pen_herdr_gpui {
    static let set = AppRecipeSet(
        family: "so-pen-herdr-gpui",
        githubRules: [
        // Herdr (herdr-gpui) — the Rust/GPUI desktop client for the Herdr
        // daemon. Homebrew's `herdr` is that daemon (a formula), not this app;
        // there is no cask. No Sparkle; its own updater reads `/releases/latest`
        // and the release's signed `update-manifest.json`, so the GitHub release
        // is the source.
        //
        // Date versions: tags `vYYYYMMDD.N`, and short == build == the tag
        // without `v` (20261007.1 and .2 checked on the real dmgs). No
        // prerelease in the list; the anchor is the backstop.
        //
        // Assets: `Herdr-<ver>-universal-apple-darwin.dmg` (universal) beside
        // `.crt`/`.sha256`/`.sha512`/`.sig` siblings, the updater's
        // `herdr-gpui-<ver>-macos-universal.app.tar.gz`, and Linux/Windows
        // builds. The pattern takes the dmg alone.
        // One-click: so.pen.herdr-gpui, Team VJAHQVZ96V, notarized.
        GitHubReleaseRule(
            bundleID: "so.pen.herdr-gpui",
            owner: "penso", repo: "herdr-gpui",
            versionPattern: #"^v([0-9]{8}\.[0-9]+)$"#,
            installAssetPattern: #"^Herdr-[0-9]{8}\.[0-9]+-universal-apple-darwin\.dmg$"#,
            installerKind: .dmg),
        ])
}
