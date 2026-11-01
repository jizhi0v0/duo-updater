import Foundation

enum co_gitup_mac {
    static let set = AppRecipeSet(
        family: "co-gitup-mac",
        changelogs: [
        // GitUp — the release body is a `## What's Changed` document written by
        // hand: a highlights section with bullets and nested bullets, then the
        // GitHub pull-request list ("* … by @user in <PR url>"), then
        // `**Full Changelog**`. The parser keeps the headings, strips the
        // `by @user in …` suffix and drops the compare link. The stable tag
        // pattern keeps the continuous build tags (b1059) out of the history.
        ChangelogRecipe(
            bundleID: "co.gitup.mac",
            source: URL(string: "https://api.github.com/repos/git-up/GitUp/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ],
        githubRules: [
        // GitUp — native Git client. It ships Sparkle 2 (`Sparkle.framework`,
        // `SUPublicEDKey`) but no `SUFeedURL`: the feed address is built in code
        // as `…/git-up/GitUp/master/appcasts/<track>/appcast.xml`, where <track>
        // is the build's own track (the repo has `stable` and `continuous`), so
        // `feed-discover` reports a templated address and the generic Sparkle
        // source never sees a feed. This rule is the route.
        //
        // Tags read `v1.5.0`; the bundle says 1.5.0 (build 1058). The asset is a
        // single universal `GitUp.zip` — co.gitup.mac, Team FP44AY6HHW,
        // notarized.
        //
        // Continuous builds are GitHub prereleases tagged by build number
        // (`b1059`) whose bundle version is the NEXT line (1.6.0): the anchored
        // tag pattern never matches one, and a copy installed from one reads
        // ahead of the stable release, so the stable rule offers it nothing
        // older. The app's own Sparkle track for such a build is `continuous`,
        // which this source does not touch.
        GitHubReleaseRule(
            bundleID: "co.gitup.mac",
            owner: "git-up", repo: "GitUp",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^GitUp\.zip$"#,
            installerKind: .zip),
        ])
}
