import Foundation

enum fr_handbrake_HandBrake {
    static let set = AppRecipeSet(
        family: "fr-handbrake-HandBrake",
        changelogs: [
        // History: docs/app-audits/fr-handbrake-HandBrake.md#历史与实测
        // HandBrake — GitHub releases, not the appcast's notes link.
        //
        // The Sparkle feed carries no `<description>`, only a
        // `<sparkle:releaseNotesLink>` to `handbrake.fr/appcast/stable.html`, and
        // that page is not kept per release: it can name an older version than the
        // feed serves and holds no change list, just an upgrade notice and a link
        // to GitHub. The notes themselves are the GitHub release bodies of
        // HandBrake/HandBrake, whose tags are the bare marketing version
        // (`1.11.2`), the same string as the app's `CFBundleShortVersionString`.
        //
        // Body shape: `## Upgrade Notice`, `## HandBrake <version>`,
        // `### All platforms` with `#### Video` / `#### Audio` / … under it, then
        // `### Linux`, `### Mac`, `### Windows`. `skipSections` drops the upgrade
        // boilerplate (its bullets are Windows .NET download links) and the two
        // other platforms' sections; the version-restating heading and the
        // item-less `All platforms` never render as headings anyway.
        //
        // Snapshots ship from a different repository (HandBrake-snapshots), so
        // this list is releases only; a `-beta.N` tag marked `prerelease` is kept
        // off this channel-less recipe by the decoder.
        //
        // `per_page` is small on purpose: every release lists two dozen assets,
        // and they, not the notes, are most of the response.
        ChangelogRecipe(
            bundleID: "fr.handbrake.HandBrake",
            source: URL(
                string: "https://api.github.com/repos/HandBrake/HandBrake/releases?per_page=10")!,
            mode: .json,
            maxEntries: 10,
            structuredFormat: .gitHubReleases,
            skipSections: ["Upgrade Notice", "Linux", "Windows"]),
        ])
}
