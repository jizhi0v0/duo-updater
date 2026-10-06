import Foundation

enum com_yetone_magpie {
    static let set = AppRecipeSet(
        family: "com-yetone-magpie",
        changelogs: [
        // The same release bodies the rule below reads inline, as a list so
        // the pane has history (magpie publishes several builds a day, so 40
        // is a few days). "Install" is download boilerplate (one bullet per
        // platform's file); the Chinese copy below `<!-- lang:zh -->` is cut
        // by `GitHubMarkdownParser.firstLanguage`.
        ChangelogRecipe(
            bundleID: "com.yetone.magpie",
            source: URL(
                string: "https://api.github.com/repos/yetone/magpie-releases/releases?per_page=40")!,
            mode: .json,
            maxEntries: 40,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: ["Install"]),
        ],
        githubRules: [
        // magpie — Go menu bar app; source in yetone/magpie, signed builds in
        // yetone/magpie-releases. No SUFeedURL: it updates itself from
        // usemagpie.ai/api/latest, which names these same release assets.
        // install.sh unpacks the zip into /Applications (or ~/Applications)
        // and the site's dmg holds the same bundle — mounted v0.1.1084: both
        // com.yetone.magpie, short == build == tag, Team LY7MVTUDZG, notarized.
        // One zip per arch (`arm64` / `amd64`); the host picks.
        GitHubReleaseRule(
            bundleID: "com.yetone.magpie",
            owner: "yetone", repo: "magpie-releases",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^magpie-darwin-(?:arm64|amd64)\.zip$"#,
            installerKind: .zip),
        ])
}
