import Foundation

enum com_tencent_QQMusicMac {
    // All three rules bind to the Mac object that carries Tencent's signed Mac
    // DMG redirect. The legacy Mac object has the same title and type, but links
    // directly to a different download host. Match the version field because
    // the filename may be opaque.
    private static let macVersionField =
        #"\{\s*"ID"\s*:\s*[0-9]+\s*,\s*"Ftype"\s*:\s*2\s*,\s*"Ftitle"\s*:\s*"Mac"\s*,\s*"Fversion"\s*:\s*"最新版[:：]\s*"#
    private static let version = #"[0-9]+(?:\.[0-9]+)+"#
    // Consume JSON strings as units, including any braces in a release note,
    // but stop at the enclosing object's braces.
    private static let withinObject = #"(?:[^{}"]|"(?:[^"\\]|\\.)*")*?"#
    private static let linkField = withinObject + #",\s*"Flink1"\s*:\s*""#
    private static let macDMG =
        #"https://c\.y\.qq\.com/cgi-bin/file_redirect\.fcg\?bid=dldir&file=ecosfile%2[fF]music_clntupate%2[fF]mac%2[fF]other%2[fF][A-Za-z0-9._-]+\.dmg&sign=[A-Za-z0-9._~-]+"#
    private static let feedURL = URL(string: "https://y.qq.com/download/download.js")!
    private static let downloadPage = URL(string: "https://y.qq.com/download/index.html")!

    static let set = AppRecipeSet(
        family: "com-tencent-QQMusicMac",
        probes: [
            // History: docs/app-audits/com-tencent-QQMusicMac.md#历史与实测
            // The JSONP feed's Fversion is the marketing version. It does not
            // expose CFBundleVersion. Flink1 supplies a fresh signed redirect
            // to the DMG containing the app bundle.
            VendorProbeRecipe(
                bundleID: "com.tencent.QQMusicMac",
                url: feedURL,
                mode: .responseBody,
                versionPattern: macVersionField + "(" + version + ")\""
                    + "(?=" + linkField + macDMG + "\")",
                downloadURL: downloadPage,
                changelogURL: downloadPage,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(macVersionField + version + "\"" + linkField + "(" + macDMG + ")\""),
                    kind: .dmg)),
        ],
        changelogs: [
            // Fdesc contains the notes and their zone-less display date.
            ChangelogRecipe(
                bundleID: "com.tencent.qqmusicmac",
                source: feedURL,
                entryPattern:
                    macVersionField + "(?<version>" + version + ")\"" + withinObject
                    + #",\s*"Fdesc"\s*:\s*"(?<body>(?:[^"\\]|\\.)*?)(?:\\n\|?)*"#
                    + #"发布时间[:：]\s*(?<date>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})"#
                    + #"(?:[^"\\]|\\.)*""# + linkField + macDMG + "\"",
                itemPatterns: [#"(?:^|\\n)\|?(?<item>(?:[^\\]|\\(?!n))+?)(?=\\n|$)"#],
                mode: .json,
                maxEntries: 1,
                minItemLength: 2),
        ])
}
