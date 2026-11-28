import Foundation

enum com_MagicQuit {
    static let bundleID = "com.MagicQuit"
    static let appcast = URL(string: "https://raw.githubusercontent.com/BigBerny/magicquit/main/appcast.xml")!

    static let set = AppRecipeSet(
        family: "com-MagicQuit",
        changelogs: [
            // History: docs/app-audits/com-MagicQuit.md#历史与实测
            // Each 2.x or newer tag pins that release series before later draft entries.
            changelog(
                majorPattern: #"(?:[2-9]|[1-9][0-9]+)"#, minimumAppVersion: "2",
                sourceTemplate: "https://raw.githubusercontent.com/BigBerny/magicquit/v{version}/CHANGELOG.md"),
            // The first release tag also includes the older website releases.
            changelog(majorPattern: #"[01]"#, belowAppVersion: "2"),
        ],
        sparkleFeeds: [
            // The old DMG has no updater feed. The newer ZIP declares this same feed itself.
            bundleID.lowercased(): appcast,
        ])

    private static func changelog(
        majorPattern: String, minimumAppVersion: String? = nil, belowAppVersion: String? = nil,
        sourceTemplate: String? = nil
    ) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://raw.githubusercontent.com/BigBerny/magicquit/v2.0/CHANGELOG.md")!,
            entryPattern:
                #"(?m)^##[ \t]+Version[ \t]+(?<version>\#(majorPattern)(?:\.[0-9]+)+)[ \t]+-[ \t]+(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[ \t]*\r?\n(?<body>.*?)(?=^##[ \t]|\z)"#,
            itemPatterns: [#"(?m)^[ \t]*[-*][ \t]+(?<item>[^\r\n]+)"#],
            markdownSource: true,
            sourceTemplate: sourceTemplate,
            headingPattern: #"(?m)^###[ \t]+(?<heading>[^\r\n]+)"#,
            minimumAppVersion: minimumAppVersion,
            belowAppVersion: belowAppVersion)
    }
}
