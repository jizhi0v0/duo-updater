import Foundation

enum com_robinebers_openusage {
    static let set = AppRecipeSet(
        family: "com-robinebers-openusage",
        changelogs: [
        // History: docs/app-audits/com-robinebers-openusage.md#历史与实测
        // OpenUsage — resolves through the generic Sparkle source, but no
        // appcast item carries a `<description>` or a `sparkle:releaseNotesLink`.
        // The vendor writes the notes on the GitHub releases of
        // robinebers/openusage instead, as Markdown lists.
        //
        // One repo, two trains, split by GitHub's `prerelease` bit: `v<x.y.z>`
        // stable and `v<x.y.z>-beta.N` prereleases. Tag minus `v` is exactly the
        // appcast's `sparkle:shortVersionString` on both trains, so entries line
        // up with what Sparkle offers.
        //
        // `includesPromotedStable` on the beta recipe follows from the feed, not
        // taste: the appcast marks betas `<sparkle:channel>beta` and leaves stable
        // items unmarked, and Sparkle offers a beta install the default channel
        // as well, so a beta copy is legitimately offered the stable release that
        // graduates (CotEditor's case, `Recipes/com-coteditor-CotEditor.swift`).
        // Without it the panel would omit the very entry the row offers.
        //
        // `per_page=40` with `maxEntries: 20` is the house shape; the stable rail
        // gets fewer than 20 because most of the newest 40 are betas.
        ChangelogRecipe(
            bundleID: "com.robinebers.openusage",
            source: URL(string: "https://api.github.com/repos/robinebers/openusage/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "com.robinebers.openusage",
            source: URL(string: "https://api.github.com/repos/robinebers/openusage/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases),
        ],
        changelogPages: [
        // The page the pane embeds when the recipes above parse nothing: the
        // Sparkle source supplies no notes link of its own.
        "com.robinebers.openusage": URL(string: "https://github.com/robinebers/openusage/releases")!,
        ])
}
