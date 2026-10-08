import Foundation

/// Audacity 3 and Audacity 4 — two products, three bundle ids, one GitHub
/// Releases list (`audacity/audacity`).
///
/// - 3.x: `org.audacityteam.audacity`, `Audacity.app`.
/// - 4.x: `org.audacityteam.audacity4`, `Audacity 4.app`.
/// - 4.0 alpha/beta builds (GitHub prereleases): `org.audacityteam.Audacity`,
///   which differs from the 3.x id only in case, and report a bare `4.0.0`.
///
/// Both trains publish into the same Releases list, interleaved by date. A
/// stable tag is `Audacity-<x.y.z>`; every 3.x/4.x prerelease carries a suffix
/// (`-alpha-N`, `-beta-N`, `-RC<N>`). Everything below reads one train out of
/// that shared list by anchoring the tag's major version at both ends.
enum org_audacityteam_audacity {

    /// The releases list every changelog recipe here reads. `per_page=100` is
    /// GitHub's maximum: each train is a filtered view of a list the other train
    /// keeps pushing down, so the page has to be deep enough that a train's
    /// newest release is still on it after the other one has shipped for a
    /// while. A train whose releases have all scrolled off reads zero entries
    /// and the pane falls back to the releases page.
    private static let releasesAPI =
        URL(string: "https://api.github.com/repos/audacity/audacity/releases?per_page=100")!

    /// Stable 4.x tags only. Shared by the 4.x recipe and the prerelease-id one
    /// so both show the same notes.
    private static let fourTag = #"^Audacity-(4\.[0-9]+\.[0-9]+)$"#

    static let set = AppRecipeSet(
        family: "org-audacityteam-audacity",
        changelogs: [
        // Audacity 3. `.gitHubReleases` reads stable releases only, and
        // `tagPattern` keeps the 4.x ones out.
        //
        // `ChangelogRecipeRegistry` groups bundle ids case-insensitively, so this
        // recipe and the prerelease id's below are ONE group, and the version
        // windows are what split it: `belowAppVersion: "4"` here and
        // `minimumAppVersion: "4"` there tile it at 4.0. Without windows the
        // group is not narrowed at all and a 4.0.0 prerelease gets this recipe,
        // the first in it. Either window alone would route 4.x correctly
        // (`scoped` drops a recipe whose window excludes the version, and
        // prefers one whose window covers it); both are declared so each
        // recipe's train is stated and `duo verify` reports an entry from the
        // other train on either page.
        ChangelogRecipe(
            bundleID: "org.audacityteam.audacity",
            source: releasesAPI,
            mode: .json,
            belowAppVersion: "4",
            structuredFormat: .gitHubReleases,
            tagPattern: #"^Audacity-(3\.[0-9]+\.[0-9]+)$"#),

        // Audacity 4. Bodies are Markdown with `## Features` /
        // `## Accessibility` / `## Bug fixes` sections, which the GitHub parser
        // renders as headings.
        ChangelogRecipe(
            bundleID: "org.audacityteam.audacity4",
            source: releasesAPI,
            mode: .json,
            structuredFormat: .gitHubReleases,
            tagPattern: fourTag),

        // The 4.0 alpha/beta builds' id. It lands in the 3.x recipe's group (see
        // above) and claims its versions from 4.0 up. It reads the stable 4.x
        // notes: those builds are pre-releases of the 4.0 line, and the one
        // update anything offers them is a stable 4.x (Homebrew's `audacity`
        // cask, when it installed the `Audacity 4.app` they replaced). Their own
        // prerelease notes are not read: `.gitHubReleases` without a channel is
        // stable-only, and their version (`4.0.0`, no suffix) cannot say which
        // prerelease they are.
        ChangelogRecipe(
            bundleID: "org.audacityteam.Audacity",
            source: releasesAPI,
            mode: .json,
            minimumAppVersion: "4",
            structuredFormat: .gitHubReleases,
            tagPattern: fourTag),
        ])
}
