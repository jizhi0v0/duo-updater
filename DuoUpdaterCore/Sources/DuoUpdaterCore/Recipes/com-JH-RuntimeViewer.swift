import Foundation

enum com_JH_RuntimeViewer {
    static let set = AppRecipeSet(
        family: "com-JH-RuntimeViewer",
        changelogs: [
        // RuntimeViewer — detection is the bundle's own Sparkle feed, which
        // carries no notes (no `<description>`, no `releaseNotesLink`). The notes
        // are the GitHub release bodies, written from `Changelogs/<tag>.md` by
        // the vendor's `release.yml`.
        //
        // Tags are `v<X.Y.Z>` for stable and `v<X.Y.Z>-beta.N` / `-RC.N` /
        // `-alpha.N` for prereleases, all flagged `prerelease`
        // (`Documentations/SparkleRelease.md`). A prerelease bundle reads the
        // bare `X.Y.Z`, so the beta recipe keeps the suffix in the version to
        // tell its entries apart. The `$` anchor keeps an unflagged rc off the
        // stable list. Betas graduate into the same numbering (2.1.0-RC.3 →
        // 2.1.0), so the beta recipe keeps the stable releases too.
        ChangelogRecipe(
            bundleID: "com.JH.RuntimeViewer",
            source: URL(string: "https://api.github.com/repos/MxIris-Reverse-Engineering/RuntimeViewer/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ChangelogRecipe(
            bundleID: "com.JH.RuntimeViewer",
            source: URL(string: "https://api.github.com/repos/MxIris-Reverse-Engineering/RuntimeViewer/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-(?:alpha|beta|RC)\.[0-9]+)?)$"#),
        ])
}
