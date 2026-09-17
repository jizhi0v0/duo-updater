import Foundation

enum com_kimi_code_desktop {
    static let set = AppRecipeSet(
        family: "com-kimi-code-desktop",
        changelogs: [
        // History: docs/app-audits/com-kimi-code-desktop.md#历史与实测
        // Kimi Code — the version comes from `ElectronManifestSource` (the bundle's
        // own `app-update.yml` names `code.kimi.com/kimi-code/desktop/`), which
        // carries no notes. The notes are the files the app's own updater reads
        // after `update-available`: `<feed>/binaries/<version>/changelog.{zh,en}.md`,
        // one per release, no index and no "latest" alias. English, like the Kimi
        // recipe; the app has no language decision here to agree with.
        //
        // The file is the notes and nothing else — it opens on `### Polish` /
        // `### Features` and never names its version — so the version comes from
        // the URL (`versionFromTemplate`), and a non-Markdown answer can't read as
        // notes: the body has to start with a `##`–`####` heading. A missing version
        // is a 404 with a JSON body, which fails the fetch before this runs.
        //
        // Each bullet is one line (`- …`); the `###` group headings render as
        // headings rather than only ending the previous group.
        ChangelogRecipe(
            bundleID: "com.kimi.code.desktop",
            source: URL(string: "https://code.kimi.com/kimi-code/desktop/latest-mac.yml")!,
            entryPattern: #"\A\s*(?<body>#{2,4}[ \t].*)\z"#,
            itemPatterns: [#"(?m)^[-*][ \t]+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 1,
            sourceTemplate: "https://code.kimi.com/kimi-code/desktop/binaries/{version}/changelog.en.md",
            versionFromTemplate: true,
            headingPattern: #"(?m)^#{2,4}[ \t]+(?<heading>[^\n]+)"#),
        ])
}
