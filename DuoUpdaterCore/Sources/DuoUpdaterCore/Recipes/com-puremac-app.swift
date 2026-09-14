import Foundation

enum com_puremac_app {
    static let set = AppRecipeSet(
        family: "com-puremac-app",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/com-puremac-app.md#历史与实测
        // PureMac — a dmg and a zip of the same build ship together; take the dmg.
        // One-click: com.puremac.app, Team H3WXHVTP97, notarized.
        //
        // The tag is anchored because this repo ships a *second product* out of
        // the same releases: a `cli-v…` tag carrying only a CLI tarball, which
        // GitHub can mark latest (History has the count when checked). The default
        // pattern is unanchored, so it reads such a tag as a version (`cli-v1.0.0`
        // as 1.0.0) — which, against the app's own higher version, evaluates as "up
        // to date" and hides every real update. The macOS-asset gate already walks
        // past such a release, but the number it walks past should never parse in
        // the first place: one guard against a silent no-update is not enough.
        GitHubReleaseRule(
            bundleID: "com.puremac.app",
            owner: "momenbasel", repo: "PureMac",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^PureMac-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
