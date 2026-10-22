import Foundation

enum onebadidea_Swift_Quit {
    static let set = AppRecipeSet(
        family: "onebadidea-Swift-Quit",
        githubRules: [
        // Swift Quit — menu-bar app (LSUIElement) that quits an app once its
        // last window closes. No updater of its own: no SUFeedURL, no Sparkle,
        // no update check in its source; GitHub Releases is the only route.
        //
        // Tags read `v1.5`, matching CFBundleShortVersionString (build is
        // always 1). One asset per release, `Swift.Quit.zip`, universal.
        // v1.5 is onebadidea.Swift-Quit, Team M4FH9KS7W7, notarized. v1.4 and
        // v1.3 are ad-hoc (no Team), so gate 3 refuses one-click from them
        // (no Team on the installed copy); they still see the update and
        // install 1.5 by hand once. Not `.publishedDigestOnly`: the latest
        // build has a Team ID, and none of these assets has a GitHub digest.
        //
        // Contents/Library/LoginItems/LaunchAtLoginHelper.app is sindresorhus/
        // LaunchAtLogin's helper: it launches the main app unless it is already
        // running, then terminates. Nothing stays resident across the swap.
        GitHubReleaseRule(
            bundleID: "onebadidea.Swift-Quit",
            owner: "onebadidea", repo: "swiftquit",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Swift\.Quit\.zip$"#,
            installerKind: .zip),
        ])
}
