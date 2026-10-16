import Foundation

enum com_zettlr_app {
    static let set = AppRecipeSet(
        family: "com-zettlr-app",
        changelogs: [
        // The GitHub source already renders the release it offers; these two
        // add the previous releases to the rail, CotEditor's pair
        // (`Recipes/com-coteditor-CotEditor.swift` says why the beta one wants
        // `includesPromotedStable`: its rule can and does offer a stable release).
        ChangelogRecipe(
            bundleID: "com.zettlr.app",
            source: URL(string: "https://api.github.com/repos/Zettlr/Zettlr/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ChangelogRecipe(
            bundleID: "com.zettlr.app",
            source: URL(string: "https://api.github.com/repos/Zettlr/Zettlr/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // Zettlr (Zettlr/Zettlr, Team QS52BN8W68, notarized) — Electron Markdown
        // editor, no SUFeedURL and no app-update.yml. Its own updater
        // (`source/app/service-providers/updates/index.ts`) asks
        // zettlr.com/api/releases/latest, which answers a copy of the newest
        // GitHub release (same tag, assets, body), then downloads the dmg into
        // ~/Downloads, checks it against the release's SHA256SUMS.txt and opens
        // it for the user to drag in. It never swaps the bundle itself.
        //
        // Since 1.0.0 the bundle id is com.zettlr.app (forge `appBundleId`,
        // earlier electron-builder `appId`); Info.plist short == build == the
        // tag minus `v` (4.7.0, 4.8.0 checked on real dmgs). Prereleases are
        // `vX.Y.Z-beta[.N]` and flagged; the `$` anchor keeps them off stable
        // even if one went out unflagged. One arm64 and one x64 dmg per
        // release; the arch is left to the source's arch preference.
        //
        // One-click: Team QS52BN8W68 on 4.7.0, 4.8.0 and 4.0.0-beta.5, all
        // notarized. The four nested `Zettlr Helper*.app` are Electron's
        // GPU/renderer/plugin child processes, not agents: they exit with the app.
        GitHubReleaseRule(
            bundleID: "com.zettlr.app",
            owner: "Zettlr", repo: "Zettlr",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Zettlr-[0-9]+(?:\.[0-9]+)+-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),

        // Beta — Preferences ▸ Advanced "Notify me about beta releases", the
        // top-level `checkForBeta` in the app's config.json (`ZettlrChannel`).
        // The app sends it as `accept-beta`, and the endpoint then serves the
        // newest release with prereleases counted, stable or beta, so this rule
        // reads the list whole and takes both tag shapes. The version keeps the
        // `-beta[.N]` suffix: a beta build's Info.plist says `4.0.0-beta.5`.
        GitHubReleaseRule(
            bundleID: "com.zettlr.app",
            owner: "Zettlr", repo: "Zettlr",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-beta(?:\.[0-9]+)?)?)$"#,
            installAssetPattern:
                #"^Zettlr-[0-9]+(?:\.[0-9]+)+(?:-beta(?:\.[0-9]+)?)?-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),

        // Before 1.0.0 (2018, 0.x) the app shipped as com.zettlr.www: the real
        // 0.20.0 dmg is x86_64 only and carries no usable signature. Detection
        // only — no Team to vouch for it, and the download is a different
        // bundle id, so the user replaces it by hand once. `variant` keeps its
        // `recipeID` apart from the stable rule's on the same repo and channel.
        GitHubReleaseRule(
            bundleID: "com.zettlr.www",
            owner: "Zettlr", repo: "Zettlr",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            variant: "www"),
        ],
        githubChannelProofs: [
        // A beta copy is legitimately offered a stable release, and stable dmg
        // names carry no channel token, so an `.artifact` proof would accuse
        // the right answer. What must not drift is the request: the list read
        // whole, and `-beta` tags accepted.
        ChannelProofKey("com.zettlr.app", .beta):
            .recipeAnchor(#"^true$|\(\?:-beta"#, in: ["usePrereleases", "versionPattern"]),
        ])
}
