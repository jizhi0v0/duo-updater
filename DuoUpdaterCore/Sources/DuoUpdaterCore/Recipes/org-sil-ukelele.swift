import Foundation

enum org_sil_ukelele {
    static let bundleID = "org.sil.ukelele"
    static let appcast = URL(string: "https://software.sil.org/downloads/r/ukelele/Ukelele_appcast.xml")!

    static func matchesFeed(bundleID: String?, feedURL: URL) -> Bool {
        bundleID?.lowercased() == self.bundleID && feedURL == appcast
    }

    static func betaVersion(_ version: String?) -> Bool {
        version?.range(of: #"\A[0-9]+(?:\.[0-9]+)+b[0-9]+\z"#, options: .regularExpression) != nil
    }

    static let set = AppRecipeSet(
        family: "org-sil-ukelele",
        changelogs: [
            // The vendor's version history separates paragraphs by release,
            // unlike the appcast's cumulative, malformed inline headings.
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://software.sil.org/ukelele/ukelele-version-history/")!,
                entryPattern: #"<h3\b[^>]*>\s*(?<date>[0-9]{1,2}\s+[A-Za-z]+\s+[0-9]{4})\s*(?:—|&mdash;|&#8212;)\s*Released version\s+(?<version>[0-9]+(?:\.[0-9]+)+(?:b[0-9]+)?)\s*</h3>(?<body>.*?)(?=<h[23]\b|</(?:article|main)>|\z)"#,
                itemPatterns: [#"<p\b[^>]*>(?<item>.*?)</p>"#]),
        ],
        sparkleFeeds: [
            // History: docs/app-audits/org-sil-ukelele.md#历史与实测
            // A literal pair of double quotes in SUFeedURL prevents URL parsing.
            bundleID: appcast,
        ])
}
