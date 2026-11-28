enum com_zenangst_Gray {
    static let bundleID = "com.zenangst.Gray"

    static let set = AppRecipeSet(
        family: "com-zenangst-Gray",
        githubRules: [
            // The published tag matches the short version. Build 1 is shared
            // across releases, including the older Intel-only previews.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "zenangst", repo: "Gray",
                versionPattern: #"\A([0-9]+\.[0-9]+\.[0-9]+)\z"#,
                installAssetPattern: #"\AGray\.zip\z"#,
                installerKind: .zip),
        ])
}
