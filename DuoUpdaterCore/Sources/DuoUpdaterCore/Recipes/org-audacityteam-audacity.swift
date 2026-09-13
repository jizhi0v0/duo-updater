import Foundation

enum org_audacityteam_audacity {
    static let set = AppRecipeSet(
        family: "org-audacityteam-audacity",
        changelogs: [
        // Audacity — GitHub releases page (same shape as Ollama/RustDesk). Each
        // release is a <section aria-labelledby="hd-…"> with an sr-only <h2> (e.g.
        // "Audacity 3.7.7"), a <relative-time datetime="…"> (ISO date), and a
        // <div class="markdown-body …"> body. The h2 carries an "Audacity " prefix,
        // so the version group anchors on that literal + a \d.\d.\d triple — which
        // also skips interleaved "Audacity-4.0.0.alpha-2" pre-release rows (hyphen,
        // not space). NOTE: Audacity is detected via Homebrew cask, not GitHub —
        // this recipe supplies NOTES only; a parse miss falls back to the page.
        ChangelogRecipe(
            bundleID: "org.audacityteam.audacity",
            source: URL(string: "https://github.com/audacity/audacity/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>Audacity (?<version>\d+\.\d+\.\d+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),
        ])
}
