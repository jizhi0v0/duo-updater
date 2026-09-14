import Foundation

enum sh_waku {
    static let set = AppRecipeSet(
        family: "sh-waku",
        changelogs: [
        // History: docs/app-audits/sh-waku.md#历史与实测
        // Waku — GitHub releases, not the appcast's own notes link.
        //
        // The appcast points `<sparkle:releaseNotesLink>` at a per-version file,
        // `releases.waku.sh/Waku-<version>.md`, whose body is a bare Markdown
        // bullet list — no heading, no title, no version in it — so it produced no
        // entries and the pane fell back to a web view rendering raw `- ` lines.
        // That file is fetchable for any version by name (History has the versions
        // tried) but the site root 404s, so there is NO index: templating it can
        // only ever show the one version being offered.
        //
        // github.com/egoist/waku carries the same bullets AND the history, each
        // release with its published date. Same content, more of it, and it reuses
        // the decoder every other GitHub-sourced app already goes through. Two of
        // those releases (v0.1.9, v0.1.7) say only "See CHANGELOG.md for
        // details."; they still get an entry, via `GitHubMarkdownParser`'s prose
        // pass, rather than leaving a gap in the version rail.
        ChangelogRecipe(
            bundleID: "sh.waku",
            source: URL(string: "https://api.github.com/repos/egoist/waku/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
