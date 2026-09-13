import Foundation

enum com_carriez_rustdesk {
    static let set = AppRecipeSet(
        family: "com-carriez-rustdesk",
        changelogs: [
        // RustDesk — GitHub releases page, same shape as Ollama but the sr-only
        // <h2> carries a bare version ("1.4.7", no leading "v"), so the version
        // group matches digits directly. Each release is a <section> with an
        // sr-only h2 (version), a <relative-time datetime="…"> (ISO datetime),
        // and a <div class="markdown-body …"> body. Notes open with a screenshot
        // and a contributor line before the change bullets; those extra <li> are
        // cosmetic and a parse miss just falls back to the embedded page.
        ChangelogRecipe(
            bundleID: "com.carriez.rustdesk",
            source: URL(string: "https://github.com/rustdesk/rustdesk/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),
        ],
        githubRules: [
        // RustDesk — tags have no `v` prefix. One-click installs the arm64 dmg
        // asset (`rustdesk-<ver>-aarch64.dmg`): the official GitHub build is a
        // notarized Developer ID app, Team ID HZF9JMC8YN (zhou huabing), matching
        // the installed copy — so the VendorInstaller Team-ID gate passes. arm64
        // only, like the other Apple-silicon recipes; an Intel asset also ships
        // (`…-x86_64.dmg`) but we don't select it.
        GitHubReleaseRule(
            bundleID: "com.carriez.rustdesk",
            owner: "rustdesk", repo: "rustdesk",
            // Anchor the whole filename (`rustdesk-<ver>-aarch64.dmg`) rather than
            // just the suffix, so a future flavored arm64 dmg (e.g. a `-sciter`
            // build) can't be picked by position instead of the canonical asset.
            installAssetPattern: #"^rustdesk-[0-9.]+-aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
