import Foundation

enum app_lorca {
    static let set = AppRecipeSet(
        family: "app-lorca",
        changelogs: [
        // Lorca — the version comes from the bundle's own Sparkle feed
        // (`SUFeedURL` = `mac-releases.lorca.app/appcast.xml`), whose items carry no
        // inline notes, only `<sparkle:releaseNotesLink>` to `Lorca-<version>.md`:
        // `scripts/release-mac.ts` extracts the version's section of the repo's
        // `CHANGELOG.md` into that file. It is `text/markdown`, which the pane
        // otherwise shows as raw text (`- ` and backticks literal).
        //
        // The file is the notes and nothing else — bullets, one per line, no
        // heading and no version (1.0.11, read 2026-10-09) — so the version comes
        // from the URL (`versionFromTemplate`), and the body has to open on a
        // bullet or a `##`–`####` heading, so nothing else reads as notes. A
        // version without a file (1.0.10 and older, 404 `text/html`) fails the
        // fetch before this runs.
        //
        // Not `CHANGELOG.md` itself: below 1.0.11 its sections are headed
        // `[0.1.10]`, `[0.1.9]` for the app's 1.0.10, 1.0.9, so no entry there
        // would name the version it belongs to.
        ChangelogRecipe(
            bundleID: "app.lorca",
            source: URL(string: "https://mac-releases.lorca.app/appcast.xml")!,
            entryPattern: #"\A\s*(?<body>(?:[-*]|#{2,4})[ \t].*)\z"#,
            itemPatterns: [#"(?m)^[-*][ \t]+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 1,
            sourceTemplate: "https://mac-releases.lorca.app/Lorca-{version}.md",
            versionFromTemplate: true,
            headingPattern: #"(?m)^#{2,4}[ \t]+(?<heading>[^\n]+)"#),
        ])
}
