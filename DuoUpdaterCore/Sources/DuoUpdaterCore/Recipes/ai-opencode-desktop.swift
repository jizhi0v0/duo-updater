import Foundation

enum ai_opencode_desktop {
    static let set = AppRecipeSet(
        family: "ai-opencode-desktop",
        changelogs: [
        // OpenCode (desktop) — the anomalyco/opencode GitHub releases (the repo
        // moved from sst/opencode via GitHub's org-rename redirect; we pin the
        // canonical anomalyco path). The desktop app and CLI share one version
        // line, so the releases' versions match the installed app build, and
        // the notes are read exactly as the OpenCode CLI's are
        // (`.opencodeReleases` → `OpencodeRelease.parseNotes`): each body up to
        // its `**Thank you to N community contributors:**` block.
        //
        // This used to scrape github.com/anomalyco/opencode/releases with a
        // `<li>` item pattern, which also took that block: on 2026-10-08 the
        // page's ten releases showed 3–5 `@handle: <pull-request title>` lines
        // each after their real changes (v1.18.35: 5 items for 2 changes).
        ChangelogRecipe(
            bundleID: "ai.opencode.desktop",
            source: OpencodeRelease.listURL,
            mode: .json,
            structuredFormat: .opencodeReleases),
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
