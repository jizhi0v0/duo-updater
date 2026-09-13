import Foundation

enum app_cyan_markedit {
    static let set = AppRecipeSet(
        family: "app-cyan-markedit",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // MarkEdit — takes the UNIVERSAL dmg (`MarkEdit-<ver>.dmg`), not the
        // `-apple-silicon` one beside it. Verified with `file`: the plain dmg is a
        // universal binary (x86_64 + arm64) while `-apple-silicon` is a single arm64
        // slice — and `apple-silicon` was not a token the asset picker recognised, so
        // pinning it read as arch-neutral and would have offered an arm64-only build
        // to an Intel Mac. (The token is recognised now, but the universal dmg is
        // still the better pin: one artifact that runs everywhere, no arch branch.)
        // The `[0-9.]+\.dmg$` anchor also keeps `-apple-silicon.dmg` out, and the
        // `UpdateArchive*.zip` payloads are for MarkEdit's own updater, not for us.
        // One-click: app.cyan.markedit, Team TCKG8FBVG6, notarized — verified on the
        // universal dmg.
        GitHubReleaseRule(
            bundleID: "app.cyan.markedit",
            owner: "MarkEdit-app", repo: "MarkEdit",
            installAssetPattern: #"^MarkEdit-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
