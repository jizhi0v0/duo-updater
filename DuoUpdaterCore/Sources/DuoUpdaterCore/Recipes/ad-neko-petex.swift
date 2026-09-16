import Foundation

enum ad_neko_petex {
    static let set = AppRecipeSet(
        family: "ad-neko-petex",
        githubRules: [
        // History: docs/app-audits/ad-neko-petex.md#历史与实测
        //
        // Petex — a desktop pet app distributed through this repo's Releases:
        // the bundle carries no `SUFeedURL`, Homebrew has no cask for it, and
        // the App Store search that would hand it to `MacAppStoreSource`
        // returns nothing (storefront and date in the audit). Its README
        // mentions a Mac App Store build; if one ever ships, this rule is not
        // what serves that copy — `GitHubReleasesSource` skips a store copy on
        // its own `isMASApp` gate before it ever reaches the rule table.
        //
        // Tags are `v<major>.<minor>.<commit height>` — the release workflow
        // stamps `package.json` from `git rev-list --count HEAD` before it
        // builds — so the patch component advances with every commit that
        // ships, and the bundle's short version, build version and tag are all
        // that same string. Nothing here needs `versionIsBuild`-style handling.
        //
        // The pattern is anchored at BOTH ends, which the default one is not,
        // and the anchors are the ONLY thing standing between this rule and a
        // prerelease. Both paths into `resolve()` filter on GitHub's
        // `prerelease` FLAG — `/releases/latest` by GitHub's own definition,
        // the list fallback through `stableOnly` — and this repo's publish
        // script never sets that flag: it runs `gh release edit <tag>
        // --draft=false --latest` on every push to master, whatever the tag
        // says. So a `v1.1.0-rc.1` here would arrive flagged stable, and an
        // unanchored pattern would read it as a plain `1.1.0` — a release that
        // was never published — and offer it to every install. Nothing else in
        // the string gives the suffix away: the patch component is a commit
        // height, so every tag looks like an ordinary release.
        //
        // Detection-only, and not as a backlog item: the macOS artifact is
        // built with `CSC_IDENTITY_AUTO_DISCOVERY: 'false'` and ships ad-hoc,
        // linker-signed, carrying no Team Identifier and no sealed resources.
        // `SignatureVerifier` gate 2 (deep/strict validity) and gate 3 (Team ID
        // match) would each refuse the swap on their own, so an
        // `installAssetPattern` here could only ever produce an Update button
        // that fails. Saying so with a nil pattern is the honest form — the
        // user gets the version and the releases page. `PetexGitHubRuleTests`
        // pins both halves.
        GitHubReleaseRule(
            bundleID: "ad.neko.petex",
            owner: "iebb", repo: "petex",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
