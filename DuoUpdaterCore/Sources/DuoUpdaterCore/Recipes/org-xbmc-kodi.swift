import Foundation

enum org_xbmc_kodi {
    private static let bundleID = "org.xbmc.kodi"
    private static let mirror = "https://mirrors.kodi.tv/releases/osx/arm64/"
    private static let releaseNotes = URL(string: "https://kodi.tv/blog/tag/release/")!
    private static let version = #"[0-9]+(?:\.[0-9]+)+"#
    private static let archiveSuffix = #"-[A-Z][a-z]+-arm64\.dmg"#
    private static let linkStart = #"<tr>\s*<td>\s*<a\s+href=""#

    static let set = AppRecipeSet(
        family: "org-xbmc-kodi",
        probes: [
            // History: docs/app-audits/org-xbmc-kodi.md#历史与实测
            // Stable archive names have a bare codename. Prereleases add a
            // suffix to the codename, and keep that tag in the installed plist.
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: mirror)!,
                mode: .responseBody,
                versionPattern: linkStart + #"kodi-(\#(version))\#(archiveSuffix)""#,
                downloadURL: URL(string: "https://kodi.tv/download/macos/"),
                changelogURL: releaseNotes,
                entryStartPattern: linkStart,
                install: VendorInstallSpec(
                    urlSource: .bodyTemplate(
                        mirror + "{0}?https=1",
                        fields: [linkStart + #"(kodi-\#(version)\#(archiveSuffix))""#]),
                    kind: .dmg),
                hostRequirement: .init(architectures: [.arm64]),
                installedVersionPattern: #"\A[0-9]+(?:\.[0-9]+)+\.?\z"#),
        ],
        changelogs: [
            // The official RSS feed carries full, escaped HTML for each article.
            // Release summaries label the bullet groups with bold paragraphs.
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://kodi.tv/rss.xml")!,
                entryPattern:
                    #"<item>\s*<title>Kodi (?<version>[0-9]+(?:\.[0-9]+)+) &quot;[A-Za-z]+&quot; - Release</title>"#
                    + #"(?:(?!</item>).)*?<pubDate>(?<date>[^<]+)</pubDate>\s*<content:encoded>(?<body>[^<]*)</content:encoded>"#,
                itemPatterns: [#"&lt;li&gt;(?<item>.*?)&lt;/li&gt;"#],
                escapedMarkup: true,
                channel: .stable,
                excludedChannels: [.alpha, .beta, .rc, .nightly],
                headingPattern: #"&lt;p&gt;&lt;strong&gt;(?<heading>(?:(?!&lt;).)+)&lt;/strong&gt;&lt;/p&gt;\s*(?=&lt;ul&gt;)"#),
        ])
}
