import Foundation

enum ai_opencode_desktop {
    static let set = AppRecipeSet(
        family: "ai-opencode-desktop",
        changelogs: [
        // OpenCode (desktop) — github.com/anomalyco/opencode/releases (the repo
        // moved from sst/opencode via GitHub's org-rename redirect; we pin the
        // canonical anomalyco path). Same GitHub-releases shape as Ollama/RustDesk:
        // each release is a <section aria-labelledby="hd-…"> with an sr-only <h2>
        // carrying the version (e.g. "v1.15.13"), a <relative-time datetime="…"> (ISO
        // date), and a <div class="markdown-body …"> body. The leading "v" is
        // dropped. The desktop app and CLI share one version line, so the releases
        // versions match the installed app build.
        ChangelogRecipe(
            bundleID: "ai.opencode.desktop",
            source: URL(string: "https://github.com/anomalyco/opencode/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>v(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),
        ],
        githubRules: [
        // OpenCode Desktop — the stable tag and the app's marketing/build versions
        // are the same bare numeric value after stripping `v`. The release carries
        // native arm64 and x64 dmgs; `installableAsset` selects the host-native one.
        // Mounted arm64 dmg: ai.opencode.desktop, Team 5NZ4Q7NXJ4, notarized.
        GitHubReleaseRule(
            bundleID: "ai.opencode.desktop",
            owner: "anomalyco", repo: "opencode",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^opencode-desktop-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),
        ])
}
