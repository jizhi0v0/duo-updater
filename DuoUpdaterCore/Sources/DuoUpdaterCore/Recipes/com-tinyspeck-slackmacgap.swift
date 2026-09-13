import Foundation

enum com_tinyspeck_slackmacgap {
    static let set = AppRecipeSet(
        family: "com-tinyspeck-slackmacgap",
        probes: [
        // Slack (desktop, mac) — the website's own "latest" download link. A
        // single 302 from slack.com/ssb/download-osx-universal lands on the
        // versioned package downloads.slack-edge.com/.../mac/universal/<ver>/
        // Slack-<ver>-macOS.dmg, so the version rides in the resolved filename
        // (HEAD+follow → lastPathComponent). Use the -universal link, NOT -osx
        // (that resolves to the x64/Intel build). ChangelogRecipe(com.tinyspeck.slackmacgap)
        // renders the notes natively. One-click: the same -universal link IS the
        // installer — the spec HEAD-follows the 302 to the versioned universal dmg
        // and swaps in place (on top of Slack's own Squirrel updater).
        VendorProbeRecipe(
            bundleID: "com.tinyspeck.slackmacgap",
            url: URL(string: "https://slack.com/ssb/download-osx-universal")!,
            mode: .redirectFilename,
            versionPattern: #"^Slack-([0-9]+\.[0-9]+\.[0-9]+)-macOS\.dmg$"#,
            downloadURL: URL(string: "https://slack.com/downloads/mac"),
            changelogURL: URL(string: "https://slack.com/release-notes/mac"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://slack.com/ssb/download-osx-universal")!),
                kind: .dmg)),
        ],
        changelogs: [
        // Slack (desktop, mac) — slack.com/release-notes/mac is a fully
        // server-rendered page listing every mac release newest-first. Each
        // release is one <article>:
        //   <article><a name="11727"></a>
        //     <h2 class="u-flex u-align--center">Slack 4.50.128</h2>
        //     <p>May 26, 2026</p>
        //     <h3>Bug Fixes</h3><ul><li>…</li></ul></article>
        // The <a name> anchor and the section <h3> vary (Bug Fixes / What's New /
        // Security Guidance, sometimes several per entry), so the body captures
        // everything up to </article> and the <li> pattern sweeps all sections.
        // The date <p> is wrapped optional for safety though every entry has one.
        ChangelogRecipe(
            bundleID: "com.tinyspeck.slackmacgap",
            source: URL(string: "https://slack.com/release-notes/mac")!,
            entryPattern:
                #"<article>\s*(?:<a name="[^"]*"></a>\s*)?"#
                + #"<h2[^>]*>Slack\s+(?<version>[\d.]+)</h2>\s*"#
                + #"(?:<p[^>]*>(?<date>[^<]*)</p>\s*)?"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 30),
        ])
}
