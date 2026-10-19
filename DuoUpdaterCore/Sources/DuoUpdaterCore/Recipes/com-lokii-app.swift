import Foundation

enum com_lokii_app {
    static let set = AppRecipeSet(
        family: "com-lokii-app",
        githubRules: [
        // Shared rationale for digest-only: Recipes/org-alacritty.swift.

        // History: docs/app-audits/com-lokii-app.md#历史与实测
        // Lokii — Rust + AppKit file search. Up to 0.1.2 no Sparkle (its own
        // AppUpdater reads `/releases/latest` of this repo) and CFBundleVersion a
        // constant `1`. From 0.1.3 it embeds Sparkle with a per-arch `SUFeedURL`
        // on huangy7.github.io, so a copy that new is answered by its feed and
        // this rule is what older copies see newer releases through. v-tags;
        // short == the tag's X.Y.Z.
        //
        // Ad-hoc signed, no Team ID (`spctl` rejects it), so the Team-ID gate
        // can't apply. It takes `.publishedDigestOnly`: on both arches of 0.1.0
        // and 0.1.1 the seal verifies (`codesign --verify --deep --strict` 0),
        // the signed identifier is com.lokii.app, the short version is the
        // tag's, and GitHub publishes a sha256 for every asset (matches the
        // downloads).
        //
        // Assets carry no version: `Lokii-arm64.dmg` / `Lokii-x86_64.dmg`; the
        // arch is left to the source's arch preference.
        GitHubReleaseRule(
            bundleID: "com.lokii.app",
            owner: "huangy7", repo: "lokii",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Lokii-(?:arm64|x86_64)\.dmg$"#,
            installerKind: .dmg,
            installTrust: .publishedDigestOnly),
        ])
}
