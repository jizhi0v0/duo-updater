import Foundation

enum com_roversx_launchnext {
    static let set = AppRecipeSet(
        family: "com-roversx-launchnext",
        githubRules: [
        // LaunchNext — the app updates itself (its README says so) and it has no
        // Homebrew core cask (only a third-party tap), so nothing answered: the
        // row was `.unknown`, which is also why there were no notes.
        //
        // Tags are bare `2.4.2`, assets `LaunchNext2.4.2.zip`. The release bodies
        // carry the changelog and `GitHubMarkdownParser` renders it, so this rule
        // supplies detection and notes together.
        //
        // Detection-only: the README says 2.4.2 is signed and notarized, but the
        // zip was not mounted here to confirm the Team ID, so no in-place install.
        GitHubReleaseRule(
            bundleID: "com.roversx.launchnext",
            owner: "RoversX", repo: "LaunchNext",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
