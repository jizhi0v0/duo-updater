import Foundation

enum de_aketo_videoquetsche {
    private static let bundleID = "de.aketo.videoquetsche"
    private static let stableTag = #"^v([0-9]+(?:\.[0-9]+)+)$"#

    static let set = AppRecipeSet(
        family: "de-aketo-videoquetsche",
        changelogs: [
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://api.github.com/repos/noestreich/videoquetsche/releases?per_page=40")!,
                mode: .json,
                maxEntries: 20,
                channel: .stable,
                structuredFormat: .gitHubReleases,
                tagPattern: stableTag),
        ],
        githubRules: [
            // The v1.1.0 archive reports 1.0 in its bundle. A newer stable
            // release still upgrades that copy through the same signed ZIP.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "noestreich",
                repo: "videoquetsche",
                versionPattern: stableTag,
                installAssetPattern: #"^Videoquetsche\.zip$"#,
                installerKind: .zip),
        ])
}
