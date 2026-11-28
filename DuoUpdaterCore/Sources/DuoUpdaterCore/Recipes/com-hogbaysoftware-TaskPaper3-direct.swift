import Foundation

enum com_hogbaysoftware_TaskPaper3_direct {
    private static let bundleID = "com.hogbaysoftware.TaskPaper3.direct"
    private static let releases = URL(string: "https://www.taskpaper.com/releases/")!
    private static let releaseHeader = #"<h2\b[^>]*>\s*TaskPaper\s+"#
    private static let version = #"3(?:\.[0-9]+)*"#
    private static let sectionTitle = #"(?:App|Sidebar|Searchbar|Palettes|Tabs/Windows|Stylesheets|Other|Scripting API|[^<>]+:)"#
    private static let sectionList = #"\s*</p>\s*<[ou]l\b"#

    static let set = AppRecipeSet(
        family: "com-hogbaysoftware-TaskPaper3-direct",
        probes: [
            // History: docs/app-audits/com-hogbaysoftware-TaskPaper3-direct.md#历史与实测
            // The first release heading is current. Require its own download to
            // advertise the same version before constructing the official URL.
            VendorProbeRecipe(
                bundleID: bundleID,
                url: releases,
                mode: .responseBody,
                versionPattern: #"<h1\b[^>]*>\s*Releases\s*</h1>\s*"# + releaseHeader
                    + #"(\#(version))\s+–\s+[^<]+<a\b[^>]*\shref="/assets/app/TaskPaper-\1\.dmg""#,
                downloadURL: releases,
                changelogURL: releases,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate("https://www.taskpaper.com/assets/app/TaskPaper-{version}.dmg"),
                    kind: .dmg),
                installedVersionPattern: #"\A\#(version)\z"#),
        ],
        changelogs: [
            ChangelogRecipe(
                bundleID: bundleID,
                source: releases,
                entryPattern: releaseHeader
                    + #"(?<version>\#(version))\s+–\s+(?<date>[^<]+)(?:<a\b[^>]*>.*?</a>)?\s*</h2>"#
                    + #"(?<body>.*?)(?=<h2\b|<footer\b|\z)"#,
                itemPatterns: [
                    #"(?<item><li\b[^>]*>.*?</li>|<p\b[^>]*>(?!\s*\#(sectionTitle)\#(sectionList)).*?</p>)"#,
                ],
                excludedChannels: [.preview],
                headingPattern: #"<p\b[^>]*>\s*(?<heading>\#(sectionTitle))\#(sectionList)"#),
        ])
}
