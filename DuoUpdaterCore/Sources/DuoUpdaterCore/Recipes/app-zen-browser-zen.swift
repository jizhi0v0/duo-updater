import Foundation

enum app_zen_browser_zen {
    static let set = AppRecipeSet(
        family: "app-zen-browser-zen",
        githubRules: [
        // Zen Browser — stable tags carry a trailing letter suffix (e.g.
        // "1.20.1b"). That suffix is PART of the CFBundleShortVersionString, so
        // the pattern MUST keep the trailing [a-z] — stripping it would read as a
        // perpetual update/downgrade. Zen also publishes a rolling "twilight"
        // prerelease; /releases/latest (usePrereleases: false) excludes it.
        //
        // Best-effort one-click: the `zen.macos-universal.dmg` wraps `Zen.app` —
        // verified 2026-06-06 a notarized Developer ID build (Team 9V5K9TP787, Mauro
        // Baladés) reporting version 1.20.2b == tag (the trailing `b` kept, matching
        // CFBundleShortVersionString), bundle id app.zen-browser.zen. A Firefox fork
        // with its own updater, so a fallback; not installed locally, so the Team-gate
        // enforces the match at install time.
        GitHubReleaseRule(
            bundleID: "app.zen-browser.zen",
            owner: "zen-browser", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"([0-9]+\.[0-9]+(?:\.[0-9]+)?[a-z]?)"#,
            installAssetPattern: #"^zen\.macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
