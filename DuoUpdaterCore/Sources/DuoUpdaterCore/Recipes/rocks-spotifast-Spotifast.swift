import Foundation

enum rocks_spotifast_Spotifast {
    static let set = AppRecipeSet(
        family: "rocks-spotifast-Spotifast",
        githubRules: [
        // Spotifast — a Rust Spotify client, formerly "Fastpotify". No SUFeedURL
        // and no Sparkle; its own updater reads this repo's releases, so the
        // GitHub release is the source. v-tags; Info.plist short == build ==
        // the tag's X.Y.Z (0.10.0, 0.11.2, 0.12.0 checked on the real dmgs).
        //
        // The rename shows in the assets: v0.8.0–v0.9.1 carry both a
        // `fastpotify-…` and a `spotifast-…` dmg (and both apps inside are
        // me.paolino.fastpotify), from v0.10.0 there is only `spotifast-…` and
        // the app is rocks.spotifast.Spotifast. The asset pattern takes the
        // `spotifast-` dmg alone, so it can never hand this id an old-id build.
        // The tag anchor keeps the `-rcN` tags out (all flagged prerelease so
        // far; the anchor is the backstop).
        //
        // Assets: `spotifast-v<ver>-macos-universal.dmg` (universal, the only
        // macOS build) beside Windows/Linux/Flatpak/AppImage and checksums.
        // One-click: rocks.spotifast.Spotifast, Team JPL7999US3, notarized.
        GitHubReleaseRule(
            bundleID: "rocks.spotifast.Spotifast",
            owner: "crmne", repo: "spotifast",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^spotifast-v[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),

        // A copy still on the pre-rename id (Fastpotify ≤ 0.9.1, same Team from
        // 0.9.1; 0.7.1 is ad-hoc signed). Detection-only on purpose: the
        // download is rocks.spotifast.Spotifast, which the bundle-id gate
        // refuses over me.paolino.fastpotify, and the vendor's notes for 0.12.0
        // say a copy on 0.9.0 or older that jumps straight to it starts with
        // fresh settings. Pointing such a copy at the release page is the
        // honest answer. (0.9.1's binary already names rocks.spotifast.Spotifast
        // and Spotifast.app, so its own updater looks built for the move; that
        // is read from strings, not run.) `variant` keeps its `recipeID` apart
        // from the rule above, which reads the same repo.
        GitHubReleaseRule(
            bundleID: "me.paolino.fastpotify",
            owner: "crmne", repo: "spotifast",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            variant: "fastpotify"),
        ])
}
