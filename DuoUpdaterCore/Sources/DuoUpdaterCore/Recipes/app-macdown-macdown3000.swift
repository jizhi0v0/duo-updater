import Foundation

enum app_macdown_macdown3000 {
    static let set = AppRecipeSet(
        family: "app-macdown-macdown3000",
        githubRules: [
        // MacDown 3000 — Markdown editor, fork of MacDown under a new bundle id
        // (not `com.uranusjr.macdown`). Stable releases through 3000.0.7 ship
        // no SUFeedURL; Sparkle 2 landed after 3000.0.7 and the rc builds
        // declare macdown.app/sparkle/macdown3000/stable/appcast.xml, which
        // `SparkleAppcastSource` answers first once it serves. Tags are
        // `v3000.0.7`; short == tag minus `v`. `-beta.N` / `-rc.N` tags are
        // flagged prerelease and not tracked. One universal dmg per release;
        // the pattern refuses the prerelease dmgs. Team EDUS6QCV5X, notarized.
        GitHubReleaseRule(
            bundleID: "app.macdown.macdown3000",
            owner: "schuyler", repo: "macdown3000",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MacDown-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
