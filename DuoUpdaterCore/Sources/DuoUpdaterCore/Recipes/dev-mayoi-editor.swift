import Foundation

enum dev_mayoi_editor {
    static let set = AppRecipeSet(
        family: "dev-mayoi-editor",
        changelogs: [
        // Detection, one-click and deltas come from `MyGoUpdateSource`, which
        // reads the feed and key linked into Mayoi's binary (`mygo.json`
        // `updates.github` = sorrycc/Mayoi). Only the history of the release
        // notes needs a recipe: the manifest carries the newest release's notes
        // alone.
        //
        // Mayoi — the repo's `CHANGELOG.md`, which the file itself says every
        // release must have a `## <version>` section in, and which the app's
        // update window shows. Each section is that release's manifest `notes`
        // (all 19 releases, 0.1.0 to 0.11.0, compared; 0.2.0 differs by one blank
        // line). Not the GitHub release list: the bodies of 0.1.0 to 0.3.2 are a
        // bare "Full Changelog" link, so six releases had no notes there.
        //
        // Sections are a `- ` list with hard-wrapped items and no `###` headings.
        // The version must start with a digit, which skips `## Unreleased`.
        ChangelogRecipe(
            bundleID: "dev.mayoi.editor",
            source: URL(string: "https://raw.githubusercontent.com/sorrycc/Mayoi/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##[ \t]+(?<version>[0-9]+(?:\.[0-9]+)+)[ \t]*\n(?<body>.*?)(?=\n##[ \t]|\z)"#,
            itemPatterns: [#"(?:^|\n)-[ \t]+(?<item>.+?)(?=\n-[ \t]|\n##[ \t]|\z)"#],
            markdownSource: true,
            maxEntries: 40),
        ])
}
