import Foundation

enum com_luckymarmot_Paw {
    static let set = AppRecipeSet(
        family: "com-luckymarmot-Paw",
        changelogs: [
            // The archive keeps both Paw and RapidAPI releases in version articles.
            // Match the version in the article's own link, not the macOS badge.
            // Changes use both lists and paragraphs; category headings are h4s.
            // History: docs/app-audits/com-luckymarmot-Paw.md#历史与实测
            ChangelogRecipe(
                bundleID: "com.luckymarmot.Paw",
                source: URL(string: "https://paw.cloud/updates")!,
                entryPattern:
                    #"<article\s+class="article-version"[^>]*>\s*<h3\s+class="version-title"[^>]*>\s*<a\s+href="/updates/(?<version>[0-9]+(?:\.[0-9]+)+)"[^>]*>"#
                    + #".*?<span\s+class="version-date"[^>]*>(?<date>[^<]+)</span>.*?</h3>\s*(?<body>.*?)</article>"#,
                itemPatterns: [#"<(?:li|p)\b[^>]*>(?<item>.*?)</(?:li|p)>"#],
                headingPattern: #"<h4\s+class="update-type"[^>]*>(?<heading>.*?)</h4>"#),
        ],
        sparkleFeeds: [
            // Paw/RapidAPI ships Sparkle with a delegate-provided feed and no
            // SUFeedURL. Fill in only that missing URL; installed keys stay intact.
            // The public feed is untagged stable, with full ZIPs and no deltas.
            // History: docs/app-audits/com-luckymarmot-Paw.md#历史与实测
            "com.luckymarmot.paw": URL(string: "https://paw.cloud/api/v2/updates/appcast")!,
        ],
        changelogPages: [
            "com.luckymarmot.paw": URL(string: "https://paw.cloud/updates")!,
        ])
}
