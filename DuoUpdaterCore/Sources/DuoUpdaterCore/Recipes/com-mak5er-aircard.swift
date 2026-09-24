import Foundation

enum com_mak5er_aircard {
    static let set = AppRecipeSet(
        family: "com-mak5er-aircard",
        githubRules: [
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // AirCard — ad-hoc signed, no Team ID (`build.sh` ends in
        // `codesign --sign -`). Tags are `v1.2.4`, matching
        // CFBundleShortVersionString; one `AirCard.dmg` asset per release.
        GitHubReleaseRule(
            bundleID: "com.mak5er.aircard",
            owner: "Mak5er", repo: "AirCard"),
        ])
}
