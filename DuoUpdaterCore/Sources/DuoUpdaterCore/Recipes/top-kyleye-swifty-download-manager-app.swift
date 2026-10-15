import Foundation

enum top_kyleye_swifty_download_manager_app {
    static let set = AppRecipeSet(
        family: "top-kyleye-swifty-download-manager-app",
        githubRules: [
        // Swifty Download Manager (Kyle-Ye/SwiftyDownloadManager, Team
        // VB7MJ8R223, notarized) — no SUFeedURL and no updater of its own.
        //
        // One track: `.github/workflows/release.yml` refuses any tag that is not
        // MAJOR.MINOR.PATCH and checks that the app's CFBundleShortVersionString
        // equals the tag, which carries no `v`. Each release attaches one
        // universal `SwiftyDownloadManager.app.zip`; 0.2.0–0.3.0 attach nothing
        // and only read as versions.
        GitHubReleaseRule(
            bundleID: "top.kyleye.swifty-download-manager-app",
            owner: "Kyle-Ye", repo: "SwiftyDownloadManager",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^SwiftyDownloadManager\.app\.zip$"#,
            installerKind: .zip),
        ])
}
