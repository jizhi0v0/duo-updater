import Foundation

enum com_puremac_app {
    static let set = AppRecipeSet(
        family: "com-puremac-app",
        githubRules: [
        // PureMac — a dmg and a zip of the same build ship together; take the dmg.
        // One-click: com.puremac.app, Team H3WXHVTP97, notarized.
        //
        // The tag is anchored because this repo ships a *second product* out of
        // the same releases: on 2026-08-17 it published `cli-v1.0.0`, carrying
        // only `puremac-cli-1.0.0.tar.gz`, and GitHub marks it latest. The default
        // pattern is unanchored, so it read that tag as version 1.0.0 — which,
        // against an installed 2.9.x, evaluates as "up to date" and hides every
        // real update. The macOS-asset gate already walks past that release, but
        // the number it walked past should never have parsed in the first place:
        // one guard against a silent no-update is not enough.
        GitHubReleaseRule(
            bundleID: "com.puremac.app",
            owner: "momenbasel", repo: "PureMac",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^PureMac-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
