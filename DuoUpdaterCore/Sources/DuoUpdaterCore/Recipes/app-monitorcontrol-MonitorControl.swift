import Foundation

enum app_monitorcontrol_MonitorControl {
    static let set = AppRecipeSet(
        family: "app-monitorcontrol-MonitorControl",
        changelogs: [
        // History: docs/app-audits/app-monitorcontrol-MonitorControl.md#历史与实测
        // MonitorControl — GitHub releases, not the appcast's notes link.
        //
        // Detection is the bundle's own Sparkle feed (`appcast2.xml`), which
        // carries no notes, only `<sparkle:releaseNotesLink>` to
        // `monitorcontrol.app/changelog.html?tag=v<version>`. That page is a
        // JS shell: it fetches this repo's `releases/tags/<tag>` and renders the
        // `body`. This reads the same bodies straight from the releases list, so
        // the pane gets every version instead of an embedded page.
        //
        // Tags are `v<CFBundleShortVersionString>`. `tagPattern` is a filter, not
        // a monorepo split: `v4.0.0-rc1` is published with `prerelease: false`,
        // so the decoder's stable filter alone would show a release candidate
        // to stable installs. The real prereleases (`v4.0.0-beta1/-beta2`) are
        // dropped by that filter as well as by the `$` anchor.
        //
        // Releases up to 4.2.0 were shipped under the predecessor identity
        // `me.guillaumeb.MonitorControl` (another Team, another feed). They stay:
        // same repo, same product, and the identity change was a re-signing
        // (the vendor's 4.3.2 notes say so), so they are this app's history.
        //
        // `skipSections` drops three headings that are never changes, matched
        // whole: the 4.0.0 translator roster, the per-release `Notes` sign-off
        // (thanks / "open an issue" / "help translating"), and 1.x's
        // `Installation` instructions. New Contributors and Full Changelog are
        // already dropped for every app by `GitHubMarkdownParser`.
        ChangelogRecipe(
            bundleID: "app.monitorcontrol.MonitorControl",
            source: URL(string: "https://api.github.com/repos/MonitorControl/MonitorControl/releases?per_page=40")!,
            mode: .json,
            structuredFormat: .gitHubReleases,
            skipSections: ["Thanks to all our translators", "Notes", "Installation"],
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
