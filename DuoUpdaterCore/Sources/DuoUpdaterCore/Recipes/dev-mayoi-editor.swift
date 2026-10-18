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
        // Mayoi — the release list of `sorrycc/Mayoi`: each release body is the
        // same text as that release's manifest notes (0.11.0 compared byte for
        // byte, up to the trailing newline), a `- ` list with hard-wrapped items.
        // Tags are `v<CFBundleShortVersionString>`; no prereleases so far.
        ChangelogRecipe(
            bundleID: "dev.mayoi.editor",
            source: URL(string: "https://api.github.com/repos/sorrycc/Mayoi/releases?per_page=40")!,
            mode: .json,
            maxEntries: 40,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ])
}
