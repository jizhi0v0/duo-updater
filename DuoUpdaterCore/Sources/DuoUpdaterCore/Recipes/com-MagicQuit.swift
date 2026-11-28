import Foundation

enum com_MagicQuit {
    static let bundleID = "com.magicquit"
    static let appcast = URL(string: "https://raw.githubusercontent.com/BigBerny/magicquit/main/appcast.xml")!

    static let set = AppRecipeSet(
        family: "com-MagicQuit",
        changelogs: [
            // History: docs/app-audits/com-MagicQuit.md#历史与实测
            // GitHub Releases and the appcast omit the detailed notes. Each
            // release tag pins the Markdown file before later draft entries.
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://raw.githubusercontent.com/BigBerny/magicquit/v2.0/CHANGELOG.md")!,
                entryPattern:
                    #"(?m)^##[ \t]+Version[ \t]+(?<version>[0-9]+(?:\.[0-9]+)+)[ \t]+-[ \t]+(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[ \t]*\r?\n(?<body>.*?)(?=^##[ \t]|\z)"#,
                itemPatterns: [#"(?m)^[ \t]*[-*][ \t]+(?<item>[^\r\n]+)"#],
                markdownSource: true,
                sourceTemplate: "https://raw.githubusercontent.com/BigBerny/magicquit/v{version}/CHANGELOG.md",
                headingPattern: #"(?m)^###[ \t]+(?<heading>[^\r\n]+)"#),
        ],
        sparkleFeeds: [
            // The old DMG has no updater feed. The newer ZIP declares this same feed itself.
            bundleID: appcast,
        ])
}
