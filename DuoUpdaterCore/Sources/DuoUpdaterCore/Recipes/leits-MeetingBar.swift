import Foundation

enum leits_MeetingBar {
    static let set = AppRecipeSet(
        family: "leits-MeetingBar",
        githubRules: [
        // MeetingBar — menu-bar meeting launcher. No SUFeedURL and no in-app
        // updater; releases are uploaded by hand (the repo has no release
        // workflow). Stable only: `/releases/latest` skips the prerelease V5
        // track (`v5.0.0`, `v5.0.0-rc2`, earlier `v4.11.beta`), whose builds
        // share this bundle id and carry no channel marker. The pattern is
        // anchored so a `-rcN` / `.beta` tag can never parse as a version.
        // Tag `vX.Y.Z` == CFBundleShortVersionString; CFBundleVersion is a
        // build counter. One unversioned `MeetingBar.dmg` per release,
        // universal. Team KGH289N6T8, notarized. The Mac App Store copy has
        // the same bundle id and is skipped here (`isMASApp`).
        GitHubReleaseRule(
            bundleID: "leits.MeetingBar",
            owner: "leits", repo: "MeetingBar",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MeetingBar\.dmg$"#,
            installerKind: .dmg),
        ])
}
