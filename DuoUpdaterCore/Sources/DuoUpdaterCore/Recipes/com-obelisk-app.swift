import Foundation

enum com_obelisk_app {
    static let set = AppRecipeSet(
        family: "com-obelisk-app",
        changelogs: [
        // Obelisk — GitHub releases, not the appcast's own notes.
        //
        // Builds from upstream's release workflow, which landed together with its
        // Sparkle updater, declare `SUFeedURL`
        // (`releases/latest/download/appcast-<arch>.xml`), so detection moves to
        // `SparkleAppcastSource` without a recipe. The `v0.2.3` tag predates that
        // workflow; no such build has been published yet. But the vendor's
        // release script (`app/scripts/update-release.mjs`) writes the GitHub
        // release body — Markdown — into a plain `<description>` with no
        // `sparkle:format`, and each feed holds one item. The production parser yields no entries for
        // that shape (the same raw-Markdown case as Waku), so the pane would draw
        // one unstructured blob for one version. The releases API carries the same
        // body, with its `##` sections, for every version.
        //
        // `skipSections`: every body since 0.2.0 has a `## Downloads` section (the
        // asset filenames), and 0.2.2 adds `## Included work` after it (PR
        // numbers restating the sections above). Neither is a change note.
        ChangelogRecipe(
            bundleID: "com.obelisk.app",
            source: URL(string: "https://api.github.com/repos/tommy0103/obelisk/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases,
            skipSections: ["Downloads", "Included work"]),
        ],
        githubRules: [
        // Obelisk — Electron session browser for coding agents. 0.2.2 and earlier
        // carry no updater at all (no `SUFeedURL`, no `app-update.yml`), so
        // `/releases/latest` is the only source for those copies; once a copy
        // declares its own Sparkle feed, that answers first and this rule is the
        // fallback. Every GitHub release is the desktop app (the CLI ships to npm). v-tags;
        // the release workflow builds `-rc` tags as GitHub prereleases, which
        // `/releases/latest` skips and the anchored pattern refuses anyway.
        // short == tag.
        //
        // Detection-only (see `Recipes/org-alacritty.swift`): the 0.2.2 build is
        // ad-hoc and linker-signed with no Team ID, so the Team-ID gate refuses
        // it, and it cannot take `.publishedDigestOnly` either — like MarkText,
        // its seal does not verify and its signed identifier is `Electron`.
        // Upstream's release workflow signs with a Developer ID, which that route
        // refuses over an ad-hoc copy anyway. Developer ID copies take the
        // Sparkle route above.
        GitHubReleaseRule(
            bundleID: "com.obelisk.app",
            owner: "tommy0103", repo: "obelisk",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
