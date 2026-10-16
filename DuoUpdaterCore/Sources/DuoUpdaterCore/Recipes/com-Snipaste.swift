import Foundation

enum com_Snipaste {
    static let set = AppRecipeSet(
        family: "com-Snipaste",
        probes: [
        // History: docs/app-audits/com-Snipaste.md#历史与实测
        // Snipaste — closed-source Qt app with its own updater, no Sparkle feed
        // and no address of that updater in the binary as a literal (it builds
        // `https://%1` at run time). The cask is `auto_updates`, so Homebrew
        // stays silent too.
        //
        // The probe reads `www.snipaste.com/versions`, the JSON the vendor's
        // own download page fills its version labels from (`js/index.js`). It
        // names one version per platform; `mac_version` is the marketing string
        // the bundle reports (`CFBundleShortVersionString` = `CFBundleVersion`).
        // The closing quote right after the digits keeps a suffixed value such
        // as `2.12-Beta` from being read as `2.12`. Two-part versions (`2.11`)
        // are real releases and match.
        //
        // `mac_date` is a dotted day (`2026.01.18`), which `ReleaseDate` does not
        // read, so there is no `publishedAtPattern`.
        //
        // One-click: the universal dmg under `download.snipaste.com/archives/`,
        // named by the version the probe resolved — the same file the download
        // page links as "Universal" and the cask installs. Snipaste.app inside,
        // com.Snipaste, Team NGTL73P583, notarized. The body publishes no digest
        // (the vendor's `dl.snipaste.com/sha-1.txt` is SHA-1, which the installer
        // does not support).
        VendorProbeRecipe(
            bundleID: "com.Snipaste",
            url: URL(string: "https://www.snipaste.com/versions")!,
            mode: .responseBody,
            versionPattern: #""mac_version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.snipaste.com/download.html"),
            changelogURL: URL(string: "https://docs.snipaste.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://download.snipaste.com/archives/Snipaste-{version}.dmg"),
                kind: .dmg)),
        ],
        changelogs: [
        // History: docs/app-audits/com-Snipaste.md#历史与实测
        // Snipaste — the docs site is docsify; `/changelog` is an alias of
        // `wiki/Changelog.md`, served as Markdown. Each release is
        // `## v<version>`, then `> <yyyy.MM.dd>`, then `*` bullets, some nested
        // two or four spaces deep; nested ones are kept as items. One changelog
        // covers Windows, Mac and Linux; platform-only items carry a `[Mac]` /
        // `[Linux]` tag in their text.
        //
        // The version must end the heading line, so `## v2.8.9 Beta (Linux)` and
        // the other beta headings are not entries; the body stops at the next
        // `## `, so a beta's items never join a release's.
        ChangelogRecipe(
            bundleID: "com.Snipaste",
            source: URL(string: "https://docs.snipaste.com/wiki/Changelog.md")!,
            entryPattern:
                #"## v(?<version>[0-9]+(?:\.[0-9]+)+)[ \t]*\n"#
                + #">[ \t]*(?<date>[0-9]{4}\.[0-9]{2}\.[0-9]{2})[ \t]*\n"#
                + #"(?<body>[\s\S]*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?m)^[ \t]*[*-][ \t]+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 20),
        ])
}
