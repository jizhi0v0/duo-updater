import Foundation

enum com_shotbase_app {
    static let set = AppRecipeSet(
        family: "com-shotbase-app",
        changelogs: [
        // History: docs/app-audits/com-shotbase-app.md#历史与实测
        // Shotbase — GitHub releases, because the appcast carries no notes at all.
        //
        // `updates.shotbase.com/appcast.xml` is a stock Sparkle feed served off
        // GitHub Pages, and `SparkleAppcastSource` already answers for the app
        // from it. What it cannot do is render notes: not one of its items
        // carries a `<description>` or a `<sparkle:releaseNotesLink>`, so there is
        // neither inline text to parse NOR a page to fall back to in a web view —
        // the pane would simply be blank.
        //
        // github.com/notnotDudu/shotbase-releases is where the notes actually live:
        // one "## What’s new" bullet list per version, same releases the
        // appcast’s enclosures are downloaded from. The trailing
        // "Source build: [`<sha>`](…)" line is not a bullet, so the strict pass
        // drops it; v1.0.0, whose body is a single sentence, still gets an entry
        // through `GitHubMarkdownParser`’s prose pass rather than leaving a gap in
        // the rail. v0.9.0 is flagged prerelease upstream (an "upgrade-rehearsal
        // baseline" kept only to exercise the Sparkle path) and this decoder skips
        // prereleases, which is the right answer — nobody opted into that track.
        ChangelogRecipe(
            bundleID: "com.shotbase.app",
            source: URL(
                string:
                    "https://api.github.com/repos/notnotDudu/shotbase-releases/releases?per_page=40"
            )!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
