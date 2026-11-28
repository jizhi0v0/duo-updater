import Foundation

enum org_ppsspp_ppsspp {
    private static let bundleID = "org.ppsspp.ppsspp"
    private static let downloads = URL(string: "https://www.ppsspp.org/download/")!
    private static let releaseNews = URL(string: "https://www.ppsspp.org/news/tags/releases/")!

    // The download card's free macOS button is separate from both Gold and the
    // history table. Read both the version and the URL from that same button.
    private static let button = #"<a\b[^>]*\sclass="download-button button-block\s*"[^>]*\shref=""#
    private static let assetBase = #"https://www\.ppsspp\.org/files/"#
    private static let assetName = #"/PPSSPP_macOS\.dmg"#

    static let set = AppRecipeSet(
        family: "org-ppsspp-ppsspp",
        probes: [
            // History: docs/app-audits/org-ppsspp-ppsspp.md#历史与实测
            VendorProbeRecipe(
                bundleID: bundleID,
                url: downloads,
                mode: .responseBody,
                versionPattern: button + assetBase + #"([0-9]+)_([0-9]+)(?:_([0-9]+))?"# + assetName + #"""#,
                downloadURL: downloads,
                changelogURL: releaseNews,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(button + "(" + assetBase
                        + #"[0-9]+_[0-9]+(?:_[0-9]+)?"# + assetName + #")""#),
                    kind: .dmg),
                installedVersionPattern: #"\A[0-9]+\.[0-9]+(?:\.[0-9]+)?\z"#),
        ],
        changelogs: [
            // Follow the article title link, since one article can carry several
            // patches. Its detailed sections label the actual release versions.
            ChangelogRecipe(
                bundleID: bundleID,
                source: releaseNews,
                entryPattern:
                    #"<h3\b[^>]*\bid="what-s-new-in-[0-9-]+"[^>]*>\s*What's new in (?<version>[0-9]+(?:\.[0-9]+)+)\s*</h3>"#
                    + #"(?<body>.*?)(?=<h3\b[^>]*\bid="what-s-new-in-|</article>)"#,
                itemPatterns: [
                    #"<li\b[^>]*>(?!\s*<p\b[^>]*>[^<]+</p>\s*<ul\b)(?<item>.*?)</li>"#,
                ],
                indexLinkPattern: #"<h2\b[^>]*\bid="release-[0-9.]+"[^>]*>\s*<a\s+href="(?<link>/news/release-[0-9]+(?:\.[0-9]+)+/)">"#,
                headingPattern: #"<li\b[^>]*>\s*<p\b[^>]*>(?<heading>[^<]+)</p>\s*<ul\b"#),
        ])
}
