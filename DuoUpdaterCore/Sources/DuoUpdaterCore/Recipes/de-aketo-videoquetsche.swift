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
            // v1.1.0 packages version 1.0. Keep its release notes, but never
            // offer that archive as an upgrade if newer assets disappear.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "noestreich",
                repo: "videoquetsche",
                versionPattern: #"^v(?!1\.1\.0$)([0-9]+(?:\.[0-9]+)+)$"#,
                installAssetPattern: #"^Videoquetsche\.zip$"#,
                installerKind: .zip),
        ])
}
