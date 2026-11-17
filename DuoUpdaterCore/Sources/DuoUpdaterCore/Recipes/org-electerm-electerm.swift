import Foundation

enum org_electerm_electerm {
    // History: docs/app-audits/org-electerm-electerm.md#历史与实测
    static let set = AppRecipeSet(
        family: "org-electerm-electerm",
        githubRules: [
        // electerm — open-source terminal / SSH / SFTP client. Its custom
        // updater checks the website's version.html and release JSON, downloads
        // a full DMG on request, then opens it for manual installation. The
        // generated app-update.yml uses a GitHub provider; it is not a generic
        // Electron manifest URL. Only ordinary Electron helpers live inside the
        // bundle; there is no resident login item or external service to restart.
        // Tags have an optional v; suffixes are excluded even if a preview is
        // accidentally published as stable. Pick the native arm64 DMG, excluding
        // the Intel/mac10 builds and .blockmap sidecars.
        GitHubReleaseRule(
            bundleID: "org.electerm.electerm",
            owner: "electerm", repo: "electerm",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^electerm-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
