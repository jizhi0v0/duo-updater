import Foundation

enum com_xd_cindy {
    static let set = AppRecipeSet(
        family: "com-xd-cindy",
        changelogs: [changelog(for: "com.xd.cindy")],
        githubRules: [
        // Cindy (global edition) — XD's Electron AI agent. One repo ships two
        // editions as separate apps: global com.xd.cindy (Team SX9RG894L5, XD
        // Entertainment) and Mainland China com.xd.cindycn (Team NTC4BJ542G,
        // X.D. Network), both "Cindy.app". This file is the shared rationale;
        // Recipes/com-xd-cindycn.swift points here.
        //
        // No Sparkle and no app-update.yml. The in-app updater reads
        // `<cdn>/manifest-darwin-<arch>[-beta|-canary].json` on
        // hotfix.cindy.app / hotfix.cindy.com.cn and swaps the whole bundle
        // (ditto the zip, rm the old .app, mv the new one), so Info.plist moves
        // with it. The manifest's `app.installer` dmg has the same sha256 as
        // this repo's asset for the same edition and arch (0.1.97, all four
        // compared), so the GitHub release is the same build. Info.plist short ==
        // build == the tag's X.Y.Z (0.1.95, 0.1.97 checked on real dmgs).
        //
        // Three shapes in the release list the anchors exist for:
        //  - `vX.Y.Z-beta` tags, flagged prerelease, whose app reads the bare
        //    X.Y.Z (0.1.96-beta's Info.plist says 0.1.96). The tag anchor keeps
        //    them out even if one went out un-flagged.
        //  - `v1.0.0`, a source snapshot with no assets at all ("official
        //    installers are distributed … through the official sites"). Its tag
        //    fits the pattern, so the dmg pattern is what keeps 1.0.0 from being
        //    offered: with no matching asset the source walks past it.
        //  - two editions × two arches per release. The edition suffix is in the
        //    pattern; the arch is left to the source's arch preference. Two
        //    rules on one repo and channel, so each carries a `variant` to keep
        //    its own `recipeID`.
        //
        // The beta track (in-app "enableBeta", the -beta tags) is not wired: the
        // bundle carries no channel marker, so a beta copy reads as stable and
        // is only ever offered a newer stable.
        // One-click: com.xd.cindy, Team SX9RG894L5, notarized.
        GitHubReleaseRule(
            bundleID: "com.xd.cindy",
            owner: "makecindy", repo: "cindy",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$"#,
            installerKind: .dmg,
            variant: "global"),
        ])

    /// Both editions' notes: one repo, one body per release, so the cn family
    /// (`Recipes/com-xd-cindycn.swift`) builds its recipe here too.
    ///
    /// Regexes over the releases JSON rather than `.gitHubReleases`. Each body
    /// is `Desktop release X.Y.Z`, `## 更新说明`, then one `### <emoji title>`
    /// plus ONE prose paragraph per change, then `## PRs` (a line of links) and,
    /// after `---`, bullets of build metadata (commit, source tag, mobile
    /// builds). `GitHubMarkdownParser` takes bullets first, so it rendered the
    /// metadata as the only "changes"; its prose pass can't take over either,
    /// with a 12-line cap these bodies routinely pass.
    ///
    ///  - `body` starts after `Desktop release ` and stops at `\n## PRs` or
    ///    `\n---`, whichever comes first (the oldest bodies have no PRs
    ///    section), so the metadata never reaches the item patterns. Requiring
    ///    the prefix also leaves out `v1.0.0`, the assetless source snapshot.
    ///  - ONE item pattern for both shapes: the line right after a `###` line
    ///    (unless it is a bullet), or any bullet line. 0.1.17–0.1.20 list their
    ///    changes under `### New Features` / `### Bug Fixes`; every later body
    ///    is paragraphs. Two patterns would be first-wins per entry, so a single
    ///    bullet in a paragraph body would drop every paragraph of that release.
    ///    The heading match starts one newline before its `###`, so each
    ///    heading sorts ahead of the change under it.
    ///  - Bare `vX.Y.Z` tags and `"prerelease":false`: the `-beta` releases
    ///    carry notes for builds a stable install is never offered.
    ///  - Captures run before the JSON unescape, hence `(?:\\[^rn]|[^"\\])`
    ///    and both newline spellings, as in `Recipes/net-imput-helium.swift`;
    ///    `\s*` around colons because the API answers compact or pretty.
    static func changelog(for bundleID: String) -> ChangelogRecipe {
        let newline = #"\\(?:r\\)?n"#
        let line = #"(?:\\[^rn]|[^"\\])+"#
        return ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://api.github.com/repos/makecindy/cindy/releases?per_page=40")!,
            entryPattern:
                #""tag_name"\s*:\s*"v(?<version>[0-9]+\.[0-9]+\.[0-9]+)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"Desktop release "#
                + #"(?<body>(?:(?!"# + newline + #"(?:## PRs|---))(?:\\.|[^"\\]))*)"#,
            itemPatterns: [
                #"(?:###[ \t]+"# + line + newline + #"(?![-*][ \t])|"# + newline + #"[-*][ \t]+)"#
                    + "(?<item>" + line + ")",
            ],
            mode: .json,
            maxEntries: 20,
            headingPattern: newline + #"###[ \t]+(?<heading>"# + line + ")")
    }
}
