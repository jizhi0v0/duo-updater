import Foundation

enum net_kovidgoyal_kitty {
    static let set = AppRecipeSet(
        family: "net-kovidgoyal-kitty",
        changelogs: [
        // Sphinx renders each detailed release as a section headed “version [date]”.
        // Match that heading rather than the numbered anchors, which shift on each
        // release, and stop the body at the section boundary.
        // History: docs/app-audits/net-kovidgoyal-kitty.md#历史与实测
        ChangelogRecipe(
            bundleID: "net.kovidgoyal.kitty",
            source: URL(string: "https://sw.kovidgoyal.net/kitty/changelog/")!,
            entryPattern:
                #"<section\b[^>]*>\s*<h3\b[^>]*>\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)"#
                + #"\s+\[(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\]\s*"#
                + #"(?:<a\b[^>]*class="headerlink"[^>]*>[^<]*</a>)?\s*</h3>"#
                + #"(?<body>.*?)(?=</?section\b)"#,
            itemPatterns: [#"<li\b[^>]*>(?<item>.*?)</li>"#]),
        ],
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // kitty — terminal. The repo carries a rolling `nightly` prerelease tag, so
        // again `/releases/latest` (not the list) is what keeps a stable install on
        // stable. One dmg per release, `kitty-<ver>.dmg`, universal.
        // One-click: net.kovidgoyal.kitty, Team NTY7FVCEKP, notarized.
        GitHubReleaseRule(
            bundleID: "net.kovidgoyal.kitty",
            owner: "kovidgoyal", repo: "kitty",
            installAssetPattern: #"^kitty-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
