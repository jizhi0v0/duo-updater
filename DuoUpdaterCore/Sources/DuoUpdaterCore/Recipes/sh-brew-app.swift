import Foundation

enum sh_brew_app {
    static let set = AppRecipeSet(
        family: "sh-brew-app",
        changelogs: [
        // BrewUI (Homebrew's official GUI, cask `homebrew-app`) — the version comes
        // from `HomebrewCaskSource`, which carries no notes at all: its only link
        // is the cask's `formulae.brew.sh` listing. The notes are the project's
        // GitHub releases, which are also where the cask downloads from
        // (`…/BrewUI/releases/download/v#{version}/Homebrew-#{version}.zip`), so
        // tag and cask version are the same number by construction: `v0.4.0`
        // ↔ cask `0.4.0` ↔ the bundle's `CFBundleShortVersionString` `0.4.0`
        // (2026-09-13).
        //
        // Bodies are GitHub's generated "What's Changed" lists, which
        // `GitHubMarkdownParser` already strips of the `by @user in <PR>` suffix
        // and the New Contributors / Full Changelog sections. The two earliest
        // releases (v0.1.0, v0.1.1) are marked prerelease and so drop out; every
        // release since is stable. The app is not a Sparkle app and has no
        // updater of its own — it upgrades itself by running `brew upgrade --cask
        // homebrew-app` — so there is no second notes source to prefer.
        ChangelogRecipe(
            bundleID: "sh.brew.app",
            source: URL(string: "https://api.github.com/repos/Homebrew/BrewUI/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
