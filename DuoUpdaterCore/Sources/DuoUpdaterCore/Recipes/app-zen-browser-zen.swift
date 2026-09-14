import Foundation

enum app_zen_browser_zen {
    static let set = AppRecipeSet(
        family: "app-zen-browser-zen",
        githubRules: [
        // History: docs/app-audits/app-zen-browser-zen.md#历史与实测
        // Zen Browser — stable tags carry a trailing letter suffix (e.g.
        // "1.20.1b"). That suffix is PART of the CFBundleShortVersionString, so
        // the pattern MUST keep the trailing [a-z] — stripping it would read as a
        // perpetual update/downgrade. Zen also publishes a rolling "twilight"
        // prerelease; /releases/latest (usePrereleases: false) excludes it.
        //
        // Best-effort one-click: the `zen.macos-universal.dmg` wraps `Zen.app`, a
        // notarized Developer ID build under Team 9V5K9TP787 (History has the
        // verification). A Firefox fork with its own updater, so a fallback; the
        // Team-ID gate (`VendorInstaller`) enforces the match at install time.
        GitHubReleaseRule(
            bundleID: "app.zen-browser.zen",
            owner: "zen-browser", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"([0-9]+\.[0-9]+(?:\.[0-9]+)?[a-z]?)"#,
            installAssetPattern: #"^zen\.macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
