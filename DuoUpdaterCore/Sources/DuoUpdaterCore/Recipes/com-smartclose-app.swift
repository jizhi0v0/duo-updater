import Foundation

enum com_smartclose_app {
    static let set = AppRecipeSet(
        family: "com-smartclose-app",
        changelogs: [
        // SmartClose — Sparkle gives detection: the bundle's `SUFeedURL` points at
        // `raw.githubusercontent.com/mahirozdin/SmartClose/main/appcast.xml`. Every
        // item in that feed carries only title/version/enclosure — no
        // `<description>` and no `<sparkle:releaseNotesLink>` — so the pane had a
        // version and nothing else.
        //
        // The GitHub release bodies are the notes the app itself links to
        // (`## Fixes` / `## Highlights` with bullets), so the shared
        // `.gitHubReleases` decoder reads them; a per-vendor HTML parser would only
        // duplicate it.
        ChangelogRecipe(
            bundleID: "com.smartclose.app",
            source: URL(
                string:
                    "https://api.github.com/repos/mahirozdin/SmartClose/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ])
}
