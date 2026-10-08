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
        ],
        githubRules: [
        // Copies installed from the vendor's dmg. A brew-installed copy never
        // reaches these: `HomebrewCaskSource` sits ahead of GitHub in
        // `SourceStack` and answers whenever the Caskroom holds the cask that
        // owns the `.app` (`audacity@3` for `Audacity.app`, `audacity` for
        // `Audacity 4.app`).
        //
        // Each rule is stable and reads `/releases/latest`, which GitHub computes
        // over BOTH trains, prereleases excluded. When that release is the other
        // train's, its `versionPattern` refuses the tag and its
        // `installAssetPattern` finds no asset, which is what sends the source to
        // the releases list — filtered to non-prerelease, non-draft releases —
        // where the newest tag of this rule's major is taken. So the asset
        // pattern is load-bearing for detection as well as for the install:
        // without one, a rule whose train is not `latest` answers nothing.
        // Both patterns pin the major at the start and anchor the end, so a
        // prerelease's suffixed tag (`Audacity-3.5.0-beta-3`) or asset
        // (`audacity-macOS-3.5.0-beta-3-arm64.dmg`) is refused even if it were
        // published as a stable release, and the `.pkg` beside some dmgs is
        // never chosen. The version pattern also keeps the other train's rows
        // out of the walk: read as this train's releases with no matching
        // asset, a run of them would end it (`maxReleasesWithoutMacOSAsset`).
        //
        // One-click: the macOS assets are notarized Developer ID dmgs. When
        // GitHub publishes a `digest` for the asset, the download is checked
        // against it before the Team-ID gate. That gate requires the installed
        // copy's Team ID, and Audacity 3 changed Team at 3.7.9 (`AWEYX923UX` →
        // `6EPAF2X3PR`): a copy at 3.7.8 or earlier is detected and offered
        // 3.7.9, and its one-click is refused by `SignatureVerifier`, so the user
        // updates by hand once. Audacity 4 has a single Team.
        //
        // The 4.0 alpha/beta id `org.audacityteam.Audacity` has NO rule, so a
        // directly installed prerelease stays unknown. Rules are keyed by exact
        // bundle id, so neither rule here answers for it. A stable rule for that
        // id would offer a prerelease install the stable train, and an install
        // of a different app: the stable 4.x is `org.audacityteam.audacity4`,
        // which `SignatureVerifier`'s bundle-id gate refuses as the replacement.
        // A prerelease rule cannot apply either: the build carries no channel
        // marker, so it is detected as stable, and its bare `4.0.0` does not say
        // which alpha or beta it is, so no `Audacity-4.0.0-beta-N` tag can be
        // compared with it.
        GitHubReleaseRule(
            bundleID: "org.audacityteam.audacity",
            owner: "audacity", repo: "audacity",
            versionPattern: #"^Audacity-(3\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^audacity-macOS-3\.[0-9]+\.[0-9]+-(?:arm64|x86_64|universal)\.dmg$"#,
            installerKind: .dmg,
            variant: "audacity3"),
        GitHubReleaseRule(
            bundleID: "org.audacityteam.audacity4",
            owner: "audacity", repo: "audacity",
            versionPattern: fourTag,
            installAssetPattern: #"^audacity-macOS-4\.[0-9]+\.[0-9]+-(?:arm64|x86_64|universal)\.dmg$"#,
            installerKind: .dmg,
            variant: "audacity4"),
        ])
}
